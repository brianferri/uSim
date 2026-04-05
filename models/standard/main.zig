//! Standard Model **phenomenology** on the uSim graph: PDG masses, quantum numbers, and tree-level-inspired
//! vertices (weak decays, γγ → f f̄, e⁺e⁻ → γγ, bremsstrahlung). This is **not** a covariant scattering
//! amplitude calculator; energies use `mass + energy` as a CM budget. Data: `sm_constants.zig` (PDG RPP 2024).
//!
//! **Simulation integrity:** each host `pairwiseInteractionPass` must leave **additive** electric charge,
//! `b3`, and lepton flavors unchanged when summed over all vertices (`sumGlobalQuantumNumbers` / `expectConservedObservablesAcrossPass`).
const std = @import("std");
const uSim = @import("usim");
const sm = @import("sm_constants.zig");
const Particle = @This();

const approxEqual = std.math.approxEqRel;
var prng = std.Random.DefaultPrng.init(0xfeed_beef);
const random = prng.random();

/// Re-seed the model RNG (call once at process start for reproducible simulations).
pub fn setSimulationRngSeed(seed: u64) void {
    prng = std.Random.DefaultPrng.init(seed);
}

/// Additive quantum numbers summed over **all vertices** in a graph snapshot (electric charge in e, baryon×3, lepton flavors).
pub const GlobalQuantumNumbers = struct {
    charge: f64,
    b3: i64,
    L_e: i64,
    L_mu: i64,
    L_tau: i64,

    pub fn eqlApprox(self: GlobalQuantumNumbers, other: GlobalQuantumNumbers) bool {
        return approxEqual(f64, self.charge, other.charge, 1e-9) and
            self.b3 == other.b3 and
            self.L_e == other.L_e and
            self.L_mu == other.L_mu and
            self.L_tau == other.L_tau;
    }
};

pub fn sumGlobalQuantumNumbers(graph: *const Graph) GlobalQuantumNumbers {
    var t = GlobalQuantumNumbers{
        .charge = 0,
        .b3 = 0,
        .L_e = 0,
        .L_mu = 0,
        .L_tau = 0,
    };
    var it = graph.vertices.iterator();
    while (it.next()) |ent| {
        const p = ent.value_ptr.*.data;
        t.charge += p.charge;
        t.b3 += @as(i64, p.b3);
        t.L_e += @as(i64, p.L_e);
        t.L_mu += @as(i64, p.L_mu);
        t.L_tau += @as(i64, p.L_tau);
    }
    return t;
}

pub const SimulationIntegrityError = error{QuantumNumbersNotConserved};

/// Debug / CI: a single `pairwiseInteractionPass` must not change summed gauge quantum numbers on this graph.
pub fn expectConservedObservablesAcrossPass(pre: GlobalQuantumNumbers, post: GlobalQuantumNumbers) SimulationIntegrityError!void {
    if (!pre.eqlApprox(post)) return error.QuantumNumbersNotConserved;
}

has_color: bool,
charge: f64,
/// Rest mass in MeV/c².
mass: f64,
/// Kinetic / internal excitation energy budget in MeV (not a covariant four-momentum; see module comment).
energy: f64,
spin: f64,
/// Baryon number × 3: +1 quark, -1 antiquark, 0 otherwise.
b3: i8,
L_e: i8,
L_mu: i8,
L_tau: i8,

/// Effective CM energy budget for decays and thresholds (MeV).
pub fn cmBudget(self: Particle) f64 {
    return @max(0.0, self.mass + self.energy);
}

pub const Type = enum {
    UpQuark,
    DownQuark,
    CharmQuark,
    StrangeQuark,
    TopQuark,
    BottomQuark,
    AntiUpQuark,
    AntiDownQuark,
    AntiCharmQuark,
    AntiStrangeQuark,
    AntiBottomQuark,
    Positron,
    Electron,
    ElectronNeutrino,
    ElectronAntiNeutrino,
    Muon,
    AntiMuon,
    MuonNeutrino,
    MuonAntiNeutrino,
    Tau,
    AntiTau,
    TauNeutrino,
    TauAntiNeutrino,
    Photon,
    WBosonPlus,
    WBosonMinus,
    ZBoson,
    Gluon,
    HiggsBoson,
    PionMinus,
    PionPlus,
    Unknown,

    const ParticleTable = [std.meta.fields(Type).len]Particle{
        .{ .has_color = true, .charge = 2.0 / 3.0, .mass = sm.up_quark_msbar_mev, .energy = 0, .spin = 0.5, .b3 = 1, .L_e = 0, .L_mu = 0, .L_tau = 0 },
        .{ .has_color = true, .charge = -1.0 / 3.0, .mass = sm.down_quark_msbar_mev, .energy = 0, .spin = 0.5, .b3 = 1, .L_e = 0, .L_mu = 0, .L_tau = 0 },
        .{ .has_color = true, .charge = 2.0 / 3.0, .mass = sm.charm_quark_msbar_mev, .energy = 0, .spin = 0.5, .b3 = 1, .L_e = 0, .L_mu = 0, .L_tau = 0 },
        .{ .has_color = true, .charge = -1.0 / 3.0, .mass = sm.strange_quark_msbar_mev, .energy = 0, .spin = 0.5, .b3 = 1, .L_e = 0, .L_mu = 0, .L_tau = 0 },
        .{ .has_color = true, .charge = 2.0 / 3.0, .mass = sm.top_quark_pole_mev, .energy = 0, .spin = 0.5, .b3 = 1, .L_e = 0, .L_mu = 0, .L_tau = 0 },
        .{ .has_color = true, .charge = -1.0 / 3.0, .mass = sm.bottom_quark_msbar_mev, .energy = 0, .spin = 0.5, .b3 = 1, .L_e = 0, .L_mu = 0, .L_tau = 0 },
        .{ .has_color = true, .charge = -2.0 / 3.0, .mass = sm.up_quark_msbar_mev, .energy = 0, .spin = -0.5, .b3 = -1, .L_e = 0, .L_mu = 0, .L_tau = 0 },
        .{ .has_color = true, .charge = 1.0 / 3.0, .mass = sm.down_quark_msbar_mev, .energy = 0, .spin = -0.5, .b3 = -1, .L_e = 0, .L_mu = 0, .L_tau = 0 },
        .{ .has_color = true, .charge = -2.0 / 3.0, .mass = sm.charm_quark_msbar_mev, .energy = 0, .spin = -0.5, .b3 = -1, .L_e = 0, .L_mu = 0, .L_tau = 0 },
        .{ .has_color = true, .charge = 1.0 / 3.0, .mass = sm.strange_quark_msbar_mev, .energy = 0, .spin = -0.5, .b3 = -1, .L_e = 0, .L_mu = 0, .L_tau = 0 },
        .{ .has_color = true, .charge = 1.0 / 3.0, .mass = sm.bottom_quark_msbar_mev, .energy = 0, .spin = -0.5, .b3 = -1, .L_e = 0, .L_mu = 0, .L_tau = 0 },
        .{ .has_color = false, .charge = 1.0, .mass = sm.electron_mass_mev, .energy = 0, .spin = -0.5, .b3 = 0, .L_e = -1, .L_mu = 0, .L_tau = 0 },
        .{ .has_color = false, .charge = -1.0, .mass = sm.electron_mass_mev, .energy = 0, .spin = 0.5, .b3 = 0, .L_e = 1, .L_mu = 0, .L_tau = 0 },
        .{ .has_color = false, .charge = 0.0, .mass = 0.0, .energy = 0, .spin = 0.5, .b3 = 0, .L_e = 1, .L_mu = 0, .L_tau = 0 },
        .{ .has_color = false, .charge = 0.0, .mass = 0.0, .energy = 0, .spin = -0.5, .b3 = 0, .L_e = -1, .L_mu = 0, .L_tau = 0 },
        .{ .has_color = false, .charge = -1.0, .mass = sm.muon_mass_mev, .energy = 0, .spin = 0.5, .b3 = 0, .L_e = 0, .L_mu = 1, .L_tau = 0 },
        .{ .has_color = false, .charge = 1.0, .mass = sm.muon_mass_mev, .energy = 0, .spin = -0.5, .b3 = 0, .L_e = 0, .L_mu = -1, .L_tau = 0 },
        .{ .has_color = false, .charge = 0.0, .mass = 0.0, .energy = 0, .spin = 0.5, .b3 = 0, .L_e = 0, .L_mu = 1, .L_tau = 0 },
        .{ .has_color = false, .charge = 0.0, .mass = 0.0, .energy = 0, .spin = -0.5, .b3 = 0, .L_e = 0, .L_mu = -1, .L_tau = 0 },
        .{ .has_color = false, .charge = -1.0, .mass = sm.tau_mass_mev, .energy = 0, .spin = 0.5, .b3 = 0, .L_e = 0, .L_mu = 0, .L_tau = 1 },
        .{ .has_color = false, .charge = 1.0, .mass = sm.tau_mass_mev, .energy = 0, .spin = -0.5, .b3 = 0, .L_e = 0, .L_mu = 0, .L_tau = -1 },
        .{ .has_color = false, .charge = 0.0, .mass = 0.0, .energy = 0, .spin = 0.5, .b3 = 0, .L_e = 0, .L_mu = 0, .L_tau = 1 },
        .{ .has_color = false, .charge = 0.0, .mass = 0.0, .energy = 0, .spin = -0.5, .b3 = 0, .L_e = 0, .L_mu = 0, .L_tau = -1 },
        .{ .has_color = false, .charge = 0.0, .mass = 0.0, .energy = 0, .spin = 1.0, .b3 = 0, .L_e = 0, .L_mu = 0, .L_tau = 0 },
        .{ .has_color = false, .charge = 1.0, .mass = sm.w_boson_mass_mev, .energy = 0, .spin = 1.0, .b3 = 0, .L_e = 0, .L_mu = 0, .L_tau = 0 },
        .{ .has_color = false, .charge = -1.0, .mass = sm.w_boson_mass_mev, .energy = 0, .spin = 1.0, .b3 = 0, .L_e = 0, .L_mu = 0, .L_tau = 0 },
        .{ .has_color = false, .charge = 0.0, .mass = sm.z_boson_mass_mev, .energy = 0, .spin = 1.0, .b3 = 0, .L_e = 0, .L_mu = 0, .L_tau = 0 },
        .{ .has_color = true, .charge = 0.0, .mass = 0.0, .energy = 0, .spin = 1.0, .b3 = 0, .L_e = 0, .L_mu = 0, .L_tau = 0 },
        .{ .has_color = false, .charge = 0.0, .mass = sm.higgs_mass_mev, .energy = 0, .spin = 0.0, .b3 = 0, .L_e = 0, .L_mu = 0, .L_tau = 0 },
        .{ .has_color = false, .charge = -1.0, .mass = sm.charged_pion_mass_mev, .energy = 0, .spin = 0.0, .b3 = 0, .L_e = 0, .L_mu = 0, .L_tau = 0 },
        .{ .has_color = false, .charge = 1.0, .mass = sm.charged_pion_mass_mev, .energy = 0, .spin = 0.0, .b3 = 0, .L_e = 0, .L_mu = 0, .L_tau = 0 },
        .{ .has_color = false, .charge = 0.0, .mass = 0.0, .energy = 0, .spin = 0.0, .b3 = 0, .L_e = 0, .L_mu = 0, .L_tau = 0 },
    };

    pub fn toParticle(self: Type) Particle {
        return ParticleTable[@intFromEnum(self)];
    }

    pub fn fromStruct(particle: *const Particle) Type {
        if (particle.has_color) {
            if (particle.spin == 1.0 and particle.mass == 0.0 and particle.charge == 0.0) return .Gluon;
            if (particle.spin == 0.5) {
                if (approxEqual(f64, particle.charge, 2.0 / 3.0, 0.02) and particle.b3 > 0) {
                    if (@abs(particle.mass - sm.up_quark_msbar_mev) < 1.0) return .UpQuark;
                    if (@abs(particle.mass - sm.charm_quark_msbar_mev) < 40.0) return .CharmQuark;
                    if (@abs(particle.mass - sm.top_quark_pole_mev) < 500.0) return .TopQuark;
                } else if (approxEqual(f64, particle.charge, -1.0 / 3.0, 0.02) and particle.b3 > 0) {
                    if (@abs(particle.mass - sm.down_quark_msbar_mev) < 1.0) return .DownQuark;
                    if (@abs(particle.mass - sm.strange_quark_msbar_mev) < 3.0) return .StrangeQuark;
                    if (@abs(particle.mass - sm.bottom_quark_msbar_mev) < 50.0) return .BottomQuark;
                }
            } else if (particle.spin == -0.5) {
                if (approxEqual(f64, particle.charge, -2.0 / 3.0, 0.02) and particle.b3 < 0) {
                    if (@abs(particle.mass - sm.charm_quark_msbar_mev) < 40.0) return .AntiCharmQuark;
                    if (@abs(particle.mass - sm.up_quark_msbar_mev) < 1.0) return .AntiUpQuark;
                } else if (approxEqual(f64, particle.charge, 1.0 / 3.0, 0.02) and particle.b3 < 0) {
                    if (@abs(particle.mass - sm.bottom_quark_msbar_mev) < 80.0) return .AntiBottomQuark;
                    if (@abs(particle.mass - sm.strange_quark_msbar_mev) < 3.0) return .AntiStrangeQuark;
                    if (@abs(particle.mass - sm.down_quark_msbar_mev) < 1.0) return .AntiDownQuark;
                }
            }
            return .Unknown;
        }

        if (particle.spin == 0.0 and @abs(particle.mass - sm.higgs_mass_mev) < 500.0 and approxEqual(f64, particle.charge, 0.0, 0.001)) return .HiggsBoson;

        if (particle.spin == 1.0) {
            if (particle.mass == 0.0 and particle.charge == 0.0) return .Photon;
            if (@abs(particle.mass - sm.w_boson_mass_mev) < 250.0 and approxEqual(f64, particle.charge, 1.0, 0.02)) return .WBosonPlus;
            if (@abs(particle.mass - sm.w_boson_mass_mev) < 250.0 and approxEqual(f64, particle.charge, -1.0, 0.02)) return .WBosonMinus;
            if (@abs(particle.mass - sm.z_boson_mass_mev) < 8.0 and approxEqual(f64, particle.charge, 0.0, 0.001)) return .ZBoson;
        }

        if (@abs(particle.mass - sm.charged_pion_mass_mev) < 1.0 and particle.spin == 0.0) {
            if (approxEqual(f64, particle.charge, -1.0, 0.02)) return .PionMinus;
            if (approxEqual(f64, particle.charge, 1.0, 0.02)) return .PionPlus;
        }

        if (@abs(particle.mass - sm.electron_mass_mev) < 1e-3) {
            if (approxEqual(f64, particle.charge, -1.0, 0.01) and particle.spin == 0.5) return .Electron;
            if (approxEqual(f64, particle.charge, 1.0, 0.01) and particle.spin == -0.5) return .Positron;
        }

        if (@abs(particle.mass - sm.muon_mass_mev) < 0.05) {
            if (approxEqual(f64, particle.charge, -1.0, 0.01) and particle.spin == 0.5) return .Muon;
            if (approxEqual(f64, particle.charge, 1.0, 0.01) and particle.spin == -0.5) return .AntiMuon;
        }

        if (@abs(particle.mass - sm.tau_mass_mev) < 0.5) {
            if (approxEqual(f64, particle.charge, -1.0, 0.01) and particle.spin == 0.5) return .Tau;
            if (approxEqual(f64, particle.charge, 1.0, 0.01) and particle.spin == -0.5) return .AntiTau;
        }

        if (particle.mass < 1.0 and approxEqual(f64, particle.charge, 0.0, 0.001)) {
            if (particle.spin == 0.5) {
                if (particle.L_e > 0) return .ElectronNeutrino;
                if (particle.L_mu > 0) return .MuonNeutrino;
                if (particle.L_tau > 0) return .TauNeutrino;
            }
            if (particle.spin == -0.5) {
                if (particle.L_e < 0) return .ElectronAntiNeutrino;
                if (particle.L_mu < 0) return .MuonAntiNeutrino;
                if (particle.L_tau < 0) return .TauAntiNeutrino;
            }
        }

        return .Unknown;
    }

    pub fn decayWithRnd(self: Type, parent: Particle, rnd: std.Random) ?[3]?Particle {
        switch (self) {
            .Muon => {
                const q = parent.cmBudget();
                if (q < sm.electron_mass_mev) return null;
                const kin = q - sm.electron_mass_mev;
                return .{
                    lep(-1, sm.electron_mass_mev, kin * 0.35, 0.5, 1, 0, 0),
                    nu_e(kin * 0.325, -0.5, -1, 0, 0),
                    nu_e(kin * 0.325, 0.5, 0, 1, 0),
                };
            },
            .AntiMuon => {
                const q = parent.cmBudget();
                if (q < sm.electron_mass_mev) return null;
                const kin = q - sm.electron_mass_mev;
                return .{
                    lep(1, sm.electron_mass_mev, kin * 0.35, -0.5, -1, 0, 0),
                    nu_e(kin * 0.325, 0.5, 1, 0, 0),
                    nu_e(kin * 0.325, -0.5, 0, -1, 0),
                };
            },
            .Tau => {
                const q = parent.cmBudget();
                if (q < sm.electron_mass_mev) return null;
                const kin = q - sm.tau_mass_mev;
                const r = rnd.float(f64);
                if (r < sm.bf_tau_to_e_nu_nu) {
                    return .{
                        lep(-1, sm.electron_mass_mev, kin * 0.35, 0.5, 1, 0, 0),
                        nu_e(kin * 0.325, -0.5, -1, 0, 0),
                        nu_e(kin * 0.325, 0.5, 0, 0, 1),
                    };
                }
                if (r < sm.bf_tau_to_e_nu_nu + sm.bf_tau_to_mu_nu_nu) {
                    return .{
                        lep(-1, sm.muon_mass_mev, kin * 0.35, 0.5, 0, 1, 0),
                        nu_e(kin * 0.325, -0.5, 0, -1, 0),
                        nu_e(kin * 0.325, 0.5, 0, 0, 1),
                    };
                }
                return .{
                    pion(-1, sm.charged_pion_mass_mev, kin * 0.55),
                    nu_e(kin * 0.45, 0.5, 0, 0, 1),
                    null,
                };
            },
            .AntiTau => {
                const q = parent.cmBudget();
                if (q < sm.electron_mass_mev) return null;
                const kin = q - sm.tau_mass_mev;
                const r = rnd.float(f64);
                if (r < sm.bf_tau_to_e_nu_nu) {
                    return .{
                        lep(1, sm.electron_mass_mev, kin * 0.35, -0.5, -1, 0, 0),
                        nu_e(kin * 0.325, 0.5, 1, 0, 0),
                        nu_e(kin * 0.325, -0.5, 0, 0, -1),
                    };
                }
                if (r < sm.bf_tau_to_e_nu_nu + sm.bf_tau_to_mu_nu_nu) {
                    return .{
                        lep(1, sm.muon_mass_mev, kin * 0.35, -0.5, 0, -1, 0),
                        nu_e(kin * 0.325, 0.5, 0, 1, 0),
                        nu_e(kin * 0.325, -0.5, 0, 0, -1),
                    };
                }
                return .{
                    pion(1, sm.charged_pion_mass_mev, kin * 0.55),
                    nu_e(kin * 0.45, -0.5, 0, 0, -1),
                    null,
                };
            },
            .WBosonPlus => return wPlusDecay(parent, rnd),
            .WBosonMinus => return wMinusDecay(parent, rnd),
            .ZBoson => return zDecay(parent, rnd),
            .HiggsBoson => return higgsDecay(parent, rnd),
            .PionMinus => {
                const q = parent.cmBudget();
                if (q < sm.muon_mass_mev) return null;
                const kin = q - sm.muon_mass_mev;
                return .{
                    lep(-1, sm.muon_mass_mev, kin * 0.7, 0.5, 0, 1, 0),
                    nu_e(kin * 0.3, -0.5, 0, -1, 0),
                    null,
                };
            },
            .PionPlus => {
                const q = parent.cmBudget();
                if (q < sm.muon_mass_mev) return null;
                const kin = q - sm.muon_mass_mev;
                return .{
                    lep(1, sm.muon_mass_mev, kin * 0.7, -0.5, 0, -1, 0),
                    nu_e(kin * 0.3, 0.5, 0, 1, 0),
                    null,
                };
            },
            .TopQuark => {
                const q = parent.cmBudget();
                if (q < sm.w_boson_mass_mev + sm.bottom_quark_msbar_mev) return null;
                const kin = q - sm.w_boson_mass_mev - sm.bottom_quark_msbar_mev;
                return .{
                    quark(-1.0 / 3.0, sm.bottom_quark_msbar_mev, kin * 0.4),
                    bosonW(1.0, sm.w_boson_mass_mev, kin * 0.6),
                    null,
                };
            },
            .CharmQuark => {
                const q = parent.cmBudget();
                if (q < sm.w_boson_mass_mev + sm.strange_quark_msbar_mev) return null;
                const kin = q - sm.w_boson_mass_mev - sm.strange_quark_msbar_mev;
                return .{
                    quark(-1.0 / 3.0, sm.strange_quark_msbar_mev, kin * 0.45),
                    bosonW(1.0, sm.w_boson_mass_mev, kin * 0.55),
                    null,
                };
            },
            .StrangeQuark => {
                const q = parent.cmBudget();
                if (q < sm.w_boson_mass_mev + sm.up_quark_msbar_mev) return null;
                const kin = q - sm.w_boson_mass_mev - sm.up_quark_msbar_mev;
                return .{
                    quark(2.0 / 3.0, sm.up_quark_msbar_mev, kin * 0.45),
                    bosonW(-1.0, sm.w_boson_mass_mev, kin * 0.55),
                    null,
                };
            },
            .BottomQuark => {
                const q = parent.cmBudget();
                if (q < sm.w_boson_mass_mev + sm.charm_quark_msbar_mev) return null;
                const kin = q - sm.w_boson_mass_mev - sm.charm_quark_msbar_mev;
                return .{
                    quark(2.0 / 3.0, sm.charm_quark_msbar_mev, kin * 0.45),
                    bosonW(-1.0, sm.w_boson_mass_mev, kin * 0.55),
                    null,
                };
            },
            .AntiCharmQuark => {
                const q = parent.cmBudget();
                if (q < sm.w_boson_mass_mev + sm.strange_quark_msbar_mev) return null;
                const kin = q - sm.w_boson_mass_mev - sm.strange_quark_msbar_mev;
                return .{
                    antiquark(1.0 / 3.0, sm.strange_quark_msbar_mev, kin * 0.45),
                    bosonW(-1.0, sm.w_boson_mass_mev, kin * 0.55),
                    null,
                };
            },
            .AntiStrangeQuark => {
                const q = parent.cmBudget();
                if (q < sm.w_boson_mass_mev + sm.up_quark_msbar_mev) return null;
                const kin = q - sm.w_boson_mass_mev - sm.up_quark_msbar_mev;
                return .{
                    antiquark(-2.0 / 3.0, sm.up_quark_msbar_mev, kin * 0.45),
                    bosonW(1.0, sm.w_boson_mass_mev, kin * 0.55),
                    null,
                };
            },
            .AntiBottomQuark => {
                const q = parent.cmBudget();
                if (q < sm.w_boson_mass_mev + sm.charm_quark_msbar_mev) return null;
                const kin = q - sm.w_boson_mass_mev - sm.charm_quark_msbar_mev;
                return .{
                    antiquark(-2.0 / 3.0, sm.charm_quark_msbar_mev, kin * 0.45),
                    bosonW(1.0, sm.w_boson_mass_mev, kin * 0.55),
                    null,
                };
            },
            else => return null,
        }
    }
};

fn lep(charge: f64, mass: f64, energy: f64, spin: f64, Le: i8, Lmu: i8, Ltau: i8) ?Particle {
    return .{ .has_color = false, .charge = charge, .mass = mass, .energy = energy, .spin = spin, .b3 = 0, .L_e = Le, .L_mu = Lmu, .L_tau = Ltau };
}

fn nu_e(energy: f64, spin: f64, Le: i8, Lmu: i8, Ltau: i8) ?Particle {
    return .{ .has_color = false, .charge = 0, .mass = 0, .energy = energy, .spin = spin, .b3 = 0, .L_e = Le, .L_mu = Lmu, .L_tau = Ltau };
}

fn pion(charge: f64, mass: f64, energy: f64) ?Particle {
    return .{ .has_color = false, .charge = charge, .mass = mass, .energy = energy, .spin = 0, .b3 = 0, .L_e = 0, .L_mu = 0, .L_tau = 0 };
}

fn quark(charge: f64, mass: f64, energy: f64) ?Particle {
    return .{ .has_color = true, .charge = charge, .mass = mass, .energy = energy, .spin = 0.5, .b3 = 1, .L_e = 0, .L_mu = 0, .L_tau = 0 };
}

fn antiquark(charge: f64, mass: f64, energy: f64) ?Particle {
    return .{ .has_color = true, .charge = charge, .mass = mass, .energy = energy, .spin = -0.5, .b3 = -1, .L_e = 0, .L_mu = 0, .L_tau = 0 };
}

fn bosonW(charge: f64, mass: f64, energy: f64) ?Particle {
    return .{ .has_color = false, .charge = charge, .mass = mass, .energy = energy, .spin = 1.0, .b3 = 0, .L_e = 0, .L_mu = 0, .L_tau = 0 };
}

fn wPlusDecay(parent: Particle, rnd: std.Random) ?[3]?Particle {
    const r = rnd.float(f64);
    const q = parent.cmBudget();
    var acc: f64 = 0;
    acc += sm.bf_w_to_e_nu;
    if (r < acc) {
        const kin = q - sm.electron_mass_mev;
        return .{
            lep(1, sm.electron_mass_mev, kin * 0.55, -0.5, -1, 0, 0),
            nu_e(kin * 0.45, 0.5, 1, 0, 0),
            null,
        };
    }
    acc += sm.bf_w_to_mu_nu;
    if (r < acc) {
        const kin = q - sm.muon_mass_mev;
        return .{
            lep(1, sm.muon_mass_mev, kin * 0.55, -0.5, 0, -1, 0),
            nu_e(kin * 0.45, 0.5, 0, 1, 0),
            null,
        };
    }
    acc += sm.bf_w_to_tau_nu;
    if (r < acc) {
        const kin = q - sm.tau_mass_mev;
        return .{
            lep(1, sm.tau_mass_mev, kin * 0.55, -0.5, 0, 0, -1),
            nu_e(kin * 0.45, 0.5, 0, 0, 1),
            null,
        };
    }
    const kin = q - sm.down_quark_msbar_mev - sm.up_quark_msbar_mev;
    return .{
        antiquark(1.0 / 3.0, sm.down_quark_msbar_mev, kin * 0.45),
        quark(2.0 / 3.0, sm.up_quark_msbar_mev, kin * 0.55),
        null,
    };
}

fn wMinusDecay(parent: Particle, rnd: std.Random) ?[3]?Particle {
    const r = rnd.float(f64);
    const q = parent.cmBudget();
    var acc: f64 = 0;
    acc += sm.bf_w_to_e_nu;
    if (r < acc) {
        const kin = q - sm.electron_mass_mev;
        return .{
            lep(-1, sm.electron_mass_mev, kin * 0.55, 0.5, 1, 0, 0),
            nu_e(kin * 0.45, -0.5, -1, 0, 0),
            null,
        };
    }
    acc += sm.bf_w_to_mu_nu;
    if (r < acc) {
        const kin = q - sm.muon_mass_mev;
        return .{
            lep(-1, sm.muon_mass_mev, kin * 0.55, 0.5, 0, 1, 0),
            nu_e(kin * 0.45, -0.5, 0, -1, 0),
            null,
        };
    }
    acc += sm.bf_w_to_tau_nu;
    if (r < acc) {
        const kin = q - sm.tau_mass_mev;
        return .{
            lep(-1, sm.tau_mass_mev, kin * 0.55, 0.5, 0, 0, 1),
            nu_e(kin * 0.45, -0.5, 0, 0, -1),
            null,
        };
    }
    const kin = q - sm.down_quark_msbar_mev - sm.up_quark_msbar_mev;
    return .{
        quark(-1.0 / 3.0, sm.down_quark_msbar_mev, kin * 0.45),
        antiquark(-2.0 / 3.0, sm.up_quark_msbar_mev, kin * 0.55),
        null,
    };
}

fn zDecay(parent: Particle, rnd: std.Random) ?[3]?Particle {
    const r = rnd.float(f64);
    const q = parent.cmBudget();
    var acc: f64 = 0;
    acc += sm.bf_z_invisible;
    if (r < acc) {
        // Z has zero lepton numbers; use a matched nu / anti-nu pair (same flavor) so L_e, L_mu, L_tau each stay 0.
        return .{
            nu_e(q * 0.5, 0.5, 1, 0, 0),
            nu_e(q * 0.5, -0.5, -1, 0, 0),
            null,
        };
    }
    acc += sm.bf_z_ee;
    if (r < acc) {
        const kin = q - 2 * sm.electron_mass_mev;
        return .{
            lep(-1, sm.electron_mass_mev, kin * 0.5, 0.5, 1, 0, 0),
            lep(1, sm.electron_mass_mev, kin * 0.5, -0.5, -1, 0, 0),
            null,
        };
    }
    acc += sm.bf_z_mumu;
    if (r < acc) {
        const kin = q - 2 * sm.muon_mass_mev;
        return .{
            lep(-1, sm.muon_mass_mev, kin * 0.5, 0.5, 0, 1, 0),
            lep(1, sm.muon_mass_mev, kin * 0.5, -0.5, 0, -1, 0),
            null,
        };
    }
    acc += sm.bf_z_tautau;
    if (r < acc) {
        const kin = q - 2 * sm.tau_mass_mev;
        return .{
            lep(-1, sm.tau_mass_mev, kin * 0.5, 0.5, 0, 0, 1),
            lep(1, sm.tau_mass_mev, kin * 0.5, -0.5, 0, 0, -1),
            null,
        };
    }
    acc += sm.bf_z_hadronic_proxy;
    if (r < acc) {
        const kin = q - 2 * sm.charged_pion_mass_mev;
        return .{
            pion(-1, sm.charged_pion_mass_mev, kin * 0.5),
            pion(1, sm.charged_pion_mass_mev, kin * 0.5),
            null,
        };
    }
    return null;
}

fn higgsDecay(parent: Particle, rnd: std.Random) ?[3]?Particle {
    const r = rnd.float(f64);
    const q = parent.cmBudget();
    var acc: f64 = 0;
    acc += sm.bf_higgs_bb;
    if (r < acc) {
        const kin = q - 2 * sm.bottom_quark_msbar_mev;
        return .{
            quark(-1.0 / 3.0, sm.bottom_quark_msbar_mev, kin * 0.5),
            antiquark(1.0 / 3.0, sm.bottom_quark_msbar_mev, kin * 0.5),
            null,
        };
    }
    acc += sm.bf_higgs_ww;
    if (r < acc) {
        const kin = q - 2 * sm.w_boson_mass_mev;
        return .{
            bosonW(1.0, sm.w_boson_mass_mev, kin * 0.5),
            bosonW(-1.0, sm.w_boson_mass_mev, kin * 0.5),
            null,
        };
    }
    acc += sm.bf_higgs_gg;
    if (r < acc) {
        const kin = q;
        return .{
            .{ .has_color = true, .charge = 0, .mass = 0, .energy = kin * 0.5, .spin = 1, .b3 = 0, .L_e = 0, .L_mu = 0, .L_tau = 0 },
            .{ .has_color = true, .charge = 0, .mass = 0, .energy = kin * 0.5, .spin = -1, .b3 = 0, .L_e = 0, .L_mu = 0, .L_tau = 0 },
            null,
        };
    }
    acc += sm.bf_higgs_tautau;
    if (r < acc) {
        const kin = q - 2 * sm.tau_mass_mev;
        return .{
            lep(-1, sm.tau_mass_mev, kin * 0.5, 0.5, 0, 0, 1),
            lep(1, sm.tau_mass_mev, kin * 0.5, -0.5, 0, 0, -1),
            null,
        };
    }
    acc += sm.bf_higgs_zz;
    if (r < acc) {
        const kin = q - 2 * sm.z_boson_mass_mev;
        return .{
            .{ .has_color = false, .charge = 0, .mass = sm.z_boson_mass_mev, .energy = kin * 0.5, .spin = 1, .b3 = 0, .L_e = 0, .L_mu = 0, .L_tau = 0 },
            .{ .has_color = false, .charge = 0, .mass = sm.z_boson_mass_mev, .energy = kin * 0.5, .spin = 1, .b3 = 0, .L_e = 0, .L_mu = 0, .L_tau = 0 },
            null,
        };
    }
    const kin = q;
    return .{
        .{ .has_color = false, .charge = 0, .mass = 0, .energy = kin * 0.5, .spin = 1, .b3 = 0, .L_e = 0, .L_mu = 0, .L_tau = 0 },
        .{ .has_color = false, .charge = 0, .mass = 0, .energy = kin * 0.5, .spin = -1, .b3 = 0, .L_e = 0, .L_mu = 0, .L_tau = 0 },
        null,
    };
}

/// Phenomenological SM-inspired rules on a graph: not covariant QFT; uses PDG masses and tree-level decay topology.
/// Order: Compton-like steps, annihilation and pair-production before bremsstrahlung, then decays.
pub fn interact(self: *Particle, other: *Particle, emission_buffer: *std.ArrayList(Particle), allocator: std.mem.Allocator) !struct { bool, bool } {
    const ta = Type.fromStruct(self);
    const tb = Type.fromStruct(other);
    const mask = pair_interaction_matrix[@intFromEnum(ta)][@intFromEnum(tb)];

    if (mask.compton and try handleCompton(self, other, emission_buffer, allocator)) {
        return .{ false, false };
    }
    if (mask.chromo_compton and try handleChromoCompton(self, other, emission_buffer, allocator)) {
        return .{ false, false };
    }
    if (mask.neutrino_lepton_nc and try handleNeutrinoLeptonNC(self, other, emission_buffer, allocator)) {
        return .{ false, false };
    }
    if (mask.quark_antiquark_annihilation and try handleQuarkAntiquarkAnnihilation(self, other, emission_buffer, allocator)) {
        return .{ true, true };
    }
    if (mask.dirac_annihilation and try handleAnnihilation(self, other, emission_buffer, allocator)) {
        return .{ true, true };
    }
    if (mask.pair_production and try handlePairProduction(self, other, emission_buffer, allocator)) {
        return .{ true, true };
    }
    if (mask.gluon_fusion and try handleGluonFusion(self, other, emission_buffer, allocator)) {
        return .{ true, true };
    }
    if (mask.bremsstrahlung and try handleScattering(self, other, emission_buffer, allocator)) {
        return .{ false, false };
    }

    var consumed: struct { bool, bool } = .{ false, false };
    consumed[0] = try handleDecay(self, emission_buffer, allocator);
    consumed[1] = try handleDecay(other, emission_buffer, allocator);
    return consumed;
}

const PairInteractionMask = packed struct(u8) {
    compton: bool = false,
    chromo_compton: bool = false,
    neutrino_lepton_nc: bool = false,
    quark_antiquark_annihilation: bool = false,
    dirac_annihilation: bool = false,
    pair_production: bool = false,
    gluon_fusion: bool = false,
    bremsstrahlung: bool = false,
};

fn isNeutrinoType(t: Type) bool {
    return switch (t) {
        .ElectronNeutrino,
        .ElectronAntiNeutrino,
        .MuonNeutrino,
        .MuonAntiNeutrino,
        .TauNeutrino,
        .TauAntiNeutrino,
        => true,
        else => false,
    };
}

fn isChargedLeptonType(t: Type) bool {
    return switch (t) {
        .Electron, .Positron, .Muon, .AntiMuon, .Tau, .AntiTau => true,
        else => false,
    };
}

fn isQuarkType(t: Type) bool {
    return switch (t) {
        .UpQuark,
        .DownQuark,
        .CharmQuark,
        .StrangeQuark,
        .TopQuark,
        .BottomQuark,
        .AntiUpQuark,
        .AntiDownQuark,
        .AntiCharmQuark,
        .AntiStrangeQuark,
        .AntiBottomQuark,
        => true,
        else => false,
    };
}

fn buildPairInteractionMask(ta: Type, tb: Type) PairInteractionMask {
    var m: PairInteractionMask = .{};
    const photon_pair = ta == .Photon and tb == .Photon;
    const one_photon = (ta == .Photon) != (tb == .Photon);
    const one_gluon = (ta == .Gluon) != (tb == .Gluon);
    const neutrino_lepton_pair =
        (isNeutrinoType(ta) and isChargedLeptonType(tb)) or
        (isNeutrinoType(tb) and isChargedLeptonType(ta));
    const quark_pair = isQuarkType(ta) and isQuarkType(tb);
    const both_gluon = ta == .Gluon and tb == .Gluon;

    if (one_photon) m.compton = true;
    if (one_gluon) m.chromo_compton = true;
    if (neutrino_lepton_pair) m.neutrino_lepton_nc = true;
    if (quark_pair) m.quark_antiquark_annihilation = true;
    if (!photon_pair and !both_gluon) m.dirac_annihilation = true;
    if (photon_pair) m.pair_production = true;
    if (both_gluon) m.gluon_fusion = true;
    m.bremsstrahlung = true;
    return m;
}

fn buildPairInteractionMatrix() [std.meta.fields(Type).len][std.meta.fields(Type).len]PairInteractionMask {
    const count = std.meta.fields(Type).len;
    @setEvalBranchQuota(20_000);
    comptime var matrix: [count][count]PairInteractionMask = undefined;
    inline for (0..count) |ia| {
        const ta: Type = @enumFromInt(ia);
        inline for (0..count) |ib| {
            const tb: Type = @enumFromInt(ib);
            matrix[ia][ib] = buildPairInteractionMask(ta, tb);
        }
    }
    return matrix;
}

const pair_interaction_matrix = buildPairInteractionMatrix();

fn handleCompton(a: *Particle, b: *Particle, emitted: *std.ArrayList(Particle), allocator: std.mem.Allocator) !bool {
    _ = emitted;
    _ = allocator;
    const ta = Type.fromStruct(a);
    const tb = Type.fromStruct(b);
    const phot_a = ta == .Photon;
    const phot_b = tb == .Photon;
    if (phot_a == phot_b) return false;
    const charged = if (phot_a) b else a;
    const gam = if (phot_a) a else b;
    if (Type.fromStruct(charged) == .Unknown or gam.charge != 0) return false;
    if (charged.charge == 0) return false;
    if (charged.cmBudget() + gam.cmBudget() < sm.min_scatter_energy_mev) return false;
    const x = sm.soft_radiation_fraction;
    const de = gam.energy * x;
    charged.energy += de;
    gam.energy = @max(0.0, gam.energy - de);
    return true;
}

fn handleChromoCompton(a: *Particle, b: *Particle, emitted: *std.ArrayList(Particle), allocator: std.mem.Allocator) !bool {
    _ = emitted;
    _ = allocator;
    const ta = Type.fromStruct(a);
    const tb = Type.fromStruct(b);
    const glu_a = ta == .Gluon;
    const glu_b = tb == .Gluon;
    if (glu_a == glu_b) return false;
    const part = if (glu_a) b else a;
    const glu = if (glu_a) a else b;
    if (!part.has_color or Type.fromStruct(part) == .Gluon) return false;
    if (part.cmBudget() + glu.cmBudget() < sm.min_scatter_energy_mev) return false;
    const de = glu.energy * sm.soft_radiation_fraction;
    part.energy += de;
    glu.energy = @max(0.0, glu.energy - de);
    return true;
}

fn handleNeutrinoLeptonNC(a: *Particle, b: *Particle, emitted: *std.ArrayList(Particle), allocator: std.mem.Allocator) !bool {
    _ = emitted;
    _ = allocator;
    if (!isNeutrinoLeptonNCpair(a, b)) return false;
    if (a.cmBudget() + b.cmBudget() < sm.min_scatter_energy_mev) return false;
    const nupart: *Particle = if (a.charge == 0) a else b;
    const leppart: *Particle = if (a.charge == 0) b else a;
    const de = leppart.energy * sm.soft_radiation_fraction;
    if (de < 1e-12) return false;
    nupart.energy += de;
    leppart.energy = @max(0.0, leppart.energy - de);
    return true;
}

fn isNeutrinoLeptonNCpair(a: *const Particle, b: *const Particle) bool {
    if (a.charge == 0 and b.charge == 0) return false;
    if (a.charge != 0 and b.charge != 0) return false;
    const nupart = if (a.charge == 0) a else b;
    const leppart = if (a.charge == 0) b else a;
    if (nupart.mass > 1.0) return false;
    if (nupart.L_e != 0 and leppart.L_e == nupart.L_e) return true;
    if (nupart.L_mu != 0 and leppart.L_mu == nupart.L_mu) return true;
    if (nupart.L_tau != 0 and leppart.L_tau == nupart.L_tau) return true;
    return false;
}

fn handleAnnihilation(a: *Particle, b: *Particle, emitted: *std.ArrayList(Particle), allocator: std.mem.Allocator) !bool {
    if (!isDiracPair(a, b)) return false;
    if (a.has_color or b.has_color) return false;
    const q = a.cmBudget() + b.cmBudget();
    if (q <= 0) return false;
    const photon_e = q / 2.0;
    const arr = try emitted.addManyAsArray(allocator, 2);
    arr[0] = .{ .has_color = false, .charge = 0, .mass = 0, .energy = photon_e, .spin = 1.0, .b3 = 0, .L_e = 0, .L_mu = 0, .L_tau = 0 };
    arr[1] = .{ .has_color = false, .charge = 0, .mass = 0, .energy = photon_e, .spin = -1.0, .b3 = 0, .L_e = 0, .L_mu = 0, .L_tau = 0 };
    return true;
}

fn isDiracPair(a: *const Particle, b: *const Particle) bool {
    if (a.mass < 1e-9 and b.mass < 1e-9 and a.charge == 0 and b.charge == 0) return false;
    if (!approxEqual(f64, a.charge, -b.charge, 1e-6)) return false;
    if (!approxEqual(f64, a.mass, b.mass, 1e-6 * @max(a.mass, 1.0))) return false;
    if (!approxEqual(f64, a.spin, -b.spin, 1e-6)) return false;
    if (a.b3 != -b.b3) return false;
    if (a.L_e != -b.L_e) return false;
    if (a.L_mu != -b.L_mu) return false;
    if (a.L_tau != -b.L_tau) return false;
    return a.mass > 0.0 or (a.L_e + a.L_mu + a.L_tau) != 0;
}

fn handleDecay(p: *Particle, emitted: *std.ArrayList(Particle), allocator: std.mem.Allocator) !bool {
    const particle_type: Type = .fromStruct(p);
    const decay = particle_type.decayWithRnd(p.*, random) orelse return false;

    if (decay[2] != null) {
        const arr = try emitted.addManyAsArray(allocator, 3);
        arr[0] = decay[0].?;
        arr[1] = decay[1].?;
        arr[2] = decay[2].?;
    } else if (decay[1] != null) {
        const arr = try emitted.addManyAsArray(allocator, 2);
        arr[0] = decay[0].?;
        arr[1] = decay[1].?;
    } else {
        const arr = try emitted.addManyAsArray(allocator, 1);
        arr[0] = decay[0].?;
    }
    return true;
}

fn handleScattering(a: *Particle, b: *Particle, emitted: *std.ArrayList(Particle), allocator: std.mem.Allocator) !bool {
    if (a.cmBudget() + b.cmBudget() < sm.min_scatter_energy_mev) return false;
    const emission_energy = (a.energy + b.energy) * sm.soft_radiation_fraction;
    if (emission_energy < 1e-6) return false;

    if (a.has_color and b.has_color) {
        try emitted.append(allocator, .{ .has_color = true, .charge = 0, .mass = 0, .energy = emission_energy, .spin = 1.0, .b3 = 0, .L_e = 0, .L_mu = 0, .L_tau = 0 });
    } else if (a.charge != 0.0 or b.charge != 0.0) {
        try emitted.append(allocator, .{ .has_color = false, .charge = 0, .mass = 0, .energy = emission_energy, .spin = 1.0, .b3 = 0, .L_e = 0, .L_mu = 0, .L_tau = 0 });
    } else return false;

    const half = emission_energy / 2.0;
    a.energy = @max(0.0, a.energy - half);
    b.energy = @max(0.0, b.energy - half);
    return true;
}

fn isQuarkAntiquarkAnnihilationPair(a: *const Particle, b: *const Particle) bool {
    if (!a.has_color or !b.has_color) return false;
    if (a.b3 + b.b3 != 0) return false;
    if (a.b3 == 0) return false;
    if (!approxEqual(f64, a.charge, -b.charge, 0.02)) return false;
    const tol = @max(80.0, 0.05 * @max(a.mass, b.mass));
    if (!approxEqual(f64, a.mass, b.mass, tol)) return false;
    if (!approxEqual(f64, a.spin, -b.spin, 0.02)) return false;
    return true;
}

fn handleQuarkAntiquarkAnnihilation(a: *Particle, b: *Particle, emitted: *std.ArrayList(Particle), allocator: std.mem.Allocator) !bool {
    if (!isQuarkAntiquarkAnnihilationPair(a, b)) return false;
    const q = a.cmBudget() + b.cmBudget();
    if (q <= 0) return false;
    const eg = q / 2.0;
    const arr = try emitted.addManyAsArray(allocator, 2);
    arr[0] = .{ .has_color = true, .charge = 0, .mass = 0, .energy = eg, .spin = 1.0, .b3 = 0, .L_e = 0, .L_mu = 0, .L_tau = 0 };
    arr[1] = .{ .has_color = true, .charge = 0, .mass = 0, .energy = eg, .spin = -1.0, .b3 = 0, .L_e = 0, .L_mu = 0, .L_tau = 0 };
    return true;
}

fn handlePairProduction(a: *Particle, b: *Particle, emitted: *std.ArrayList(Particle), allocator: std.mem.Allocator) !bool {
    if (Type.fromStruct(a) != .Photon or Type.fromStruct(b) != .Photon) return false;
    const total = a.cmBudget() + b.cmBudget();

    if (total >= 2.0 * sm.tau_mass_mev) {
        const arr = try emitted.addManyAsArray(allocator, 2);
        const e_each = total / 2.0;
        arr[0] = .{ .has_color = false, .charge = -1.0, .mass = sm.tau_mass_mev, .energy = e_each - sm.tau_mass_mev, .spin = 0.5, .b3 = 0, .L_e = 0, .L_mu = 0, .L_tau = 1 };
        arr[1] = .{ .has_color = false, .charge = 1.0, .mass = sm.tau_mass_mev, .energy = e_each - sm.tau_mass_mev, .spin = -0.5, .b3 = 0, .L_e = 0, .L_mu = 0, .L_tau = -1 };
        return true;
    }
    if (total >= 2.0 * sm.muon_mass_mev) {
        const arr = try emitted.addManyAsArray(allocator, 2);
        const e_each = total / 2.0;
        arr[0] = .{ .has_color = false, .charge = -1.0, .mass = sm.muon_mass_mev, .energy = e_each - sm.muon_mass_mev, .spin = 0.5, .b3 = 0, .L_e = 0, .L_mu = 1, .L_tau = 0 };
        arr[1] = .{ .has_color = false, .charge = 1.0, .mass = sm.muon_mass_mev, .energy = e_each - sm.muon_mass_mev, .spin = -0.5, .b3 = 0, .L_e = 0, .L_mu = -1, .L_tau = 0 };
        return true;
    }
    if (total >= 2.0 * sm.electron_mass_mev) {
        const arr = try emitted.addManyAsArray(allocator, 2);
        const e_each = total / 2.0;
        arr[0] = .{ .has_color = false, .charge = -1.0, .mass = sm.electron_mass_mev, .energy = e_each - sm.electron_mass_mev, .spin = 0.5, .b3 = 0, .L_e = 1, .L_mu = 0, .L_tau = 0 };
        arr[1] = .{ .has_color = false, .charge = 1.0, .mass = sm.electron_mass_mev, .energy = e_each - sm.electron_mass_mev, .spin = -0.5, .b3 = 0, .L_e = -1, .L_mu = 0, .L_tau = 0 };
        return true;
    }
    return false;
}

fn handleGluonFusion(a: *Particle, b: *Particle, emitted: *std.ArrayList(Particle), allocator: std.mem.Allocator) !bool {
    if (Type.fromStruct(a) != .Gluon or Type.fromStruct(b) != .Gluon) return false;
    const s = a.cmBudget() + b.cmBudget();
    if (s < sm.higgs_mass_mev * 0.98) return false;
    const kin = s - sm.higgs_mass_mev;
    try emitted.append(allocator, .{
        .has_color = false,
        .charge = 0,
        .mass = sm.higgs_mass_mev,
        .energy = @max(0.0, kin),
        .spin = 0,
        .b3 = 0,
        .L_e = 0,
        .L_mu = 0,
        .L_tau = 0,
    });
    return true;
}

fn nextUsize(curr: u64) u64 {
    return curr + 1;
}

fn lessThan(a: u64, b: u64) std.math.Order {
    return std.math.order(a, b);
}

/// Hooks for `RelationalLayout` (spring rest length and strength vs local degree).
pub const layout_hooks: uSim.RelationalLayout.LayoutHooks = .{
    .length_chain = &.{
        uSim.RelationalLayout.hooks.length_identity,
        uSim.RelationalLayout.hooks.length_shorten_with_degree,
    },
    .strength_chain = &.{
        uSim.RelationalLayout.hooks.strength_identity,
        uSim.RelationalLayout.hooks.strength_boost_with_degree,
    },
};

pub const Graph = uSim.Graph(u64, Particle, nextUsize, lessThan);

pub const EdgeField = enum {
    none,
    electromagnetic,
    weak,
    strong,
    mixed,
};

fn isWeakBosonType(t: Type) bool {
    return switch (t) {
        .WBosonPlus, .WBosonMinus, .ZBoson => true,
        else => false,
    };
}

/// First pass at "fields on edges": infer coupling domain from endpoint particles.
pub fn inferEdgeField(a: *const Particle, b: *const Particle) EdgeField {
    const ta = Type.fromStruct(a);
    const tb = Type.fromStruct(b);
    const strong = a.has_color and b.has_color;
    const em = (a.charge != 0 or b.charge != 0) and !strong;
    const weak = isNeutrinoType(ta) or isNeutrinoType(tb) or isWeakBosonType(ta) or isWeakBosonType(tb);

    if (strong and weak) return .mixed;
    if (strong) return .strong;
    if (em and weak) return .mixed;
    if (em) return .electromagnetic;
    if (weak) return .weak;
    return .none;
}

pub fn edgeFieldForGraph(graph: *Graph, from: u64, to: u64) ?EdgeField {
    if (!graph.hasAdjEdge(from, to)) return null;
    const a = graph.getVertex(from) orelse return null;
    const b = graph.getVertex(to) orelse return null;
    return inferEdgeField(&a.data, &b.data);
}

/// Hadron cluster classification / partition (`clusters/hadron/`); viz registry is in `vlib`.
pub const clusters = @import("clusters/hadron/main.zig");

pub fn cloneGraph(g: *const Graph, allocator: std.mem.Allocator) !Graph {
    return uSim.cloneAutoIdGraph(u64, Particle, nextUsize, lessThan, g, allocator);
}

pub fn initializeGraph(allocator: std.mem.Allocator, particle_count: comptime_int) !Graph {
    var graph: Graph = .init(allocator, 0);
    for (0..particle_count) |_| {
        const kind: Type = while (true) {
            const k = random.enumValue(Type);
            if (k != .Unknown) break k;
        };
        var particle = kind.toParticle();
        particle.energy = random.float(f64) * 1000.0;
        _ = try graph.putVertexAuto(particle);
    }

    // Cap total directed degree (out + in) per vertex on the initial graph so wiring looks more like
    // propagator chains (Feynman-style leg count). Only this model's `initializeGraph` uses this rule.
    const initial_vertex_max_incident: usize = 2;
    if (graph.vertices.count() >= 2) {
        const n: u64 = @intCast(graph.vertices.count());
        var attempt: u32 = 0;
        const max_attempts: u32 = @intCast(@min(50_000, n * n * 8));
        while (attempt < max_attempts) : (attempt += 1) {
            const from = random.intRangeLessThan(u64, 0, n);
            const to = random.intRangeLessThan(u64, 0, n);
            if (to == from) continue;
            const nf = graph.getVertex(from) orelse continue;
            const nt = graph.getVertex(to) orelse continue;
            const deg_f = nf.adjacency_set.count() + nf.incidency_set.count();
            const deg_t = nt.adjacency_set.count() + nt.incidency_set.count();
            if (deg_f >= initial_vertex_max_incident or deg_t >= initial_vertex_max_incident) continue;
            try graph.addEdge(from, to);
        }
    }

    return graph;
}

/// Multi-line summary for a single vertex (UI / debug).
/// Graph is directed: `edges_out` / `edges_in` are adjacency and incidency counts (same convention as `Graph.addEdge`).
pub fn formatInspector(allocator: std.mem.Allocator, self: Particle, key: u64, edges_out: usize, edges_in: usize) ![]u8 {
    const ty = Type.fromStruct(&self);
    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer aw.deinit();
    var writer = &aw.writer;
    try writer.print("vertex key: {d}\n", .{key});
    try writer.print("type: {s}\n", .{@tagName(ty)});
    try writer.print("charge: {d:.4} e\n", .{self.charge});
    try writer.print("mass: {d:.4} MeV/c^2\n", .{self.mass});
    try writer.print("energy: {d:.4} MeV\n", .{self.energy});
    try writer.print("spin: {d:.2}\n", .{self.spin});
    try writer.print("b3 (baryon*3): {d}\n", .{self.b3});
    try writer.print("Le Lmu Ltau: {d} {d} {d}\n", .{ self.L_e, self.L_mu, self.L_tau });
    try writer.print("has_color: {}\n", .{self.has_color});
    try writer.print("edges out: {d}\nedges in: {d}\n", .{ edges_out, edges_in });
    if (edges_out + edges_in == 0)
        try writer.print("(no graph links; common after parents were removed)\n", .{});
    try writer.print("cm budget: {d:.4} MeV\n", .{self.cmBudget()});
    return try aw.toOwnedSlice();
}

pub fn formatEdgeInspector(allocator: std.mem.Allocator, graph: *Graph, from: u64, to: u64) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer aw.deinit();
    const w = &aw.writer;

    try w.print("edge: {d} -> {d}\n", .{ from, to });
    const a = graph.getVertex(from) orelse {
        try w.print("source vertex missing\n", .{});
        return try aw.toOwnedSlice();
    };
    const b = graph.getVertex(to) orelse {
        try w.print("target vertex missing\n", .{});
        return try aw.toOwnedSlice();
    };

    const ta = Type.fromStruct(&a.data);
    const tb = Type.fromStruct(&b.data);
    const ef = inferEdgeField(&a.data, &b.data);
    try w.print("source type: {s}\n", .{@tagName(ta)});
    try w.print("target type: {s}\n", .{@tagName(tb)});
    try w.print("inferred field: {s}\n", .{@tagName(ef)});
    try w.print("source charge: {d:.4} e, target charge: {d:.4} e\n", .{ a.data.charge, b.data.charge });
    try w.print("source has_color: {}, target has_color: {}\n", .{ a.data.has_color, b.data.has_color });
    return try aw.toOwnedSlice();
}

/// Light-quark inventory and **combinatorial ceilings** for uud (proton-like) and udd (neutron-like)
/// triplets. Ignores graph connectivity and color; use as a rough guide when comparing to the view.
pub fn formatHadronStructureHint(allocator: std.mem.Allocator, graph: *Graph) ![]u8 {
    var nu: usize = 0;
    var nd: usize = 0;
    var ns: usize = 0;
    var n_anti_light: usize = 0;
    var it = graph.vertices.iterator();
    while (it.next()) |ent| {
        switch (Type.fromStruct(&ent.value_ptr.*.data)) {
            .UpQuark => nu += 1,
            .DownQuark => nd += 1,
            .StrangeQuark => ns += 1,
            .AntiUpQuark, .AntiDownQuark, .AntiStrangeQuark => n_anti_light += 1,
            else => {},
        }
    }

    const max_uud = @min(nu / 2, nd);
    const max_udd = @min(nd / 2, nu);
    const max_uds = @min(@min(nu, nd), ns);

    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer aw.deinit();
    const w = &aw.writer;
    try w.print(
        "Light quarks in graph: u={d} d={d} s={d}  (light anti-quarks: {d})\n",
        .{ nu, nd, ns, n_anti_light },
    );
    try w.print(
        "Combinatorial ceilings (ignore binding/color): proton-like uud <= {d}, neutron-like udd <= {d}, Lambda-like uds <= {d}\n",
        .{ max_uud, max_udd, max_uds },
    );
    try w.print(
        "Viz mode \"clusters\": cluster layer exports live in `Particle.clusters`; `vlib` manifest lists " ++
            "which modules register (`cluster_registry`).\n",
        .{},
    );
    return try aw.toOwnedSlice();
}

pub fn print(allocator: std.mem.Allocator, graph: *Graph) ![]u8 {
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

    const avg_edges = @as(f64, @floatFromInt(total_edges)) / @as(f64, @floatFromInt(num_vertices));

    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer aw.deinit();
    var writer = &aw.writer;
    try writer.print("Particles (vertices): {}\n", .{num_vertices});
    try writer.print("Edges: {}\n", .{total_edges});
    try writer.print("Average edges per particle: {d:.2}\n", .{avg_edges});
    try writer.print("Total Mass: {d:.3} MeV/c^2\n", .{total_mass});
    try writer.print("Total Charge: {d:.3} e\n", .{total_charge});
    try writer.print("Total kinetic (sum of .energy, not cmBudget): {d:.3} MeV\n", .{total_energy});

    inline for (@typeInfo(Type).@"enum".fields, 0..) |field, i|
        try writer.print("{s}: {any}\n", .{ field.name, counts[i] });

    return try aw.toOwnedSlice();
}

// --- tests ---
test "PDG masses round-trip fromStruct" {
    try std.testing.expectEqual(Type.UpQuark, Type.fromStruct(&Type.UpQuark.toParticle()));
    try std.testing.expectEqual(Type.Electron, Type.fromStruct(&Type.Electron.toParticle()));
    try std.testing.expectEqual(Type.Muon, Type.fromStruct(&Type.Muon.toParticle()));
    try std.testing.expectEqual(Type.WBosonPlus, Type.fromStruct(&Type.WBosonPlus.toParticle()));
    try std.testing.expectEqual(Type.ZBoson, Type.fromStruct(&Type.ZBoson.toParticle()));
    try std.testing.expectEqual(Type.HiggsBoson, Type.fromStruct(&Type.HiggsBoson.toParticle()));
    try std.testing.expectEqual(Type.PionMinus, Type.fromStruct(&Type.PionMinus.toParticle()));
}

test "two photons do not undergo bremsstrahlung without charges" {
    var g1 = Type.Photon.toParticle();
    g1.energy = 50.0;
    var g2 = Type.Photon.toParticle();
    g2.energy = 50.0;
    var buf: std.ArrayList(Particle) = .empty;
    defer buf.deinit(std.testing.allocator);
    try std.testing.expect(!try handleScattering(&g1, &g2, &buf, std.testing.allocator));
    try std.testing.expectEqual(@as(usize, 0), buf.items.len);
    try std.testing.expectApproxEqAbs(50.0, g1.energy, 1e-9);
    try std.testing.expectApproxEqAbs(50.0, g2.energy, 1e-9);
}

test "up antiup annihilation yields two gluons" {
    var u = Type.UpQuark.toParticle();
    u.energy = 5000.0;
    var au = Type.AntiUpQuark.toParticle();
    au.energy = 5000.0;
    var buf: std.ArrayList(Particle) = .empty;
    defer buf.deinit(std.testing.allocator);
    try std.testing.expect(try handleQuarkAntiquarkAnnihilation(&u, &au, &buf, std.testing.allocator));
    try std.testing.expectEqual(@as(usize, 2), buf.items.len);
    try std.testing.expect(buf.items[0].has_color and buf.items[1].has_color);
}

test "interact annihilates up antiup before bremsstrahlung" {
    var u = Type.UpQuark.toParticle();
    u.energy = 5000.0;
    var au = Type.AntiUpQuark.toParticle();
    au.energy = 5000.0;
    var buf: std.ArrayList(Particle) = .empty;
    defer buf.deinit(std.testing.allocator);
    const c = try interact(&u, &au, &buf, std.testing.allocator);
    try std.testing.expect(c[0] and c[1]);
    try std.testing.expectEqual(@as(usize, 2), buf.items.len);
}

test "quark quark bremsstrahlung emits one colored quantum" {
    var a = Type.UpQuark.toParticle();
    a.energy = 200.0;
    var b = Type.UpQuark.toParticle();
    b.energy = 200.0;
    var buf: std.ArrayList(Particle) = .empty;
    defer buf.deinit(std.testing.allocator);
    try std.testing.expect(try handleScattering(&a, &b, &buf, std.testing.allocator));
    try std.testing.expectEqual(@as(usize, 1), buf.items.len);
    try std.testing.expect(buf.items[0].has_color);
}

test "gluon fusion produces Higgs above threshold" {
    var g1 = Type.Gluon.toParticle();
    g1.energy = sm.higgs_mass_mev * 0.6;
    var g2 = Type.Gluon.toParticle();
    g2.energy = sm.higgs_mass_mev * 0.5;
    var buf: std.ArrayList(Particle) = .empty;
    defer buf.deinit(std.testing.allocator);
    try std.testing.expect(try handleGluonFusion(&g1, &g2, &buf, std.testing.allocator));
    try std.testing.expectEqual(@as(usize, 1), buf.items.len);
    try std.testing.expectEqual(Type.HiggsBoson, Type.fromStruct(&buf.items[0]));
}

test "sumGlobalQuantumNumbers electron and positron" {
    var g = Graph.init(std.testing.allocator, 0);
    defer g.deinit();
    try g.putVertex(0, Type.Electron.toParticle());
    try g.putVertex(1, Type.Positron.toParticle());
    const t = sumGlobalQuantumNumbers(&g);
    try std.testing.expectApproxEqAbs(@as(f64, 0), t.charge, 1e-9);
    try std.testing.expectEqual(@as(i64, 0), t.b3);
    try std.testing.expectEqual(@as(i64, 0), t.L_e);
}

test "neutrino electron NC transfers energy" {
    var nu_part = Type.ElectronNeutrino.toParticle();
    nu_part.energy = 1.0;
    var e = Type.Electron.toParticle();
    e.energy = 100.0;
    var buf: std.ArrayList(Particle) = .empty;
    defer buf.deinit(std.testing.allocator);
    const e0 = e.energy;
    try std.testing.expect(try handleNeutrinoLeptonNC(&nu_part, &e, &buf, std.testing.allocator));
    try std.testing.expect(nu_part.energy > 1.0);
    try std.testing.expect(e.energy < e0);
}

test "ZBoson two massless daughters conserve summed gauge quantum numbers" {
    var z = Type.ZBoson.toParticle();
    z.energy = sm.z_boson_mass_mev * 2.0;
    var massless_pairs: usize = 0;
    for (0..20_000) |s| {
        var local = std.Random.DefaultPrng.init(s);
        const daughters = Type.ZBoson.decayWithRnd(z, local.random()) orelse continue;
        const a = daughters[0] orelse continue;
        const b = daughters[1] orelse continue;
        if (daughters[2] != null) continue;
        if (a.mass != 0 or b.mass != 0) continue;
        massless_pairs += 1;
        try std.testing.expectApproxEqAbs(@as(f64, 0), a.charge + b.charge, 1e-9);
        try std.testing.expectEqual(@as(i32, 0), @as(i32, a.b3) + b.b3);
        try std.testing.expectEqual(@as(i32, 0), @as(i32, a.L_e) + b.L_e);
        try std.testing.expectEqual(@as(i32, 0), @as(i32, a.L_mu) + b.L_mu);
        try std.testing.expectEqual(@as(i32, 0), @as(i32, a.L_tau) + b.L_tau);
    }
    try std.testing.expect(massless_pairs > 500);
}

test "pair interaction matrix marks photon photon pair production" {
    const aa = pair_interaction_matrix[@intFromEnum(Type.Photon)][@intFromEnum(Type.Photon)];
    try std.testing.expect(aa.pair_production);
    try std.testing.expect(!aa.compton);
    try std.testing.expect(!aa.chromo_compton);
}

test "pair interaction matrix marks photon electron compton" {
    const pe = pair_interaction_matrix[@intFromEnum(Type.Photon)][@intFromEnum(Type.Electron)];
    const ep = pair_interaction_matrix[@intFromEnum(Type.Electron)][@intFromEnum(Type.Photon)];
    try std.testing.expect(pe.compton);
    try std.testing.expect(ep.compton);
    try std.testing.expect(pe.bremsstrahlung);
    try std.testing.expect(ep.bremsstrahlung);
}

test "pair interaction matrix marks gluon gluon fusion" {
    const gg = pair_interaction_matrix[@intFromEnum(Type.Gluon)][@intFromEnum(Type.Gluon)];
    try std.testing.expect(gg.gluon_fusion);
    try std.testing.expect(!gg.pair_production);
    try std.testing.expect(gg.bremsstrahlung);
}
