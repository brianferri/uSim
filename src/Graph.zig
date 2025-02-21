const std = @import("std");
const testing = std.testing;

pub fn Graph(comptime K: type, comptime T: type) type {
    return struct {
        const Node = struct {
            const FakeSet = std.AutoHashMap(K, void);

            data: T,
            adjacency_set: FakeSet,
            incidency_set: FakeSet,

            pub fn init(allocator: std.mem.Allocator, data: T) Node {
                return .{
                    .data = data,
                    .adjacency_set = FakeSet.init(allocator),
                    .incidency_set = FakeSet.init(allocator),
                };
            }

            pub fn deinit(self: *Node) void {
                self.adjacency_set.deinit();
                self.incidency_set.deinit();
                self.* = undefined;
            }

            pub fn pointsTo(self: *Node, vertex: K) bool {
                return self.adjacency_set.contains(vertex);
            }

            pub fn pointedBy(self: *Node, vertex: K) bool {
                return self.incidency_set.contains(vertex);
            }

            pub fn addAdjEdge(self: *Node, vertex: K) !void {
                try self.adjacency_set.put(vertex, {});
            }

            pub fn removeAdjEdge(self: *Node, vertex: K) !void {
                _ = self.adjacency_set.remove(vertex);
            }

            pub fn addIncEdge(self: *Node, vertex: K) !void {
                try self.incidency_set.put(vertex, {});
            }

            pub fn removeIncEdge(self: *Node, vertex: K) !void {
                _ = self.incidency_set.remove(vertex);
            }
        };

        const Vertices = std.AutoHashMap(K, *Node);
        const Self = @This();
        allocator: std.mem.Allocator,

        vertices: Vertices,
        next_vertex_index: K,

        pub fn init(allocator: std.mem.Allocator, initial_index: K) Self {
            return .{
                .allocator = allocator,
                .vertices = Vertices.init(allocator),
                .next_vertex_index = initial_index,
            };
        }

        pub fn deinit(self: *Self) void {
            var vertex_iterator = self.vertices.valueIterator();

            while (vertex_iterator.next()) |vertex| {
                vertex.*.deinit();
                self.allocator.destroy(vertex.*);
            }

            self.vertices.deinit();
            self.* = undefined;
        }

        pub fn addVertex(self: *Self, data: T) !K {
            const node = try self.allocator.create(Node);
            node.* = Node.init(self.allocator, data);

            try self.vertices.put(self.next_vertex_index, node);
            self.next_vertex_index += 1;
            return self.next_vertex_index - 1;
        }

        pub fn getVertex(self: *Self, index: K) ?*Node {
            return self.vertices.get(index);
        }

        pub fn getVertexData(self: *Self, index: K) ?T {
            return if (self.getVertex(index)) |v| v.*.data else null;
        }

        pub fn removeVertex(self: *Self, index: K) bool {
            if (self.getVertex(index)) |vertex| {
                var vertex_iterator = self.vertices.iterator();
                while (vertex_iterator.next()) |entry| {
                    try self.removeEdge(entry.key_ptr.*, index);
                }

                vertex.deinit();
                self.allocator.destroy(vertex);

                return self.vertices.remove(index);
            }

            return false;
        }

        /// Is directional
        ///
        /// Only checks if vertex `v1` is "pointing" to vertex `v2`
        pub fn hasAdjEdge(self: *Self, v1: K, v2: K) bool {
            if (self.getVertex(v1)) |v| {
                return v.pointsTo(v2);
            }

            return false;
        }

        /// Is directional
        ///
        /// Only checks if the vertex `v1` is being pointed by vertex `v2`
        pub fn hasIncEdge(self: *Self, v1: K, v2: K) bool {
            if (self.getVertex(v1)) |v| {
                return v.pointedBy(v2);
            }

            return false;
        }

        pub fn addEdge(self: *Self, v1: K, v2: K) !void {
            //? This check is here to help cache misses???
            // TODO: Verify if the above is true
            if (self.hasAdjEdge(v1, v2) or self.hasIncEdge(v2, v1)) return;

            if (self.getVertex(v1)) |v| {
                try v.addAdjEdge(v2);
            }

            if (self.getVertex(v2)) |v| {
                try v.addIncEdge(v1);
            }
        }

        pub fn removeEdge(self: *Self, v1: K, v2: K) !void {
            //? This check is here to help cache misses???
            // TODO: Verify if the above is true
            if (!self.hasAdjEdge(v1, v2) or !self.hasIncEdge(v2, v1)) return;

            if (self.getVertex(v1)) |v| {
                try v.removeAdjEdge(v2);
            }

            if (self.getVertex(v2)) |v| {
                try v.removeIncEdge(v1);
            }
        }

        pub fn setVertex(self: *Self, index: K, data: T) !void {
            try self.vertices.put(index, data);
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

    try testing.expect(graph.getVertexData(index) == 123);
}

test "add and remove vertex" {
    var graph = Graph(usize, u32).init(testing.allocator, 0);
    defer graph.deinit();

    const index = try graph.addVertex(123);

    try testing.expect(graph.getVertexData(index) == 123);
    try testing.expect(graph.removeVertex(index) == true);
    try testing.expect(graph.getVertexData(index) == null);
}

test "add edge between two vertices" {
    var graph = Graph(usize, u32).init(testing.allocator, 0);
    defer graph.deinit();

    const index1 = try graph.addVertex(123);
    const index2 = try graph.addVertex(456);

    try testing.expect(!graph.hasAdjEdge(index1, index2));
    try graph.addEdge(index1, index2);
    try testing.expect(graph.hasAdjEdge(index1, index2));
}

test "add and remove an edge" {
    var graph = Graph(usize, u32).init(testing.allocator, 0);
    defer graph.deinit();

    const index1 = try graph.addVertex(123);
    const index2 = try graph.addVertex(456);

    try graph.addEdge(index1, index2);
    try testing.expect(graph.hasAdjEdge(index1, index2));

    try graph.removeEdge(index1, index2);
    try testing.expect(!graph.hasAdjEdge(index1, index2));
}

test "add vertexes and edges, remove vertex, test for edges" {
    var graph = Graph(usize, u32).init(testing.allocator, 0);
    defer graph.deinit();

    const index1 = try graph.addVertex(123);
    try testing.expect(graph.getVertexData(index1) == 123);
    const index2 = try graph.addVertex(456);
    try testing.expect(graph.getVertexData(index2) == 456);

    try testing.expect(!graph.hasAdjEdge(index1, index2));
    try graph.addEdge(index1, index2);
    try testing.expect(graph.hasAdjEdge(index1, index2));

    try testing.expect(!graph.hasAdjEdge(index2, index1));
    try graph.addEdge(index2, index1);
    try testing.expect(graph.hasAdjEdge(index2, index1));

    try testing.expect(graph.removeVertex(index1));
    try testing.expect(graph.getVertexData(index1) == null);
    try testing.expect(!graph.hasAdjEdge(index1, index2));
    try testing.expect(!graph.hasAdjEdge(index2, index1));
}

test "getting neighbors" {
    var graph = Graph(usize, u32).init(testing.allocator, 0);
    defer graph.deinit();

    const index1 = try graph.addVertex(123);
    try testing.expect(graph.getVertexData(index1) == 123);
    const index2 = try graph.addVertex(456);
    try testing.expect(graph.getVertexData(index2) == 456);

    try testing.expect(!graph.hasAdjEdge(index1, index2));
    try graph.addEdge(index1, index2);
    try testing.expect(graph.hasAdjEdge(index1, index2));

    try testing.expect(graph.getVertex(index1).?.pointsTo(index2));
    try testing.expect(!graph.getVertex(index2).?.pointsTo(index1));

    try testing.expect(graph.getVertex(index2).?.pointedBy(index1));
    try testing.expect(!graph.getVertex(index1).?.pointedBy(index2));
}

test "graph in a graph" {
    var graph = Graph(usize, Graph(usize, u32)).init(testing.allocator, 0);
    defer graph.deinit();

    const index = try graph.addVertex(Graph(usize, u32).init(testing.allocator, 0));
    var inner_graph_data: Graph(usize, u32) = graph.getVertexData(index).?;
    defer inner_graph_data.deinit();

    const inner_index = try inner_graph_data.addVertex(123);
    try testing.expect(inner_graph_data.getVertexData(inner_index) == 123);
}
