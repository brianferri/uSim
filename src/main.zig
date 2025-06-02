const std = @import("std");
const uSim = @import("usim");
const Particle = @import("ulib");
const stat = @import("./util/stat.zig").stat;
const options = @import("options");

const time = std.time;
const useStat = options.stat;

const Graph = uSim.Graph;

const MAX_EDGES_PER_PARTICLE = 2;

const Interaction = struct {
    from: usize,
    to: usize,
    emitted: []Particle,
    annihilated: bool,
};

// TODO Revisit this to establish a correct pipeline for interactions and possible "annihilation"/"decay"/"replacement" of particles
fn processInteractions(allocator: std.mem.Allocator, graph: *Graph(usize, Particle)) !void {
    var interactions = std.ArrayList(Interaction).init(allocator);
    defer interactions.deinit();
    defer for (interactions.items) |interaction| {
        allocator.free(interaction.emitted);
    };

    var vertex_iter = graph.vertices.iterator();
    while (vertex_iter.next()) |entry| {
        const id = entry.key_ptr.*;
        const node = entry.value_ptr.*;

        var adj_iter = node.adjacency_set.keyIterator();
        while (adj_iter.next()) |adj_id| {
            if (adj_id.* > id) {
                if (graph.getVertex(adj_id.*)) |other_node| {
                    const emitted = try node.data.interact(&other_node.data, allocator);
                    const was_annihilated = emitted.len == 2 and emitted[0].kind == .Photon and emitted[1].kind == .Photon;
                    try interactions.append(.{
                        .from = id,
                        .to = adj_id.*,
                        .emitted = emitted,
                        .annihilated = was_annihilated,
                    });
                }
            }
        }
    }

    for (interactions.items) |interaction| {
        for (interaction.emitted) |new_particle| {
            const new_id = try graph.addVertex(new_particle);
            try graph.addEdge(interaction.from, new_id);
            try graph.addEdge(interaction.to, new_id);
        }
        if (interaction.annihilated) {
            _ = graph.removeVertex(interaction.from);
            _ = graph.removeVertex(interaction.to);
        }
    }
}

fn logIteration(
    allocator: std.mem.Allocator,
    file: *std.fs.File,
    graph: *Graph(usize, Particle),
    iter: usize,
    iter_time: f64,
) !void {
    var buf: [1000]u8 = undefined;
    var edges: usize = 0;

    var vertices = graph.vertices.valueIterator();
    while (vertices.next()) |v| {
        edges += v.*.adjacency_set.count();
    }

    if (comptime useStat) {
        const memory = try stat(&buf);
        try file.writeAll(try std.fmt.allocPrint(allocator, "{d},{d},{d},{d},{d}\n", .{
            iter, graph.vertices.count(), edges, iter_time, memory.rss,
        }));
    } else {
        try file.writeAll(try std.fmt.allocPrint(allocator, "{d},{d},{d},{d}\n", .{
            iter, graph.vertices.count(), edges, iter_time,
        }));
    }
}

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    const allocator = gpa.allocator();

    var graph = try Particle.initializeGraph(allocator);
    defer graph.deinit();
    Particle.print(&graph);

    var file = try std.fs.cwd().createFile("zig-out/out.csv", .{});
    defer file.close();
    _ = try file.write("iter,vertices,num_edges,iter_time,mem\n");

    var outer_timer = try time.Timer.start();

    for (0..450) |i| {
        var timer = try time.Timer.start();
        try processInteractions(allocator, &graph);

        const iter_time = @as(f64, @floatFromInt(timer.read())) / time.ns_per_ms;
        try logIteration(allocator, &file, &graph, i, iter_time);

        std.debug.print("\x1B[2J\x1B[H", .{});
        std.debug.print("iter: {d} | time: {d}", .{ i, iter_time });
        Particle.print(&graph);

        if (graph.vertices.count() == 0) break;
    }

    std.debug.print("Total time: {d:.3}ms\n", .{@as(f64, @floatFromInt(outer_timer.read())) / time.ns_per_ms});
}
