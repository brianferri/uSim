//! Flavor / exclusion rules for hadron-shaped cluster matching.

const Mdl = @import("../../main.zig");
const Type = Mdl.Type;

pub fn isQuarkFlavor(t: Type) bool {
    return switch (t) {
        .UpQuark, .DownQuark, .StrangeQuark, .CharmQuark, .BottomQuark, .TopQuark => true,
        else => false,
    };
}

pub fn isAntiquarkFlavor(t: Type) bool {
    return switch (t) {
        .AntiUpQuark, .AntiDownQuark, .AntiStrangeQuark, .AntiCharmQuark, .AntiBottomQuark => true,
        else => false,
    };
}

pub fn typeExcludedFromHadronCluster(t: Type) bool {
    return switch (t) {
        .Unknown => true,
        .Gluon, .Photon, .ZBoson, .WBosonPlus, .WBosonMinus, .HiggsBoson => true,
        .Electron, .Positron, .Muon, .AntiMuon, .Tau, .AntiTau => true,
        .ElectronNeutrino, .ElectronAntiNeutrino, .MuonNeutrino, .MuonAntiNeutrino, .TauNeutrino, .TauAntiNeutrino => true,
        else => false,
    };
}
