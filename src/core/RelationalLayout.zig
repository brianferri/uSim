const std = @import("std");
const testing = std.testing;

/// View-space layout derived from the graph each frame: **no velocity** and no key-only placement in
/// relational mode. `syncFromGraph` is **incremental** (drops removed vertices); **new keys on a cold
/// embedding** get a **BFS shell** (root at origin, neighbors at distance `1/degree` on symmetric
/// directions: opposite pair, planar thirds, tetrahedron for four, ring for five+). If some positions
/// already exist, new keys still use the legacy **edge-hash** seed so old coordinates stay valid.
/// `step` refines from there using **relaxation** and **max_displacement** per substep.
/// For id-only projection use `embedVertexKey` in a separate visualization mode.
pub const Vec3 = @Vector(3, f32);

pub const PairCtx = struct {
    key_from: u64,
    key_to: u64,
    deg_from: u32,
    deg_to: u32,
};

pub const LayoutHooks = struct {
    length_chain: []const *const fn (f32, PairCtx) f32,
    strength_chain: []const *const fn (f32, PairCtx) f32,
};

pub const StepParams = struct {
    base_ideal_length: f32 = 1.2,
    k_spring: f32 = 0.10,
    k_repulse: f32 = 5.5,
    dt: f32 = 0.12,
    /// Scales `f * dt` before applying (stabilizes cold start each frame).
    relaxation: f32 = 0.38,
    /// Max world-units moved per vertex per substep.
    max_displacement: f32 = 0.32,
    repulse_cutoff: f32 = 12.0,
    spatial_repulsion: bool = true,
    /// Below this, all-pairs repulsion is used; at and above, uniform grid (27-stencil) is used.
    spatial_repulsion_min_n: usize = 64,
};

pub const Embedding = struct {
    pos: std.AutoHashMap(u64, Vec3),
    force: std.AutoHashMap(u64, Vec3),
    keys_scratch: std.ArrayList(u64),
    /// Dedupes adjacency + incidency neighbors in O(degree) when seeding new vertices.
    neighbor_tags: std.AutoHashMap(u64, void),
    cell_buckets: std.AutoHashMap(u64, std.ArrayListUnmanaged(usize)),

    pub fn init(allocator: std.mem.Allocator) Embedding {
        return .{
            .pos = .init(allocator),
            .force = .init(allocator),
            .keys_scratch = .empty,
            .neighbor_tags = .init(allocator),
            .cell_buckets = .init(allocator),
        };
    }

    pub fn deinit(self: *Embedding) void {
        clearCellBuckets(self);
        self.cell_buckets.deinit();
        self.neighbor_tags.deinit();
        self.keys_scratch.deinit(self.pos.allocator);
        self.force.deinit();
        self.pos.deinit();
        self.* = undefined;
    }

    /// Remove stale keys, then seed vertices missing from `pos` (BFS shell if embedding was empty).
    pub fn syncFromGraph(self: *Embedding, comptime G: type, graph: *G) !void {
        const allocator = self.pos.allocator;
        var to_remove: std.ArrayList(u64) = .empty;
        defer to_remove.deinit(allocator);
        var pit = self.pos.iterator();
        while (pit.next()) |e| {
            if (graph.getVertex(e.key_ptr.*) == null)
                try to_remove.append(allocator, e.key_ptr.*);
        }
        for (to_remove.items) |k| {
            _ = self.pos.remove(k);
            _ = self.force.remove(k);
        }

        var any_missing = false;
        var any_present = false;
        var git = graph.vertices.iterator();
        while (git.next()) |ent| {
            if (self.pos.contains(ent.key_ptr.*)) {
                any_present = true;
            } else {
                any_missing = true;
            }
        }
        if (!any_missing) return;

        if (!any_present) {
            try bfsShellSeedAllVertices(G, graph, self, allocator);
        } else {
            git = graph.vertices.iterator();
            while (git.next()) |ent| {
                const k = ent.key_ptr.*;
                if (!self.pos.contains(k)) {
                    try self.pos.put(k, try relationalSeedForVertex(G, graph, k, self));
                }
            }
        }
    }
};

/// Deterministic key-only placement for non-relational visualization modes.
pub fn embedVertexKey(key: u64) Vec3 {
    const t = @as(f32, @floatFromInt(key % 997)) * 0.137;
    return .{
        @sin(t) * 2.5,
        @cos(t * 1.7) * 2.5,
        @sin(t * 0.9) * 2.5,
    };
}

fn vecLen(v: Vec3) f32 {
    return @sqrt(@reduce(.Add, v * v));
}

fn vecLenSq(v: Vec3) f32 {
    return @reduce(.Add, v * v);
}

fn degreeOf(node: anytype) u32 {
    return @intCast(node.adjacency_set.count() + node.incidency_set.count());
}

/// Unit direction for undirected edge `{lo, hi}` with `lo <= hi`; uses only the pair, not global ids alone.
fn unitVecFromUndirectedEdge(lo: u64, hi: u64) Vec3 {
    std.debug.assert(lo <= hi);
    var h = lo;
    h ^= hi +% 0x9e3779b97f4a7c15 +% (h << 6) +% (h >> 2);
    h *%= 0xbf58476d1ce4e5b9;
    h ^= h >> 32;
    const w0: u32 = @truncate(h);
    const w1: u32 = @truncate(h >> 32);
    const t1 = std.math.tau * (@as(f32, @floatFromInt(w0 & 0xffffff)) / @as(f32, @floatFromInt(@as(u32, 0xffffff))));
    const t2 = std.math.tau * (@as(f32, @floatFromInt(w1 & 0xffffff)) / @as(f32, @floatFromInt(@as(u32, 0xffffff))));
    const ring = @cos(t2);
    const dir = Vec3{ ring * @cos(t1), @sin(t2), ring * @sin(t1) };
    const len = vecLen(dir);
    if (len < 1e-6) return .{ 1, 0, 0 };
    return dir / @as(Vec3, @splat(len));
}

fn collectNeighborsUniqueIntoScratch(
    node: anytype,
    tags: *std.AutoHashMap(u64, void),
    out: *std.ArrayList(u64),
    alloc: std.mem.Allocator,
) !void {
    out.clearRetainingCapacity();
    tags.clearRetainingCapacity();
    var ait = node.adjacency_set.iterator();
    while (ait.next()) |e| {
        const nk = e.key_ptr.*;
        const gop = try tags.getOrPut(nk);
        if (!gop.found_existing) try out.append(alloc, nk);
    }
    var iit = node.incidency_set.iterator();
    while (iit.next()) |e| {
        const nk = e.key_ptr.*;
        const gop = try tags.getOrPut(nk);
        if (!gop.found_existing) try out.append(alloc, nk);
    }
}

fn cross3(a: Vec3, b: Vec3) Vec3 {
    return .{
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    };
}

fn normalizeSafe(v: Vec3) Vec3 {
    const l = vecLen(v);
    if (l < 1e-8) return .{ 1, 0, 0 };
    return v / @as(Vec3, @splat(l));
}

fn basisPerpendicular(outward: Vec3) struct { u: Vec3, w: Vec3 } {
    const o = normalizeSafe(outward);
    const a: Vec3 = if (@abs(o[0]) < 0.9) .{ 1, 0, 0 } else .{ 0, 1, 0 };
    const u = normalizeSafe(cross3(a, o));
    const w = normalizeSafe(cross3(o, u));
    return .{ .u = u, .w = w };
}

/// Four unit directions of a regular tetrahedron (centered at origin), in canonical axes.
fn tetrahedronUnitDirs() [4]Vec3 {
    const r = 1.0 / @sqrt(3.0);
    return .{
        sanitizeVec3(.{ r, r, r }),
        sanitizeVec3(.{ r, -r, -r }),
        sanitizeVec3(.{ -r, r, -r }),
        sanitizeVec3(.{ -r, -r, r }),
    };
}

fn transformDirToBasis(outward: Vec3, u_axis: Vec3, w_axis: Vec3, local: Vec3) Vec3 {
    return sanitizeVec3(
        outward * @as(Vec3, @splat(local[0])) +
            u_axis * @as(Vec3, @splat(local[1])) +
            w_axis * @as(Vec3, @splat(local[2])),
    );
}

/// `m` unit directions around `v`: symmetric in the plane (`u`,`w`) or tetrahedron when `m==4` and not root ring.
fn shellDirections(
    allocator: std.mem.Allocator,
    m: usize,
    outward: Vec3,
    u_axis: Vec3,
    w_axis: Vec3,
    is_component_root: bool,
) ![]Vec3 {
    const dirs = try allocator.alloc(Vec3, m);
    errdefer allocator.free(dirs);

    if (m == 1) {
        dirs[0] = if (is_component_root) normalizeSafe(.{ 1, 0, 0 }) else normalizeSafe(outward);
        return dirs;
    }
    if (m == 2) {
        dirs[0] = normalizeSafe(u_axis);
        dirs[1] = normalizeSafe(-u_axis);
        return dirs;
    }
    if (m == 3) {
        const tau = std.math.tau;
        var i: usize = 0;
        while (i < 3) : (i += 1) {
            const t = tau * (@as(f32, @floatFromInt(i)) / 3.0);
            dirs[i] = normalizeSafe(u_axis * @as(Vec3, @splat(@cos(t))) + w_axis * @as(Vec3, @splat(@sin(t))));
        }
        return dirs;
    }
    if (m == 4) {
        if (is_component_root) {
            const t = tetrahedronUnitDirs();
            for (t, 0..) |loc, i| dirs[i] = normalizeSafe(loc);
        } else {
            const t = tetrahedronUnitDirs();
            for (t, 0..) |loc, i| {
                dirs[i] = normalizeSafe(transformDirToBasis(outward, u_axis, w_axis, loc));
            }
        }
        return dirs;
    }
    const tau = std.math.tau;
    var i: usize = 0;
    while (i < m) : (i += 1) {
        const t = tau * (@as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(m)));
        dirs[i] = normalizeSafe(u_axis * @as(Vec3, @splat(@cos(t))) + w_axis * @as(Vec3, @splat(@sin(t))));
    }
    return dirs;
}

const ShellBasis3 = struct { o: Vec3, ua: Vec3, wa: Vec3 };

fn collectAllKeysSorted(comptime G: type, allocator: std.mem.Allocator, graph: *G) ![]u64 {
    const n = graph.vertices.count();
    const keys = try allocator.alloc(u64, n);
    var it = graph.vertices.iterator();
    var i: usize = 0;
    while (it.next()) |ent| {
        keys[i] = ent.key_ptr.*;
        i += 1;
    }
    std.sort.pdq(u64, keys, {}, std.sort.asc(u64));
    return keys;
}

fn bfsShellSeedAllVertices(comptime G: type, graph: *G, emb: *Embedding, allocator: std.mem.Allocator) !void {
    const sorted_keys = try collectAllKeysSorted(G, allocator, graph);
    defer allocator.free(sorted_keys);

    var parents = std.AutoHashMap(u64, u64).init(allocator);
    defer parents.deinit();

    var queue: std.ArrayList(u64) = .empty;
    defer queue.deinit(allocator);

    var comp_offset: f32 = 0;
    const comp_spacing: f32 = 10.0;

    while (true) {
        var root: ?u64 = null;
        for (sorted_keys) |rk| {
            if (!emb.pos.contains(rk)) {
                root = rk;
                break;
            }
        }
        const r = root orelse break;

        queue.clearRetainingCapacity();
        const origin = Vec3{ comp_offset, 0, 0 };
        try emb.pos.put(r, sanitizeVec3(origin));
        parents.clearRetainingCapacity();
        try queue.append(allocator, r);
        var qh: usize = 0;

        while (qh < queue.items.len) {
            const v = queue.items[qh];
            qh += 1;

            const pos_v = emb.pos.get(v) orelse continue;
            const v_node = graph.getVertex(v) orelse continue;
            try collectNeighborsUniqueIntoScratch(v_node.*, &emb.neighbor_tags, &emb.keys_scratch, allocator);

            var unplaced_n: usize = 0;
            for (emb.keys_scratch.items) |nk| {
                if (!emb.pos.contains(nk)) unplaced_n += 1;
            }
            if (unplaced_n == 0) {
                emb.keys_scratch.clearRetainingCapacity();
                emb.neighbor_tags.clearRetainingCapacity();
                continue;
            }

            const unplaced = try allocator.alloc(u64, unplaced_n);
            defer allocator.free(unplaced);
            var uj: usize = 0;
            for (emb.keys_scratch.items) |nk| {
                if (!emb.pos.contains(nk)) {
                    unplaced[uj] = nk;
                    uj += 1;
                }
            }
            emb.keys_scratch.clearRetainingCapacity();
            emb.neighbor_tags.clearRetainingCapacity();

            std.sort.pdq(u64, unplaced, {}, std.sort.asc(u64));

            const deg_v = degreeOf(v_node.*);
            if (deg_v == 0) continue;
            const dist = 1.0 / @as(f32, @floatFromInt(deg_v));
            const m = unplaced.len;

            const is_component_root = v == r;
            const shell_basis: ShellBasis3 = if (is_component_root) .{
                .o = .{ 0, 0, 1 },
                .ua = .{ 1, 0, 0 },
                .wa = .{ 0, 1, 0 },
            } else blk: {
                const p = parents.get(v).?;
                const pos_p = emb.pos.get(p).?;
                const out = normalizeSafe(pos_v - pos_p);
                const uw = basisPerpendicular(out);
                break :blk .{ .o = out, .ua = uw.u, .wa = uw.w };
            };

            const dirs = try shellDirections(allocator, m, shell_basis.o, shell_basis.ua, shell_basis.wa, is_component_root);
            defer allocator.free(dirs);

            for (unplaced, 0..) |w, di| {
                const off = dirs[di] * @as(Vec3, @splat(dist));
                try emb.pos.put(w, sanitizeVec3(pos_v + off));
                try parents.put(w, v);
                try queue.append(allocator, w);
            }
        }

        comp_offset += comp_spacing;
    }
}

fn relationalSeedForVertex(comptime G: type, graph: *G, k: u64, emb: *Embedding) !Vec3 {
    const alloc = emb.pos.allocator;
    const node = graph.getVertex(k).?;
    try collectNeighborsUniqueIntoScratch(node.*, &emb.neighbor_tags, &emb.keys_scratch, alloc);
    defer {
        emb.keys_scratch.clearRetainingCapacity();
        emb.neighbor_tags.clearRetainingCapacity();
    }

    const scale: f32 = 1.2;
    if (emb.keys_scratch.items.len == 0) return @splat(0);

    var acc = Vec3{ 0, 0, 0 };
    for (emb.keys_scratch.items) |n| {
        const lo = @min(k, n);
        const hi = @max(k, n);
        var d = unitVecFromUndirectedEdge(lo, hi);
        if (k == hi) d = -d;
        acc += d;
    }
    const inv_deg: f32 = 1.0 / @as(f32, @floatFromInt(emb.keys_scratch.items.len));
    var p = acc * @as(Vec3, @splat(scale * inv_deg));
    if (vecLenSq(p) < 1e-10) {
        const n0 = emb.keys_scratch.items[0];
        const lo = @min(k, n0);
        const hi = @max(k, n0);
        var d = unitVecFromUndirectedEdge(lo, hi);
        if (k == hi) d = -d;
        p = d * @as(Vec3, @splat(scale));
    }
    return sanitizeVec3(p);
}

fn packCell(cx: i64, cy: i64, cz: i64) u64 {
    const bias: i64 = 1024;
    const mask: i64 = 0x7ff;
    const ux = @as(u64, @intCast((cx + bias) & mask));
    const uy = @as(u64, @intCast((cy + bias) & mask));
    const uz = @as(u64, @intCast((cz + bias) & mask));
    return (ux << 22) | (uy << 11) | uz;
}

fn scaledCoordToCellIndex(scaled: f32) i32 {
    const t = @floor(scaled);
    if (!std.math.isFinite(t)) return 0;
    const hi: f32 = 2_147_483_000.0;
    const lo: f32 = -2_147_483_000.0;
    const c = if (t > hi) hi else if (t < lo) lo else t;
    return @intFromFloat(c);
}

fn cellCoords(p: Vec3, inv_cell: f32) [3]i32 {
    return .{
        scaledCoordToCellIndex(p[0] * inv_cell),
        scaledCoordToCellIndex(p[1] * inv_cell),
        scaledCoordToCellIndex(p[2] * inv_cell),
    };
}

fn sanitizeVec3(v: Vec3) Vec3 {
    var o = v;
    inline for (0..3) |i| {
        if (!std.math.isFinite(o[i])) o[i] = 0;
    }
    return o;
}

fn clearCellBuckets(emb: *Embedding) void {
    const a = emb.pos.allocator;
    var it = emb.cell_buckets.iterator();
    while (it.next()) |e| {
        e.value_ptr.deinit(a);
    }
    emb.cell_buckets.clearRetainingCapacity();
}

pub const hooks = struct {
    pub fn length_identity(L: f32, ctx: PairCtx) f32 {
        _ = ctx;
        return L;
    }

    pub fn length_shorten_with_degree(L: f32, ctx: PairCtx) f32 {
        const s = @as(f32, @floatFromInt(ctx.deg_from +| ctx.deg_to));
        return L / (1.0 + 0.06 * s);
    }

    pub fn strength_identity(S: f32, ctx: PairCtx) f32 {
        _ = ctx;
        return S;
    }

    pub fn strength_boost_with_degree(S: f32, ctx: PairCtx) f32 {
        const s = @as(f32, @floatFromInt(ctx.deg_from +| ctx.deg_to));
        return S * (1.0 + 0.04 * s);
    }
};

fn applyRepulsionPair(
    force: *std.AutoHashMap(u64, Vec3),
    key_a: u64,
    key_b: u64,
    pu: Vec3,
    pv: Vec3,
    cutoff_sq: f32,
    k_repulse: f32,
) void {
    const delta = pu - pv;
    const dist_sq = vecLenSq(delta);
    if (dist_sq > cutoff_sq or dist_sq < 1e-5) return;
    const dist = @sqrt(dist_sq);
    const dist_eff = @max(dist, 0.08);
    const dir = delta / @as(Vec3, @splat(dist));
    const mag = k_repulse / (dist_eff * dist_eff);
    const f = dir * @as(Vec3, @splat(mag));
    if (force.getPtr(key_a)) |fp| fp.* += f;
    if (force.getPtr(key_b)) |fp| fp.* -= f;
}

pub fn step(
    comptime G: type,
    graph: *G,
    emb: *Embedding,
    hooks_opt: LayoutHooks,
    params: StepParams,
) !void {
    const allocator = emb.pos.allocator;

    // Zero forces in place. Avoid `clearRetainingCapacity` + `put` per key each substep: that
    // rehashes and reinserts every vertex every time (~3 substeps per frame at ipc=100).
    var kit = emb.pos.iterator();
    while (kit.next()) |e| {
        const k = e.key_ptr.*;
        if (emb.force.getPtr(k)) |fp| {
            fp.* = @splat(0);
        } else {
            try emb.force.put(k, @splat(0));
        }
    }

    var uit = graph.vertices.iterator();
    while (uit.next()) |ue| {
        const u = ue.key_ptr.*;
        const u_node = ue.value_ptr.*;
        const du = degreeOf(u_node.*);

        var ait = u_node.adjacency_set.iterator();
        while (ait.next()) |ae| {
            const v = ae.key_ptr.*;
            if (v <= u) continue;
            const v_node = graph.getVertex(v) orelse continue;
            const dv = degreeOf(v_node.*);

            const ctx = PairCtx{
                .key_from = u,
                .key_to = v,
                .deg_from = du,
                .deg_to = dv,
            };

            var ideal = params.base_ideal_length;
            for (hooks_opt.length_chain) |h| {
                ideal = h(ideal, ctx);
            }
            var strength: f32 = 1.0;
            for (hooks_opt.strength_chain) |h| {
                strength = h(strength, ctx);
            }

            const pu = emb.pos.get(u) orelse continue;
            const pv = emb.pos.get(v) orelse continue;
            const delta = pv - pu;
            const dist = vecLen(delta);
            if (dist < 1e-5) continue;
            const dir = delta / @as(Vec3, @splat(dist));
            const mag = params.k_spring * strength * (dist - ideal);
            const f = dir * @as(Vec3, @splat(mag));

            if (emb.force.getPtr(u)) |fp| fp.* += f;
            if (emb.force.getPtr(v)) |fp| fp.* -= f;
        }
    }

    emb.keys_scratch.clearRetainingCapacity();
    kit = emb.pos.iterator();
    while (kit.next()) |e| try emb.keys_scratch.append(allocator, e.key_ptr.*);

    const n = emb.keys_scratch.items.len;
    const cutoff_sq = params.repulse_cutoff * params.repulse_cutoff;
    const use_spatial = params.spatial_repulsion and n >= params.spatial_repulsion_min_n;

    if (use_spatial) {
        const cell_size = params.repulse_cutoff;
        const inv_cell = 1.0 / cell_size;
        clearCellBuckets(emb);

        for (emb.keys_scratch.items, 0..) |key, idx| {
            const p = emb.pos.get(key) orelse continue;
            const c = cellCoords(p, inv_cell);
            const ck = packCell(c[0], c[1], c[2]);
            const gop = try emb.cell_buckets.getOrPut(ck);
            if (!gop.found_existing) gop.value_ptr.* = .{};
            try gop.value_ptr.append(allocator, idx);
        }

        for (emb.keys_scratch.items, 0..) |key_a, idx| {
            const pu = emb.pos.get(key_a) orelse continue;
            const ca = cellCoords(pu, inv_cell);
            var ox: i32 = -1;
            while (ox <= 1) : (ox += 1) {
                var oy: i32 = -1;
                while (oy <= 1) : (oy += 1) {
                    var oz: i32 = -1;
                    while (oz <= 1) : (oz += 1) {
                        const nk = packCell(@as(i64, ca[0]) + ox, @as(i64, ca[1]) + oy, @as(i64, ca[2]) + oz);
                        const list = emb.cell_buckets.get(nk) orelse continue;
                        for (list.items) |jdx| {
                            if (jdx <= idx) continue;
                            const key_b = emb.keys_scratch.items[jdx];
                            const pv = emb.pos.get(key_b) orelse continue;
                            applyRepulsionPair(&emb.force, key_a, key_b, pu, pv, cutoff_sq, params.k_repulse);
                        }
                    }
                }
            }
        }
    } else {
        var i: usize = 0;
        while (i < n) : (i += 1) {
            var j = i + 1;
            while (j < n) : (j += 1) {
                const key_a = emb.keys_scratch.items[i];
                const key_b = emb.keys_scratch.items[j];
                const pu = emb.pos.get(key_a) orelse continue;
                const pv = emb.pos.get(key_b) orelse continue;
                applyRepulsionPair(&emb.force, key_a, key_b, pu, pv, cutoff_sq, params.k_repulse);
            }
        }
    }

    kit = emb.pos.iterator();
    while (kit.next()) |e| {
        const k = e.key_ptr.*;
        const frc = emb.force.get(k) orelse @as(Vec3, @splat(0));
        var disp = sanitizeVec3(frc * @as(Vec3, @splat(params.dt * params.relaxation)));
        const len = vecLen(disp);
        const cap = params.max_displacement;
        if (len > cap and len > 1e-8) {
            disp *= @as(Vec3, @splat(cap / len));
        }
        e.value_ptr.* = sanitizeVec3(e.value_ptr.* + disp);
    }
}

pub fn stepRepeated(
    comptime G: type,
    graph: *G,
    emb: *Embedding,
    hooks_opt: LayoutHooks,
    params: StepParams,
    sub_steps: u32,
) !void {
    var s: u32 = 0;
    while (s < sub_steps) : (s += 1) {
        try step(G, graph, emb, hooks_opt, params);
    }
}

fn testNextU64(c: u64) u64 {
    return c + 1;
}
fn testOrderU64(a: u64, b: u64) std.math.Order {
    return std.math.order(a, b);
}

test "embedding sync adds keys" {
    const Graph = @import("graph.zig").Graph;

    var g = Graph(u64, u32, testNextU64, testOrderU64).init(testing.allocator, 0);
    defer g.deinit();
    try g.putVertexAuto(10);
    try g.putVertexAuto(20);

    var emb = Embedding.init(testing.allocator);
    defer emb.deinit();
    try emb.syncFromGraph(@TypeOf(g), &g);
    try testing.expect(emb.pos.count() == 2);
}

test "relational seed separates edge endpoints" {
    const Graph = @import("graph.zig").Graph;

    var g = Graph(u64, u32, testNextU64, testOrderU64).init(testing.allocator, 0);
    defer g.deinit();
    const a = try g.putVertexAuto(1);
    const b = try g.putVertexAuto(2);
    try g.addEdge(a, b);

    var emb = Embedding.init(testing.allocator);
    defer emb.deinit();
    try emb.syncFromGraph(@TypeOf(g), &g);
    const pa = emb.pos.get(a).?;
    const pb = emb.pos.get(b).?;
    try testing.expect(vecLenSq(pa - pb) > 1e-6);
}

test "layout step runs without panic" {
    const Graph = @import("graph.zig").Graph;

    var g = Graph(u64, u32, testNextU64, testOrderU64).init(testing.allocator, 0);
    defer g.deinit();
    _ = try g.putVertexAuto(1);
    _ = try g.putVertexAuto(2);
    try g.addEdge(0, 1);

    var emb = Embedding.init(testing.allocator);
    defer emb.deinit();
    try emb.syncFromGraph(@TypeOf(g), &g);

    const hk: LayoutHooks = .{
        .length_chain = &.{ hooks.length_identity, hooks.length_shorten_with_degree },
        .strength_chain = &.{ hooks.strength_identity, hooks.strength_boost_with_degree },
    };
    try step(@TypeOf(g), &g, &emb, hk, .{});
    try testing.expect(emb.pos.get(0) != null);
}

test "spatial repulsion path with many nodes" {
    const Graph = @import("graph.zig").Graph;

    var g = Graph(u64, u32, testNextU64, testOrderU64).init(testing.allocator, 0);
    defer g.deinit();
    for (0..100) |_| _ = try g.putVertexAuto(0);

    var emb = Embedding.init(testing.allocator);
    defer emb.deinit();
    try emb.syncFromGraph(@TypeOf(g), &g);

    const hk: LayoutHooks = .{
        .length_chain = &.{hooks.length_identity},
        .strength_chain = &.{hooks.strength_identity},
    };
    try step(@TypeOf(g), &g, &emb, hk, .{ .spatial_repulsion_min_n = 32 });
    try testing.expect(emb.pos.count() == 100);
}

test "packCell avoids i32 overflow on bias and neighbors" {
    _ = packCell(std.math.maxInt(i32), std.math.maxInt(i32), std.math.maxInt(i32));
    _ = packCell(@as(i64, std.math.maxInt(i32)) + 1, 0, 0);
    _ = packCell(std.math.minInt(i32), 0, 0);
}

test "spatial repulsion tolerates huge or non-finite coordinates" {
    const Graph = @import("graph.zig").Graph;

    var g = Graph(u64, u32, testNextU64, testOrderU64).init(testing.allocator, 0);
    defer g.deinit();
    for (0..100) |_| _ = try g.putVertexAuto(0);

    var emb = Embedding.init(testing.allocator);
    defer emb.deinit();
    try emb.syncFromGraph(@TypeOf(g), &g);

    var pit = emb.pos.iterator();
    const ent = pit.next() orelse unreachable;
    ent.value_ptr.* = @Vector(3, f32){ 1.0e12, -1.0e12, std.math.inf(f32) };

    const hk: LayoutHooks = .{
        .length_chain = &.{hooks.length_identity},
        .strength_chain = &.{hooks.strength_identity},
    };
    try step(@TypeOf(g), &g, &emb, hk, .{ .spatial_repulsion_min_n = 32 });
    try testing.expect(emb.pos.count() == 100);
}
