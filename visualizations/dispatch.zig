//! `vlib` root: functional pipeline. Host assigns `frame_ctx` each frame before `Software3D` draws the particle layer.
//!
//! **Boundaries:** Stock modes (`relational/`, `clusters/`) import `ulib` for concrete vertex payloads (`Particle`, `Particle.Graph`) and `usim` for `Graph` math, `RelationalLayout`, and `Widgets` (Renderer/Camera). That is the intentional coupling point; there is no second hidden model state in `vlib` beyond `frame_ctx`, `relational_frame_emb`, and `Active` (all host-driven each frame).
//!
//! **Interfaces / vtables:** The 3D stack uses `Renderer.Layer` (`Widgets.Renderer`) with a small vtable (`draw`); visualization draw functions are plain Zig on `Embedding` + graph pointers, not OO hierarchies. To support another model package later, keep using the host-injected `graph` pointer and move color/hook selection behind `ulib` exports so `dispatch` does not branch on model names.
const std = @import("std");
const relational = @import("relational/main.zig");
const clusters = @import("clusters/main.zig");
pub const cluster_registry = @import("clusters/registry.zig");
pub const cluster_fmt = @import("clusters/format.zig");
const Particle = @import("ulib");
const uSim = @import("usim");
const Renderer = uSim.Widgets.Renderer;
const Camera = uSim.Widgets.Camera;

pub const Active = enum {
    relational,
    /// Weak components + active cluster layer; see `vlib.cluster_registry` / manifest.
    clusters,
};

/// Short copy for the host info panel (not physics truth, just how to read the view).
pub const VizHelp = struct {
    title: []const u8,
    bullets: []const []const u8,
};

pub fn vizModeHelp(active: Active) VizHelp {
    return switch (active) {
        .relational => .{
            .title = "Relational layout",
            .bullets = &.{
                "Vertices are particles; directed edges are interaction links.",
                "3D positions come from a force-directed pass on the current graph.",
                "Toggle Layout to freeze or relax the embedding each frame.",
                "Dense neighborhoods tend to cohere; isolates read as loners.",
            },
        },
        .clusters => .{
            .title = "Field-linked groups (aggregates)",
            .bullets = &.{
                "Outer groups merge by the active layer edge rule; stock hadron layer uses inferred edge field and joins strong/mixed links.",
                "Each group is partitioned by the active cluster layer into matched pieces and a residual; hubs and spokes show aggregates (see layer `class_name` / colors).",
                "Vertices that the layer leaves unmatched stay in the residual (hub + spokes) or draw as singletons.",
                "When `cluster_registry.partition_max_bruteforce_n` is non-zero, large components may skip expensive sub-matches; lighter rules still apply.",
                "Click a hub to inspect that aggregate, or click an edge for inferred field info. Picked clusters now get bold rings and highlighted internal links.",
                "Singletons look like relational points; turn Edges on to see directed links.",
            },
        },
    };
}

pub const WorldBounds = relational.WorldBounds;
pub const ViewPick = clusters.ViewPick;

fn accentRingColor(c: Renderer.Color) Renderer.Color {
    return .{
        .r = @min(255, @as(u16, c.r) + 55),
        .g = @min(255, @as(u16, c.g) + 55),
        .b = @min(255, @as(u16, c.b) + 55),
        .a = 255,
    };
}

fn drawPickedVertexOverlays(
    emb: *const uSim.RelationalLayout.Embedding,
    graph: *Particle.Graph,
    ren: Renderer,
    keys: []const u64,
) void {
    const cluster_pick = keys.len > 1;
    if (cluster_pick) {
        var i: usize = 0;
        while (i < keys.len) : (i += 1) {
            var j: usize = i + 1;
            while (j < keys.len) : (j += 1) {
                const a = keys[i];
                const b = keys[j];
                if (graph.hasAdjEdge(a, b) or graph.hasAdjEdge(b, a)) {
                    ren.drawLine3D(
                        relational.worldPosition(emb, a),
                        relational.worldPosition(emb, b),
                        .{ .r = 255, .g = 245, .b = 160, .a = 255 },
                    );
                }
            }
        }
    }
    for (keys) |k| {
        const pos = relational.worldPosition(emb, k);
        const pix = ren.project(pos) orelse continue;
        const node = graph.getVertex(k) orelse continue;
        const ty = Particle.Type.fromStruct(&node.data);
        const base = relational.colorFromType(ty);
        const ring = accentRingColor(base);
        const cx: i32 = @intCast(pix.x);
        const cy: i32 = @intCast(pix.y);
        if (cluster_pick) {
            ren.drawFilledDiscPixels(cx, cy, 5, base);
            ren.drawCircleOutline(cx, cy, 10, ring);
            ren.drawCircleOutline(cx, cy, 13, .{
                .r = 255,
                .g = 245,
                .b = 140,
                .a = 255,
            });
        } else {
            ren.drawFilledDiscPixels(cx, cy, 3, base);
            ren.drawCircleOutline(cx, cy, 7, ring);
        }
    }
}

fn pointSegmentDistanceSquared(
    px: f32,
    py: f32,
    x1: f32,
    y1: f32,
    x2: f32,
    y2: f32,
) f32 {
    const vx = x2 - x1;
    const vy = y2 - y1;
    const wx = px - x1;
    const wy = py - y1;
    const vv = vx * vx + vy * vy;
    if (vv <= 1e-6) {
        const dx = px - x1;
        const dy = py - y1;
        return dx * dx + dy * dy;
    }
    var t = (wx * vx + wy * vy) / vv;
    if (t < 0) t = 0;
    if (t > 1) t = 1;
    const nx = x1 + t * vx;
    const ny = y1 + t * vy;
    const dx = px - nx;
    const dy = py - ny;
    return dx * dx + dy * dy;
}

fn pickNearestEdge(
    fv: FrameView,
    camera: Camera,
    width: usize,
    height: usize,
    fx: f32,
    fy: f32,
    pick_radius_px: f32,
) !?ViewPick {
    const emb = relationalFrameEmbeddingPtr() orelse return null;
    const ren = Renderer.init(.{
        .width = width,
        .height = height,
        .camera = camera,
    });
    const r2 = pick_radius_px * pick_radius_px;
    var best_d2: f32 = std.math.inf(f32);
    var best: ?struct { from: u64, to: u64, field: Particle.EdgeField } = null;

    var uit = fv.graph.vertices.iterator();
    while (uit.next()) |ue| {
        const from = ue.key_ptr.*;
        const p_from = ren.project(relational.worldPosition(emb, from)) orelse continue;
        var ait = ue.value_ptr.*.adjacency_set.iterator();
        while (ait.next()) |ae| {
            const to = ae.key_ptr.*;
            const p_to = ren.project(relational.worldPosition(emb, to)) orelse continue;
            const d2 = pointSegmentDistanceSquared(
                fx,
                fy,
                @floatFromInt(p_from.x),
                @floatFromInt(p_from.y),
                @floatFromInt(p_to.x),
                @floatFromInt(p_to.y),
            );
            if (d2 < best_d2 and d2 <= r2) {
                const ef = Particle.edgeFieldForGraph(fv.graph, from, to) orelse .none;
                best_d2 = d2;
                best = .{ .from = from, .to = to, .field = ef };
            }
        }
    }

    if (best) |e| {
        return .{ .edge = .{
            .from = e.from,
            .to = e.to,
            .field = e.field,
        } };
    }
    return null;
}

/// Host overwrites this at the start of each frame before `Software3D` draws the particle layer.
pub var frame_ctx: FrameView = undefined;

/// One relational embedding per frame (after `beginRelationalFrameEmbedding`, before `endRelationalFrameEmbedding`).
var relational_frame_emb: ?uSim.RelationalLayout.Embedding = null;

/// Drop any cached embedding. Safe to call when cache is empty.
pub fn endRelationalFrameEmbedding() void {
    if (relational_frame_emb) |*e| {
        e.deinit();
        relational_frame_emb = null;
    }
}

/// Rebuild cache for this frame. Call once per frame after the graph is in its displayed state.
pub fn beginRelationalFrameEmbedding(
    active: Active,
    allocator: std.mem.Allocator,
    graph: *Particle.Graph,
    apply_layout: bool,
) !void {
    _ = active;
    endRelationalFrameEmbedding();
    relational_frame_emb = try relational.computeEmbedding(allocator, graph, apply_layout);
}

pub fn relationalFrameEmbeddingPtr() ?*uSim.RelationalLayout.Embedding {
    if (relational_frame_emb) |*e| return e else return null;
}

pub const FrameView = struct {
    active: *const Active,
    graph: *Particle.Graph,
    show_edges: *const bool,
    apply_layout: *const bool,
    allocator: std.mem.Allocator,
    /// Picked vertex / cluster members: drawn with a larger disc and ring on top of the particle layer.
    highlight_keys: []const u64,
};

/// Both stock views share the same force-directed embedding; the Layout toggle still applies.
pub fn layoutRuns(active: Active) bool {
    _ = active;
    return true;
}

pub fn worldPositionForVertex(fv: FrameView, key: u64) !?Renderer.Vec3 {
    _ = fv;
    const emb = relationalFrameEmbeddingPtr() orelse return null;
    return relational.worldPosition(emb, key);
}

pub fn worldBounds(
    allocator: std.mem.Allocator,
    active: Active,
    graph: *Particle.Graph,
    apply_layout: bool,
) !?WorldBounds {
    _ = allocator;
    _ = active;
    _ = apply_layout;
    const emb = relationalFrameEmbeddingPtr() orelse return null;
    return relational.worldBoundsFromEmbedding(graph, emb);
}

pub fn pickNearestVertex(
    fv: FrameView,
    camera: Camera,
    width: usize,
    height: usize,
    fx: f32,
    fy: f32,
    pick_radius_px: f32,
) error{OutOfMemory}!?u64 {
    const emb = relationalFrameEmbeddingPtr() orelse return null;
    const ren = Renderer.init(.{
        .width = width,
        .height = height,
        .camera = camera,
    });

    const G = @TypeOf(fv.graph.*);
    const keys = try uSim.structure_analysis.graphKeysSorted(G, fv.allocator, fv.graph);
    defer fv.allocator.free(keys);

    const r2 = pick_radius_px * pick_radius_px;
    var best_k: ?u64 = null;
    var best_d2: f32 = std.math.inf(f32);

    for (keys) |k| {
        const wpos = relational.worldPosition(emb, k);
        const pix = ren.project(wpos) orelse continue;
        const dx = @as(f32, @floatFromInt(pix.x)) - fx;
        const dy = @as(f32, @floatFromInt(pix.y)) - fy;
        const d2 = dx * dx + dy * dy;
        if (d2 < best_d2) {
            best_d2 = d2;
            best_k = k;
        }
    }

    if (best_d2 > r2) return null;
    return best_k;
}

/// Relational: nearest vertex. Clusters: hub centroid vs vertex (hub wins when closer or tied).
pub fn pickMainView(
    allocator: std.mem.Allocator,
    fv: FrameView,
    camera: Camera,
    width: usize,
    height: usize,
    fx: f32,
    fy: f32,
) !?ViewPick {
    const vhit: ?ViewPick = switch (fv.active.*) {
        .relational => if (try pickNearestVertex(fv, camera, width, height, fx, fy, 22.0)) |k|
            ViewPick{ .vertex = k }
        else
            null,
        .clusters => blk: {
            const emb = relationalFrameEmbeddingPtr() orelse break :blk null;
            break :blk try clusters.pickClusterOrVertex(
                allocator,
                emb,
                fv.graph,
                camera,
                width,
                height,
                fx,
                fy,
                22.0,
                36.0,
            );
        },
    };
    if (vhit) |h| return h;
    return try pickNearestEdge(fv, camera, width, height, fx, fy, 12.0);
}

/// Centroid of embedded positions for the given vertex keys (camera framing).
pub fn centroidWorldForKeys(keys: []const u64) ?Renderer.Vec3 {
    const emb = relationalFrameEmbeddingPtr() orelse return null;
    if (keys.len == 0) return null;
    var s = Renderer.Vec3{ 0, 0, 0 };
    for (keys) |k| {
        s += relational.worldPosition(emb, k);
    }
    return s / @as(Renderer.Vec3, @splat(@as(f32, @floatFromInt(keys.len))));
}

pub const ParticlesLayer = struct {
    interface: Renderer.Layer,

    fn initInterface() Renderer.Layer {
        return .{
            .vtable = &.{
                .draw = draw,
            },
        };
    }

    pub fn layer() ParticlesLayer {
        return .{
            .interface = initInterface(),
        };
    }

    fn draw(render_layer: *Renderer.Layer, r: Renderer) void {
        _ = render_layer;
        const fv = frame_ctx;
        const emb = relationalFrameEmbeddingPtr() orelse return;
        switch (fv.active.*) {
            .relational => relational.draw(emb, fv.graph, fv.show_edges.*, r),
            .clusters => clusters.draw(emb, fv.graph, fv.show_edges.*, r),
        }
        drawPickedVertexOverlays(emb, fv.graph, r, fv.highlight_keys);
    }
};
