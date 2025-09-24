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

const EmissionTx = struct {
    parents: [2]usize,
    consumed: [2]bool,
    emitted: []Particle,
};

fn collectInteractions(allocator: std.mem.Allocator, graph: *ParticleGraph) !std.ArrayList(EmissionTx) {
    var txs: std.ArrayList(EmissionTx) = .empty;

    var iter = graph.vertices.iterator();
    while (iter.next()) |entry| {
        const i = entry.key_ptr.*;
        const node_i = entry.value_ptr.*;

        var adj_iter = node_i.adjacency_set.iterator();
        while (adj_iter.next()) |adj_entry| {
            const j = adj_entry.key_ptr.*;
            if (i >= j) continue;

            const node_j = graph.getVertex(j) orelse continue;

            var emitted: std.ArrayList(Particle) = .empty;
            const consumed = try Particle.interact(&node_i.data, &node_j.data, &emitted, allocator);

            try txs.append(allocator, .{
                .parents = .{ i, j },
                .emitted = try emitted.toOwnedSlice(allocator),
                .consumed = consumed,
            });
        }
    }
    return txs;
}

fn applyTransactions(allocator: std.mem.Allocator, graph: *ParticleGraph, transactions: std.ArrayList(EmissionTx)) !void {
    var max_key: usize = 0;
    var it = graph.vertices.iterator();
    while (it.next()) |entry| {
        if (entry.key_ptr.* > max_key)
            max_key = entry.key_ptr.*;
    }
    var next_key = max_key + 1;

    for (transactions.items) |transaction| {
        defer allocator.free(transaction.emitted);
        const parents = transaction.parents;

        for (transaction.emitted) |particle| {
            const new_id = next_key;
            next_key += 1;
            try graph.putVertex(new_id, particle);

            for (parents) |particle_id| {
                if (graph.getVertex(particle_id)) |_| {
                    _ = try graph.addEdge(particle_id, new_id);
                    _ = try graph.addEdge(new_id, particle_id);
                }
            }
        }

        if (transaction.consumed[0]) _ = graph.removeVertex(parents[0]);
        if (transaction.consumed[1]) _ = graph.removeVertex(parents[1]);
    }
}

fn applyRemovals(graph: *ParticleGraph, to_remove: *std.AutoHashMap(usize, void)) void {
    var it = to_remove.iterator();
    while (it.next()) |removed_entry| {
        const idx = removed_entry.key_ptr.*;
        _ = graph.removeVertex(idx);
    }
}

fn processInteractions(allocator: std.mem.Allocator, graph: *ParticleGraph) !void {
    var txs = try collectInteractions(allocator, graph);
    defer txs.deinit(allocator);
    try applyTransactions(allocator, graph, txs);
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
    while (vertices.next()) |v|
        edges += v.*.adjacency_set.count();

    if (useStat) try file.print("{d},{d},{d},{d},{d}\n", .{
        iter, graph.vertices.count(), edges, iter_time, try stat(&buf).rss,
    }) else try file.print("{d},{d},{d},{d}\n", .{
        iter, graph.vertices.count(), edges, iter_time,
    });

    try file.flush();
}

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var outer_timer = try time.Timer.start();
    var graph = try Particle.initializeGraph(allocator, ipc);
    defer graph.deinit();
    std.debug.print(
        "Initialized in: {d:.3}ms\n",
        .{@as(f64, @floatFromInt(outer_timer.read())) / time.ns_per_ms},
    );

    var file_buffer: [1024]u8 = undefined;
    var file = try std.fs.cwd().createFile("zig-out/out.csv", .{});
    var file_writer = file.writer(&file_buffer);
    const file_interface = &file_writer.interface;
    defer file.close();

    try file_interface.print("iter,vertices,num_edges,iter_time{s}\n", .{if (useStat) ",mem" else ""});

    var particle_stats_file_buffer: [1024]u8 = undefined;
    var particle_stats_file = try std.fs.cwd().createFile("zig-out/parts.csv", .{});
    var particle_stats_file_writer = particle_stats_file.writer(&particle_stats_file_buffer);
    const particle_stats_file_interface = &particle_stats_file_writer.interface;
    defer particle_stats_file.close();

    try Particle.print(&graph, allocator, particle_stats_file_interface, 0);

    var prev_graph_state = graph.vertices.count();
    var i: usize = 1;
    while (true) : (i += 1) {
        std.debug.print("Calculating iter: {d}...\n", .{i});

        var timer = try time.Timer.start();
        try processInteractions(allocator, &graph);
        if (graph.vertices.count() == 0) break;

        const curr_graph_state = graph.vertices.count();
        const iter_time = @as(f64, @floatFromInt(timer.read())) / time.ns_per_ms;
        try logIteration(file_interface, &graph, i, iter_time);

        std.debug.print("\x1B[2J\x1B[H", .{});
        std.debug.print("iter: {d} | time: {d}\n", .{ i, iter_time });
        if (prev_graph_state == curr_graph_state and i != 0) break; //? Reached stable state
        prev_graph_state = curr_graph_state;

        try Particle.print(&graph, allocator, particle_stats_file_interface, i);
    }

    std.debug.print(
        "Total time: {d:.3}ms\n",
        .{@as(f64, @floatFromInt(outer_timer.read())) / time.ns_per_ms},
    );
}
