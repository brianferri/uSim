const std = @import("std");
const UniverseLib = @import("root.zig");
const stat = @import("./util/stat.zig").stat;

const options = @import("options");
const useStat = options.stat;

const Graph = UniverseLib.Graph;
const String = UniverseLib.Particle;

pub fn main() !void {
    const time = std.time;
    const Timer = time.Timer;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var graph = Graph(usize, String).init(allocator, 0);
    defer graph.deinit();

    var file = try std.fs.cwd().createFile("zig-out/out.csv", .{});
    defer file.close();

    _ = try file.write("iter,vertices,num_edges,iter_time,mem\n");

    var outer_timer = try Timer.start();
    var timer = try Timer.start();

    const p1 = String{
        .tension = 1.0,
        .vibration_mode = 10.0,
        .phase = 0.0,
    };
    const p2 = String{
        .tension = 1.5,
        .vibration_mode = 15.0,
        .phase = 0.2,
    };

    const id1 = try graph.addVertex(p1);
    const id2 = try graph.addVertex(p2);
    try graph.addEdge(id1, id2);

    for (0..450) |i| {
        const Interaction = struct {
            from: usize,
            to: usize,
            emitted: []String,
            annihilated: bool,
        };

        var interactions = std.ArrayList(Interaction).init(allocator);
        defer {
            for (interactions.items) |interaction| {
                allocator.free(interaction.emitted);
            }
            interactions.deinit();
        }

        var vertex_iter = graph.vertices.iterator();
        while (vertex_iter.next()) |entry| {
            const id = entry.key_ptr.*;
            const node = entry.value_ptr;

            var adj_iter = node.*.adjacency_set.keyIterator();
            while (adj_iter.next()) |adj_id| {
                if (adj_id.* > id) {
                    if (graph.getVertex(adj_id.*)) |other_node| {
                        const emitted = try node.*.data.interact(&other_node.data, allocator);
                        const was_annihilated = node.*.data.annihilate(&other_node.data);
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
            if (interaction.annihilated) {
                _ = graph.removeVertex(interaction.from);
                _ = graph.removeVertex(interaction.to);
            } else {
                for (interaction.emitted) |new_particle| {
                    const new_id = try graph.addVertex(new_particle);
                    try graph.addEdge(interaction.from, new_id);
                    try graph.addEdge(interaction.to, new_id);
                }
            }
        }

        const iter_time = @as(f64, @floatFromInt(timer.read())) / time.ns_per_ms;
        var buf: [1000]u8 = undefined;
        var edges: u64 = 0;

        var vertices = graph.vertices.valueIterator();
        while (vertices.next()) |v| {
            edges += v.*.adjacency_set.count();
        }

        if (comptime useStat) {
            _ = try file.write(try std.fmt.allocPrint(std.heap.page_allocator, "{d},{d},{d},{d},{d}\n", .{ i, graph.vertices.count(), edges, iter_time, (try stat(&buf)).rss }));
        } else {
            _ = try file.write(try std.fmt.allocPrint(std.heap.page_allocator, "{d},{d},{d},{d}\n", .{ i, graph.vertices.count(), edges, iter_time }));
        }

        if (i % 100 == 0) {
            if (graph.getVertex(0)) |sample| {
                std.debug.print("Iter {}: mode = {}, phase = {}\n", .{ i, sample.data.vibration_mode, sample.data.phase });
            }
        }
    }

    std.debug.print("Time to complete tasks: {d:.3}ms\n", .{
        @as(f64, @floatFromInt(outer_timer.read())) / time.ns_per_ms,
    });
}
