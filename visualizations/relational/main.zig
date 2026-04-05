//! Force-directed layout from the graph only: no saved visualization state in this module.
//! Callers may build one `Embedding` per frame (`vlib.beginRelationalFrameEmbedding`) and reuse it for draw, pick, and bounds.
const std = @import("std");
const uSim = @import("usim");
const Particle = @import("ulib");
const Renderer = uSim.Widgets.Renderer;

/// Centroid and radius for relational world framing (one named type so `worldBoundsForGraph` and `worldBoundsFromEmbedding` match).
pub const WorldBounds = struct {
    center: Renderer.Vec3,
    radius: f32,
};

/// Sync from `graph`, then optional layout substeps. Caller owns return value (`defer deinit`).
pub fn computeEmbedding(
    allocator: std.mem.Allocator,
    graph: *Particle.Graph,
    apply_layout: bool,
) !uSim.RelationalLayout.Embedding {
    var emb = uSim.RelationalLayout.Embedding.init(allocator);
    errdefer emb.deinit();
    try emb.syncFromGraph(@TypeOf(graph.*), graph);
    if (apply_layout) {
        const n = graph.vertices.count();
        // `computeEmbedding` dominates interactive cost at high vertex counts; cap substeps aggressively.
        // 1 pass from 129 up; small graphs keep extra passes for a steadier cold layout.
        const sub_steps: u32 = if (n > 128) 1 else if (n > 48) 2 else 4;
        try uSim.RelationalLayout.stepRepeated(
            @TypeOf(graph.*),
            graph,
            &emb,
            Particle.layout_hooks,
            .{},
            sub_steps,
        );
    }
    return emb;
}

pub fn worldPosition(emb: *const uSim.RelationalLayout.Embedding, key: u64) Renderer.Vec3 {
    return emb.pos.get(key) orelse @splat(0);
}

/// Bounding sphere from an existing embedding (avoids recomputing layout). `emb.pos` keys must match
/// `graph.vertices` (true after relational `syncFromGraph`).
pub fn worldBoundsFromEmbedding(graph: *Particle.Graph, emb: *const uSim.RelationalLayout.Embedding) ?WorldBounds {
    _ = graph;
    const n = emb.pos.count();
    if (n == 0) return null;

    var sum = Renderer.Vec3{ 0, 0, 0 };
    var pit = emb.pos.iterator();
    while (pit.next()) |ent| {
        sum += ent.value_ptr.*;
    }
    const inv_n: f32 = 1.0 / @as(f32, @floatFromInt(n));
    const center = sum * @as(Renderer.Vec3, @splat(inv_n));

    var max_r_sq: f32 = 0;
    pit = emb.pos.iterator();
    while (pit.next()) |ent| {
        const d = ent.value_ptr.* - center;
        max_r_sq = @max(max_r_sq, @reduce(.Add, d * d));
    }
    return .{ .center = center, .radius = @sqrt(max_r_sq) };
}

pub fn worldBoundsForGraph(
    allocator: std.mem.Allocator,
    graph: *Particle.Graph,
    apply_layout: bool,
) !?WorldBounds {
    const n = graph.vertices.count();
    if (n == 0) return null;

    var emb = try computeEmbedding(allocator, graph, apply_layout);
    defer emb.deinit();

    return worldBoundsFromEmbedding(graph, &emb);
}

pub fn colorFromType(t: Particle.Type) Renderer.Color {
    const h = (@as(u32, @intFromEnum(t)) *% 0x9e3779b1);
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

pub fn draw(emb: *const uSim.RelationalLayout.Embedding, graph: *Particle.Graph, edges_on: bool, renderer: Renderer) void {
    if (edges_on) {
        const edge_col = Renderer.Color{ .r = 100, .g = 105, .b = 125, .a = 220 };
        var uit = graph.vertices.iterator();
        while (uit.next()) |ue| {
            const u = ue.key_ptr.*;
            const pu = worldPosition(emb, u);
            var ait = ue.value_ptr.*.adjacency_set.iterator();
            while (ait.next()) |ae| {
                const v = ae.key_ptr.*;
                const pv = worldPosition(emb, v);
                renderer.drawLine3D(pu, pv, edge_col);
            }
        }
    }

    var it = graph.vertices.iterator();
    while (it.next()) |ent| {
        const key = ent.key_ptr.*;
        const node = ent.value_ptr.*;
        const pos = worldPosition(emb, key);
        const ty = Particle.Type.fromStruct(&node.data);
        var c = colorFromType(ty);
        const n_out = node.adjacency_set.count();
        const n_in = node.incidency_set.count();
        const isolated = (n_out + n_in) == 0;
        if (isolated) c = mixTowardGray(c, 170, 6);

        if (renderer.project(pos)) |pix| {
            renderer.drawPoint(pix.x, pix.y, c);
            if (isolated)
                renderer.drawPlusMarker(pix.x, pix.y, 2, Renderer.Color{ .r = 255, .g = 220, .b = 80, .a = 255 });
        }
    }
}
