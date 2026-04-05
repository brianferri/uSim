//! One FSM transition: a full pairwise interaction pass over the graph (deterministic given iterator order).
const std = @import("std");
const Particle = @import("ulib");
const uSim = @import("usim");

const pairwise_debug_ring_cap = 96;

const PairwiseDebugEntry = struct {
    k1: u64,
    k2: u64,
    t1: Particle.Type,
    t2: Particle.Type,
    consumed: [2]bool,
    n_emit: usize,
};

fn pushPairwiseDebug(buf: *[pairwise_debug_ring_cap]PairwiseDebugEntry, total_pairs: *usize, entry: PairwiseDebugEntry) void {
    buf.*[total_pairs.* % pairwise_debug_ring_cap] = entry;
    total_pairs.* += 1;
}

/// Smallest vertex id among undirected neighbors of `a` or `b` (adj ∪ inc), excluding `a` and `b`.
/// Used as a single “spectator” anchor so we do not attach products to the whole graph (that explodes
/// degree and causes runaway bremsstrahlung / Compton in one pass).
fn smallestUndirectedNeighborApartFrom(g: *Particle.Graph, a: u64, b: u64) ?u64 {
    var m: ?u64 = null;
    for ([_]u64{ a, b }) |v| {
        const node = g.getVertex(v) orelse continue;
        var out_it = node.adjacency_set.iterator();
        while (out_it.next()) |e| {
            const k = e.key_ptr.*;
            if (k == a or k == b) continue;
            m = if (m) |old| @min(old, k) else k;
        }
        var in_it = node.incidency_set.iterator();
        while (in_it.next()) |e| {
            const k = e.key_ptr.*;
            if (k == a or k == b) continue;
            m = if (m) |old| @min(old, k) else k;
        }
    }
    return m;
}

/// Bidirectional link used for emission ↔ anchor (two directed edges).
fn addBidirectionalLink(g: *Particle.Graph, a: u64, b: u64) !void {
    try g.addEdge(a, b);
    try g.addEdge(b, a);
}

/// If the graph has several **weak** components, add topology-only edges so they become one component.
/// Uses a **chain** of representatives (smallest vertex id per component, sorted), so each vertex gains
/// at most two bridge neighbors instead of star-wiring into one hub (which amplified scattering).
/// Does not change particle data; additive quantum sums are unchanged.
fn weaklyConnectComponentsInChain(alloc: std.mem.Allocator, g: *Particle.Graph) !void {
    const G = @TypeOf(g.*);
    const keys = try uSim.structure_analysis.graphKeysSorted(G, alloc, g);
    defer alloc.free(keys);
    if (keys.len <= 1) return;

    const roots = try uSim.structure_analysis.weaklyConnectedRootPerKey(G, alloc, g, keys);
    defer alloc.free(roots);

    var min_key_for_root = std.AutoHashMap(usize, u64).init(alloc);
    defer min_key_for_root.deinit();
    for (keys, roots) |k, r| {
        const gop = try min_key_for_root.getOrPut(r);
        if (!gop.found_existing) {
            gop.value_ptr.* = k;
        } else {
            gop.value_ptr.* = @min(gop.value_ptr.*, k);
        }
    }

    var reps = std.ArrayList(u64).empty;
    defer reps.deinit(alloc);
    var mit = min_key_for_root.iterator();
    while (mit.next()) |ent| {
        try reps.append(alloc, ent.value_ptr.*);
    }
    if (reps.items.len <= 1) return;

    std.sort.pdq(u64, reps.items, {}, std.sort.asc(u64));
    var i: usize = 0;
    while (i + 1 < reps.items.len) : (i += 1) {
        try addBidirectionalLink(g, reps.items[i], reps.items[i + 1]);
    }
}

fn printPairwiseDebugOnFailure(buf: *const [pairwise_debug_ring_cap]PairwiseDebugEntry, total_pairs: usize) void {
    if (total_pairs == 0) {
        std.debug.print("pairwiseInteractionPass: no pair attempts logged\n", .{});
        return;
    }
    const n = @min(total_pairs, pairwise_debug_ring_cap);
    std.debug.print(
        "pairwiseInteractionPass: last {} pair attempts (newest first): keys (k1 k2), types, consumed[2], n_emit\n",
        .{n},
    );
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const idx = (total_pairs - 1 - i) % pairwise_debug_ring_cap;
        const e = buf[idx];
        std.debug.print(
            "  #{d}: k1={} k2={} | {s} + {s} | consumed={any} | emissions={d}\n",
            .{ i, e.k1, e.k2, @tagName(e.t1), @tagName(e.t2), e.consumed, e.n_emit },
        );
    }
}

pub fn pairwiseInteractionPass(alloc: std.mem.Allocator, g: *Particle.Graph) (Particle.SimulationIntegrityError || std.mem.Allocator.Error)!void {
    const pre_obs = Particle.sumGlobalQuantumNumbers(g);

    var particle_status: std.AutoArrayHashMap(u64, bool) = .init(alloc);
    defer particle_status.deinit();

    // One buffer for all pairs: avoids per-edge ArrayList init/deinit (hot when degree is high).
    var emission_buffer: std.ArrayList(Particle) = .empty;
    defer emission_buffer.deinit(alloc);

    var debug_ring: [pairwise_debug_ring_cap]PairwiseDebugEntry = undefined;
    var debug_total_pairs: usize = 0;

    var iter = g.vertices.iterator();
    while (iter.next()) |entry| {
        const p1_key = entry.key_ptr.*;
        if ((try particle_status.getOrPutValue(p1_key, false)).found_existing) continue;
        const p1_value = entry.value_ptr.*;

        var adj_iter = p1_value.adjacency_set.iterator();
        while (adj_iter.next()) |adj_entry| {
            const p2_key = adj_entry.key_ptr.*;
            // The same outer vertex p1 can be adjacent to several others in one pass. If an earlier
            // interaction already consumed p1 (annihilation / decay / pair production), we must not run
            // another handler on p1: a later `put(p1_key, false)` would overwrite `true` and skip removal
            // while extra emissions stay in the graph, breaking summed charge/b3.
            if (particle_status.get(p1_key) orelse false) break;
            if ((try particle_status.getOrPutValue(p2_key, false)).found_existing) continue;
            const p2_value = g.getVertex(p2_key) orelse continue;

            const t1 = Particle.Type.fromStruct(&p1_value.data);
            const t2 = Particle.Type.fromStruct(&p2_value.data);

            emission_buffer.clearRetainingCapacity();
            const consumed = try Particle.interact(&p1_value.data, &p2_value.data, &emission_buffer, alloc);
            try particle_status.put(p1_key, consumed[0]);
            try particle_status.put(p2_key, consumed[1]);

            // When both parents are removed, products would otherwise often become isolates (shelved next
            // advance). Link them to at most one external spectator (min vertex id) and to each other,
            // so we stay connected without wiring every product to the full parent neighborhood.
            const bridge_anchor: ?u64 = if (consumed[0] and consumed[1])
                smallestUndirectedNeighborApartFrom(g, p1_key, p2_key)
            else
                null;

            var sibling_emission_keys: std.ArrayList(u64) = .empty;
            defer sibling_emission_keys.deinit(alloc);

            for (emission_buffer.items) |particle| {
                const next_key = try g.putVertexAuto(particle);
                // Four directed edges attach each emission to both parents so later passes can reach
                // the new vertex from either side. This is a host topology policy, not a literal
                // Feynman diagram: degree grows quickly and is not "number of SM gauge couplings".
                try g.addEdge(p1_key, next_key);
                try g.addEdge(p2_key, next_key);
                try g.addEdge(next_key, p1_key);
                try g.addEdge(next_key, p2_key);
                try particle_status.put(next_key, false);

                if (consumed[0] and consumed[1]) {
                    if (bridge_anchor) |nk| {
                        if (nk != next_key) try addBidirectionalLink(g, nk, next_key);
                    }
                    for (sibling_emission_keys.items) |sk| {
                        try addBidirectionalLink(g, sk, next_key);
                    }
                    try sibling_emission_keys.append(alloc, next_key);
                }
            }

            pushPairwiseDebug(&debug_ring, &debug_total_pairs, .{
                .k1 = p1_key,
                .k2 = p2_key,
                .t1 = t1,
                .t2 = t2,
                .consumed = consumed,
                .n_emit = emission_buffer.items.len,
            });
        }
    }

    var status_iter = particle_status.iterator();
    while (status_iter.next()) |status| {
        if (status.value_ptr.*) _ = try g.removeVertex(status.key_ptr.*);
    }

    try weaklyConnectComponentsInChain(alloc, g);

    const post_obs = Particle.sumGlobalQuantumNumbers(g);
    Particle.expectConservedObservablesAcrossPass(pre_obs, post_obs) catch |err| {
        std.debug.print(
            "QuantumNumbersNotConserved: pre charge={d} b3={} L_e={} L_mu={} L_tau={}\n",
            .{ pre_obs.charge, pre_obs.b3, pre_obs.L_e, pre_obs.L_mu, pre_obs.L_tau },
        );
        std.debug.print(
            "QuantumNumbersNotConserved: post charge={d} b3={} L_e={} L_mu={} L_tau={}\n",
            .{ post_obs.charge, post_obs.b3, post_obs.L_e, post_obs.L_mu, post_obs.L_tau },
        );
        printPairwiseDebugOnFailure(&debug_ring, debug_total_pairs);
        return err;
    };
}

test "pairwiseInteractionPass conserves observables one step ipc 100" {
    Particle.setSimulationRngSeed(0xfeed_beef);
    var g = try Particle.initializeGraph(std.testing.allocator, 100);
    defer g.deinit();
    try pairwiseInteractionPass(std.testing.allocator, &g);
}

test "weaklyConnectComponentsInChain links disjoint pieces" {
    const testing = std.testing;
    var g: Particle.Graph = .init(testing.allocator, 0);
    defer g.deinit();
    try g.putVertex(0, Particle.Type.Electron.toParticle());
    try g.putVertex(1, Particle.Type.Positron.toParticle());
    try g.putVertex(10, Particle.Type.Photon.toParticle());
    try g.putVertex(11, Particle.Type.Photon.toParticle());
    try g.addEdge(0, 1);
    try g.addEdge(10, 11);

    try weaklyConnectComponentsInChain(testing.allocator, &g);

    const stats = try uSim.structure_analysis.weaklyConnectedComponentStats(@TypeOf(g), testing.allocator, &g);
    try testing.expectEqual(@as(usize, 1), stats.n_components);
}

test "emissions bridge to undirected neighbors when both parents consumed" {
    const testing = std.testing;
    var g: Particle.Graph = .init(testing.allocator, 0);
    defer g.deinit();

    var ep = Particle.Type.Positron.toParticle();
    ep.energy = 500.0;
    var em = Particle.Type.Electron.toParticle();
    em.energy = 500.0;
    var spectator = Particle.Type.Photon.toParticle();
    spectator.energy = 10.0;

    try g.putVertex(0, ep);
    try g.putVertex(1, em);
    try g.putVertex(2, spectator);
    try g.addEdge(0, 1);
    try g.addEdge(0, 2);

    try pairwiseInteractionPass(testing.allocator, &g);

    var it = g.vertices.iterator();
    while (it.next()) |ent| {
        const node = ent.value_ptr.*;
        const deg = node.adjacency_set.count() + node.incidency_set.count();
        try testing.expect(deg > 0);
    }
}
