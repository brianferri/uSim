const std = @import("std");
const uSim = @import("usim");

const Graph = uSim.Graph;

const Self = @This();

const ParticleType = enum {
    Electron,
    Positron,
    Photon,
    WPlus,
    WMinus,
};

kind: ParticleType,
charge: f64,
mass: f64,
energy: f64,

pub fn interact(self: *Self, other: *Self, allocator: std.mem.Allocator) ![]Self {
    var emitted = std.ArrayList(Self).init(allocator);

    if (try handleAnnihilation(self, other, &emitted)) return emitted.toOwnedSlice();
    if (try handlePhotonEmission(self, other, &emitted)) return emitted.toOwnedSlice();
    if (try handlePhotonPhotonInteraction(self, other, &emitted)) return emitted.toOwnedSlice();
    if (try handleWBosonAnnihilation(self, other, &emitted)) return emitted.toOwnedSlice();

    return emitted.toOwnedSlice();
}

fn handleAnnihilation(a: *Self, b: *Self, emitted: *std.ArrayList(Self)) !bool {
    if ((a.kind == .Electron and b.kind == .Positron) or
        (a.kind == .Positron and b.kind == .Electron))
    {
        const energy = (a.energy + b.energy) / 2.0;
        try emitted.append(.{ .kind = .Photon, .charge = 0.0, .mass = 0.0, .energy = energy });
        try emitted.append(.{ .kind = .Photon, .charge = 0.0, .mass = 0.0, .energy = energy });
        return true;
    }
    return false;
}

fn handlePhotonEmission(a: *Self, b: *Self, emitted: *std.ArrayList(Self)) !bool {
    if ((a.kind == .Electron or a.kind == .Positron) and b.kind == .Photon) {
        const photon_energy = a.energy * 0.1;
        a.energy -= photon_energy;
        try emitted.append(.{ .kind = .Photon, .charge = 0.0, .mass = 0.0, .energy = photon_energy });
        return true;
    }
    return false;
}

fn handlePhotonPhotonInteraction(a: *Self, b: *Self, emitted: *std.ArrayList(Self)) !bool {
    if (a.kind == .Photon and b.kind == .Photon and (a.energy + b.energy) >= 1.022) {
        const total_energy = a.energy + b.energy;
        try emitted.append(.{ .kind = .Electron, .charge = -1.0, .mass = 0.511, .energy = total_energy / 2.0 });
        try emitted.append(.{ .kind = .Positron, .charge = 1.0, .mass = 0.511, .energy = total_energy / 2.0 });
        return true;
    }
    return false;
}

fn handleWBosonAnnihilation(a: *Self, b: *Self, emitted: *std.ArrayList(Self)) !bool {
    if ((a.kind == .WPlus and b.kind == .WMinus) or (a.kind == .WMinus and b.kind == .WPlus)) {
        const energy = (a.energy + b.energy) / 2.0;
        try emitted.append(.{ .kind = .Photon, .charge = 0.0, .mass = 0.0, .energy = energy });
        try emitted.append(.{ .kind = .Photon, .charge = 0.0, .mass = 0.0, .energy = energy });
        return true;
    }
    return false;
}

pub fn canAnnihilate(a: *const Self, b: *const Self) bool {
    return (a.kind == .Electron and b.kind == .Positron) or
        (a.kind == .Positron and b.kind == .Electron);
}

pub fn initializeGraph(allocator: std.mem.Allocator) !Graph(usize, Self) {
    var graph = Graph(usize, Self).init(allocator, 0);

    var prng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    const random = prng.random();

    const particle_count = 5;

    for (0..particle_count) |_| {
        const kind = random.enumValue(ParticleType);

        const charge: f64 = switch (kind) {
            .Electron => -1.0,
            .Positron => 1.0,
            .Photon => 0.0,
            .WPlus => 1.0,
            .WMinus => -1.0,
        };

        const mass: f64 = switch (kind) {
            .Electron, .Positron => 0.511,
            .Photon => 0.0,
            .WPlus, .WMinus => 80.379,
        };

        const energy = random.float(f64) * 100.0;

        const p: Self = .{
            .kind = kind,
            .charge = charge,
            .mass = mass,
            .energy = energy,
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
