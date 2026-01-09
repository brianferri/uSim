const std = @import("std");
const uSim = @import("usim");
const Particle = @import("ulib");
const stat = @import("./util/stat.zig").stat;
const options = @import("options");

const time = std.time;
const ipc = options.initial_particle_count;

const Graph = uSim.Graph;
const ParticleGraph = Graph(usize, Particle);

fn processInteractions(allocator: std.mem.Allocator, graph: *ParticleGraph) !void {
    var particle_status: std.AutoArrayHashMap(usize, bool) = .init(allocator);
    defer particle_status.deinit();

    // TODO: find a better way to track new IDs
    var max_key: usize = 0;
    var it = graph.vertices.iterator();
    while (it.next()) |entry| {
        if (entry.key_ptr.* > max_key)
            max_key = entry.key_ptr.*;
    }
    var next_key = max_key + 1;

    var iter = graph.vertices.iterator();
    while (iter.next()) |entry| {
        const p1_key = entry.key_ptr.*;
        if ((try particle_status.getOrPutValue(p1_key, false)).found_existing) continue;
        const p1_value = entry.value_ptr.*;

        var adj_iter = p1_value.adjacency_set.iterator();
        while (adj_iter.next()) |adj_entry| {
            const p2_key = adj_entry.key_ptr.*;
            if ((try particle_status.getOrPutValue(p2_key, false)).found_existing) continue;
            const p2_value = graph.getVertex(p2_key) orelse continue;

            var emission_buffer: std.ArrayList(Particle) = .empty;
            defer emission_buffer.deinit(allocator);

            const consumed = try Particle.interact(&p1_value.data, &p2_value.data, &emission_buffer, allocator);
            try particle_status.put(p1_key, consumed[0]);
            try particle_status.put(p2_key, consumed[1]);

            for (emission_buffer.items) |particle| {
                defer next_key += 1;
                try graph.putVertex(next_key, particle);
                try graph.addEdge(p1_key, next_key);
                try graph.addEdge(p2_key, next_key);
                try graph.addEdge(next_key, p1_key);
                try graph.addEdge(next_key, p2_key);
                try particle_status.put(next_key, false);
            }
        }
    }

    var status_iter = particle_status.iterator();
    while (status_iter.next()) |status| {
        if (status.value_ptr.*) _ = graph.removeVertex(status.key_ptr.*);
    }
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

    const process_stat = stat(&buf) catch |err| switch (err) {
        error.FileNotFound => null,
        else => return err,
    };
    try file.print("{d},{d},{d},{d},{d}\n", .{
        iter, graph.vertices.count(), edges, iter_time, if (process_stat) |s| s.rss else 0,
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
    var file = try std.fs.cwd().createFile("zig-out/stats.csv", .{});
    var file_writer = file.writer(&file_buffer);
    const file_interface = &file_writer.interface;
    defer file.close();

    try file_interface.print("iter,vertices,num_edges,iter_time,mem", .{});

    var particle_stats_file_buffer: [1024]u8 = undefined;
    var particle_stats_file = try std.fs.cwd().createFile("zig-out/parts.csv", .{});
    var particle_stats_file_writer = particle_stats_file.writer(&particle_stats_file_buffer);
    const particle_stats_file_interface = &particle_stats_file_writer.interface;
    defer particle_stats_file.close();

    try Particle.print(&graph, allocator, particle_stats_file_interface, 0);

    var prev_graph_state = graph;
    var i: usize = 1;
    while (true) : (i += 1) {
        std.debug.print("Calculating iter: {d}...\n", .{i});

        var timer = try time.Timer.start();
        try processInteractions(allocator, &graph);
        if (graph.vertices.count() == 0) break;

        const iter_time = @as(f64, @floatFromInt(timer.read())) / time.ns_per_ms;
        try logIteration(file_interface, &graph, i, iter_time);

        std.debug.print("\x1B[2J\x1B[H", .{});
        std.debug.print("iter: {d} | time: {d}\n", .{ i, iter_time });
        if (std.meta.eql(prev_graph_state, graph) and i != 0) break; //? Reached stable state
        prev_graph_state = graph;

        try Particle.print(&graph, allocator, particle_stats_file_interface, i);
    }

    std.debug.print(
        "Total time: {d:.3}ms\n",
        .{@as(f64, @floatFromInt(outer_timer.read())) / time.ns_per_ms},
    );
}
