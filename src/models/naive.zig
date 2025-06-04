const std = @import("std");
const uSim = @import("usim");

const Graph = uSim.Graph;

const Self = @This();

/// e
charge: f64,
/// MeV/c²
mass: f64,
/// MeV
energy: f64,
spin: f64,
has_color: bool,

const ParticleType = enum {
    UpQuark,
    DownQuark,
    CharmQuark,
    StrangeQuark,
    TopQuark,
    BottomQuark,
    Positron,
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
    Unknown,
};

/// | Particle          | Mass (MeV/c²) | Tolerance (MeV/c²) | Charge (e) | Spin | Color Charge |
/// | ----------------- | ------------- | ------------------ | ---------- | ---- | ------------ |
/// | Up Quark          | 2.16          | ±0.49              | +2/3       | 0.5  | Yes          |
/// | Down Quark        | 4.67          | ±0.48              | -1/3       | 0.5  | Yes          |
/// | Charm Quark       | 1275          | ±25                | +2/3       | 0.5  | Yes          |
/// | Strange Quark     | 93            | ±11                | -1/3       | 0.5  | Yes          |
/// | Top Quark         | 171770        | ±380               | +2/3       | 0.5  | Yes          |
/// | Bottom Quark      | 4180          | ±30                | -1/3       | 0.5  | Yes          |
/// | Electron          | 0.51099895    | ±0.00000015        | -1         | 0.5  | No           |
/// | Positron          | 0.51099895    | ±0.00000015        | +1         | 0.5  | No           |
/// | Electron Neutrino | <0.8          | N/A                | 0          | 0.5  | No           |
/// | Muon              | 105.6583755   | ±0.0000023         | -1         | 0.5  | No           |
/// | Tau               | 1776.86       | ±0.12              | -1         | 0.5  | No           |
/// | Gluon             | 0             | 0                  | 0          | 1.0  | Yes          |
/// | Photon            | 0             | 0                  | 0          | 1.0  | No           |
/// | W Boson           | 80379         | ±12                | ±1         | 1.0  | No           |
/// | Z Boson           | 91187.6       | ±2.1               | 0          | 1.0  | No           |
/// | Higgs Boson       | 125100        | ±300               | 0          | 0.0  | No           |
pub fn describeParticle(p: Self) ParticleType {
    const approxEqual = std.math.approxEqRel;
    // zig fmt: off
         if (approxEqual(f64, p.mass, 0.51099895, 0.00000015) and approxEqual(f64, p.charge, -1.0, 0.01) and p.spin == 0.5 and !p.has_color) return .Electron
    else if (approxEqual(f64, p.mass, 0.51099895, 0.00000015) and approxEqual(f64, p.charge, 1.0, 0.01) and p.spin == -0.5 and !p.has_color) return .Positron
    else if (approxEqual(f64, p.mass, 2.16, 0.49) and approxEqual(f64, p.charge, 2.0 / 3.0, 0.01) and p.spin == 0.5 and p.has_color) return .UpQuark
    else if (p.mass == 0.0 and p.charge == 0.0 and p.spin == 1.0 and p.has_color) return .Gluon
    else if (p.mass == 0.0 and p.charge == 0.0 and @abs(p.spin) == 1.0 and !p.has_color) return .Photon
    else if (p.mass < 0.8 and approxEqual(f64, p.charge, 0.0, 0.001) and p.spin == 0.5 and !p.has_color) return .ElectronNeutrino
    else if (approxEqual(f64, p.mass, 4.67, 0.48) and approxEqual(f64, p.charge, -1.0 / 3.0, 0.01) and p.spin == 0.5 and p.has_color) return .DownQuark
    else if (approxEqual(f64, p.mass, 93.0, 11.0) and approxEqual(f64, p.charge, -1.0 / 3.0, 0.01) and p.spin == 0.5 and p.has_color) return .StrangeQuark
    else if (approxEqual(f64, p.mass, 105.6583755, 0.0000023) and approxEqual(f64, p.charge, -1.0, 0.01) and p.spin == 0.5 and !p.has_color) return .Muon
    else if (approxEqual(f64, p.mass, 1275.0, 25.0) and approxEqual(f64, p.charge, 2.0 / 3.0, 0.01) and p.spin == 0.5 and p.has_color) return .CharmQuark
    else if (approxEqual(f64, p.mass, 4180.0, 30.0) and approxEqual(f64, p.charge, -1.0 / 3.0, 0.01) and p.spin == 0.5 and p.has_color) return .BottomQuark
    else if (approxEqual(f64, p.mass, 1776.86, 0.12) and approxEqual(f64, p.charge, -1.0, 0.01) and p.spin == 0.5 and !p.has_color) return .Tau
    else if (approxEqual(f64, p.mass, 80379.0, 12.0) and approxEqual(f64, p.charge, 1.0, 0.01) and p.spin == 1.0 and !p.has_color) return .WBosonPlus
    else if (approxEqual(f64, p.mass, 80379.0, 12.0) and approxEqual(f64, p.charge, -1.0, 0.01) and p.spin == 1.0 and !p.has_color) return .WBosonMinus
    else if (approxEqual(f64, p.mass, 91187.6, 2.1) and approxEqual(f64, p.charge, 0.0, 0.001) and p.spin == 1.0 and !p.has_color) return .ZBoson
    else if (approxEqual(f64, p.mass, 171770.0, 380.0) and approxEqual(f64, p.charge, 2.0 / 3.0, 0.01) and p.spin == 0.5 and p.has_color) return .TopQuark
    else if (approxEqual(f64, p.mass, 125100.0, 300.0) and approxEqual(f64, p.charge, 0.0, 0.001) and p.spin == 0.0 and !p.has_color) return .HiggsBoson
    // zig fmt: on

    else return .Unknown;
}

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

/// Simulates the annihilation of a particle-antiparticle pair into photons.
///
/// This function checks if two particles are mutual antiparticles by verifying:
/// - Opposite electric charges
/// - Equal masses
/// - Opposite spins
/// - Absence of color charge
/// - Non-zero mass
///
/// If these conditions are met, it simulates their annihilation into two photons,
/// each carrying half of the total energy and opposite spins to conserve angular momentum.
fn handleAnnihilation(a: *Self, b: *Self, emitted: *std.ArrayList(Self)) !bool {
    if (std.math.approxEqRel(f64, a.charge, -b.charge, 1e-6) and
        std.math.approxEqRel(f64, a.mass, b.mass, 1e-6) and
        std.math.approxEqRel(f64, a.spin, -b.spin, 1e-6) and
        !a.has_color and !b.has_color and
        a.mass > 0.0)
    {
        const total_energy = a.energy + b.energy;
        const photon_energy = total_energy / 2.0;
        try emitted.append(.{ .charge = 0.0, .mass = 0.0, .energy = photon_energy, .spin = 1.0, .has_color = false });
        try emitted.append(.{ .charge = 0.0, .mass = 0.0, .energy = photon_energy, .spin = -1.0, .has_color = false });
        return true;
    }
    return false;
}

/// Simulates the decay of unstable particles into their respective decay products.
///
/// Depending on the particle type, this function models the decay process as follows:
/// - **Muon (μ⁻):** Decays into an electron (e⁻), an electron antineutrino (ν̄ₑ), and a muon neutrino (ν_μ).
/// - **Tau (τ⁻):** Decays into a muon (μ⁻), a muon antineutrino (ν̄_μ), and a tau neutrino (ν_τ).
/// - **W Boson (W⁺/W⁻):** Decays into a lepton and its corresponding neutrino or antineutrino.
/// - **Z Boson (Z⁰):** Decays into a lepton-antilepton pair, such as an electron and a positron.
/// - **Higgs Boson (H⁰):** Decays into a pair of photons.
///
/// The energy is distributed among the decay products based on typical decay kinematics.
fn handleDecay(p: *Self, emitted: *std.ArrayList(Self)) !bool {
    switch (describeParticle(p.*)) {
        .Muon => {
            try emitted.append(.{ .charge = -1.0, .mass = 0.51099895, .energy = p.energy * 0.3, .spin = 0.5, .has_color = false }); // Electron
            try emitted.append(.{ .charge = 0.0, .mass = 0.0, .energy = p.energy * 0.35, .spin = -0.5, .has_color = false }); // Electron antineutrino
            try emitted.append(.{ .charge = 0.0, .mass = 0.0, .energy = p.energy * 0.35, .spin = 0.5, .has_color = false }); // Muon neutrino
            return true;
        },
        .Tau => {
            try emitted.append(.{ .charge = -1.0, .mass = 105.66, .energy = p.energy * 0.3, .spin = 0.5, .has_color = false }); // Muon
            try emitted.append(.{ .charge = 0.0, .mass = 0.0, .energy = p.energy * 0.35, .spin = -0.5, .has_color = false }); // Muon antineutrino
            try emitted.append(.{ .charge = 0.0, .mass = 0.0, .energy = p.energy * 0.35, .spin = 0.5, .has_color = false }); // Tau neutrino
            return true;
        },
        .WBosonPlus => {
            try emitted.append(.{ .charge = 1.0, .mass = 0.51099895, .energy = p.energy * 0.5, .spin = -0.5, .has_color = false }); // Positron
            try emitted.append(.{ .charge = 0.0, .mass = 0.0, .energy = p.energy * 0.5, .spin = 0.5, .has_color = false }); // Electron neutrino
            return true;
        },
        .WBosonMinus => {
            try emitted.append(.{ .charge = -1.0, .mass = 0.51099895, .energy = p.energy * 0.5, .spin = 0.5, .has_color = false }); // Electron
            try emitted.append(.{ .charge = 0.0, .mass = 0.0, .energy = p.energy * 0.5, .spin = -0.5, .has_color = false }); // Electron antineutrino
            return true;
        },
        .ZBoson => {
            try emitted.append(.{ .charge = -1.0, .mass = 0.51099895, .energy = p.energy / 2.0, .spin = 0.5, .has_color = false }); // Electron
            try emitted.append(.{ .charge = 1.0, .mass = 0.51099895, .energy = p.energy / 2.0, .spin = -0.5, .has_color = false }); // Positron
            return true;
        },
        .HiggsBoson => {
            try emitted.append(.{ .charge = 0.0, .mass = 0.0, .energy = p.energy / 2.0, .spin = 1.0, .has_color = false }); // Photon
            try emitted.append(.{ .charge = 0.0, .mass = 0.0, .energy = p.energy / 2.0, .spin = -1.0, .has_color = false }); // Photon
            return true;
        },
        else => return false,
    }
}

/// Simulates the scattering interaction between two particles, potentially emitting radiation.
///
/// This function models the emission of photons or gluons during particle scattering:
/// - If either particle carries electric charge, a photon is emitted.
/// - If both particles possess color charge, a gluon is emitted.
///
/// The emitted radiation carries away a portion of the total energy (10%), which is equally
/// subtracted from both particles to conserve energy.
fn handleScattering(a: *Self, b: *Self, emitted: *std.ArrayList(Self)) !bool {
    if ((a.energy + b.energy) < 1.0) return false;
    const emission_energy = (a.energy + b.energy) * 0.1;

    if (a.charge != 0.0 or b.charge != 0.0) {
        try emitted.append(.{ .charge = 0.0, .mass = 0.0, .energy = emission_energy, .spin = 1.0, .has_color = false }); // Photon
    }
    if (a.has_color and b.has_color) {
        try emitted.append(.{ .charge = 0.0, .mass = 0.0, .energy = emission_energy, .spin = 1.0, .has_color = true }); // Gluon
    }

    const half_emission = emission_energy / 2.0;
    a.energy = @max(0.0, a.energy - half_emission);
    b.energy = @max(0.0, b.energy - half_emission);

    return false;
}

/// Simulates the pair production process where two photons convert into a particle-antiparticle pair.
///
/// This function checks if both interacting particles are photons (massless, neutral, no color charge).
/// If so, and if their combined energy exceeds the threshold for creating a particle-antiparticle pair,
/// it simulates the creation of:
/// - A muon-antimuon pair if energy > 211.32 MeV (2 × 105.66 MeV)
/// - An electron-positron pair if energy > 1.022 MeV (2 × 0.51099895 MeV)
///
/// The energy is equally divided between the two produced particles, and their spins are set to conserve angular momentum.
fn handlePairProduction(a: *Self, b: *Self, emitted: *std.ArrayList(Self)) !bool {
    if (describeParticle(a.*) == .Photon and describeParticle(b.*) == .Photon) {
        const total_energy = a.energy + b.energy;

        const muon_mass = 105.66; // MeV
        const electron_mass = 0.51099895; // MeV

        if (total_energy >= 2.0 * muon_mass) {
            const energy_per_particle = total_energy / 2.0;
            try emitted.append(.{ .charge = -1.0, .mass = muon_mass, .energy = energy_per_particle, .spin = 0.5, .has_color = false }); // Muon
            try emitted.append(.{ .charge = 1.0, .mass = muon_mass, .energy = energy_per_particle, .spin = -0.5, .has_color = false }); // Antimuon
            return true;
        } else if (total_energy >= 2.0 * electron_mass) {
            const energy_per_particle = total_energy / 2.0;
            try emitted.append(.{ .charge = -1.0, .mass = electron_mass, .energy = energy_per_particle, .spin = 0.5, .has_color = false }); // Electron
            try emitted.append(.{ .charge = 1.0, .mass = electron_mass, .energy = energy_per_particle, .spin = -0.5, .has_color = false }); // Positron
            return true;
        }
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

    const particle_count = 200;

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
            .Electron => .{ .charge = -1.0, .mass = 0.51099895, .spin = 0.5, .has_color = false },
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
            else => .{ .charge = 2.0 / 3.0, .mass = 2.3, .spin = 0.5, .has_color = true },
        };

        const energy = random.float(f64) * 1000.0;

        const p: Self = .{
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
        counts[@intFromEnum(describeParticle(p))] += 1;
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
