const std = @import("std");
const uSim = @import("usim");
const Particle = @import("ulib");
const options = @import("options");

const stat = @import("./util/stat.zig").stat;

const time = std.time;
const ipc = options.initial_particle_count;

const ParticleGraph = Particle.Graph;

fn processInteractions(allocator: std.mem.Allocator, graph: *ParticleGraph) !void {
    var particle_status: std.AutoArrayHashMap(usize, bool) = .init(allocator);
    defer particle_status.deinit();

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
                const next_key = try graph.putVertexAuto(particle);
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

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var graph = try Particle.initializeGraph(allocator, ipc);
    defer graph.deinit();

    var prev_graph_state = graph;
    var i: usize = 1;
    while (true) : (i += 1) {
        try processInteractions(allocator, &graph);
        if (graph.vertices.count() == 0) break;

        if (std.meta.eql(prev_graph_state, graph) and i != 0) break; //? Reached stable state
        prev_graph_state = graph;
    }
}
