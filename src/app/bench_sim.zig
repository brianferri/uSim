//! Headless frontier stepping for profiling the simulation (no dvui/SDL).
//! Build: `zig build -Doptimize=ReleaseFast -Dipc=200 install` (bench uses same `-Dipc` / `-Dmodel` as the app).
//! Run: `zig build bench -- 40`  or  `perf record -g --call-graph dwarf -o zig-out/perf/sim.data -- zig-out/bin/bench_sim 25`
const std = @import("std");
const Particle = @import("ulib");
const options = @import("options");
const uSim = @import("usim");
const DetachedTopologyShelf = @import("host/detached_shelf.zig").DetachedTopologyShelf;
const LinearTimeline = @import("host/timeline.zig").LinearTimeline;

const BenchStats = struct {
    vertices: usize,
    isolates: usize,
    photons: usize,
    muons: usize,
    gluons: usize,
    photon_energy_avg: f64,
    photon_photon_edges: usize,
};

fn collectStats(g: *Particle.Graph) BenchStats {
    var stats: BenchStats = .{
        .vertices = g.vertices.count(),
        .isolates = 0,
        .photons = 0,
        .muons = 0,
        .gluons = 0,
        .photon_energy_avg = 0.0,
        .photon_photon_edges = 0,
    };
    var photon_energy_sum: f64 = 0.0;
    var it = g.vertices.iterator();
    while (it.next()) |ent| {
        const node = ent.value_ptr.*;
        const ty = Particle.Type.fromStruct(&node.data);
        if (node.adjacency_set.count() + node.incidency_set.count() == 0) {
            stats.isolates += 1;
        }
        switch (ty) {
            .Photon => {
                stats.photons += 1;
                photon_energy_sum += node.data.energy;
                var ait = node.adjacency_set.iterator();
                while (ait.next()) |ae| {
                    const k = ae.key_ptr.*;
                    const nb = g.getVertex(k) orelse continue;
                    if (Particle.Type.fromStruct(&nb.data) == .Photon) {
                        stats.photon_photon_edges += 1;
                    }
                }
            },
            .Muon, .AntiMuon => stats.muons += 1,
            .Gluon => stats.gluons += 1,
            else => {},
        }
    }
    if (stats.photons > 0) {
        stats.photon_energy_avg = photon_energy_sum / @as(f64, @floatFromInt(stats.photons));
    }
    return stats;
}

fn printDebugStep(
    allocator: std.mem.Allocator,
    step: usize,
    g: *Particle.Graph,
    shelf_count: usize,
) !void {
    const st = collectStats(g);
    const wcc = try uSim.structure_analysis.weaklyConnectedComponentStats(
        @TypeOf(g.*),
        allocator,
        g,
    );
    std.debug.print(
        "bench step {d}: V={d} iso={d} wcc={d} largest={d} shelf={d} photon={d} avgE={d:.3} gamma-gamma-edges={d} muon={d} gluon={d}\n",
        .{
            step,
            st.vertices,
            st.isolates,
            wcc.n_components,
            wcc.largest,
            shelf_count,
            st.photons,
            st.photon_energy_avg,
            st.photon_photon_edges,
            st.muons,
            st.gluons,
        },
    );
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var arg_iter = try std.process.argsWithAllocator(alloc);
    defer arg_iter.deinit();
    _ = arg_iter.skip();
    const steps_str = arg_iter.next();
    const steps = if (steps_str) |s| try std.fmt.parseUnsigned(usize, s, 10) else 30;
    const debug = if (arg_iter.next()) |s| std.mem.eql(u8, s, "--debug") else false;

    Particle.setSimulationRngSeed(options.simulation_rng_seed);
    const g = try Particle.initializeGraph(alloc, options.initial_particle_count);
    var tl = try LinearTimeline.initOwnedGenesis(alloc, g);
    defer tl.deinit();
    var shelf = DetachedTopologyShelf.init(alloc);
    defer shelf.deinit();

    if (debug) {
        const frontier = &tl.steps.items[tl.frontierStep()];
        try printDebugStep(alloc, 0, frontier, shelf.graphCount());
    }

    var i: usize = 0;
    while (i < steps) : (i += 1) {
        if (tl.loop_pair != null) break;
        if (debug) {
            try tl.advanceFrontier(&shelf);
            const frontier = &tl.steps.items[tl.frontierStep()];
            try printDebugStep(alloc, i + 1, frontier, shelf.graphCount());
        } else {
            try tl.advanceFrontier(null);
        }
    }
}
