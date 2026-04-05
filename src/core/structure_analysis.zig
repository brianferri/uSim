//! Emergent structure hints from the **relational embedding** (3D) plus **weak** graph connectivity.
//! Radial shells summarize distance-from-centroid mass (often reads as concentric rings in the view).
//! k-means is a cheap spatial partition; weak components ignore edge direction.
const std = @import("std");
const testing = std.testing;
const RelationalLayout = @import("RelationalLayout.zig");
const Vec3 = RelationalLayout.Vec3;

pub const FormatOptions = struct {
    shell_bins: usize = 24,
    /// Upper cap; actual k is `min(k_clusters, n)`.
    k_clusters: usize = 8,
    k_means_iters: usize = 18,
};

fn vecLenSq(v: Vec3) f32 {
    return @reduce(.Add, v * v);
}

fn vecLen(v: Vec3) f32 {
    return @sqrt(vecLenSq(v));
}

fn centroidOf(points: []const Vec3) Vec3 {
    if (points.len == 0) return @splat(0);
    var s = Vec3{ 0, 0, 0 };
    for (points) |p| s += p;
    return s / @as(Vec3, @splat(@as(f32, @floatFromInt(points.len))));
}

pub fn graphKeysSorted(comptime G: type, allocator: std.mem.Allocator, graph: *G) ![]u64 {
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

fn positionsForKeys(comptime G: type, graph: *G, emb: *const RelationalLayout.Embedding, keys: []const u64, allocator: std.mem.Allocator) ![]Vec3 {
    const pts = try allocator.alloc(Vec3, keys.len);
    for (keys, 0..) |k, j| {
        _ = graph.getVertex(k) orelse return error.MissingVertex;
        pts[j] = emb.pos.get(k) orelse Vec3{ 0, 0, 0 };
    }
    return pts;
}

const Dsu = struct {
    parent: []usize,
    size: []usize,

    fn init(allocator: std.mem.Allocator, n: usize) !Dsu {
        const parent = try allocator.alloc(usize, n);
        const size = try allocator.alloc(usize, n);
        for (0..n) |i| {
            parent[i] = i;
            size[i] = 1;
        }
        return .{ .parent = parent, .size = size };
    }

    fn deinit(self: *Dsu, allocator: std.mem.Allocator) void {
        allocator.free(self.parent);
        allocator.free(self.size);
    }

    fn find(self: *Dsu, x: usize) usize {
        var i = x;
        while (self.parent[i] != i) i = self.parent[i];
        var j = x;
        while (self.parent[j] != j) {
            const n = self.parent[j];
            self.parent[j] = i;
            j = n;
        }
        return i;
    }

    fn unite(self: *Dsu, a: usize, b: usize) void {
        var ra = self.find(a);
        var rb = self.find(b);
        if (ra == rb) return;
        if (self.size[ra] < self.size[rb]) std.mem.swap(usize, &ra, &rb);
        self.parent[rb] = ra;
        self.size[ra] += self.size[rb];
    }
};

pub fn weaklyConnectedComponentStats(comptime G: type, allocator: std.mem.Allocator, graph: *G) !struct {
    n_components: usize,
    largest: usize,
    second: usize,
} {
    const keys = try graphKeysSorted(G, allocator, graph);
    defer allocator.free(keys);
    if (keys.len == 0) return .{ .n_components = 0, .largest = 0, .second = 0 };

    var idx_of = std.AutoHashMap(u64, usize).init(allocator);
    defer idx_of.deinit();
    for (keys, 0..) |k, i| try idx_of.put(k, i);

    var dsu = try Dsu.init(allocator, keys.len);
    defer dsu.deinit(allocator);

    for (keys) |u| {
        const ui = idx_of.get(u).?;
        const node = graph.getVertex(u) orelse continue;
        var ait = node.adjacency_set.iterator();
        while (ait.next()) |e| {
            const v = e.key_ptr.*;
            if (idx_of.get(v)) |vi| dsu.unite(ui, vi);
        }
        var iit = node.incidency_set.iterator();
        while (iit.next()) |e| {
            const v = e.key_ptr.*;
            if (idx_of.get(v)) |vi| dsu.unite(ui, vi);
        }
    }

    var hist = std.AutoHashMap(usize, usize).init(allocator);
    defer hist.deinit();
    for (0..keys.len) |i| {
        const r = dsu.find(i);
        const gop = try hist.getOrPutValue(r, 0);
        gop.value_ptr.* += 1;
    }

    var largest: usize = 0;
    var second: usize = 0;
    var it = hist.valueIterator();
    while (it.next()) |sz| {
        const s = sz.*;
        if (s > largest) {
            second = largest;
            largest = s;
        } else if (s > second) {
            second = s;
        }
    }

    return .{
        .n_components = hist.count(),
        .largest = largest,
        .second = second,
    };
}

/// One DSU root index per `keys` entry (same order). Caller frees with `allocator`.
pub fn weaklyConnectedRootPerKey(comptime G: type, allocator: std.mem.Allocator, graph: *G, keys: []const u64) ![]usize {
    if (keys.len == 0) return allocator.alloc(usize, 0);

    var idx_of = std.AutoHashMap(u64, usize).init(allocator);
    defer idx_of.deinit();
    for (keys, 0..) |k, i| try idx_of.put(k, i);

    var dsu = try Dsu.init(allocator, keys.len);
    defer dsu.deinit(allocator);

    for (keys) |u| {
        const ui = idx_of.get(u).?;
        const node = graph.getVertex(u) orelse continue;
        var ait = node.adjacency_set.iterator();
        while (ait.next()) |e| {
            const v = e.key_ptr.*;
            if (idx_of.get(v)) |vi| dsu.unite(ui, vi);
        }
        var iit = node.incidency_set.iterator();
        while (iit.next()) |e| {
            const v = e.key_ptr.*;
            if (idx_of.get(v)) |vi| dsu.unite(ui, vi);
        }
    }

    const roots = try allocator.alloc(usize, keys.len);
    for (0..keys.len) |i| roots[i] = dsu.find(i);
    return roots;
}

/// Like `weaklyConnectedRootPerKey`, but an undirected edge **u--v** merges components only when
/// `unify_edge(graph, u, v)` is true (viz / domain filter on top of raw adjacency).
pub fn weaklyConnectedRootPerKeyFiltered(
    comptime G: type,
    comptime unify_edge: fn (*G, u64, u64) bool,
    allocator: std.mem.Allocator,
    graph: *G,
    keys: []const u64,
) ![]usize {
    if (keys.len == 0) return allocator.alloc(usize, 0);

    var idx_of = std.AutoHashMap(u64, usize).init(allocator);
    defer idx_of.deinit();
    for (keys, 0..) |k, i| try idx_of.put(k, i);

    var dsu = try Dsu.init(allocator, keys.len);
    defer dsu.deinit(allocator);

    for (keys) |u| {
        const ui = idx_of.get(u).?;
        const node = graph.getVertex(u) orelse continue;
        var ait = node.adjacency_set.iterator();
        while (ait.next()) |e| {
            const v = e.key_ptr.*;
            if (idx_of.get(v)) |vi| {
                if (unify_edge(graph, u, v)) dsu.unite(ui, vi);
            }
        }
        var iit = node.incidency_set.iterator();
        while (iit.next()) |e| {
            const v = e.key_ptr.*;
            if (idx_of.get(v)) |vi| {
                if (unify_edge(graph, u, v)) dsu.unite(ui, vi);
            }
        }
    }

    const roots = try allocator.alloc(usize, keys.len);
    for (0..keys.len) |i| roots[i] = dsu.find(i);
    return roots;
}

/// Runtime-function-pointer variant of `weaklyConnectedRootPerKeyFiltered`.
/// `ctx` is passed to `unify_edge` so callers can recover a layer object (vtable + fieldParentPtr).
pub fn weaklyConnectedRootPerKeyFilteredDyn(
    comptime G: type,
    comptime Ctx: type,
    allocator: std.mem.Allocator,
    graph: *G,
    keys: []const u64,
    ctx: *Ctx,
    unify_edge: *const fn (*Ctx, *G, u64, u64) bool,
) ![]usize {
    if (keys.len == 0) return allocator.alloc(usize, 0);

    var idx_of = std.AutoHashMap(u64, usize).init(allocator);
    defer idx_of.deinit();
    for (keys, 0..) |k, i| try idx_of.put(k, i);

    var dsu = try Dsu.init(allocator, keys.len);
    defer dsu.deinit(allocator);

    for (keys) |u| {
        const ui = idx_of.get(u).?;
        const node = graph.getVertex(u) orelse continue;
        var ait = node.adjacency_set.iterator();
        while (ait.next()) |e| {
            const v = e.key_ptr.*;
            if (idx_of.get(v)) |vi| {
                if (unify_edge(ctx, graph, u, v)) dsu.unite(ui, vi);
            }
        }
        var iit = node.incidency_set.iterator();
        while (iit.next()) |e| {
            const v = e.key_ptr.*;
            if (idx_of.get(v)) |vi| {
                if (unify_edge(ctx, graph, u, v)) dsu.unite(ui, vi);
            }
        }
    }

    const roots = try allocator.alloc(usize, keys.len);
    for (0..keys.len) |i| roots[i] = dsu.find(i);
    return roots;
}

pub const Snapshot = struct {
    centroid: Vec3,
    r_lo: f32,
    r_hi: f32,
    shell_nb: usize,
    shell_counts: []usize,
    wcc_n: usize,
    wcc_largest: usize,
    wcc_second: usize,
    k: usize,
    k_sizes: []usize,
    k_inertia: f32,
    alloc: std.mem.Allocator,

    pub fn deinit(self: *Snapshot) void {
        self.alloc.free(self.shell_counts);
        self.alloc.free(self.k_sizes);
    }
};

pub fn formatShellBlock(allocator: std.mem.Allocator, snap: *const Snapshot) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer aw.deinit();
    const w = &aw.writer;
    try w.print("Radius range [{d:.4}, {d:.4}] world units ({d} bins)\n", .{ snap.r_lo, snap.r_hi, snap.shell_nb });
    var max_c: usize = 1;
    for (snap.shell_counts) |bc| max_c = @max(max_c, bc);
    for (snap.shell_counts, 0..) |bc, bi| {
        const bar_w: usize = 40;
        const nhash = if (max_c == 0) 0 else @min(bar_w, bc * bar_w / max_c);
        try w.print("  {d:2}: {d:4} |", .{ bi, bc });
        var h: usize = 0;
        while (h < nhash) : (h += 1) try w.print("#", .{});
        try w.print("\n", .{});
    }
    return try aw.toOwnedSlice();
}

pub fn formatKMeansBlock(allocator: std.mem.Allocator, snap: *const Snapshot, max_iters: usize) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer aw.deinit();
    const w = &aw.writer;
    try w.print("k={d}, up to {d} iterations, inertia ~{d:.4}\n", .{ snap.k, max_iters, snap.k_inertia });
    for (snap.k_sizes, 0..) |sz, j| {
        try w.print("  cluster {d}: {d} vertices\n", .{ j, sz });
    }
    return try aw.toOwnedSlice();
}

pub fn computeStructureSnapshot(
    comptime G: type,
    allocator: std.mem.Allocator,
    graph: *G,
    emb: *const RelationalLayout.Embedding,
    opts: FormatOptions,
) !Snapshot {
    const keys = try graphKeysSorted(G, allocator, graph);
    defer allocator.free(keys);
    if (keys.len == 0) {
        return Snapshot{
            .centroid = @splat(0),
            .r_lo = 0,
            .r_hi = 0,
            .shell_nb = 0,
            .shell_counts = try allocator.alloc(usize, 0),
            .wcc_n = 0,
            .wcc_largest = 0,
            .wcc_second = 0,
            .k = 0,
            .k_sizes = try allocator.alloc(usize, 0),
            .k_inertia = 0,
            .alloc = allocator,
        };
    }

    const pts = try positionsForKeys(G, graph, emb, keys, allocator);
    defer allocator.free(pts);

    const c = centroidOf(pts);
    const nb = @max(4, opts.shell_bins);
    const bin_counts = try allocator.alloc(usize, nb);
    var r_lo: f32 = undefined;
    var r_hi: f32 = undefined;
    radialShellFill(c, pts, bin_counts, &r_lo, &r_hi);

    const wcc = try weaklyConnectedComponentStats(G, allocator, graph);

    const kk = @min(opts.k_clusters, @max(1, pts.len));
    const sizes = try allocator.alloc(usize, kk);
    var inertia: f32 = undefined;
    try kMeansRun(allocator, pts, kk, opts.k_means_iters, sizes, &inertia);

    return Snapshot{
        .centroid = c,
        .r_lo = r_lo,
        .r_hi = r_hi,
        .shell_nb = nb,
        .shell_counts = bin_counts,
        .wcc_n = wcc.n_components,
        .wcc_largest = wcc.largest,
        .wcc_second = wcc.second,
        .k = kk,
        .k_sizes = sizes,
        .k_inertia = inertia,
        .alloc = allocator,
    };
}

fn radialShellFill(c: Vec3, points: []const Vec3, bin_counts: []usize, r_min: *f32, r_max: *f32) void {
    @memset(bin_counts, 0);
    if (points.len == 0) {
        r_min.* = 0;
        r_max.* = 0;
        return;
    }

    var lo: f32 = std.math.floatMax(f32);
    var hi: f32 = 0;
    for (points) |p| {
        const r = vecLen(p - c);
        lo = @min(lo, r);
        hi = @max(hi, r);
    }
    r_min.* = lo;
    r_max.* = hi;
    const span = hi - lo;
    const nb = bin_counts.len;
    if (span < 1e-8) {
        bin_counts[0] = points.len;
        return;
    }
    const inv = @as(f32, @floatFromInt(nb)) / span;
    for (points) |p| {
        const r = vecLen(p - c);
        var b: usize = @intFromFloat((r - lo) * inv);
        if (b >= nb) b = nb - 1;
        bin_counts[b] += 1;
    }
}

fn kMeansAssignInertia(points: []const Vec3, centroids: []const Vec3, assignment: []usize) f32 {
    var inertia: f32 = 0;
    for (points, 0..) |p, i| {
        var best: usize = 0;
        var best_d: f32 = std.math.floatMax(f32);
        for (centroids, 0..) |c, j| {
            const d = vecLenSq(p - c);
            if (d < best_d) {
                best_d = d;
                best = j;
            }
        }
        assignment[i] = best;
        inertia += best_d;
    }
    return inertia;
}

fn kMeansUpdate(points: []const Vec3, assignment: []const usize, centroids: []Vec3, counts: []usize) bool {
    @memset(counts, 0);
    for (centroids) |*c| c.* = @splat(0);
    for (points, assignment) |p, a| {
        centroids[a] += p;
        counts[a] += 1;
    }
    var moved = false;
    for (centroids, counts) |*c, cnt| {
        if (cnt == 0) continue;
        const newc = c.* / @as(Vec3, @splat(@as(f32, @floatFromInt(cnt))));
        if (vecLenSq(newc - c.*) > 1e-10) moved = true;
        c.* = newc;
    }
    return moved;
}

/// Deterministic seeds: evenly spaced samples along vertex sort order.
fn kMeansRun(
    allocator: std.mem.Allocator,
    points: []const Vec3,
    k: usize,
    max_iter: usize,
    cluster_sizes: []usize,
    out_inertia: *f32,
) !void {
    @memset(cluster_sizes, 0);
    out_inertia.* = 0;
    if (points.len == 0 or k == 0) return;

    const kk = @min(k, points.len);
    var centroids = try allocator.alloc(Vec3, kk);
    defer allocator.free(centroids);
    const assignment = try allocator.alloc(usize, points.len);
    defer allocator.free(assignment);
    const counts = try allocator.alloc(usize, kk);
    defer allocator.free(counts);

    if (kk == 1) {
        centroids[0] = centroidOf(points);
        _ = kMeansAssignInertia(points, centroids, assignment);
        for (assignment) |a| cluster_sizes[a] += 1;
        out_inertia.* = kMeansAssignInertia(points, centroids, assignment);
        return;
    }

    const step = @max(1, points.len / kk);
    var s: usize = 0;
    var ci: usize = 0;
    while (ci < kk) : (ci += 1) {
        centroids[ci] = points[@min(s, points.len - 1)];
        s += step;
    }

    var it: usize = 0;
    while (it < max_iter) : (it += 1) {
        _ = kMeansAssignInertia(points, centroids, assignment);
        const moved = kMeansUpdate(points, assignment, centroids, counts);
        if (!moved) break;
    }
    out_inertia.* = kMeansAssignInertia(points, centroids, assignment);
    for (assignment) |a| cluster_sizes[a] += 1;
}

pub fn formatStructureReport(
    comptime G: type,
    allocator: std.mem.Allocator,
    graph: *G,
    emb: *const RelationalLayout.Embedding,
    opts: FormatOptions,
) ![]u8 {
    var snap = try computeStructureSnapshot(G, allocator, graph, emb, opts);
    defer snap.deinit();

    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer aw.deinit();
    const w = &aw.writer;

    if (graph.vertices.count() == 0) {
        try w.print("No vertices.\n", .{});
        return try aw.toOwnedSlice();
    }

    const c = snap.centroid;
    try w.print("Embedding centroid (world): ({d:.3}, {d:.3}, {d:.3})\n", .{ c[0], c[1], c[2] });

    try w.print("Radial shells (distance from centroid, {d} bins): r in [{d:.4}, {d:.4}]\n", .{ snap.shell_nb, snap.r_lo, snap.r_hi });

    var max_c: usize = 1;
    for (snap.shell_counts) |bc| max_c = @max(max_c, bc);
    for (snap.shell_counts, 0..) |bc, bi| {
        const bar_w: usize = 40;
        const nhash = if (max_c == 0) 0 else @min(bar_w, bc * bar_w / max_c);
        try w.print("  {d:2}: {d:4} |", .{ bi, bc });
        var h: usize = 0;
        while (h < nhash) : (h += 1) try w.print("#", .{});
        try w.print("\n", .{});
    }

    try w.print(
        "\nWeak components (undirected view): {d}  largest {d}  second {d}\n",
        .{ snap.wcc_n, snap.wcc_largest, snap.wcc_second },
    );

    try w.print("\nk-means spatial (k={d}, iters<={d}) inertia~{d:.4}\n", .{ snap.k, opts.k_means_iters, snap.k_inertia });
    for (snap.k_sizes, 0..) |sz, j| {
        try w.print("  cluster {d}: {d} vertices\n", .{ j, sz });
    }

    try w.print(
        "\n(Heuristic only: layout is a viewport construct, not a physical observable.)\n",
        .{},
    );

    return try aw.toOwnedSlice();
}

fn testNextU64_sa(x: u64) u64 {
    return x + 1;
}
fn testOrderU64_sa(a: u64, b: u64) std.math.Order {
    return std.math.order(a, b);
}

test "weaklyConnected two islands" {
    const Graph = @import("graph.zig").Graph;
    const P = struct {
        has_color: bool = false,
        charge: f64 = 0,
        mass: f64 = 0,
        energy: f64 = 0,
        spin: f64 = 0,
        b3: i32 = 0,
        L_e: i32 = 0,
        L_mu: i32 = 0,
        L_tau: i32 = 0,
    };
    var g = Graph(u64, P, testNextU64_sa, testOrderU64_sa).init(testing.allocator, 0);
    defer g.deinit();
    try g.putVertex(0, .{});
    try g.putVertex(1, .{});
    try g.putVertex(2, .{});
    try g.addEdge(0, 1);

    const s = try weaklyConnectedComponentStats(@TypeOf(g), testing.allocator, &g);
    try testing.expectEqual(@as(usize, 2), s.n_components);
    try testing.expectEqual(@as(usize, 2), s.largest);
    try testing.expectEqual(@as(usize, 1), s.second);
}

fn normalizeOrX(v: Vec3) Vec3 {
    const l = vecLen(v);
    if (l < 1e-8) return .{ 1, 0, 0 };
    return v / @as(Vec3, @splat(l));
}

test "weaklyConnectedRootPerKey matches component count" {
    const Graph = @import("graph.zig").Graph;

    var g = Graph(u64, u32, testNextU64_sa, testOrderU64_sa).init(testing.allocator, 0);
    defer g.deinit();
    try g.putVertex(0, 0);
    try g.putVertex(1, 0);
    try g.putVertex(2, 0);
    try g.addEdge(0, 1);

    const keys = try graphKeysSorted(@TypeOf(g), testing.allocator, &g);
    defer testing.allocator.free(keys);
    const roots = try weaklyConnectedRootPerKey(@TypeOf(g), testing.allocator, &g, keys);
    defer testing.allocator.free(roots);

    try testing.expectEqual(@as(usize, 3), roots.len);
    try testing.expect(roots[0] == roots[1]);
    try testing.expect(roots[2] != roots[0]);
}

test "weaklyConnectedRootPerKeyFiltered can refuse edges" {
    const Graph = @import("graph.zig").Graph;
    const GraphType = Graph(u64, u32, testNextU64_sa, testOrderU64_sa);
    var g = GraphType.init(testing.allocator, 0);
    defer g.deinit();
    try g.putVertex(0, 0);
    try g.putVertex(1, 0);
    try g.addEdge(0, 1);

    const keys = try graphKeysSorted(GraphType, testing.allocator, &g);
    defer testing.allocator.free(keys);

    const unifyNever = struct {
        fn f(_: *GraphType, _: u64, _: u64) bool {
            return false;
        }
    }.f;

    const roots = try weaklyConnectedRootPerKeyFiltered(GraphType, unifyNever, testing.allocator, &g, keys);
    defer testing.allocator.free(roots);
    try testing.expect(roots[0] != roots[1]);
}

test "radialShell single radius" {
    const c = Vec3{ 0, 0, 0 };
    var pts: [100]Vec3 = undefined;
    for (&pts) |*p| p.* = normalizeOrX(Vec3{ 1, 0, 0 }) * @as(Vec3, @splat(2.0));

    var bins: [8]usize = undefined;
    var r_lo: f32 = undefined;
    var r_hi: f32 = undefined;
    radialShellFill(c, &pts, &bins, &r_lo, &r_hi);
    var sum: usize = 0;
    for (bins) |b| sum += b;
    try testing.expectEqual(@as(usize, 100), sum);
    try testing.expect(r_hi - r_lo < 0.01);
}
