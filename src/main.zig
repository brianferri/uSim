const std = @import("std");
const UniverseLib = @import("root.zig");
const stat = @import("./util/stat.zig").stat;

const Graph = UniverseLib.Graph;
const String = UniverseLib.String;

pub fn main() !void {
    const time = std.time;
    const Timer = time.Timer;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var graph = Graph(usize, usize).init(allocator, 0);
    defer graph.deinit();

    var file = try std.fs.cwd().createFile("out.csv", .{});
    defer file.close();

    _ = try file.write("iter,vertices,num_edges,iter_time,mem\n");

    var outer_timer = try Timer.start();
    var timer = try Timer.start();
    for (0..450) |i| {
        // timer = try Timer.start();
        _ = try graph.addVertex(i);
        // std.debug.print("Adding index1: {d:.3}ms\n", .{
        //     @as(f64, @floatFromInt(timer.read())) / time.ns_per_ms,
        // });

        // timer = try Timer.start();
        _ = try graph.addVertex(456);
        // std.debug.print("Adding index2: {d:.3}ms\n", .{
        //     @as(f64, @floatFromInt(timer.read())) / time.ns_per_ms,
        // });

        var vertices1 = graph.vertices.keyIterator();

        timer = try Timer.start();
        while (vertices1.next()) |vertex1| {
            // if (graph.getVertex(vertex1.*).?.adjacency_set.count() >= 5) continue;
            var vertices2 = graph.vertices.keyIterator();
            while (vertices2.next()) |vertex2| {
                // if (graph.getVertex(vertex2.*).?.adjacency_set.count() >= 5) continue;
                if (vertex1 == vertex2) continue;

                // timer = try Timer.start();
                // const v1n = graph.getVertex(vertex1.*).?.adjacency_set;
                // const v2n = graph.getVertex(vertex2.*).?.adjacency_set;
                // std.debug.print("Getting Neighbors: {d:.3}ms\n", .{
                //     @as(f64, @floatFromInt(timer.read())) / time.ns_per_ms,
                // });

                // std.debug.print("Vertex {d} Neighbors: {d}\n", .{ vertex1.*, v1n.?.count() });
                // std.debug.print("Vertex {d} Neighbors: {d}\n", .{ vertex2.*, v2n.?.count() });

                // timer = try Timer.start();
                try graph.addEdge(vertex1.*, vertex2.*);
                try graph.addEdge(vertex2.*, vertex1.*);
                // std.debug.print("Adding edge: {d:.3}ms\n", .{
                //     @as(f64, @floatFromInt(timer.read())) / time.ns_per_ms,
                // });
            }
        }
        const iter_time = @as(f64, @floatFromInt(timer.read())) / time.ns_per_ms;
        // std.debug.print("Adding edges between all vertices: {d:.3}ms\n", .{
        //     @as(f64, @floatFromInt(iter_time)) / time.ns_per_ms,
        // });
        var buf: [1000]u8 = undefined;
        const stats = try stat(&buf);
        var edges: u64 = 0;

        var vertices = graph.vertices.valueIterator();
        while (vertices.next()) |v| {
            edges += v.*.adjacency_set.count();
        }

        _ = try file.write(try std.fmt.allocPrint(std.heap.page_allocator, "{d},{d},{d},{d},{d}\n", .{ i, graph.vertices.count(), edges, iter_time, stats.rss }));

        // timer = try Timer.start();
        // std.debug.print("{d} vertices\n", .{graph.vertices.count()});
        // std.debug.print("Counting vertices: {d:.3}ms\n\n", .{
        //     @as(f64, @floatFromInt(timer.read())) / time.ns_per_ms,
        // });
    }
    std.debug.print("Time to complete tasks: {d:.3}ms\n", .{
        @as(f64, @floatFromInt(outer_timer.read())) / time.ns_per_ms,
    });
}
