//! Cluster viz: **outer** groups use `weaklyConnectedRootPerKeyFilteredDyn` with the active layer's
//! `unites_edge` (for standard hadron layer this now follows inferred edge fields: strong/mixed).
//! Layer vtables come from `registry.zig` / `manifest.zig` (`ulib` cluster exports + optional extra
//! modules). Same idea as `Renderer.Grid`: each module exports `layerPtr()` to an embedded
//! `cluster_viz.ClusterLayerInterface`. Directed edges optional (relational). Shape tab still uses
//! full weak components.
const std = @import("std");
const uSim = @import("usim");
const Particle = @import("ulib");
const reg = @import("registry.zig");
const ClusterIface = reg.ClusterLayerIface;
const Cv = uSim.cluster_viz;
const Renderer = uSim.Widgets.Renderer;
const Camera = uSim.Widgets.Camera;
const RelationalLayout = uSim.RelationalLayout;

const Vec3 = RelationalLayout.Vec3;

/// Result of `pickClusterOrVertex`. Caller frees `cluster.members` when tag is `.cluster`.
pub const ViewPick = union(enum) {
    vertex: u64,
    edge: struct {
        from: u64,
        to: u64,
        field: Particle.EdgeField,
    },
    cluster: struct {
        rep_min_key: u64,
        partition_match: bool,
        class_id: ?u16,
        members: []u64,
    },
};

const HubWin = struct {
    d2: f32,
    members: []u64,
    rep_min_key: u64,
    partition_match: bool,
    class_id: ?u16,
};

const hub_unclassified = Renderer.Color{ .r = 210, .g = 185, .b = 130, .a = 255 };

fn layerColorToRenderer(c: Cv.ClusterVizColor) Renderer.Color {
    return .{ .r = c.r, .g = c.g, .b = c.b, .a = c.a };
}

fn worldPosition(emb: *const RelationalLayout.Embedding, key: u64) Vec3 {
    return emb.pos.get(key) orelse @splat(0);
}

fn hashKeyColor(k: u64) Renderer.Color {
    const h = (@as(u32, @truncate(k)) *% 0x9e3779b1);
    return .{
        .r = @truncate(h >> 16),
        .g = @truncate(h >> 8),
        .b = @truncate(h),
        .a = 255,
    };
}

fn mixTowardGray(c: Renderer.Color, gray: u8, gray_weight: u32) Renderer.Color {
    const w: u32 = gray_weight;
    const inv: u32 = 10 - w;
    return .{
        .r = @truncate((@as(u32, c.r) * inv + @as(u32, gray) * w) / 10),
        .g = @truncate((@as(u32, c.g) * inv + @as(u32, gray) * w) / 10),
        .b = @truncate((@as(u32, c.b) * inv + @as(u32, gray) * w) / 10),
        .a = c.a,
    };
}

fn fieldEdgeColor(field: Particle.EdgeField) Renderer.Color {
    return switch (field) {
        .electromagnetic => .{ .r = 255, .g = 228, .b = 120, .a = 220 },
        .weak => .{ .r = 165, .g = 210, .b = 255, .a = 220 },
        .strong => .{ .r = 255, .g = 130, .b = 130, .a = 220 },
        .mixed => .{ .r = 230, .g = 170, .b = 255, .a = 220 },
        .none => .{ .r = 105, .g = 110, .b = 130, .a = 200 },
    };
}

fn inferredFieldForEdge(graph: *Particle.Graph, u: u64, v: u64) Particle.EdgeField {
    if (@hasDecl(Particle, "edgeFieldForGraph")) {
        return Particle.edgeFieldForGraph(graph, u, v) orelse .none;
    }
    return .none;
}

fn drawRadialBlobSized(ren: Renderer, pos: Vec3, col: Renderer.Color, rad: i32) void {
    const pix = ren.project(pos) orelse return;
    const cx: i32 = @intCast(pix.x);
    const cy: i32 = @intCast(pix.y);
    var dy: i32 = -rad;
    while (dy <= rad) : (dy += 1) {
        var dx: i32 = -rad;
        while (dx <= rad) : (dx += 1) {
            if (dx * dx + dy * dy <= rad * rad + 1)
                ren.drawPoint(cx + dx, cy + dy, col);
        }
    }
}

fn drawSingletonVertex(
    emb: *const RelationalLayout.Embedding,
    graph: *Particle.Graph,
    renderer: Renderer,
    k: u64,
) void {
    const node = graph.getVertex(k) orelse return;
    const pos = worldPosition(emb, k);
    var c = hashKeyColor(k);
    const n_out = node.adjacency_set.count();
    const n_in = node.incidency_set.count();
    if (n_out + n_in == 0) c = mixTowardGray(c, 170, 6);
    if (renderer.project(pos)) |pix| {
        renderer.drawPoint(pix.x, pix.y, c);
        if (n_out + n_in == 0)
            renderer.drawPlusMarker(pix.x, pix.y, 2, Renderer.Color{
                .r = 255,
                .g = 220,
                .b = 80,
                .a = 255,
            });
    }
}

fn drawResidualAggregate(
    emb: *const RelationalLayout.Embedding,
    graph: *Particle.Graph,
    layer: *ClusterIface,
    ren: Renderer,
    res: []const u64,
    spoke_col: Renderer.Color,
) void {
    if (res.len == 0) return;
    const cls_id = layer.classifyResidual(graph, res);
    var sumv: Vec3 = @splat(0);
    for (res) |mk| {
        sumv += worldPosition(emb, mk);
    }
    const inv: f32 = 1.0 / @as(f32, @floatFromInt(res.len));
    const cen = sumv * @as(Vec3, @splat(inv));
    for (res) |mk| {
        ren.drawLine3D(worldPosition(emb, mk), cen, spoke_col);
    }
    const hub_col = if (cls_id) |cid|
        layerColorToRenderer(layer.classColor(cid))
    else
        hub_unclassified;
    drawRadialBlobSized(ren, cen, hub_col, 3);
}

fn drawLayerAggregate(
    emb: *const RelationalLayout.Embedding,
    renderer: Renderer,
    piece: Cv.ClusterLayerPiece,
    class_col: Renderer.Color,
    spoke_col: Renderer.Color,
) void {
    if (piece.keys.len == 0) return;
    if (piece.keys.len == 1) {
        drawRadialBlobSized(renderer, worldPosition(emb, piece.keys[0]), class_col, 2);
        return;
    }
    var sumv: Vec3 = @splat(0);
    for (piece.keys) |mk| sumv += worldPosition(emb, mk);
    const inv: f32 = 1.0 / @as(f32, @floatFromInt(piece.keys.len));
    const cen = sumv * @as(Vec3, @splat(inv));
    for (piece.keys) |mk| {
        renderer.drawLine3D(worldPosition(emb, mk), cen, spoke_col);
    }
    drawRadialBlobSized(renderer, cen, class_col, 3);
}

fn minKeyOf(keys: []const u64) u64 {
    var m = keys[0];
    for (keys[1..]) |x| m = @min(m, x);
    return m;
}

fn tryOfferHub(
    allocator: std.mem.Allocator,
    ren: Renderer,
    fx: f32,
    fy: f32,
    r2h: f32,
    cen: Vec3,
    keys: []const u64,
    partition_match: bool,
    class_id: ?u16,
    win: *?HubWin,
) !void {
    if (keys.len == 0) return;
    const pix = ren.project(cen) orelse return;
    const dx = @as(f32, @floatFromInt(pix.x)) - fx;
    const dy = @as(f32, @floatFromInt(pix.y)) - fy;
    const d2 = dx * dx + dy * dy;
    if (d2 >= r2h) return;
    if (win.*) |cur| {
        if (d2 >= cur.d2) return;
        allocator.free(cur.members);
    }
    const copy = try allocator.dupe(u64, keys);
    errdefer allocator.free(copy);
    win.* = .{
        .d2 = d2,
        .members = copy,
        .rep_min_key = minKeyOf(keys),
        .partition_match = partition_match,
        .class_id = class_id,
    };
}

fn enumerateClusterHubScreens(
    alloc: std.mem.Allocator,
    emb: *const RelationalLayout.Embedding,
    graph: *Particle.Graph,
    members: []const u64,
    ren: Renderer,
    fx: f32,
    fy: f32,
    r2h: f32,
    win: *?HubWin,
) !void {
    if (members.len <= 1) return;
    const layer = reg.activeLayer();
    var part = try layer.partitionWeakComponent(alloc, graph, members);
    defer part.deinit(alloc);
    for (part.pieces) |piece| {
        if (piece.keys.len == 0) continue;
        var sumv: Vec3 = @splat(0);
        for (piece.keys) |mk| {
            sumv += worldPosition(emb, mk);
        }
        const inv = 1.0 / @as(f32, @floatFromInt(piece.keys.len));
        const cen = sumv * @as(Vec3, @splat(inv));
        try tryOfferHub(
            alloc,
            ren,
            fx,
            fy,
            r2h,
            cen,
            piece.keys,
            true,
            piece.class_id,
            win,
        );
    }
    if (part.residual.len > 1) {
        var sumv: Vec3 = @splat(0);
        for (part.residual) |mk| {
            sumv += worldPosition(emb, mk);
        }
        const inv: f32 = 1.0 / @as(f32, @floatFromInt(part.residual.len));
        const cen = sumv * @as(Vec3, @splat(inv));
        const cid = layer.classifyResidual(graph, part.residual);
        try tryOfferHub(
            alloc,
            ren,
            fx,
            fy,
            r2h,
            cen,
            part.residual,
            false,
            cid,
            win,
        );
    }
}

/// Screen-space pick: aggregate **hub** centroids (same geometry as draw) vs vertices.
pub fn pickClusterOrVertex(
    allocator: std.mem.Allocator,
    emb: *const RelationalLayout.Embedding,
    graph: *Particle.Graph,
    camera: Camera,
    width: usize,
    height: usize,
    fx: f32,
    fy: f32,
    r_vertex_px: f32,
    r_hub_px: f32,
) !?ViewPick {
    const G = @TypeOf(graph.*);
    const ren = Renderer.init(.{
        .width = width,
        .height = height,
        .camera = camera,
    });

    const keys = try uSim.structure_analysis.graphKeysSorted(G, allocator, graph);
    defer allocator.free(keys);
    if (keys.len == 0) return null;

    const layer = reg.activeLayer();
    var unify_ctx = uSim.cluster_viz.WeakUnifyContext(ClusterIface, G){ .layer = layer };
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

    var by_root = std.AutoHashMap(usize, std.ArrayListUnmanaged(u64)).init(allocator);
    defer {
        var it = by_root.iterator();
        while (it.next()) |e| e.value_ptr.deinit(allocator);
        by_root.deinit();
    }
    for (keys, roots) |k, r| {
        const gop = try by_root.getOrPutValue(r, .{});
        try gop.value_ptr.append(allocator, k);
    }

    const r2v = r_vertex_px * r_vertex_px;
    const r2h = r_hub_px * r_hub_px;

    var win_hub: ?HubWin = null;
    defer if (win_hub) |wh| allocator.free(wh.members);

    var hit = by_root.iterator();
    while (hit.next()) |ent| {
        try enumerateClusterHubScreens(
            allocator,
            emb,
            graph,
            ent.value_ptr.items,
            ren,
            fx,
            fy,
            r2h,
            &win_hub,
        );
    }

    var best_vd2: f32 = std.math.inf(f32);
    var best_vk: ?u64 = null;
    for (keys) |k| {
        const wpos = worldPosition(emb, k);
        const pix = ren.project(wpos) orelse continue;
        const dx = @as(f32, @floatFromInt(pix.x)) - fx;
        const dy = @as(f32, @floatFromInt(pix.y)) - fy;
        const d2 = dx * dx + dy * dy;
        if (d2 < best_vd2) {
            best_vd2 = d2;
            best_vk = k;
        }
    }

    const hub_ok = win_hub != null and win_hub.?.d2 < r2h;
    const vtx_ok = best_vd2 < r2v;

    if (hub_ok and (!vtx_ok or win_hub.?.d2 <= best_vd2)) {
        const wh = win_hub.?;
        const out_mem = try allocator.dupe(u64, wh.members);
        return .{ .cluster = .{
            .rep_min_key = wh.rep_min_key,
            .partition_match = wh.partition_match,
            .class_id = wh.class_id,
            .members = out_mem,
        } };
    }
    if (vtx_ok) return .{ .vertex = best_vk.? };
    return null;
}

fn drawCompositeWeakComponent(
    emb: *const RelationalLayout.Embedding,
    graph: *Particle.Graph,
    alloc: std.mem.Allocator,
    members: []const u64,
    renderer: Renderer,
    spoke_col: Renderer.Color,
) !void {
    const layer = reg.activeLayer();
    var part = try layer.partitionWeakComponent(alloc, graph, members);
    defer part.deinit(alloc);

    for (part.pieces) |piece| {
        const class_col = layerColorToRenderer(layer.classColor(piece.class_id));
        drawLayerAggregate(emb, renderer, piece, class_col, spoke_col);
    }

    if (part.residual.len == 0) return;
    if (part.residual.len == 1) {
        drawSingletonVertex(emb, graph, renderer, part.residual[0]);
        return;
    }
    drawResidualAggregate(emb, graph, layer, renderer, part.residual, spoke_col);
}

fn drawInner(
    emb: *const RelationalLayout.Embedding,
    graph: *Particle.Graph,
    edges_on: bool,
    renderer: Renderer,
) !void {
    const G = @TypeOf(graph.*);
    const alloc = graph.allocator;

    if (edges_on) {
        var uit = graph.vertices.iterator();
        while (uit.next()) |ue| {
            const u = ue.key_ptr.*;
            const pu = worldPosition(emb, u);
            var ait = ue.value_ptr.*.adjacency_set.iterator();
            while (ait.next()) |ae| {
                const v = ae.key_ptr.*;
                const pv = worldPosition(emb, v);
                const ef = inferredFieldForEdge(graph, u, v);
                renderer.drawLine3D(pu, pv, fieldEdgeColor(ef));
            }
        }
    }

    const keys = try uSim.structure_analysis.graphKeysSorted(G, alloc, graph);
    defer alloc.free(keys);
    if (keys.len == 0) return;

    const layer = reg.activeLayer();
    var unify_ctx = uSim.cluster_viz.WeakUnifyContext(ClusterIface, G){ .layer = layer };
    const roots = try uSim.structure_analysis.weaklyConnectedRootPerKeyFilteredDyn(
        G,
        @TypeOf(unify_ctx),
        alloc,
        graph,
        keys,
        &unify_ctx,
        @TypeOf(unify_ctx).unify,
    );
    defer alloc.free(roots);

    var by_root = std.AutoHashMap(usize, std.ArrayListUnmanaged(u64)).init(alloc);
    defer {
        var it = by_root.iterator();
        while (it.next()) |e| e.value_ptr.deinit(alloc);
        by_root.deinit();
    }
    for (keys, roots) |k, r| {
        const gop = try by_root.getOrPutValue(r, .{});
        try gop.value_ptr.append(alloc, k);
    }

    const spoke_col = Renderer.Color{ .r = 130, .g = 140, .b = 165, .a = 200 };

    var it = by_root.iterator();
    while (it.next()) |ent| {
        const members = ent.value_ptr.items;
        if (members.len == 1) {
            drawSingletonVertex(emb, graph, renderer, members[0]);
            continue;
        }
        try drawCompositeWeakComponent(emb, graph, alloc, members, renderer, spoke_col);
    }
}

pub fn draw(emb: *const RelationalLayout.Embedding, graph: *Particle.Graph, edges_on: bool, renderer: Renderer) void {
    drawInner(emb, graph, edges_on, renderer) catch return;
}
