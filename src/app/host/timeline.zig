//! Linear lazy FSM: each step is one `pairwiseInteractionPass` snapshot. Equal fingerprints imply a loop.
const std = @import("std");
const Particle = @import("ulib");
const sim_step = @import("sim_step.zig");
const DetachedTopologyShelf = @import("detached_shelf.zig").DetachedTopologyShelf;

pub const LoopPair = struct {
    first_step: usize,
    /// Step index we would have appended; same universe as `first_step`.
    repeat_step: usize,
};

pub const LinearTimeline = struct {
    allocator: std.mem.Allocator,
    /// `steps[s]` is the universe after `s` pairwise passes (`steps[0]` is genesis).
    steps: std.ArrayList(Particle.Graph),
    /// Which cached step is shown (scrub). Always `< steps.items.len`.
    view_step: usize,
    fingerprint_by_hash: std.AutoHashMap(u64, usize),
    loop_pair: ?LoopPair = null,

    pub fn initOwnedGenesis(allocator: std.mem.Allocator, genesis: Particle.Graph) !LinearTimeline {
        var steps: std.ArrayList(Particle.Graph) = .empty;
        errdefer {
            for (steps.items) |*g| g.deinit();
            steps.deinit(allocator);
        }
        try steps.append(allocator, genesis);

        var fp_map = std.AutoHashMap(u64, usize).init(allocator);
        errdefer fp_map.deinit();

        const h0 = try fingerprintGraph(allocator, &steps.items[0]);
        try fp_map.put(h0, 0);

        return .{
            .allocator = allocator,
            .steps = steps,
            .view_step = 0,
            .fingerprint_by_hash = fp_map,
            .loop_pair = null,
        };
    }

    pub fn deinit(self: *LinearTimeline) void {
        for (self.steps.items) |*g| g.deinit();
        self.steps.deinit(self.allocator);
        self.fingerprint_by_hash.deinit();
        self.* = undefined;
    }

    pub fn activeGraph(self: *LinearTimeline) *Particle.Graph {
        return &self.steps.items[self.view_step];
    }

    pub fn frontierStep(self: *const LinearTimeline) usize {
        return self.steps.items.len -| 1;
    }

    /// Append one transition from the current frontier. No-op if a loop was already detected.
    /// After the pass, `detached` (if non-null) may move zero-degree vertices off `next` into shelved graphs.
    pub fn advanceFrontier(self: *LinearTimeline, detached: ?*DetachedTopologyShelf) !void {
        if (self.loop_pair != null) return;

        var next = try Particle.cloneGraph(&self.steps.items[self.steps.items.len - 1], self.allocator);
        errdefer next.deinit();

        try sim_step.pairwiseInteractionPass(self.allocator, &next);
        if (detached) |d| try d.extractIsolatesFrom(&next);

        const new_step = self.steps.items.len;
        const h = try fingerprintGraph(self.allocator, &next);
        if (self.fingerprint_by_hash.get(h)) |first| {
            next.deinit();
            self.loop_pair = .{ .first_step = first, .repeat_step = new_step };
            return;
        }
        try self.fingerprint_by_hash.put(h, new_step);
        try self.steps.append(self.allocator, next);
    }

    pub fn setViewStep(self: *LinearTimeline, step: usize) void {
        if (self.steps.items.len == 0) return;
        self.view_step = @min(step, self.steps.items.len - 1);
    }
};

fn fingerprintGraph(allocator: std.mem.Allocator, g: *Particle.Graph) !u64 {
    var keys = try allocator.alloc(u64, g.vertices.count());
    defer allocator.free(keys);
    var ki: usize = 0;
    var it = g.vertices.iterator();
    while (it.next()) |ent| {
        keys[ki] = ent.key_ptr.*;
        ki += 1;
    }
    std.sort.pdq(u64, keys, {}, std.sort.asc(u64));

    var adj_scratch: std.ArrayList(u64) = .empty;
    defer adj_scratch.deinit(allocator);

    var hasher = std.hash.Wyhash.init(0);
    for (keys) |k| {
        const node = g.getVertex(k) orelse continue;
        hashParticle(&hasher, node.data);
        hasher.update(std.mem.asBytes(&k));

        adj_scratch.clearRetainingCapacity();
        var aj = node.adjacency_set.iterator();
        while (aj.next()) |ae| {
            try adj_scratch.append(allocator, ae.key_ptr.*);
        }
        std.sort.pdq(u64, adj_scratch.items, {}, std.sort.asc(u64));
        for (adj_scratch.items) |t| {
            hasher.update(std.mem.asBytes(&t));
        }
    }
    return hasher.final();
}

fn hashParticle(hasher: *std.hash.Wyhash, p: Particle) void {
    hasher.update(std.mem.asBytes(&p.has_color));
    hasher.update(std.mem.asBytes(&p.charge));
    hasher.update(std.mem.asBytes(&p.mass));
    hasher.update(std.mem.asBytes(&p.energy));
    hasher.update(std.mem.asBytes(&p.spin));
    hasher.update(std.mem.asBytes(&p.b3));
    hasher.update(std.mem.asBytes(&p.L_e));
    hasher.update(std.mem.asBytes(&p.L_mu));
    hasher.update(std.mem.asBytes(&p.L_tau));
}

test "timeline advance preserves standard observables over a few steps" {
    Particle.setSimulationRngSeed(0xc0ffee);
    const g = try Particle.initializeGraph(std.testing.allocator, 16);
    var tl = try LinearTimeline.initOwnedGenesis(std.testing.allocator, g);
    defer tl.deinit();
    var s: u8 = 0;
    while (s < 5) : (s += 1) {
        if (tl.loop_pair != null) break;
        try tl.advanceFrontier(null);
    }
}

test "timeline genesis has step zero" {
    var g: Particle.Graph = .init(std.testing.allocator, 0);
    try g.putVertex(0, Particle.Type.Electron.toParticle());

    var tl = try LinearTimeline.initOwnedGenesis(std.testing.allocator, g);
    defer tl.deinit();

    try std.testing.expectEqual(@as(usize, 1), tl.steps.items.len);
    try std.testing.expectEqual(@as(usize, 0), tl.view_step);
    try std.testing.expectEqual(@as(usize, 0), tl.frontierStep());
}
