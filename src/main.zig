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

    for (0..450) |i| {
        const p1 = String{
            .tension = 1.0 + @as(f64, @floatFromInt(i)) * 0.01,
            .vibration_mode = 10.0,
            .phase = 0.0,
        };
        const p2 = String{
            .tension = 1.5 + @as(f64, @floatFromInt(i)) * 0.01,
            .vibration_mode = 15.0,
            .phase = 0.2,
        };

        _ = try graph.addVertex(p1);
        _ = try graph.addVertex(p2);

        var vertices1 = graph.vertices.keyIterator();
        while (vertices1.next()) |v1| {
            var vertices2 = graph.vertices.keyIterator();
            while (vertices2.next()) |v2| {
                if (v1 == v2) continue;
                try graph.addEdge(v1.*, v2.*);
            }
        }

        var vertex_iter = graph.vertices.iterator();
        while (vertex_iter.next()) |entry| {
            const id = entry.key_ptr.*;
            const node = entry.value_ptr;

            var adj_iter = node.*.adjacency_set.keyIterator();
            while (adj_iter.next()) |adj_id| {
                if (adj_id.* > id) {
                    if (graph.getVertex(adj_id.*)) |other_node| {
                        node.*.data.interact(&other_node.data);
                    }
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

        // Debug print every 100 iterations
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
