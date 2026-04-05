//! Pick-panel strings for cluster viz (host Pick tab).

const std = @import("std");
const uSim = @import("usim");
const Particle = @import("ulib");
const registry = @import("registry.zig");

const Graph = Particle.Graph;
const ClusterIface = registry.ClusterLayerIface;

/// Weak component + partition slot for one vertex (active cluster layer).
pub fn formatMembershipHint(
    allocator: std.mem.Allocator,
    graph: *Graph,
    vertex_key: u64,
) ![]u8 {
    const G = Graph;
    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer aw.deinit();
    const w = &aw.writer;

    const keys = try uSim.structure_analysis.graphKeysSorted(G, allocator, graph);
    defer allocator.free(keys);

    var ki: ?usize = null;
    for (keys, 0..) |k, i| {
        if (k == vertex_key) {
            ki = i;
            break;
        }
    }
    if (ki == null) {
        try w.print("Vertex key {d} is not in the current graph.\n", .{vertex_key});
        return try aw.toOwnedSlice();
    }

    const layer_ptr = registry.activeLayer();
    var unify_ctx = uSim.cluster_viz.WeakUnifyContext(ClusterIface, G){
        .layer = layer_ptr,
    };
    const roots = try uSim.structure_analysis.weaklyConnectedRootPerKeyFilteredDyn(
        G,
        @TypeOf(unify_ctx),
        allocator,
        graph,
        keys,
        &unify_ctx,
        @TypeOf(unify_ctx).unify,
    );
    defer allocator.free(roots);
    const r = roots[ki.?];

    var member_count: usize = 0;
    for (roots) |root| {
        if (root == r) member_count += 1;
    }

    var members = try allocator.alloc(u64, member_count);
    defer allocator.free(members);
    var mi: usize = 0;
    var rep_key: ?u64 = null;
    for (keys, roots) |k, root| {
        if (root == r) {
            members[mi] = k;
            mi += 1;
            rep_key = if (rep_key) |x| @min(x, k) else k;
        }
    }
    std.sort.pdq(u64, members, {}, std.sort.asc(u64));
    const rep = rep_key.?;

    try w.print(
        "Cluster viz group (active layer edge rule): {d} vertices (min key {d} is the viz grouping id).\n",
        .{ member_count, rep },
    );
    try w.print(
        "Positions are from the relational embedding, not physical space.\n",
        .{},
    );

    var part = try layer_ptr.partitionWeakComponent(allocator, graph, members);
    defer part.deinit(allocator);

    var in_piece: ?struct {
        class_id: u16,
        keys: []const u64,
    } = null;
    for (part.pieces) |p| {
        for (p.keys) |pk| {
            if (pk == vertex_key) {
                in_piece = .{
                    .class_id = p.class_id,
                    .keys = p.keys,
                };
                break;
            }
        }
        if (in_piece != null) break;
    }

    if (in_piece) |ip| {
        const nm = layer_ptr.className(ip.class_id);
        try w.print(
            "Partition: matched piece ({s}), {d} vertices.\n",
            .{ nm, ip.keys.len },
        );
        if (ip.keys.len <= 8) {
            try w.print("  Member keys: ", .{});
            for (ip.keys, 0..) |pk, j| {
                if (j > 0) try w.print(", ", .{});
                try w.print("{d}", .{pk});
            }
            try w.print("\n", .{});
        }
    } else {
        try w.print(
            "Partition: residual (not in a matched layer piece).\n",
            .{},
        );
        try w.print("  Residual size: {d} vertices.\n", .{part.residual.len});
        if (part.residual.len <= 12) {
            try w.print("  Residual keys: ", .{});
            for (part.residual, 0..) |rk, j| {
                if (j > 0) try w.print(", ", .{});
                try w.print("{d}", .{rk});
            }
            try w.print("\n", .{});
        }
        if (part.residual.len >= 2) {
            if (layer_ptr.classifyResidual(graph, part.residual)) |cid| {
                try w.print(
                    "  Entire residual matches single layer class: {s}.\n",
                    .{layer_ptr.className(cid)},
                );
            } else {
                try w.print(
                    "  Entire residual has no single layer classification.\n",
                    .{},
                );
            }
        }
    }

    const cap = registry.partition_max_bruteforce_n;
    if (cap > 0 and member_count > cap) {
        try w.print(
            "Note: layer partition may skip expensive sub-matches for components " ++
                "above {d} vertices; lighter rules still apply.\n",
            .{cap},
        );
    }

    return try aw.toOwnedSlice();
}

/// Pick-panel copy when the user selects a **cluster hub** in viz mode clusters.
pub fn formatHubInspector(
    allocator: std.mem.Allocator,
    graph: *Graph,
    rep_min_key: u64,
    partition_match: bool,
    class_id: ?u16,
    members: []const u64,
) ![]u8 {
    const layer_ptr = registry.activeLayer();
    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer aw.deinit();
    const w = &aw.writer;
    try w.print("Cluster hub (viz)\n", .{});
    try w.print("Grouping id (min key): {d}\n", .{rep_min_key});
    if (partition_match) {
        if (class_id) |cid| {
            try w.print(
                "Kind: matched piece ({s})\n",
                .{layer_ptr.className(cid)},
            );
        } else {
            try w.print("Kind: matched piece\n", .{});
        }
    } else {
        if (class_id) |cid| {
            try w.print(
                "Kind: residual aggregate ({s})\n",
                .{layer_ptr.className(cid)},
            );
        } else {
            try w.print("Kind: residual aggregate (unclassified)\n", .{});
        }
    }
    try w.print("Member particles ({d}):\n", .{members.len});
    for (members) |mk| {
        const node = graph.getVertex(mk) orelse {
            try w.print("  {d}: (removed)\n", .{mk});
            continue;
        };
        const ty = Particle.Type.fromStruct(&node.data);
        try w.print("  {d}: {s}\n", .{ mk, @tagName(ty) });
    }
    return try aw.toOwnedSlice();
}

test "formatMembershipHint weak component and proton piece" {
    var g = Graph.init(std.testing.allocator, 0);
    defer g.deinit();
    try g.putVertex(10, Particle.Type.UpQuark.toParticle());
    try g.putVertex(11, Particle.Type.UpQuark.toParticle());
    try g.putVertex(12, Particle.Type.DownQuark.toParticle());
    try g.putVertex(20, Particle.Type.UpQuark.toParticle());
    try g.putVertex(21, Particle.Type.UpQuark.toParticle());
    try g.putVertex(22, Particle.Type.DownQuark.toParticle());
    try g.addEdge(10, 11);
    try g.addEdge(11, 12);
    try g.addEdge(20, 21);
    try g.addEdge(21, 22);

    const hint = try formatMembershipHint(std.testing.allocator, &g, 10);
    defer std.testing.allocator.free(hint);
    try std.testing.expect(
        std.mem.indexOf(u8, hint, "Cluster viz group (active layer edge rule): 3 vertices") != null,
    );
    try std.testing.expect(std.mem.indexOf(u8, hint, "proton_like") != null);
    try std.testing.expect(std.mem.indexOf(u8, hint, "10") != null);
}
