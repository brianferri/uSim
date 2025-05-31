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

pub fn interact(self: *Self, other: *Self, allocator: std.mem.Allocator) ![]Self {
    var emitted = std.ArrayList(Self).init(allocator);

    if (try handleAnnihilation(self, other, &emitted)) return emitted.toOwnedSlice();
    if (try handlePhotonEmission(self, other, &emitted)) return emitted.toOwnedSlice();
    if (try handlePhotonPhotonInteraction(self, other, &emitted)) return emitted.toOwnedSlice();
    if (try handleWBosonInteraction(self, other, &emitted)) return emitted.toOwnedSlice();
    if (try handleGluonEmission(self, other, &emitted)) return emitted.toOwnedSlice();
    if (try handleHiggsDecay(self, other, &emitted)) return emitted.toOwnedSlice();
    if (try handleNeutrinoInteraction(self, other, &emitted)) return emitted.toOwnedSlice();
    if (try handleZBosonDecay(self, other, &emitted)) return emitted.toOwnedSlice();
    if (try handleQuarkPairProduction(self, other, &emitted)) return emitted.toOwnedSlice();
    if (try handleWeakLeptonInteraction(self, other, &emitted)) return emitted.toOwnedSlice();

    return emitted.toOwnedSlice();
}

fn handleAnnihilation(a: *Self, b: *Self, emitted: *std.ArrayList(Self)) !bool {
    if (a.kind == .Electron and b.kind == .Electron and a.charge != b.charge) {
        const energy = (a.energy + b.energy) / 2.0;
        try emitted.append(.{ .kind = .Photon, .charge = 0.0, .mass = 0.0, .energy = energy, .spin = 1.0, .has_color = false });
        try emitted.append(.{ .kind = .Photon, .charge = 0.0, .mass = 0.0, .energy = energy, .spin = 1.0, .has_color = false });
        return true;
    }
    return false;
}

fn handlePhotonEmission(a: *Self, b: *Self, emitted: *std.ArrayList(Self)) !bool {
    if ((a.kind == .Electron or a.kind == .Muon or a.kind == .Tau) and b.kind == .Photon) {
        const photon_energy = a.energy * 0.1;
        a.energy -= photon_energy;
        try emitted.append(.{ .kind = .Photon, .charge = 0.0, .mass = 0.0, .energy = photon_energy, .spin = 1.0, .has_color = false });
        return true;
    }
    return false;
}

fn handlePhotonPhotonInteraction(a: *Self, b: *Self, emitted: *std.ArrayList(Self)) !bool {
    if (a.kind == .Photon and b.kind == .Photon and (a.energy + b.energy) >= 1.022) {
        const total_energy = a.energy + b.energy;
        try emitted.append(.{ .kind = .Electron, .charge = -1.0, .mass = 0.511, .energy = total_energy / 2.0, .spin = 0.5, .has_color = false });
        try emitted.append(.{ .kind = .Electron, .charge = 1.0, .mass = 0.511, .energy = total_energy / 2.0, .spin = 0.5, .has_color = false });
        return true;
    }
    return false;
}

fn handleWBosonInteraction(a: *Self, b: *Self, emitted: *std.ArrayList(Self)) !bool {
    if ((a.kind == .WBosonPlus and b.kind == .WBosonMinus) or (a.kind == .WBosonMinus and b.kind == .WBosonPlus)) {
        const energy = (a.energy + b.energy) / 2.0;
        try emitted.append(.{ .kind = .ZBoson, .charge = 0.0, .mass = 91.1876, .energy = energy, .spin = 1.0, .has_color = false });
        return true;
    }
    return false;
}

fn handleGluonEmission(a: *Self, b: *Self, emitted: *std.ArrayList(Self)) !bool {
    if ((a.has_color and b.kind == .Gluon) or (b.has_color and a.kind == .Gluon)) {
        const emitter = if (a.has_color) a else b;
        const energy = emitter.energy * 0.05;
        if (energy < 1.0) return false;

        emitter.energy -= energy;
        try emitted.append(.{ .kind = .Gluon, .charge = 0.0, .mass = 0.0, .energy = energy, .spin = 1.0, .has_color = true });
        return true;
    }
    return false;
}

fn handleHiggsDecay(a: *Self, b: *Self, emitted: *std.ArrayList(Self)) !bool {
    if (a.kind != .HiggsBoson and b.kind != .HiggsBoson) return false;

    const higgs = if (a.kind == .HiggsBoson) a else b;
    if (higgs.energy < 10.0) return false;

    const energy = higgs.energy / 2.0;

    try emitted.append(.{ .kind = .BottomQuark, .charge = -1.0 / 3.0, .mass = 4180.0, .energy = energy, .spin = 0.5, .has_color = true });
    try emitted.append(.{ .kind = .BottomQuark, .charge = 1.0 / 3.0, .mass = 4180.0, .energy = energy, .spin = 0.5, .has_color = true });
    return true;
}

fn handleNeutrinoInteraction(a: *Self, b: *Self, emitted: *std.ArrayList(Self)) !bool {
    const is_neutrino = a.kind == .ElectronNeutrino or a.kind == .MuonNeutrino or a.kind == .TauNeutrino or
        b.kind == .ElectronNeutrino or b.kind == .MuonNeutrino or b.kind == .TauNeutrino;

    if (!is_neutrino) return false;

    const charged_lepton: ParticleType = switch (a.kind) {
        .ElectronNeutrino => .Electron,
        .MuonNeutrino => .Muon,
        .TauNeutrino => .Tau,
        else => switch (b.kind) {
            .ElectronNeutrino => .Electron,
            .MuonNeutrino => .Muon,
            .TauNeutrino => .Tau,
            else => return false,
        },
    };

    const energy = (a.energy + b.energy) / 2.0;

    try emitted.append(.{ .kind = charged_lepton, .charge = -1.0, .mass = switch (charged_lepton) {
        .Electron => 0.511,
        .Muon => 105.66,
        .Tau => 1776.86,
        else => unreachable,
    }, .energy = energy, .spin = 0.5, .has_color = false });

    return true;
}

fn handleZBosonDecay(a: *Self, b: *Self, emitted: *std.ArrayList(Self)) !bool {
    if (a.kind != .ZBoson and b.kind != .ZBoson) return false;

    const z = if (a.kind == .ZBoson) a else b;
    if (z.energy < 1.1) return false;

    const energy = z.energy / 2.0;

    try emitted.append(.{ .kind = .Electron, .charge = -1.0, .mass = 0.511, .energy = energy, .spin = 0.5, .has_color = false });
    try emitted.append(.{ .kind = .Electron, .charge = 1.0, .mass = 0.511, .energy = energy, .spin = 0.5, .has_color = false });
    return true;
}

fn handleQuarkPairProduction(a: *Self, b: *Self, emitted: *std.ArrayList(Self)) !bool {
    if ((a.kind == .Photon or a.kind == .Gluon) and (b.kind == .Photon or b.kind == .Gluon)) {
        const total_energy = a.energy + b.energy;
        if (total_energy < 10.0) return false;

        const energy = total_energy / 2.0;

        try emitted.append(.{ .kind = .UpQuark, .charge = 2.0 / 3.0, .mass = 2.3, .energy = energy, .spin = 0.5, .has_color = true });
        try emitted.append(.{ .kind = .UpQuark, .charge = -2.0 / 3.0, .mass = 2.3, .energy = energy, .spin = 0.5, .has_color = true });
        return true;
    }
    return false;
}

fn handleWeakLeptonInteraction(a: *Self, b: *Self, emitted: *std.ArrayList(Self)) !bool {
    const is_lepton = switch (a.kind) {
        .Electron, .Muon, .Tau => true,
        else => switch (b.kind) {
            .Electron, .Muon, .Tau => true,
            else => false,
        },
    };

    const is_wboson = a.kind == .WBosonPlus or a.kind == .WBosonMinus or b.kind == .WBosonPlus or b.kind == .WBosonMinus;

    if (!is_lepton or !is_wboson) return false;

    const energy = (a.energy + b.energy) / 2.0;
    const lepton: ParticleType = if (a.kind == .Electron or b.kind == .Electron) .Electron else if (a.kind == .Muon or b.kind == .Muon) .Muon else .Tau;
    const neutrino: ParticleType = switch (lepton) {
        .Electron => .ElectronNeutrino,
        .Muon => .MuonNeutrino,
        .Tau => .TauNeutrino,
        else => unreachable,
    };

    try emitted.append(.{ .kind = neutrino, .charge = 0.0, .mass = 0.0, .energy = energy, .spin = 0.5, .has_color = false });

    return true;
}

pub fn canAnnihilate(a: *const Self, b: *const Self) bool {
    return a.kind == b.kind and a.charge != b.charge and a.spin == b.spin and a.mass == b.mass;
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
            try graph.addEdge(i, i + 1);
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
