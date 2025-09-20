const std = @import("std");
const uSim = @import("usim");

const Graph = uSim.Graph;

const Particle = @This();

const approxEqual = std.math.approxEqRel;
const random = std.crypto.random;

has_color: bool,
/// e
charge: f64,
/// MeV/c²
mass: f64,
/// MeV
energy: f64,
spin: f64,

const Type = enum {
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

    // Energy of particles is randomly calculated when created.
    const ParticleTable = [std.meta.fields(Type).len]Particle{
        .{ .charge = 2.0 / 3.0, .mass = 2.3, .energy = 0, .spin = 0.5, .has_color = true },
        .{ .charge = -1.0 / 3.0, .mass = 4.8, .energy = 0, .spin = 0.5, .has_color = true },
        .{ .charge = 2.0 / 3.0, .mass = 1275.0, .energy = 0, .spin = 0.5, .has_color = true },
        .{ .charge = -1.0 / 3.0, .mass = 95.0, .energy = 0, .spin = 0.5, .has_color = true },
        .{ .charge = 2.0 / 3.0, .mass = 172760.0, .energy = 0, .spin = 0.5, .has_color = true },
        .{ .charge = -1.0 / 3.0, .mass = 4180.0, .energy = 0, .spin = 0.5, .has_color = true },
        .{ .charge = 2.0 / 3.0, .mass = 2.3, .energy = 0, .spin = 0.5, .has_color = true },
        .{ .charge = -1.0, .mass = 0.51099895, .energy = 0, .spin = 0.5, .has_color = false },
        .{ .charge = 0.0, .mass = 0.0, .spin = 0.5, .energy = 0, .has_color = false },
        .{ .charge = -1.0, .mass = 105.66, .spin = 0.5, .energy = 0, .has_color = false },
        .{ .charge = 0.0, .mass = 0.0, .spin = 0.5, .energy = 0, .has_color = false },
        .{ .charge = -1.0, .mass = 1776.86, .spin = 0.5, .energy = 0, .has_color = false },
        .{ .charge = 0.0, .mass = 0.0, .spin = 0.5, .energy = 0, .has_color = false },
        .{ .charge = 0.0, .mass = 0.0, .spin = 1.0, .energy = 0, .has_color = false },
        .{ .charge = 1.0, .mass = 80.379, .spin = 1.0, .energy = 0, .has_color = false },
        .{ .charge = -1.0, .mass = 80.379, .spin = 1.0, .energy = 0, .has_color = false },
        .{ .charge = 0.0, .mass = 91.1876, .spin = 1.0, .energy = 0, .has_color = false },
        .{ .charge = 0.0, .mass = 0.0, .spin = 1.0, .energy = 0, .has_color = true },
        .{ .charge = 0.0, .mass = 125100.0, .spin = 0.0, .energy = 0, .has_color = false },
        .{ .charge = 2.0 / 3.0, .mass = 2.3, .spin = 0.5, .energy = 0, .has_color = true },
    };

    fn toParticle(self: Type) Particle {
        return ParticleTable[@intFromEnum(self)];
    }

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
    fn fromStruct(particle: *Particle) Type {
        if (particle.has_color) {
            if (particle.spin == 0.5) {
                if (approxEqual(f64, particle.charge, 2.0 / 3.0, 0.01)) {
                    // zig fmt: off
                    if (approxEqual(f64, particle.mass, 2.16, 0.49)) return .UpQuark
                    else if (approxEqual(f64, particle.mass, 1275.0, 25.0)) return .CharmQuark
                    else if (approxEqual(f64, particle.mass, 171770.0, 380.0)) return .TopQuark;
                    // zig fmt: on
                } else if (approxEqual(f64, particle.charge, -1.0 / 3.0, 0.01)) {
                    // zig fmt: off
                    if (approxEqual(f64, particle.mass, 4.67, 0.48)) return .DownQuark
                    else if (approxEqual(f64, particle.mass, 93.0, 11.0)) return .StrangeQuark
                    else if (approxEqual(f64, particle.mass, 4180.0, 30.0)) return .BottomQuark;
                    // zig fmt: on
                }
            } else if (particle.spin == 1.0 and particle.mass == 0.0 and particle.charge == 0.0) return .Gluon;
            return .Unknown;
        }

        if (particle.spin == 0.0 and approxEqual(f64, particle.mass, 125100.0, 300.0) and approxEqual(f64, particle.charge, 0.0, 0.001)) return .HiggsBoson;

        if (particle.spin == 1.0) {
            if (particle.mass == 0.0 and particle.charge == 0.0) return .Photon;
            if (particle.charge != 0.0) {
                if (!approxEqual(f64, particle.mass, 80379.0, 12.0)) return .Unknown; // Fast path
                // zig fmt: off
                if (approxEqual(f64, particle.charge, 1.0, 0.01)) return .WBosonPlus
                else if (approxEqual(f64, particle.charge, -1.0, 0.01)) return .WBosonMinus;
                // zig fmt: on
            }
            if (approxEqual(f64, particle.mass, 91187.6, 2.1)) return .ZBoson;
        }

        if (approxEqual(f64, particle.mass, 0.51099895, 0.00000015)) {
            // zig fmt: off
            if (approxEqual(f64, particle.charge, -1.0, 0.01) and particle.spin == 0.5) return .Electron 
            else if (approxEqual(f64, particle.charge, 1.0, 0.01) and particle.spin == -0.5) return .Positron;
            // zig fmt: on
        }

        if (particle.spin == 0.5) {
            if (approxEqual(f64, particle.charge, -1.0, 0.01)) {
                // zig fmt: off
                if (approxEqual(f64, particle.mass, 105.6583755, 0.0000023)) return .Muon
                else if (approxEqual(f64, particle.mass, 1776.86, 0.12)) return .Tau;
                // zig fmt: on
            } else if (particle.mass < 0.8 and approxEqual(f64, particle.charge, 0.0, 0.001)) return .ElectronNeutrino;
        }

        return .Unknown;
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
    // Only third particle can be null for now
    fn decay(self: Type, energy: f64) ?[3]?Particle {
        return switch (self) {
            .Muon => .{
                .{ .charge = -1.0, .mass = 0.51099895, .energy = energy * 0.3, .spin = 0.5, .has_color = false }, // Electron
                .{ .charge = 0.0, .mass = 0.0, .energy = energy * 0.35, .spin = -0.5, .has_color = false }, // Electron antineutrino
                .{ .charge = 0.0, .mass = 0.0, .energy = energy * 0.35, .spin = 0.5, .has_color = false }, // Muon neutrino
            },
            .Tau => .{
                .{ .charge = -1.0, .mass = 105.66, .energy = energy * 0.3, .spin = 0.5, .has_color = false }, // Muon
                .{ .charge = 0.0, .mass = 0.0, .energy = energy * 0.35, .spin = -0.5, .has_color = false }, // Muon antineutrino
                .{ .charge = 0.0, .mass = 0.0, .energy = energy * 0.35, .spin = 0.5, .has_color = false }, // Tau neutrino
            },
            .WBosonPlus => .{
                .{ .charge = 1.0, .mass = 0.51099895, .energy = energy * 0.5, .spin = -0.5, .has_color = false }, // Positron
                .{ .charge = 0.0, .mass = 0.0, .energy = energy * 0.5, .spin = 0.5, .has_color = false }, // Electron neutrino
                null,
            },
            .WBosonMinus => .{
                .{ .charge = -1.0, .mass = 0.51099895, .energy = energy * 0.5, .spin = 0.5, .has_color = false }, // Electron
                .{ .charge = 0.0, .mass = 0.0, .energy = energy * 0.5, .spin = -0.5, .has_color = false }, // Electron antineutrino
                null,
            },
            .ZBoson => .{
                .{ .charge = -1.0, .mass = 0.51099895, .energy = energy / 2, .spin = 0.5, .has_color = false }, // Electron
                .{ .charge = 1.0, .mass = 0.51099895, .energy = energy / 2, .spin = -0.5, .has_color = false }, // Positron
                null,
            },
            .HiggsBoson => .{
                .{ .charge = 0.0, .mass = 0.0, .energy = energy / 2, .spin = 1, .has_color = false }, // Photon
                .{ .charge = 0.0, .mass = 0.0, .energy = energy / 2, .spin = -1, .has_color = false }, // Photon
                null,
            },
            else => null,
        };
    }
};

/// Returns `true` if the emission consumed the interacting particles
pub fn interact(self: *Particle, other: *Particle, emission_buffer: *std.ArrayList(Particle), allocator: std.mem.Allocator) !bool {
    if (try handleAnnihilation(self, other, emission_buffer, allocator)) return true;
    if (try handlePairProduction(self, other, emission_buffer, allocator)) return true;

    const consumed_self = try handleDecay(self, emission_buffer, allocator);
    const consumed_other = try handleDecay(other, emission_buffer, allocator);
    if (consumed_self or consumed_other) return true;

    _ = try handleScattering(self, other, emission_buffer, allocator);
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
fn handleAnnihilation(a: *Particle, b: *Particle, emitted: *std.ArrayList(Particle), allocator: std.mem.Allocator) !bool {
    if (std.math.approxEqRel(f64, a.charge, -b.charge, 1e-6) and
        std.math.approxEqRel(f64, a.mass, b.mass, 1e-6) and
        std.math.approxEqRel(f64, a.spin, -b.spin, 1e-6) and
        !a.has_color and !b.has_color and
        a.mass > 0.0)
    {
        const total_energy = a.energy + b.energy;
        const photon_energy = total_energy / 2.0;
        const arr = try emitted.addManyAsArray(allocator, 2);
        arr[0] = .{ .charge = 0.0, .mass = 0.0, .energy = photon_energy, .spin = 1.0, .has_color = false };
        arr[1] = .{ .charge = 0.0, .mass = 0.0, .energy = photon_energy, .spin = -1.0, .has_color = false };
        return true;
    }
    return false;
}

fn handleDecay(p: *Particle, emitted: *std.ArrayList(Particle), allocator: std.mem.Allocator) !bool {
    var particle_type: Type = .fromStruct(p);
    const decay = particle_type.decay(p.energy) orelse return false;

    if (decay[2] != null) {
        const arr = try emitted.addManyAsArray(allocator, 3);
        arr[0] = decay[0].?;
        arr[1] = decay[1].?;
        arr[2] = decay[2].?;
    } else {
        const arr = try emitted.addManyAsArray(allocator, 2);
        arr[0] = decay[0].?;
        arr[1] = decay[1].?;
    }

    return true;
}

/// Simulates the scattering interaction between two particles, potentially emitting radiation.
///
/// This function models the emission of photons or gluons during particle scattering:
/// - If either particle carries electric charge, a photon is emitted.
/// - If both particles possess color charge, a gluon is emitted.
///
/// The emitted radiation carries away a portion of the total energy (10%), which is equally
/// subtracted from both particles to conserve energy.
fn handleScattering(a: *Particle, b: *Particle, emitted: *std.ArrayList(Particle), allocator: std.mem.Allocator) !bool {
    if ((a.energy + b.energy) < 1.0) return false;
    const emission_energy = (a.energy + b.energy) * 0.1;

    if (a.charge != 0.0 or b.charge != 0.0) {
        try emitted.append(allocator, .{ .charge = 0.0, .mass = 0.0, .energy = emission_energy, .spin = 1.0, .has_color = false }); // Photon
    }
    if (a.has_color and b.has_color) {
        try emitted.append(allocator, .{ .charge = 0.0, .mass = 0.0, .energy = emission_energy, .spin = 1.0, .has_color = true }); // Gluon
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
fn handlePairProduction(a: *Particle, b: *Particle, emitted: *std.ArrayList(Particle), allocator: std.mem.Allocator) !bool {
    const particle_a = Type.fromStruct(a);
    const particle_b = Type.fromStruct(b);
    if (particle_a != .Photon and particle_b != .Photon) return false;

    const total_energy = a.energy + b.energy;

    const muon_mass = 105.66; // MeV
    const electron_mass = 0.51099895; // MeV

    if (total_energy >= 2.0 * muon_mass) {
        const arr = try emitted.addManyAsArray(allocator, 2);
        const energy_per_particle = total_energy / 2.0;
        arr[0] = .{ .charge = -1.0, .mass = muon_mass, .energy = energy_per_particle, .spin = 0.5, .has_color = false }; // Muon
        arr[1] = .{ .charge = 1.0, .mass = muon_mass, .energy = energy_per_particle, .spin = -0.5, .has_color = false }; // Antimuon

    } else if (total_energy >= 2.0 * electron_mass) {
        const arr = try emitted.addManyAsArray(allocator, 2);
        const energy_per_particle = total_energy / 2.0;
        arr[0] = .{ .charge = -1.0, .mass = electron_mass, .energy = energy_per_particle, .spin = 0.5, .has_color = false }; // Electron
        arr[1] = .{ .charge = 1.0, .mass = electron_mass, .energy = energy_per_particle, .spin = -0.5, .has_color = false }; // Positron

    }

    return true;
}

pub fn initializeGraph(allocator: std.mem.Allocator, particle_count: comptime_int) !Graph(usize, Particle) {
    var graph: Graph(usize, Particle) = .init(allocator);
    for (0..particle_count) |i| {
        const kind = random.enumValue(Type);

        var particle = kind.toParticle();
        particle.energy = random.float(f64) * 1000.0;

        _ = try graph.putVertex(i, particle);
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

pub fn print(
    graph: *Graph(usize, Particle),
    allocator: std.mem.Allocator,
    file: *std.Io.Writer,
    iter: usize,
) !void {
    const num_vertices: usize = graph.vertices.count();
    var total_edges: usize = 0;

    var counts = [_]usize{0} ** @typeInfo(Type).@"enum".fields.len;
    var total_mass: f64 = 0.0;
    var total_charge: f64 = 0.0;
    var total_energy: f64 = 0.0;

    var vertices = graph.vertices.valueIterator();
    while (vertices.next()) |v| {
        total_edges += v.*.adjacency_set.count();

        var p = v.*.*.data;
        counts[@intFromEnum(Type.fromStruct(&p))] += 1;
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

    inline for (@typeInfo(Type).@"enum".fields, 0..) |field, i|
        std.debug.print("{s}: {any}\n", .{ field.name, counts[i] });

    std.debug.print("-----------------------------\n\n", .{});

    if (iter == 0) {
        try file.print("iter,vertices,num_edges,total_mass,total_charge,total_energy", .{});
        inline for (@typeInfo(Type).@"enum".fields) |field| {
            try file.print(",{s}", .{field.name});
        }
        try file.print("\n", .{});
    }

    try file.print("{d},{d},{d},{d:.3},{d:.3},{d:.3}", .{
        iter,
        num_vertices,
        total_edges,
        total_mass,
        total_charge,
        total_energy,
    });

    inline for (counts) |c| try file.print(",{d}", .{c});
    try file.print("\n", .{});
    try file.flush();

    var gfile_buffer: [1024]u8 = undefined;
    const gfile_name = try std.fmt.allocPrint(allocator, "zig-out/graph/iter_{d}.gv", .{iter});
    defer allocator.free(gfile_name);
    var gfile = try std.fs.cwd().createFile(gfile_name, .{});
    var gfile_writer = gfile.writer(&gfile_buffer);
    const gfile_interface = &gfile_writer.interface;
    defer gfile.close();
    try gfile_interface.print("digraph G {{\n", .{});

    var it = graph.vertices.iterator();
    while (it.next()) |entry| {
        const vertex_id = entry.key_ptr.*;
        var p = entry.value_ptr.*.data;
        const label = try std.fmt.allocPrint(allocator, "{s}\\nm:{d:.1} q:{d:.1}", .{
            @tagName(Type.fromStruct(&p)),
            p.mass,
            p.charge,
        });
        defer allocator.free(label);
        try gfile_interface.print("  {d} [label=\"{s}\"];\n", .{ vertex_id, label });

        var neighbors = entry.value_ptr.*.adjacency_set.iterator();
        while (neighbors.next()) |dst| {
            try gfile_interface.print("  {d} -> {d};\n", .{ vertex_id, dst.key_ptr.* });
        }
    }

    try gfile_interface.print("}}\n", .{});
    try gfile_interface.flush();
}
