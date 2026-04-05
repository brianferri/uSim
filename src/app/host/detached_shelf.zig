//! Topologies removed from the active simulation graph (currently: zero-degree / isolated vertices).
//! Shelving runs only when the timeline **frontier** advances (`advanceFrontier`), so scrubbing to an
//! earlier step still shows historical isolates inside that step's main graph. The shelf accumulates
//! for the session; each shelved piece is stored as its own `Graph` for future richer topology rules.
const std = @import("std");
const Particle = @import("ulib");

pub const DetachedTopologyShelf = struct {
    allocator: std.mem.Allocator,
    /// Each entry is one connected piece shelved from the main graph (today usually one vertex).
    graphs: std.ArrayList(Particle.Graph),

    pub fn init(alloc: std.mem.Allocator) DetachedTopologyShelf {
        return .{ .allocator = alloc, .graphs = .empty };
    }

    pub fn deinit(self: *DetachedTopologyShelf) void {
        for (self.graphs.items) |*g| g.deinit();
        self.graphs.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn graphCount(self: *const DetachedTopologyShelf) usize {
        return self.graphs.items.len;
    }

    /// Every vertex with no outgoing and no incoming edges is moved into a new graph appended to `self`.
    pub fn extractIsolatesFrom(self: *DetachedTopologyShelf, g: *Particle.Graph) !void {
        var keys = std.ArrayList(u64).empty;
        defer keys.deinit(self.allocator);

        var it = g.vertices.iterator();
        while (it.next()) |ent| {
            const node = ent.value_ptr.*;
            if (node.adjacency_set.count() + node.incidency_set.count() == 0) {
                try keys.append(self.allocator, ent.key_ptr.*);
            }
        }

        std.sort.pdq(u64, keys.items, {}, std.sort.asc(u64));

        for (keys.items) |k| {
            const node_ptr = g.getVertex(k) orelse continue;
            const data = node_ptr.data;

            var piece: Particle.Graph = .init(self.allocator, 0);
            errdefer piece.deinit();
            try piece.putVertex(k, data);
            try self.graphs.append(self.allocator, piece);
            _ = try g.removeVertex(k);
        }
    }
};

test "extractIsolatesFrom moves each isolate into its own graph" {
    const a = std.testing.allocator;
    var g: Particle.Graph = .init(a, 0);
    defer g.deinit();
    try g.putVertex(10, Particle.Type.Electron.toParticle());
    try g.putVertex(20, Particle.Type.Photon.toParticle());

    var shelf = DetachedTopologyShelf.init(a);
    defer shelf.deinit();

    try shelf.extractIsolatesFrom(&g);

    try std.testing.expectEqual(@as(usize, 0), g.vertices.count());
    try std.testing.expectEqual(@as(usize, 2), shelf.graphs.items.len);
    try std.testing.expect(shelf.graphs.items[0].getVertex(10) != null);
    try std.testing.expect(shelf.graphs.items[1].getVertex(20) != null);
}

test "extractIsolatesFrom leaves connected vertices" {
    const a = std.testing.allocator;
    var g: Particle.Graph = .init(a, 0);
    defer g.deinit();
    try g.putVertex(1, Particle.Type.Electron.toParticle());
    try g.putVertex(2, Particle.Type.Positron.toParticle());
    try g.addEdge(1, 2);

    var shelf = DetachedTopologyShelf.init(a);
    defer shelf.deinit();

    try shelf.extractIsolatesFrom(&g);

    try std.testing.expectEqual(@as(usize, 2), g.vertices.count());
    try std.testing.expectEqual(@as(usize, 0), shelf.graphs.items.len);
}
