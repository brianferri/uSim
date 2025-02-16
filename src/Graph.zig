const std = @import("std");
const stat = @import("./stat.zig").stat;
const testing = std.testing;

pub fn Graph(comptime K: type, comptime T: type) type {
    return struct {
        const Self = @This();
        allocator: std.mem.Allocator,

        vertices: std.AutoHashMap(K, T),
        adjacency_lists: std.AutoHashMap(K, std.AutoHashMap(K, void)),
        incidency_lists: std.AutoHashMap(K, std.AutoHashMap(K, void)),
        next_vertex_index: K,

        pub fn init(allocator: std.mem.Allocator, initial_index: K) Self {
            return .{
                .allocator = allocator,
                .vertices = std.AutoHashMap(K, T).init(allocator),
                .adjacency_lists = std.AutoHashMap(K, std.AutoHashMap(K, void)).init(allocator),
                .incidency_lists = std.AutoHashMap(K, std.AutoHashMap(K, void)).init(allocator),
                .next_vertex_index = initial_index,
            };
        }

        pub fn deinit(self: *Self) void {
            self.vertices.deinit();
            var adj_lists_iter = self.adjacency_lists.valueIterator();
            while (adj_lists_iter.next()) |list| {
                list.deinit();
            }
            self.adjacency_lists.deinit();
            var inc_lists_iter = self.incidency_lists.valueIterator();
            while (inc_lists_iter.next()) |list| {
                list.deinit();
            }
            self.incidency_lists.deinit();
            self.* = undefined;
        }

        pub fn addVertex(self: *Self, data: T) !K {
            // Consider using `getOrPut` to avoid clobbering data
            try self.vertices.put(self.next_vertex_index, data);
            try self.adjacency_lists.put(self.next_vertex_index, std.AutoHashMap(K, void).init(self.allocator));
            try self.incidency_lists.put(self.next_vertex_index, std.AutoHashMap(K, void).init(self.allocator));
            self.next_vertex_index += 1;
            return self.next_vertex_index - 1;
        }

        pub fn getVertex(self: *Self, index: K) ?T {
            return self.vertices.get(index);
        }

        pub fn removeVertex(self: *Self, index: K) bool {
            if (!self.vertices.contains(index)) return false;
            if (self.incidency_lists.get(index)) |i| {
                var incident_vertexes = i.keyIterator();
                while (incident_vertexes.next()) |incident_vertex| {
                    if (self.adjacency_lists.getPtr(incident_vertex.*)) |adj_ptr|
                        _ = adj_ptr.remove(index);
                }
            }
            if (self.adjacency_lists.getPtr(index)) |list| list.deinit();
            return self.adjacency_lists.remove(index) and self.vertices.remove(index);
        }

        /// Is directional
        ///
        /// Only checks if vertex `v1` is "pointing" to vertex `v2`
        pub fn hasEdge(self: *Self, v1: K, v2: K) bool {
            if (self.adjacency_lists.get(v1)) |v1_adjacency_list| {
                if (v1_adjacency_list.get(v2) != null) return true;
            }
            return false;
        }

        pub fn addEdge(self: *Self, v1: K, v2: K) !void {
            if (self.hasEdge(v1, v2)) return;
            if (self.adjacency_lists.getPtr(v1)) |v1_adjacency_list| {
                try v1_adjacency_list.put(v2, {});
            }
            if (self.incidency_lists.getPtr(v2)) |v2_incidency_list| {
                try v2_incidency_list.put(v1, {});
            }
        }

        pub fn removeEdge(self: *Self, v1: K, v2: K) !void {
            if (!self.hasEdge(v1, v2)) return;
            if (self.adjacency_lists.getPtr(v1)) |v1_adjacency_list| {
                _ = v1_adjacency_list.remove(v2);
            }
            if (self.incidency_lists.getPtr(v2)) |v2_incidency_list| {
                _ = v2_incidency_list.remove(v1);
            }
        }

        pub fn setVertex(self: *Self, index: K, data: T) !void {
            try self.vertices.put(index, data);
        }

        pub fn getAdjNeighbors(self: *Self, index: K) std.AutoHashMap(K, void) {
            return if (self.adjacency_lists.get(index)) |adjacency_list| return adjacency_list else unreachable;
        }

        pub fn getIncNeighbors(self: *Self, index: K) std.AutoHashMap(K, void) {
            return if (self.incidency_lists.get(index)) |incidency_list| return incidency_list else unreachable;
        }
    };
}

test "graph initialization" {
    var graph = Graph(usize, u32).init(testing.allocator, 0);
    defer graph.deinit();
}

test "add vertex" {
    var graph = Graph(usize, u32).init(testing.allocator, 0);
    defer graph.deinit();

    const index = try graph.addVertex(123);

    try testing.expect(graph.getVertex(index) == 123);
}

test "add and remove vertex" {
    var graph = Graph(usize, u32).init(testing.allocator, 0);
    defer graph.deinit();

    const index = try graph.addVertex(123);

    try testing.expect(graph.getVertex(index) == 123);
    try testing.expect(graph.removeVertex(index) == true);
    try testing.expect(graph.getVertex(index) == null);
}

test "add edge between two vertices" {
    var graph = Graph(usize, u32).init(testing.allocator, 0);
    defer graph.deinit();

    const index1 = try graph.addVertex(123);
    const index2 = try graph.addVertex(456);

    try testing.expect(!graph.hasEdge(index1, index2));
    try graph.addEdge(index1, index2);
    try testing.expect(graph.hasEdge(index1, index2));
}

test "add and remove an edge" {
    var graph = Graph(usize, u32).init(testing.allocator, 0);
    defer graph.deinit();

    const index1 = try graph.addVertex(123);
    const index2 = try graph.addVertex(456);

    try graph.addEdge(index1, index2);
    try testing.expect(graph.hasEdge(index1, index2));

    try graph.removeEdge(index1, index2);
    try testing.expect(!graph.hasEdge(index1, index2));
}

test "add vertexes and edges, remove vertex, test for edges" {
    var graph = Graph(usize, u32).init(testing.allocator, 0);
    defer graph.deinit();

    const index1 = try graph.addVertex(123);
    try testing.expect(graph.getVertex(index1) == 123);
    const index2 = try graph.addVertex(456);
    try testing.expect(graph.getVertex(index2) == 456);

    try testing.expect(!graph.hasEdge(index1, index2));
    try graph.addEdge(index1, index2);
    try testing.expect(graph.hasEdge(index1, index2));

    try testing.expect(!graph.hasEdge(index2, index1));
    try graph.addEdge(index2, index1);
    try testing.expect(graph.hasEdge(index2, index1));

    try testing.expect(graph.removeVertex(index1));
    try testing.expect(graph.getVertex(index1) == null);
    try testing.expect(!graph.hasEdge(index1, index2));
    try testing.expect(!graph.hasEdge(index2, index1));
}

test "getting neighbors" {
    var graph = Graph(usize, u32).init(testing.allocator, 0);
    defer graph.deinit();

    const index1 = try graph.addVertex(123);
    try testing.expect(graph.getVertex(index1) == 123);
    const index2 = try graph.addVertex(456);
    try testing.expect(graph.getVertex(index2) == 456);

    try testing.expect(!graph.hasEdge(index1, index2));
    try graph.addEdge(index1, index2);
    try testing.expect(graph.hasEdge(index1, index2));

    try testing.expect(graph.getAdjNeighbors(index1).contains(index2));
    try testing.expect(!graph.getAdjNeighbors(index2).contains(index1));

    try testing.expect(graph.getIncNeighbors(index2).contains(index1));
    try testing.expect(!graph.getIncNeighbors(index1).contains(index2));
}

pub fn main() !void {
    const time = std.time;
    const Timer = time.Timer;

    var graph = Graph(usize, usize).init(std.heap.page_allocator, 0);
    defer graph.deinit();

    var file = try std.fs.cwd().createFile("out.csv", .{});
    defer file.close();

    _ = try file.write("iter,vertices,num_edges,iter_time,mem\n");

    // var outer_timer = try Timer.start();
    var timer = try Timer.start();
    for (0..1_000_000) |i| {
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
            // if (graph.getNeighbors(vertex1.*).?.count() >= 5) continue;
            var vertices2 = graph.vertices.keyIterator();
            while (vertices2.next()) |vertex2| {
                // if (graph.getNeighbors(vertex2.*).?.count() >= 5) continue;
                if (vertex1 == vertex2) continue;

                // timer = try Timer.start();
                // const v1n = graph.getNeighbors(vertex1.*);
                // const v2n = graph.getNeighbors(vertex2.*);
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
        const iter_time = timer.read();
        // std.debug.print("Adding edges between all vertices: {d:.3}ms\n", .{
        //     @as(f64, @floatFromInt(iter_time)) / time.ns_per_ms,
        // });
        var buf: [1000]u8 = undefined;
        const stats = try stat(&buf);
        var edges: u64 = 0;
        var adj_lists_val = graph.adjacency_lists.valueIterator();
        while (adj_lists_val.next()) |e| {
            edges += e.count();
        }

        _ = try file.write(try std.fmt.allocPrint(std.heap.page_allocator, "{d},{d},{d},{d},{d}\n", .{ i, graph.vertices.count(), edges, iter_time, stats.rss }));

        // timer = try Timer.start();
        // std.debug.print("{d} vertices\n", .{graph.vertices.count()});
        // std.debug.print("Counting vertices: {d:.3}ms\n\n", .{
        //     @as(f64, @floatFromInt(timer.read())) / time.ns_per_ms,
        // });
    }
    // std.debug.print("Time to complete tasks: {d:.3}ms\n", .{
    //     @as(f64, @floatFromInt(outer_timer.read())) / time.ns_per_ms,
    // });
}
