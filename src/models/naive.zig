const std = @import("std");
const uSim = @import("usim");

const Graph = uSim.Graph;

const Self = @This();

const ParticleType = enum {
    UpQuark,
    DownQuark,
    CharmQuark,
    StrangeQuark,
    TopQuark,
    BottomQuark,
    Electron,
    ElectronNeutrino,
    Muon,
    MuonNeutrino,
    Tau,
    TauNeutrino,
    Photon,
    WBosonPlus,
    WBosonMinus,
    ZBoson,
    Gluon,
    HiggsBoson,
};

kind: ParticleType,
charge: f64,
mass: f64,
energy: f64,
spin: f64,
has_color: bool,

/// Returns `true` if the emission consumed the interacting particles
pub fn interact(self: *Self, other: *Self, emission_buffer: *std.ArrayList(Self)) !bool {
    if (try handleAnnihilation(self, other, emission_buffer)) return true;
    if (try handlePairProduction(self, other, emission_buffer)) return true;

    const consumed_self = try handleDecay(self, emission_buffer);
    const consumed_other = try handleDecay(other, emission_buffer);
    if (consumed_self or consumed_other) return true;

    _ = try handleScattering(self, other, emission_buffer);
    return false;
}

fn handleAnnihilation(a: *Self, b: *Self, emitted: *std.ArrayList(Self)) !bool {
    if (a.mass == 0.0 or b.mass == 0.0) return false;
    if (a.charge == -b.charge and a.kind != b.kind and a.mass == b.mass) {
        const total_energy = a.energy + b.energy;
        const photon_energy = total_energy / 2.0;
        try emitted.append(.{ .kind = .Photon, .charge = 0.0, .mass = 0.0, .energy = photon_energy, .spin = 1.0, .has_color = false });
        try emitted.append(.{ .kind = .Photon, .charge = 0.0, .mass = 0.0, .energy = photon_energy, .spin = -1.0, .has_color = false });
        return true;
    }
    return false;
}

fn handleDecay(p: *Self, emitted: *std.ArrayList(Self)) !bool {
    switch (p.kind) {
        .Muon => {
            // Muon -> Electron + ElectronNeutrino + MuonNeutrino
            try emitted.append(.{ .kind = .Electron, .charge = -1.0, .mass = 0.511, .energy = p.energy * 0.5, .spin = 0.5, .has_color = false });
            try emitted.append(.{ .kind = .ElectronNeutrino, .charge = 0.0, .mass = 0.0, .energy = p.energy * 0.25, .spin = 0.5, .has_color = false });
            try emitted.append(.{ .kind = .MuonNeutrino, .charge = 0.0, .mass = 0.0, .energy = p.energy * 0.25, .spin = 0.5, .has_color = false });
            return true;
        },
        .WBosonPlus => {
            // W+ -> Positron + ElectronNeutrino
            try emitted.append(.{ .kind = .Electron, .charge = 1.0, .mass = 0.511, .energy = p.energy * 0.6, .spin = 0.5, .has_color = false });
            try emitted.append(.{ .kind = .ElectronNeutrino, .charge = 0.0, .mass = 0.0, .energy = p.energy * 0.4, .spin = 0.5, .has_color = false });
            return true;
        },
        .WBosonMinus => {
            try emitted.append(.{ .kind = .Electron, .charge = -1.0, .mass = 0.511, .energy = p.energy * 0.6, .spin = 0.5, .has_color = false });
            try emitted.append(.{ .kind = .ElectronNeutrino, .charge = 0.0, .mass = 0.0, .energy = p.energy * 0.4, .spin = 0.5, .has_color = false });
            return true;
        },
        else => return false,
    }
}

fn handleScattering(a: *Self, b: *Self, emitted: *std.ArrayList(Self)) !bool {
    const emission_energy = (a.energy + b.energy) * 0.1;

    if (a.charge != 0.0 and b.charge != 0.0) {
        try emitted.append(.{ .kind = .Photon, .charge = 0.0, .mass = 0.0, .energy = emission_energy, .spin = 1.0, .has_color = false });
    } else if (a.has_color and b.has_color) {
        try emitted.append(.{ .kind = .Gluon, .charge = 0.0, .mass = 0.0, .energy = emission_energy, .spin = 1.0, .has_color = true });
    } else {
        return false;
    }

    // Split the energy cost equally
    const half_emission = emission_energy / 2.0;
    a.energy = @max(0.0, a.energy - half_emission);
    b.energy = @max(0.0, b.energy - half_emission);

    return false;
}

fn handlePairProduction(a: *Self, b: *Self, emitted: *std.ArrayList(Self)) !bool {
    if (a.kind == .Photon and b.kind == .Photon and (a.energy + b.energy) > 2.0 * 0.511) {
        // Photon + Photon -> Electron + Positron (simplified)
        const e_per_particle = (a.energy + b.energy) / 2.0;
        try emitted.append(.{ .kind = .Electron, .charge = -1.0, .mass = 0.511, .energy = e_per_particle, .spin = 0.5, .has_color = false });
        try emitted.append(.{ .kind = .Electron, .charge = 1.0, .mass = 0.511, .energy = e_per_particle, .spin = -0.5, .has_color = false });
        return true;
    }
    return false;
}

pub fn initializeGraph(allocator: std.mem.Allocator) !Graph(usize, Self) {
    var graph = Graph(usize, Self).init(allocator, 0);

    var prng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    const random = prng.random();

    const particle_count = 20;

    for (0..particle_count) |_| {
        const kind = random.enumValue(ParticleType);

        const info: struct {
            charge: f64,
            mass: f64,
            spin: f64,
            has_color: bool,
        } = switch (kind) {
            .UpQuark => .{ .charge = 2.0 / 3.0, .mass = 2.3, .spin = 0.5, .has_color = true },
            .DownQuark => .{ .charge = -1.0 / 3.0, .mass = 4.8, .spin = 0.5, .has_color = true },
            .CharmQuark => .{ .charge = 2.0 / 3.0, .mass = 1275.0, .spin = 0.5, .has_color = true },
            .StrangeQuark => .{ .charge = -1.0 / 3.0, .mass = 95.0, .spin = 0.5, .has_color = true },
            .TopQuark => .{ .charge = 2.0 / 3.0, .mass = 172760.0, .spin = 0.5, .has_color = true },
            .BottomQuark => .{ .charge = -1.0 / 3.0, .mass = 4180.0, .spin = 0.5, .has_color = true },
            .Electron => .{ .charge = -1.0, .mass = 0.511, .spin = 0.5, .has_color = false },
            .ElectronNeutrino => .{ .charge = 0.0, .mass = 0.0, .spin = 0.5, .has_color = false },
            .Muon => .{ .charge = -1.0, .mass = 105.66, .spin = 0.5, .has_color = false },
            .MuonNeutrino => .{ .charge = 0.0, .mass = 0.0, .spin = 0.5, .has_color = false },
            .Tau => .{ .charge = -1.0, .mass = 1776.86, .spin = 0.5, .has_color = false },
            .TauNeutrino => .{ .charge = 0.0, .mass = 0.0, .spin = 0.5, .has_color = false },
            .Photon => .{ .charge = 0.0, .mass = 0.0, .spin = 1.0, .has_color = false },
            .WBosonPlus => .{ .charge = 1.0, .mass = 80.379, .spin = 1.0, .has_color = false },
            .WBosonMinus => .{ .charge = -1.0, .mass = 80.379, .spin = 1.0, .has_color = false },
            .ZBoson => .{ .charge = 0.0, .mass = 91.1876, .spin = 1.0, .has_color = false },
            .Gluon => .{ .charge = 0.0, .mass = 0.0, .spin = 1.0, .has_color = true },
            .HiggsBoson => .{ .charge = 0.0, .mass = 125100.0, .spin = 0.0, .has_color = false },
        };

        const energy = random.float(f64) * 1000.0;

        const p: Self = .{
            .kind = kind,
            .charge = info.charge,
            .mass = info.mass,
            .energy = energy,
            .spin = info.spin,
            .has_color = info.has_color,
        };

        _ = try graph.addVertex(p);
    }

    if (graph.vertices.count() >= 2) {
        for (0..(graph.vertices.count() - 1)) |i| {
            for (0..(graph.vertices.count() - 1)) |j| {
                if (i == j) continue;
                try graph.addEdge(i, j);
            }
        }
    }

    return graph;
}

pub fn print(graph: *Graph(usize, Self)) void {
    const num_vertices: usize = graph.vertices.count();
    var total_edges: usize = 0;

    var counts = [_]usize{0} ** @typeInfo(ParticleType).@"enum".fields.len;
    var total_mass: f64 = 0.0;
    var total_charge: f64 = 0.0;
    var total_energy: f64 = 0.0;

    var vertices = graph.vertices.valueIterator();
    while (vertices.next()) |v| {
        total_edges += v.*.adjacency_set.count();

        const p = v.*.*.data;
        counts[@intFromEnum(p.kind)] += 1;
        total_mass += p.mass;
        total_charge += p.charge;
        total_energy += p.energy;
    }

    const avg_edges_per_particle = @as(f64, @floatFromInt(total_edges)) / @as(f64, @floatFromInt(num_vertices));

    std.debug.print("\n--- Simulation Statistics ---\n", .{});
    std.debug.print("Particles (vertices): {}\n", .{num_vertices});
    std.debug.print("Edges: {}\n", .{total_edges});
    std.debug.print("Average edges per particle: {d:.2}\n", .{avg_edges_per_particle});
    std.debug.print("Total Mass: {d:.3} MeV/c^2\n", .{total_mass});
    std.debug.print("Total Charge: {d:.3} e\n", .{total_charge});
    std.debug.print("Total Energy: {d:.3} MeV\n", .{total_energy});

    inline for (@typeInfo(ParticleType).@"enum".fields, 0..) |field, i|
        std.debug.print("{s}: {any}\n", .{ field.name, counts[i] });

    std.debug.print("-----------------------------\n\n", .{});
}
