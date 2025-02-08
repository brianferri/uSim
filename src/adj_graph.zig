const std = @import("std");
const testing = std.testing;

pub fn Graph(comptime K: type, comptime T: type) type {
    return struct {
        const Self = @This();
        allocator: std.mem.Allocator,

        vertices: std.AutoHashMap(K, T),
        adjacency_lists: std.AutoHashMap(K, std.AutoHashMap(K, void)),
        next_vertex_index: K,

        pub fn init(allocator: std.mem.Allocator, initial_index: K) Self {
            return .{
                .allocator = allocator,
                .vertices = std.AutoHashMap(K, T).init(allocator),
                .adjacency_lists = std.AutoHashMap(K, std.AutoHashMap(K, void)).init(allocator),
                .next_vertex_index = initial_index,
            };
        }

        pub fn deinit(self: *Self) void {
            self.vertices.deinit();
            var adj_lists_iter = self.adjacency_lists.valueIterator();
            while (adj_lists_iter.next()) |item| {
                item.deinit();
            }
            self.adjacency_lists.deinit();
            self.* = undefined;
        }

        pub fn addVertex(self: *Self, data: T) !K {
            // Consider using `getOrPut` to avoid clobbering data
            try self.vertices.put(self.next_vertex_index, data);
            try self.adjacency_lists.put(self.next_vertex_index, std.AutoHashMap(K, void).init(self.allocator));
            self.next_vertex_index += 1;
            return self.next_vertex_index;
        }

        pub fn getVertex(self: *Self, index: K) ?T {
            return self.vertices.get(index);
        }

        pub fn removeVertex(self: *Self, index: K) bool {
            return self.vertices.remove(index);
        }

        pub fn hasEdge(self: *Self, v1: K, v2: K) bool {
            if (!self.adjacency_lists.contains(v1)) return false;
            if (self.adjacency_lists.get(v1)) |v1_adj_list| {
                if (v1_adj_list.get(v2) != null) return true;
            }
            return false;
        }

        pub fn addEdge(self: *Self, v1: K, v2: K) !void {
            if (self.hasEdge(v1, v2)) return;
            if (self.adjacency_lists.getPtr(v1)) |vertex_adjacency_list| {
                try vertex_adjacency_list.put(v2, {});
            }
        }

        pub fn removeEdge(self: *Self, v1: K, v2: K) !void {
            if (!self.hasEdge(v1, v2)) return;
            if (self.adjacency_lists.getPtr(v1)) |vertex_adjacency_list| {
                _ = vertex_adjacency_list.remove(v2);
            }
        }

        pub fn setVertex(self: *Self, index: K, data: T) !void {
            try self.vertices.put(index, data);
        }

        pub fn getNeighbors(self: *Self, index: K) ?std.ArrayList(K) {
            return self.adjacency_lists.get(index);
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
    try testing.expect(graph.getVertex(index - 1) == 123);
}

test "add edge between two vertices" {
    var graph = Graph(usize, u32).init(testing.allocator, 0);
    defer graph.deinit();
    const index1 = try graph.addVertex(123);
    const index2 = try graph.addVertex(456);
    const has_edge_before = graph.hasEdge(index1, index2);
    try testing.expect(!has_edge_before);
    try graph.addEdge(index1, index2);
    const has_edge_after = graph.hasEdge(index1, index2);
    try testing.expect(has_edge_after);
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
