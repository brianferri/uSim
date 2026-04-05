//! Hadron cluster layer: baryon triplets, meson pairs, lone charged pions.
//! `Particle.clusters` is the model’s cluster-layer export for `visualizations/clusters/manifest.zig`.

const std = @import("std");
const uSim = @import("usim");
const Mdl = @import("../../main.zig");
const hz = @import("types.zig");
const rules = @import("rules.zig");

const Graph = Mdl.Graph;
const Type = Mdl.Type;

const Cv = uSim.cluster_viz;
const Iface = Cv.ClusterLayerInterface(Graph, Mdl);

pub const ClusterVizClass = hz.ClusterVizClass;
pub const HadronVizPiece = hz.HadronVizPiece;
pub const ClusterVizPartitionResult = hz.ClusterVizPartitionResult;

/// Max |V| for O(n³) triplet enumeration; larger components skip triplet search.
pub const partition_max_bruteforce_n: usize = 22;

fn tripletClassPriority(c: ClusterVizClass) u8 {
    return switch (c) {
        .proton_like => 0,
        .neutron_like => 1,
        .other_baryon => 2,
        .antibaryon => 3,
        else => 255,
    };
}

/// Classify a **minimal** vertex set as a drawn hadron aggregate, else null.
pub fn classifyComponent(graph: *Graph, members: []const u64) ?ClusterVizClass {
    if (members.len == 0) return null;

    if (members.len == 1) {
        const node = graph.getVertex(members[0]) orelse return null;
        return switch (Type.fromStruct(&node.data)) {
            .PionPlus, .PionMinus => .single_meson_vertex,
            else => null,
        };
    }

    if (members.len == 2) {
        const na = graph.getVertex(members[0]) orelse return null;
        const nb = graph.getVertex(members[1]) orelse return null;
        const ta = Type.fromStruct(&na.data);
        const tb = Type.fromStruct(&nb.data);
        if (ta == .Unknown or tb == .Unknown) return null;
        if (rules.typeExcludedFromHadronCluster(ta) or rules.typeExcludedFromHadronCluster(tb)) return null;
        if ((rules.isQuarkFlavor(ta) and rules.isAntiquarkFlavor(tb)) or
            (rules.isQuarkFlavor(tb) and rules.isAntiquarkFlavor(ta)))
        {
            return .meson;
        }
        return null;
    }

    if (members.len == 3) {
        var b3sum: i32 = 0;
        var types: [3]Type = undefined;
        for (members, 0..) |k, i| {
            const node = graph.getVertex(k) orelse return null;
            types[i] = Type.fromStruct(&node.data);
            if (types[i] == .Unknown) return null;
            if (rules.typeExcludedFromHadronCluster(types[i])) return null;
            b3sum += node.data.b3;
        }
        if (b3sum == 3) {
            if (!rules.isQuarkFlavor(types[0]) or !rules.isQuarkFlavor(types[1]) or
                !rules.isQuarkFlavor(types[2])) return null;
            var nu: u8 = 0;
            var nd: u8 = 0;
            for (types) |t| {
                switch (t) {
                    .UpQuark => nu += 1,
                    .DownQuark => nd += 1,
                    else => {},
                }
            }
            if (nu == 2 and nd == 1) return .proton_like;
            if (nu == 1 and nd == 2) return .neutron_like;
            return .other_baryon;
        }
        if (b3sum == -3) {
            if (!rules.isAntiquarkFlavor(types[0]) or !rules.isAntiquarkFlavor(types[1]) or
                !rules.isAntiquarkFlavor(types[2])) return null;
            return .antibaryon;
        }
        return null;
    }

    return null;
}

/// Greedy disjoint packing: baryons, meson pairs, lone charged pions; rest in `residual`.
pub fn partitionWeakComponent(
    allocator: std.mem.Allocator,
    graph: *Graph,
    members: []const u64,
) !ClusterVizPartitionResult {
    if (members.len == 0) {
        return .{
            .pieces = try allocator.alloc(HadronVizPiece, 0),
            .residual = try allocator.alloc(u64, 0),
        };
    }
    if (members.len == 1) {
        const pieces = try allocator.alloc(HadronVizPiece, 0);
        errdefer allocator.free(pieces);
        const residual = try allocator.dupe(u64, members);
        return .{ .pieces = pieces, .residual = residual };
    }

    var used = try allocator.alloc(bool, members.len);
    defer allocator.free(used);
    @memset(used, false);

    var pieces_al: std.ArrayList(HadronVizPiece) = .empty;
    errdefer {
        for (pieces_al.items) |p| allocator.free(p.keys);
        pieces_al.deinit(allocator);
    }

    const TripleCand = struct { a: usize, b: usize, c: usize, class: ClusterVizClass };

    if (members.len >= 3 and members.len <= partition_max_bruteforce_n) {
        var cand: std.ArrayList(TripleCand) = .empty;
        defer cand.deinit(allocator);

        const n = members.len;
        var i: usize = 0;
        while (i < n) : (i += 1) {
            var j = i + 1;
            while (j < n) : (j += 1) {
                var k = j + 1;
                while (k < n) : (k += 1) {
                    const buf = [_]u64{ members[i], members[j], members[k] };
                    if (classifyComponent(graph, &buf)) |cls| {
                        switch (cls) {
                            .proton_like, .neutron_like, .other_baryon, .antibaryon => {
                                try cand.append(allocator, .{
                                    .a = i,
                                    .b = j,
                                    .c = k,
                                    .class = cls,
                                });
                            },
                            else => {},
                        }
                    }
                }
            }
        }

        std.sort.pdq(TripleCand, cand.items, {}, struct {
            fn less(_: void, x: TripleCand, y: TripleCand) bool {
                const px = tripletClassPriority(x.class);
                const py = tripletClassPriority(y.class);
                if (px != py) return px < py;
                if (x.a != y.a) return x.a < y.a;
                if (x.b != y.b) return x.b < y.b;
                return x.c < y.c;
            }
        }.less);

        for (cand.items) |t| {
            if (used[t.a] or used[t.b] or used[t.c]) continue;
            used[t.a] = true;
            used[t.b] = true;
            used[t.c] = true;
            const keys_copy = try allocator.dupe(u64, &[_]u64{
                members[t.a],
                members[t.b],
                members[t.c],
            });
            errdefer allocator.free(keys_copy);
            try pieces_al.append(allocator, .{ .keys = keys_copy, .class = t.class });
        }
    }

    if (members.len >= 2) {
        const PairCand = struct { a: usize, b: usize };
        var cand2: std.ArrayList(PairCand) = .empty;
        defer cand2.deinit(allocator);

        const n = members.len;
        var ii: usize = 0;
        while (ii < n) : (ii += 1) {
            if (used[ii]) continue;
            var jj = ii + 1;
            while (jj < n) : (jj += 1) {
                if (used[jj]) continue;
                const buf = [_]u64{ members[ii], members[jj] };
                if (classifyComponent(graph, &buf)) |cls| {
                    if (cls == .meson) try cand2.append(allocator, .{ .a = ii, .b = jj });
                }
            }
        }

        std.sort.pdq(PairCand, cand2.items, {}, struct {
            fn less(_: void, x: PairCand, y: PairCand) bool {
                if (x.a != y.a) return x.a < y.a;
                return x.b < y.b;
            }
        }.less);

        for (cand2.items) |t| {
            if (used[t.a] or used[t.b]) continue;
            used[t.a] = true;
            used[t.b] = true;
            const keys_copy = try allocator.dupe(u64, &[_]u64{
                members[t.a],
                members[t.b],
            });
            errdefer allocator.free(keys_copy);
            try pieces_al.append(allocator, .{ .keys = keys_copy, .class = .meson });
        }
    }

    var si: usize = 0;
    while (si < members.len) : (si += 1) {
        if (used[si]) continue;
        const buf = [_]u64{members[si]};
        if (classifyComponent(graph, &buf)) |cls| {
            if (cls == .single_meson_vertex) {
                used[si] = true;
                const keys_copy = try allocator.dupe(u64, &[_]u64{members[si]});
                errdefer allocator.free(keys_copy);
                try pieces_al.append(allocator, .{
                    .keys = keys_copy,
                    .class = .single_meson_vertex,
                });
            }
        }
    }

    var res_count: usize = 0;
    for (used) |u| {
        if (!u) res_count += 1;
    }

    var res = try allocator.alloc(u64, res_count);
    errdefer allocator.free(res);
    var ri: usize = 0;
    for (members, 0..) |k, idx| {
        if (!used[idx]) {
            res[ri] = k;
            ri += 1;
        }
    }

    return .{
        .pieces = try pieces_al.toOwnedSlice(allocator),
        .residual = res,
    };
}

fn partitionLayerImpl(
    allocator: std.mem.Allocator,
    graph: *Graph,
    members: []const u64,
) !Cv.ClusterLayerPartitionResult {
    var base = try partitionWeakComponent(allocator, graph, members);
    errdefer base.deinit(allocator);

    var out: std.ArrayList(Cv.ClusterLayerPiece) = .empty;
    errdefer {
        for (out.items) |p| allocator.free(p.keys);
        out.deinit(allocator);
    }

    for (base.pieces) |p| {
        try out.append(allocator, .{
            .keys = try allocator.dupe(u64, p.keys),
            .class_id = @intCast(@intFromEnum(p.class)),
        });
    }

    const residual = try allocator.dupe(u64, base.residual);
    return .{ .pieces = try out.toOwnedSlice(allocator), .residual = residual };
}

/// Hadron cluster layer object (`interface` + vtable; callbacks use `@fieldParentPtr`).
const HadronClusterLayer = struct {
    interface: Iface,

    const vtable: Iface.VTable = .{
        .id = "hadron",
        .partition_weak_component = partitionCb,
        .class_name = classNameCb,
        .class_color = classColorCb,
        .include_particle = includeCb,
        .unites_edge = unitesCb,
        .classify_residual = classifyResidualCb,
    };

    var singleton: HadronClusterLayer = .{
        .interface = .{ .vtable = &vtable },
    };

    fn partitionCb(
        iface: *Iface,
        allocator: std.mem.Allocator,
        graph: *Graph,
        members: []const u64,
    ) !Cv.ClusterLayerPartitionResult {
        const self: *HadronClusterLayer = @alignCast(@fieldParentPtr("interface", iface));
        _ = self;
        return partitionLayerImpl(allocator, graph, members);
    }

    fn classNameCb(iface: *Iface, class_id: u16) []const u8 {
        const self: *HadronClusterLayer = @alignCast(@fieldParentPtr("interface", iface));
        _ = self;
        const cls: ClusterVizClass = @enumFromInt(class_id);
        return @tagName(cls);
    }

    fn classColorCb(iface: *Iface, class_id: u16) Cv.ClusterVizColor {
        const self: *HadronClusterLayer = @alignCast(@fieldParentPtr("interface", iface));
        _ = self;
        const cls: ClusterVizClass = @enumFromInt(class_id);
        return switch (cls) {
            .proton_like => .{ .r = 120, .g = 170, .b = 255, .a = 255 },
            .neutron_like => .{ .r = 200, .g = 200, .b = 210, .a = 255 },
            .other_baryon => .{ .r = 200, .g = 140, .b = 255, .a = 255 },
            .antibaryon => .{ .r = 255, .g = 160, .b = 90, .a = 255 },
            .meson => .{ .r = 120, .g = 230, .b = 160, .a = 255 },
            .single_meson_vertex => .{ .r = 255, .g = 140, .b = 200, .a = 255 },
        };
    }

    fn includeCb(iface: *Iface, _: *const Mdl) bool {
        const self: *HadronClusterLayer = @alignCast(@fieldParentPtr("interface", iface));
        _ = self;
        return true;
    }

    fn unitesCb(iface: *Iface, graph: *Graph, u: u64, v: u64) bool {
        const self: *HadronClusterLayer = @alignCast(@fieldParentPtr("interface", iface));
        _ = self;
        const ef = Mdl.edgeFieldForGraph(graph, u, v) orelse return false;
        return switch (ef) {
            .strong, .mixed => true,
            else => false,
        };
    }

    fn classifyResidualCb(iface: *Iface, graph: *Graph, members: []const u64) ?u16 {
        const self: *HadronClusterLayer = @alignCast(@fieldParentPtr("interface", iface));
        _ = self;
        const c = classifyComponent(graph, members) orelse return null;
        return @intCast(@intFromEnum(c));
    }
};

/// Pointer to the embedded `ClusterLayerInterface` (for `visualizations/clusters/manifest.zig`).
pub fn layerPtr() *Iface {
    return &HadronClusterLayer.singleton.interface;
}

test "classifyComponent uud proton weak component" {
    var g = Graph.init(std.testing.allocator, 0);
    defer g.deinit();
    try g.putVertex(0, Type.UpQuark.toParticle());
    try g.putVertex(1, Type.UpQuark.toParticle());
    try g.putVertex(2, Type.DownQuark.toParticle());
    try g.addEdge(0, 1);
    try g.addEdge(1, 2);
    var mem = [_]u64{ 0, 1, 2 };
    try std.testing.expectEqual(ClusterVizClass.proton_like, classifyComponent(&g, &mem).?);
}

test "classifyComponent udd neutron" {
    var g = Graph.init(std.testing.allocator, 0);
    defer g.deinit();
    try g.putVertex(0, Type.UpQuark.toParticle());
    try g.putVertex(1, Type.DownQuark.toParticle());
    try g.putVertex(2, Type.DownQuark.toParticle());
    try g.addEdge(0, 1);
    var mem = [_]u64{ 0, 1, 2 };
    try std.testing.expectEqual(ClusterVizClass.neutron_like, classifyComponent(&g, &mem).?);
}

test "classifyComponent quark antiquark meson" {
    var g = Graph.init(std.testing.allocator, 0);
    defer g.deinit();
    try g.putVertex(0, Type.UpQuark.toParticle());
    try g.putVertex(1, Type.AntiUpQuark.toParticle());
    var mem = [_]u64{ 0, 1 };
    try std.testing.expectEqual(ClusterVizClass.meson, classifyComponent(&g, &mem).?);
}

test "classifyComponent rejects four vertices" {
    var g = Graph.init(std.testing.allocator, 0);
    defer g.deinit();
    try g.putVertex(0, Type.UpQuark.toParticle());
    try g.putVertex(1, Type.UpQuark.toParticle());
    try g.putVertex(2, Type.DownQuark.toParticle());
    try g.putVertex(3, Type.DownQuark.toParticle());
    var mem = [_]u64{ 0, 1, 2, 3 };
    try std.testing.expect(classifyComponent(&g, &mem) == null);
}

test "partitionWeakComponent two disjoint uud" {
    var g = Graph.init(std.testing.allocator, 0);
    defer g.deinit();
    try g.putVertex(10, Type.UpQuark.toParticle());
    try g.putVertex(11, Type.UpQuark.toParticle());
    try g.putVertex(12, Type.DownQuark.toParticle());
    try g.putVertex(20, Type.UpQuark.toParticle());
    try g.putVertex(21, Type.UpQuark.toParticle());
    try g.putVertex(22, Type.DownQuark.toParticle());
    var mem = [_]u64{ 10, 11, 12, 20, 21, 22 };
    var pr = try partitionWeakComponent(std.testing.allocator, &g, &mem);
    defer pr.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 2), pr.pieces.len);
    try std.testing.expectEqual(@as(usize, 0), pr.residual.len);
    try std.testing.expectEqual(ClusterVizClass.proton_like, pr.pieces[0].class);
    try std.testing.expectEqual(ClusterVizClass.proton_like, pr.pieces[1].class);
}

test "weak edge unites when either end has color" {
    var g = Graph.init(std.testing.allocator, 0);
    defer g.deinit();
    try g.putVertex(1, Type.UpQuark.toParticle());
    try g.putVertex(2, Type.Photon.toParticle());
    try g.putVertex(3, Type.Gluon.toParticle());
    try g.putVertex(4, Type.Photon.toParticle());
    const ly = layerPtr();
    try std.testing.expect(ly.unitesEdge(&g, 1, 2));
    try std.testing.expect(ly.unitesEdge(&g, 1, 3));
    try std.testing.expect(!ly.unitesEdge(&g, 2, 4));
}
