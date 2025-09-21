const std = @import("std");
const uSim = @import("usim");
const Particle = @import("ulib");
const stat = @import("./util/stat.zig").stat;
const options = @import("options");

const time = std.time;
const useStat = options.stat;
const ipc = options.initial_particle_count;

const Graph = uSim.Graph;
const ParticleGraph = Graph(usize, Particle);

/// Key is the `from`
const InteractionTransaction = std.AutoHashMap(usize, struct {
    to: usize,
    emitted: []Particle,
    /// If the particles that interacted were consumed in the interaction and are flagged for removal from the graph
    consumed: bool,
});

/// Clones adjacency and incidency sets from a source node to a new node,
/// and updates adjacent and incident vertices to reference the new node.
fn connectClonedEdges(graph: *ParticleGraph, new_id: usize, source: *ParticleGraph.Node) !void {
    var new = graph.getVertex(new_id) orelse unreachable;

    var adj_iter = source.adjacency_set.iterator();
    while (adj_iter.next()) |entry| {
        const adj_v_id = entry.key_ptr.*;
        try new.addAdjEdge(adj_v_id);
        const adj_v = graph.getVertex(adj_v_id) orelse continue;
        try adj_v.addIncEdge(new_id);
    }

    var inc_iter = source.incidency_set.iterator();
    while (inc_iter.next()) |entry| {
        const inc_v_id = entry.key_ptr.*;
        try new.addIncEdge(inc_v_id);
        const inc_v = graph.getVertex(inc_v_id) orelse continue;
        try inc_v.addAdjEdge(new_id);
    }
}

/// Gathers a map of particle interaction transactions by evaluating all eligible vertex pairs.
fn collectInteractionTransactions(allocator: std.mem.Allocator, graph: *ParticleGraph) !InteractionTransaction {
    var transactions: InteractionTransaction = .init(allocator);

    var iter = graph.vertices.iterator();
    while (iter.next()) |entry| {
        const from_id = entry.key_ptr.*;
        if (transactions.contains(from_id)) continue;

        const from = entry.value_ptr.*;
        var to_it = from.adjacency_set.keyIterator();
        const to_id = (to_it.next() orelse continue).*;

        if (from_id == to_id or transactions.contains(to_id)) continue;

        const to = graph.getVertex(to_id) orelse continue;

        std.debug.print(
            "\rInteracting: v1 = {d} (edges: {d}), v2 = {d} (edges: {d})\x1B[0K",
            .{ from_id, from.adjacency_set.count(), to_id, to.adjacency_set.count() },
        );

        var emitted: std.ArrayList(Particle) = .empty;
        const consumed = try Particle.interact(&from.data, &to.data, &emitted, allocator);

        try transactions.put(from_id, .{
            .to = to_id,
            .emitted = try emitted.toOwnedSlice(allocator),
            .consumed = consumed,
        });
    }

    std.debug.print("\nTransactions to apply: {d}\n", .{transactions.count()});
    return transactions;
}

/// Applies the provided list of interaction transactions to the particle graph.
fn applyTransactions(allocator: std.mem.Allocator, graph: *ParticleGraph, transactions: InteractionTransaction) !void {
    var apply_index: usize = 0;
    var tx_iter = transactions.iterator();
    while (tx_iter.next()) |entry| : (apply_index += 1) {
        const tx = entry.value_ptr.*;
        const from = entry.key_ptr.*;
        const to = tx.to;

        std.debug.print(
            "\rApplying Tx {d}: from = {d}, to = {d}, emitted = {d}, consumed = {any}\x1B[0K",
            .{ apply_index, from, to, tx.emitted.len, tx.consumed },
        );

        const source_from = graph.getVertex(from) orelse return;
        const source_to = graph.getVertex(to) orelse return;
        const vertex_count = graph.vertices.count();
        for (tx.emitted, 0..) |p, i| {
            const new_id = vertex_count + i;
            try graph.putVertex(new_id, p);
            try connectClonedEdges(graph, new_id, source_from);
            try connectClonedEdges(graph, new_id, source_to);
        }

        if (tx.emitted.len > 0) allocator.free(tx.emitted);

        if (tx.consumed) {
            _ = graph.removeVertex(from);
            _ = graph.removeVertex(to);
        }
    }
}

/// Processes all particle interactions in the graph, applies emitted particles, and removes consumed particles.
fn processInteractions(allocator: std.mem.Allocator, graph: *ParticleGraph) !void {
    var transactions = try collectInteractionTransactions(allocator, graph);
    defer transactions.deinit();
    try applyTransactions(allocator, graph, transactions);
}

fn logIteration(
    file: *std.Io.Writer,
    graph: *ParticleGraph,
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
        try file.print("{d},{d},{d},{d},{d}\n", .{
            iter, graph.vertices.count(), edges, iter_time, memory.rss,
        });
    } else {
        try file.print("{d},{d},{d},{d}\n", .{
            iter, graph.vertices.count(), edges, iter_time,
        });
    }

    try file.flush();
}

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var outer_timer = try time.Timer.start();
    var graph = try Particle.initializeGraph(allocator, ipc);
    std.debug.print("Initialized in: {d:.3}ms\n", .{@as(f64, @floatFromInt(outer_timer.read())) / time.ns_per_ms});
    defer graph.deinit();

    var file_buffer: [1024]u8 = undefined;
    var file = try std.fs.cwd().createFile("zig-out/out.csv", .{});
    var file_writer = file.writer(&file_buffer);
    const file_interface = &file_writer.interface;
    defer file.close();

    try file_interface.print("iter,vertices,num_edges,iter_time{s}\n", .{if (comptime useStat) ",mem" else ""});

    var particle_stats_file_buffer: [1024]u8 = undefined;
    var particle_stats_file = try std.fs.cwd().createFile("zig-out/parts.csv", .{});
    var particle_stats_file_writer = particle_stats_file.writer(&particle_stats_file_buffer);
    const particle_stats_file_interface = &particle_stats_file_writer.interface;
    defer particle_stats_file.close();

    try Particle.print(&graph, allocator, particle_stats_file_interface, 0);

    var graph_state = graph;
    var i: usize = 1;
    while (true) : (i += 1) {
        std.debug.print("Calculating iter: {d}...\n", .{i});

        var timer = try time.Timer.start();
        try processInteractions(allocator, &graph);
        const iter_time = @as(f64, @floatFromInt(timer.read())) / time.ns_per_ms;
        try logIteration(file_interface, &graph, i, iter_time);

        std.debug.print("\x1B[2J\x1B[H", .{});
        std.debug.print("iter: {d} | time: {d}\n", .{ i, iter_time });
        if (std.meta.eql(graph, graph_state) and i != 0) break; //? Reached stable state
        try Particle.print(&graph, allocator, particle_stats_file_interface, i);

        if (graph.vertices.count() == 0) break;
        graph_state = graph;
    }

    std.debug.print("Total time: {d:.3}ms\n", .{@as(f64, @floatFromInt(outer_timer.read())) / time.ns_per_ms});
}
