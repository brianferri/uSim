const std = @import("std");
const testing = std.testing;

pub fn Graph(
    comptime K: type,
    comptime V: type,
    comptime nextFn: ?fn (K) K,
    comptime compareFn: ?fn (a: K, b: K) std.math.Order,
) type {
    return struct {
        pub const Node = struct {
            const Edges = std.AutoHashMapUnmanaged(K, void);

            data: V,
            outgoing: Edges,
            incoming: Edges,

            pub fn init(data: V) Node {
                return .{
                    .data = data,
                    .outgoing = .empty,
                    .incoming = .empty,
                };
            }

            pub fn deinit(self: *Node, allocator: std.mem.Allocator) void {
                self.outgoing.deinit(allocator);
                self.incoming.deinit(allocator);
                self.* = undefined;
            }

            pub fn pointsTo(self: *Node, vertex: K) bool {
                return self.outgoing.contains(vertex);
            }

            pub fn pointedBy(self: *Node, vertex: K) bool {
                return self.incoming.contains(vertex);
            }

            pub fn addAdjEdge(self: *Node, allocator: std.mem.Allocator, vertex: K) !void {
                try self.outgoing.put(allocator, vertex, {});
            }

            pub fn removeAdjEdge(self: *Node, vertex: K) !void {
                _ = self.outgoing.remove(vertex);
            }

            pub fn addIncEdge(self: *Node, allocator: std.mem.Allocator, vertex: K) !void {
                try self.incoming.put(allocator, vertex, {});
            }

            pub fn removeIncEdge(self: *Node, vertex: K) !void {
                _ = self.incoming.remove(vertex);
            }
        };

        const Vertices = std.AutoHashMapUnmanaged(K, *Node);
        const Self = @This();

        fn compareFnAuto(context: void, a: K, b: K) std.math.Order {
            if (compareFn == null) @panic("This graph doesn't support index comparisons");
            _ = context;
            return compareFn.?(a, b);
        }

        vertices: Vertices,
        next_id: K,
        free_ids: std.PriorityQueue(K, void, compareFnAuto),

        fn init(allocator: std.mem.Allocator, first_id: K) Self {
            return .{
                .vertices = .empty,
                .next_id = first_id,
                .free_ids = .init(allocator, {}),
            };
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            var vertex_iterator = self.vertices.valueIterator();

            while (vertex_iterator.next()) |vertex| {
                vertex.*.deinit(allocator);
                allocator.destroy(vertex.*);
            }

            self.free_ids.deinit();
            self.vertices.deinit(allocator);
            self.* = undefined;
        }

        /// Assumes the index is free.
        /// One should use `getVertex` first to make sure the index doesn't exist
        /// and `removeVertex` if it does
        pub fn putVertex(self: *Self, allocator: std.mem.Allocator, index: K, data: V) !void {
            const node = try allocator.create(Node);
            node.* = .init(data);
            try self.vertices.put(allocator, index, node);
        }

        pub fn putVertexAuto(self: *Self, allocator: std.mem.Allocator, data: V) !K {
            if (nextFn == null) @panic("This graph doesn't support auto indexing");
            var id: K = undefined;

            if (self.free_ids.removeOrNull()) |recycled| id = recycled else {
                id = self.next_id;
                self.next_id = nextFn.?(self.next_id);
            }
            try self.putVertex(allocator, id, data);
            return id;
        }

        pub fn getVertex(self: *Self, index: K) ?*Node {
            return self.vertices.get(index);
        }

        pub fn getVertexData(self: *Self, index: K) ?V {
            return if (self.getVertex(index)) |v| v.*.data else null;
        }

        /// If there is an `Entry` with a matching key, it is deleted from
        /// the hash map, and this function returns true.  Otherwise this
        /// function returns false.
        pub fn removeVertex(self: *Self, allocator: std.mem.Allocator, index: K) bool {
            if (self.getVertex(index)) |vertex| {
                var vertex_iterator = self.vertices.iterator();
                while (vertex_iterator.next()) |entry| {
                    try self.removeEdge(entry.key_ptr.*, index);
                }

                vertex.deinit(allocator);
                allocator.destroy(vertex);

                if (self.vertices.remove(index)) {
                    self.free_ids.add(index) catch {};
                    return true;
                }
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

        pub fn addEdge(self: *Self, allocator: std.mem.Allocator, v1: K, v2: K) !void {
            //? Check helps branch prediction
            if (self.hasAdjEdge(v1, v2) or self.hasIncEdge(v2, v1)) return;

            if (self.getVertex(v1)) |v| {
                try v.addAdjEdge(allocator, v2);
            }

            if (self.getVertex(v2)) |v| {
                try v.addIncEdge(allocator, v1);
            }
        }

        pub fn removeEdge(self: *Self, v1: K, v2: K) !void {
            //? Check helps branch prediction
            if (!self.hasAdjEdge(v1, v2) or !self.hasIncEdge(v2, v1)) return;

            if (self.getVertex(v1)) |v| {
                try v.removeAdjEdge(v2);
            }

            if (self.getVertex(v2)) |v| {
                try v.removeIncEdge(v1);
            }
        }

        pub fn setVertex(self: *Self, allocator: std.mem.Allocator, index: K, data: V) !void {
            try self.vertices.put(allocator, index, data);
        }
    };
}

pub fn AutoGraph(comptime K: type, comptime T: type) type {
    return Graph(K, T, null, null);
}

test "graph initialization" {
    var graph: AutoGraph(usize, u32) = .init(testing.allocator, 0);
    defer graph.deinit(testing.allocator);
}

test "add vertex" {
    var graph: AutoGraph(usize, u32) = .init(testing.allocator, 0);
    defer graph.deinit(testing.allocator);

    try graph.putVertex(testing.allocator, 1, 123);

    try testing.expect(graph.getVertexData(1) == 123);
}

test "add and remove vertex" {
    var graph: AutoGraph(usize, u32) = .init(testing.allocator, 0);
    defer graph.deinit(testing.allocator);

    try graph.putVertex(testing.allocator, 1, 123);

    try testing.expect(graph.getVertexData(1) == 123);
    try testing.expect(graph.removeVertex(testing.allocator, 1) == true);
    try testing.expect(graph.getVertexData(1) == null);
}

test "add edge between two vertices" {
    var graph: AutoGraph(usize, u32) = .init(testing.allocator, 0);
    defer graph.deinit(testing.allocator);

    try graph.putVertex(testing.allocator, 1, 123);
    try graph.putVertex(testing.allocator, 2, 456);

    try testing.expect(!graph.hasAdjEdge(1, 2));
    try graph.addEdge(testing.allocator, 1, 2);
    try testing.expect(graph.hasAdjEdge(1, 2));
}

test "add and remove an edge" {
    var graph: AutoGraph(usize, u32) = .init(testing.allocator, 0);
    defer graph.deinit(testing.allocator);

    try graph.putVertex(testing.allocator, 1, 123);
    try graph.putVertex(testing.allocator, 2, 456);

    try graph.addEdge(testing.allocator, 1, 2);
    try testing.expect(graph.hasAdjEdge(1, 2));

    try graph.removeEdge(1, 2);
    try testing.expect(!graph.hasAdjEdge(1, 2));
}

test "add vertexes and edges, remove vertex, test for edges" {
    var graph: AutoGraph(usize, u32) = .init(testing.allocator, 0);
    defer graph.deinit(testing.allocator);

    try graph.putVertex(testing.allocator, 1, 123);
    try testing.expect(graph.getVertexData(1) == 123);
    try graph.putVertex(testing.allocator, 2, 456);
    try testing.expect(graph.getVertexData(2) == 456);

    try testing.expect(!graph.hasAdjEdge(1, 2));
    try graph.addEdge(testing.allocator, 1, 2);
    try testing.expect(graph.hasAdjEdge(1, 2));

    try testing.expect(!graph.hasAdjEdge(2, 1));
    try graph.addEdge(testing.allocator, 2, 1);
    try testing.expect(graph.hasAdjEdge(2, 1));

    try testing.expect(graph.removeVertex(testing.allocator, 1));
    try testing.expect(graph.getVertexData(1) == null);
    try testing.expect(!graph.hasAdjEdge(1, 2));
    try testing.expect(!graph.hasAdjEdge(2, 1));
}

test "getting neighbors" {
    var graph: AutoGraph(usize, u32) = .init(testing.allocator, 0);
    defer graph.deinit(testing.allocator);

    try graph.putVertex(testing.allocator, 1, 123);
    try testing.expect(graph.getVertexData(1) == 123);
    try graph.putVertex(testing.allocator, 2, 456);
    try testing.expect(graph.getVertexData(2) == 456);

    try testing.expect(!graph.hasAdjEdge(1, 2));
    try graph.addEdge(testing.allocator, 1, 2);
    try testing.expect(graph.hasAdjEdge(1, 2));

    try testing.expect(graph.getVertex(1).?.pointsTo(2));
    try testing.expect(!graph.getVertex(2).?.pointsTo(1));

    try testing.expect(graph.getVertex(2).?.pointedBy(1));
    try testing.expect(!graph.getVertex(1).?.pointedBy(2));
}

test "graph in a graph" {
    var graph = AutoGraph(usize, AutoGraph(usize, u32)).init(testing.allocator, 0);
    defer graph.deinit(testing.allocator);

    try graph.putVertex(testing.allocator, 1, .init(testing.allocator, 0));
    var inner_graph_data: AutoGraph(usize, u32) = graph.getVertexData(1).?;
    defer inner_graph_data.deinit(testing.allocator);

    try inner_graph_data.putVertex(testing.allocator, 1, 123);
    try testing.expect(inner_graph_data.getVertexData(1) == 123);
}

fn nextUsize(curr: usize) usize {
    return curr + 1;
}

fn lessThan(a: usize, b: usize) std.math.Order {
    return std.math.order(a, b);
}

test "putVertexAuto basic increasing IDs" {
    var graph: Graph(usize, u32, nextUsize, lessThan) =
        .init(testing.allocator, 0);
    defer graph.deinit(testing.allocator);

    const id1 = try graph.putVertexAuto(testing.allocator, 100);
    const id2 = try graph.putVertexAuto(testing.allocator, 200);
    const id3 = try graph.putVertexAuto(testing.allocator, 300);

    try testing.expect(id1 == 0);
    try testing.expect(id2 == 1);
    try testing.expect(id3 == 2);

    try testing.expect(graph.getVertexData(0) == 100);
    try testing.expect(graph.getVertexData(1) == 200);
    try testing.expect(graph.getVertexData(2) == 300);
}

test "putVertexAuto reuses freed IDs" {
    var graph: Graph(usize, u32, nextUsize, lessThan) =
        .init(testing.allocator, 0);
    defer graph.deinit(testing.allocator);

    const a = try graph.putVertexAuto(testing.allocator, 11);
    const b = try graph.putVertexAuto(testing.allocator, 22);
    const c = try graph.putVertexAuto(testing.allocator, 33);

    try testing.expect(a == 0);
    try testing.expect(b == 1);
    try testing.expect(c == 2);

    try testing.expect(graph.removeVertex(testing.allocator, 1));

    const d = try graph.putVertexAuto(testing.allocator, 44);

    try testing.expect(d == 1);
    try testing.expect(graph.getVertexData(1) == 44);

    const e = try graph.putVertexAuto(testing.allocator, 55);
    try testing.expect(e == 3);
}

const Letter = struct {
    c: u8,
};
fn nextLetter(k: Letter) Letter {
    return .{ .c = k.c + 1 };
}
fn lessThanLetter(k1: Letter, k2: Letter) std.math.Order {
    return std.math.order(k1.c, k2.c);
}
test "putVertexAuto works with non-numeric key" {
    var graph: Graph(Letter, u32, nextLetter, lessThanLetter) =
        .init(testing.allocator, .{ .c = 'a' });
    defer graph.deinit(testing.allocator);

    const id1 = try graph.putVertexAuto(testing.allocator, 10);
    const id2 = try graph.putVertexAuto(testing.allocator, 20);
    const id3 = try graph.putVertexAuto(testing.allocator, 30);

    try testing.expect(id1.c == 'a');
    try testing.expect(id2.c == 'b');
    try testing.expect(id3.c == 'c');

    try testing.expect(graph.getVertexData(.{ .c = 'b' }) == 20);

    try testing.expect(graph.removeVertex(testing.allocator, .{ .c = 'b' }));

    const id4 = try graph.putVertexAuto(testing.allocator, 40);
    try testing.expect(id4.c == 'b');
}
