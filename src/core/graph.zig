const std = @import("std");
const testing = std.testing;

pub fn Graph(
    comptime K: type,
    comptime T: type,
    comptime nextFn: ?fn (K) K,
    comptime compareFn: ?fn (a: K, b: K) std.math.Order,
) type {
    return struct {
        pub const Node = struct {
            const FakeSet = std.AutoHashMap(K, void);

            data: T,
            adjacency_set: FakeSet,
            incidency_set: FakeSet,

            pub fn init(allocator: std.mem.Allocator, data: T) Node {
                return .{
                    .data = data,
                    .adjacency_set = .init(allocator),
                    .incidency_set = .init(allocator),
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

        pub fn compareFnAuto(context: void, a: K, b: K) std.math.Order {
            if (compareFn == null) @panic("This graph doesn't support index comparisons");
            _ = context;
            return compareFn.?(a, b);
        }

        allocator: std.mem.Allocator,
        vertices: Vertices,
        next_id: K,
        free_ids: std.PriorityQueue(K, void, compareFnAuto),

        pub const init = if (nextFn != null) init1 else initAuto;

        fn initAuto(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .vertices = .init(allocator),
                .next_id = undefined,
                .free_ids = .init(allocator, {}),
            };
        }

        fn init1(allocator: std.mem.Allocator, first_id: K) Self {
            return .{
                .allocator = allocator,
                .vertices = .init(allocator),
                .next_id = first_id,
                .free_ids = .init(allocator, {}),
            };
        }

        pub fn deinit(self: *Self) void {
            var vertex_iterator = self.vertices.valueIterator();

            while (vertex_iterator.next()) |vertex| {
                vertex.*.deinit();
                self.allocator.destroy(vertex.*);
            }

            self.free_ids.deinit();
            self.vertices.deinit();
            self.* = undefined;
        }

        /// Assumes the index is free.
        /// One should use `getVertex` first to make sure the index doesn't exist
        /// and `removeVertex` if it does
        pub fn putVertex(self: *Self, index: K, data: T) !void {
            const node = try self.allocator.create(Node);
            node.* = Node.init(self.allocator, data);
            try self.vertices.put(index, node);
        }

        pub fn putVertexAuto(self: *Self, data: T) !K {
            if (nextFn == null) @panic("This graph doesn't support auto indexing");
            var id: K = undefined;

            if (self.free_ids.removeOrNull()) |recycled| id = recycled else {
                id = self.next_id;
                self.next_id = nextFn.?(self.next_id);
            }
            try self.putVertex(id, data);
            return id;
        }

        pub fn getVertex(self: *Self, index: K) ?*Node {
            return self.vertices.get(index);
        }

        pub fn getVertexData(self: *Self, index: K) ?T {
            return if (self.getVertex(index)) |v| v.*.data else null;
        }

        /// If there is an `Entry` with a matching key, it is deleted from
        /// the hash map, and this function returns true.  Otherwise this
        /// function returns false.
        pub fn removeVertex(self: *Self, index: K) !bool {
            const vertex = self.getVertex(index) orelse return false;

            const n_in = vertex.incidency_set.count();
            const n_out = vertex.adjacency_set.count();
            const scratch = try self.allocator.alloc(K, @max(n_in, n_out));
            defer self.allocator.free(scratch);

            var i: usize = 0;
            var inc_it = vertex.incidency_set.iterator();
            while (inc_it.next()) |e| : (i += 1) scratch[i] = e.key_ptr.*;
            for (0..i) |j| try self.removeEdge(scratch[j], index);

            i = 0;
            var adj_it = vertex.adjacency_set.iterator();
            while (adj_it.next()) |e| : (i += 1) scratch[i] = e.key_ptr.*;
            for (0..i) |j| try self.removeEdge(index, scratch[j]);

            vertex.deinit();
            self.allocator.destroy(vertex);

            if (self.vertices.remove(index)) {
                self.free_ids.add(index) catch {};
                return true;
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
            const out_from = self.getVertex(v1) orelse return;
            if (out_from.pointsTo(v2)) return;
            const into = self.getVertex(v2) orelse return;
            try out_from.addAdjEdge(v2);
            try into.addIncEdge(v1);
        }

        /// Same as `addEdge` but skips duplicate checks. Caller must guarantee `v1 -> v2` is absent (e.g. cloning from a consistent graph).
        pub fn addEdgeUnchecked(self: *Self, v1: K, v2: K) !void {
            const out_from = self.getVertex(v1) orelse return;
            const into = self.getVertex(v2) orelse return;
            try out_from.addAdjEdge(v2);
            try into.addIncEdge(v1);
        }

        pub fn removeEdge(self: *Self, v1: K, v2: K) !void {
            const out_from = self.getVertex(v1) orelse return;
            if (!out_from.pointsTo(v2)) return;
            const into = self.getVertex(v2) orelse return;
            try out_from.removeAdjEdge(v2);
            try into.removeIncEdge(v1);
        }

        pub fn setVertex(self: *Self, index: K, data: T) !void {
            if (self.getVertex(index)) |v| {
                v.*.data = data;
            } else {
                return error.VertexNotFound;
            }
        }
    };
}

/// Deep copy for graphs with auto ids (`nextFn`) and a total order on keys (`compareFn`).
pub fn cloneAutoIdGraph(
    comptime K: type,
    comptime T: type,
    comptime nextFn: fn (K) K,
    comptime compareFn: fn (a: K, b: K) std.math.Order,
    self: *const Graph(K, T, nextFn, compareFn),
    allocator: std.mem.Allocator,
) !Graph(K, T, nextFn, compareFn) {
    const G = Graph(K, T, nextFn, compareFn);
    var out: G = .{
        .allocator = allocator,
        .vertices = .init(allocator),
        .next_id = self.next_id,
        .free_ids = blk: {
            var fq = std.PriorityQueue(K, void, G.compareFnAuto).init(allocator, {});
            for (self.free_ids.items) |id| try fq.add(id);
            break :blk fq;
        },
    };
    errdefer out.deinit();

    var vit = self.vertices.iterator();
    while (vit.next()) |ent| {
        const node = ent.value_ptr.*;
        const new_n = try allocator.create(G.Node);
        new_n.* = G.Node.init(allocator, node.data);
        try out.vertices.put(ent.key_ptr.*, new_n);
    }

    vit = self.vertices.iterator();
    while (vit.next()) |ent| {
        const k = ent.key_ptr.*;
        const node = ent.value_ptr.*;
        var aj = node.adjacency_set.iterator();
        while (aj.next()) |ae| {
            try out.addEdgeUnchecked(k, ae.key_ptr.*);
        }
    }
    return out;
}

pub fn AutoGraph(comptime K: type, comptime T: type) type {
    return Graph(K, T, null, null);
}

fn cloneTestNext(x: usize) usize {
    return x + 1;
}

fn cloneTestOrder(a: usize, b: usize) std.math.Order {
    return std.math.order(a, b);
}

test "cloneAutoIdGraph copies structure" {
    const G = Graph(usize, u32, cloneTestNext, cloneTestOrder);
    var g: G = .init(testing.allocator, 0);
    defer g.deinit();
    try g.putVertex(5, 100);
    try g.putVertex(7, 200);
    try g.addEdge(5, 7);

    var c = try cloneAutoIdGraph(usize, u32, cloneTestNext, cloneTestOrder, &g, testing.allocator);
    defer c.deinit();

    try testing.expectEqual(@as(usize, 2), c.vertices.count());
    try testing.expectEqual(@as(u32, 100), c.getVertexData(5).?);
    try testing.expectEqual(@as(u32, 200), c.getVertexData(7).?);
    try testing.expect(c.hasAdjEdge(5, 7));

    try c.setVertex(5, 999);
    try testing.expectEqual(@as(u32, 100), g.getVertexData(5).?);
    try testing.expectEqual(@as(u32, 999), c.getVertexData(5).?);
}

test "graph initialization" {
    var graph: AutoGraph(usize, u32) = .init(testing.allocator);
    defer graph.deinit();
}

test "add vertex" {
    var graph: AutoGraph(usize, u32) = .init(testing.allocator);
    defer graph.deinit();

    try graph.putVertex(1, 123);

    try testing.expect(graph.getVertexData(1) == 123);
}

test "add and remove vertex" {
    var graph: AutoGraph(usize, u32) = .init(testing.allocator);
    defer graph.deinit();

    try graph.putVertex(1, 123);

    try testing.expect(graph.getVertexData(1) == 123);
    try testing.expect(try graph.removeVertex(1));
    try testing.expect(graph.getVertexData(1) == null);
}

test "add edge between two vertices" {
    var graph: AutoGraph(usize, u32) = .init(testing.allocator);
    defer graph.deinit();

    try graph.putVertex(1, 123);
    try graph.putVertex(2, 456);

    try testing.expect(!graph.hasAdjEdge(1, 2));
    try graph.addEdge(1, 2);
    try testing.expect(graph.hasAdjEdge(1, 2));
}

test "add and remove an edge" {
    var graph: AutoGraph(usize, u32) = .init(testing.allocator);
    defer graph.deinit();

    try graph.putVertex(1, 123);
    try graph.putVertex(2, 456);

    try graph.addEdge(1, 2);
    try testing.expect(graph.hasAdjEdge(1, 2));

    try graph.removeEdge(1, 2);
    try testing.expect(!graph.hasAdjEdge(1, 2));
}

test "add vertexes and edges, remove vertex, test for edges" {
    var graph: AutoGraph(usize, u32) = .init(testing.allocator);
    defer graph.deinit();

    try graph.putVertex(1, 123);
    try testing.expect(graph.getVertexData(1) == 123);
    try graph.putVertex(2, 456);
    try testing.expect(graph.getVertexData(2) == 456);

    try testing.expect(!graph.hasAdjEdge(1, 2));
    try graph.addEdge(1, 2);
    try testing.expect(graph.hasAdjEdge(1, 2));

    try testing.expect(!graph.hasAdjEdge(2, 1));
    try graph.addEdge(2, 1);
    try testing.expect(graph.hasAdjEdge(2, 1));

    try testing.expect(try graph.removeVertex(1));
    try testing.expect(graph.getVertexData(1) == null);
    try testing.expect(!graph.hasAdjEdge(1, 2));
    try testing.expect(!graph.hasAdjEdge(2, 1));
}

test "getting neighbors" {
    var graph: AutoGraph(usize, u32) = .init(testing.allocator);
    defer graph.deinit();

    try graph.putVertex(1, 123);
    try testing.expect(graph.getVertexData(1) == 123);
    try graph.putVertex(2, 456);
    try testing.expect(graph.getVertexData(2) == 456);

    try testing.expect(!graph.hasAdjEdge(1, 2));
    try graph.addEdge(1, 2);
    try testing.expect(graph.hasAdjEdge(1, 2));

    try testing.expect(graph.getVertex(1).?.pointsTo(2));
    try testing.expect(!graph.getVertex(2).?.pointsTo(1));

    try testing.expect(graph.getVertex(2).?.pointedBy(1));
    try testing.expect(!graph.getVertex(1).?.pointedBy(2));
}

test "graph in a graph" {
    var graph = AutoGraph(usize, AutoGraph(usize, u32)).init(testing.allocator);
    defer graph.deinit();

    try graph.putVertex(1, AutoGraph(usize, u32).init(testing.allocator));
    var inner_graph_data: AutoGraph(usize, u32) = graph.getVertexData(1).?;
    defer inner_graph_data.deinit();

    try inner_graph_data.putVertex(1, 123);
    try testing.expect(inner_graph_data.getVertexData(1) == 123);
}

fn nextUsize(curr: usize) usize {
    return curr + 1;
}

fn lessThan(a: usize, b: usize) std.math.Order {
    return std.math.order(a, b);
}

test "putVertexAuto basic increasing IDs" {
    var graph = Graph(usize, u32, nextUsize, lessThan).init(testing.allocator, 0);
    defer graph.deinit();

    const id1 = try graph.putVertexAuto(100);
    const id2 = try graph.putVertexAuto(200);
    const id3 = try graph.putVertexAuto(300);

    try testing.expect(id1 == 0);
    try testing.expect(id2 == 1);
    try testing.expect(id3 == 2);

    try testing.expect(graph.getVertexData(0) == 100);
    try testing.expect(graph.getVertexData(1) == 200);
    try testing.expect(graph.getVertexData(2) == 300);
}

test "putVertexAuto reuses freed IDs" {
    var graph = Graph(usize, u32, nextUsize, lessThan).init(testing.allocator, 0);
    defer graph.deinit();

    const a = try graph.putVertexAuto(11);
    const b = try graph.putVertexAuto(22);
    const c = try graph.putVertexAuto(33);

    try testing.expect(a == 0);
    try testing.expect(b == 1);
    try testing.expect(c == 2);

    try testing.expect(try graph.removeVertex(1));

    const d = try graph.putVertexAuto(44);

    try testing.expect(d == 1);
    try testing.expect(graph.getVertexData(1) == 44);

    const e = try graph.putVertexAuto(55);
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
    var graph = Graph(Letter, u32, nextLetter, lessThanLetter).init(testing.allocator, .{ .c = 'a' });
    defer graph.deinit();

    const id1 = try graph.putVertexAuto(10);
    const id2 = try graph.putVertexAuto(20);
    const id3 = try graph.putVertexAuto(30);

    try testing.expect(id1.c == 'a');
    try testing.expect(id2.c == 'b');
    try testing.expect(id3.c == 'c');

    try testing.expect(graph.getVertexData(.{ .c = 'b' }) == 20);

    try testing.expect(try graph.removeVertex(.{ .c = 'b' }));

    const id4 = try graph.putVertexAuto(40);
    try testing.expect(id4.c == 'b');
}
