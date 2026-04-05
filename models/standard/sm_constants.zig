//! Masses in MeV/c² and dimensionless branching central values.
//! Reference: PDG RPP 2024 (https://pdg.lbl.gov/2024), summary tables and gauge-boson listings.
//! This module is data only; the simulator uses phenomenological rules, not full QFT.

pub const electron_mass_mev = 0.510998950;
pub const muon_mass_mev = 105.6583755;
pub const tau_mass_mev = 1776.86;

/// MS-bar masses at μ = 2 GeV where applicable (PDG light quarks).
pub const up_quark_msbar_mev = 2.16;
pub const down_quark_msbar_mev = 4.70;
pub const strange_quark_msbar_mev = 93.5;
/// m_c (MS-bar), order 1.27 GeV.
pub const charm_quark_msbar_mev = 1273.0;
pub const bottom_quark_msbar_mev = 4183.0;
/// Top pole mass ~172.57 GeV.
pub const top_quark_pole_mev = 172_570.0;

pub const charged_pion_mass_mev = 139.57039;

pub const w_boson_mass_mev = 80_369.2;
pub const z_boson_mass_mev = 91_187.6;
pub const higgs_mass_mev = 125_250.0;

// --- Tau (leptonic modes; PDG central order-of-magnitude fit) ---
pub const bf_tau_to_e_nu_nu = 0.1782;
pub const bf_tau_to_mu_nu_nu = 0.1741;
/// Remainder ~ hadronic and other; we route to π⁻ ν channel as effective mode.
pub const bf_tau_to_hadronic_proxy = 1.0 - bf_tau_to_e_nu_nu - bf_tau_to_mu_nu_nu;

// --- W± (lepton flavor universality; PDG sum hadronic ~67%) ---
pub const bf_w_to_e_nu = 0.1071;
pub const bf_w_to_mu_nu = 0.1063;
pub const bf_w_to_tau_nu = 0.1138;
/// Chosen so leptonic + hadronic = 1.0 with PDG-like flavor splits.
pub const bf_w_hadronic = 1.0 - bf_w_to_e_nu - bf_w_to_mu_nu - bf_w_to_tau_nu;

// --- Z⁰ (simplified partition; invisible dominated by νν̄) ---
pub const bf_z_invisible = 0.20;
pub const bf_z_ee = 0.03363;
pub const bf_z_mumu = 0.03366;
pub const bf_z_tautau = 0.03370;
/// Remainder: inclusive hadronic (PDG ~70%).
pub const bf_z_hadronic_proxy = 0.699;

// --- Higgs (dominant modes; PDG 2024 style central values, normalized) ---
pub const bf_higgs_bb = 0.5824;
pub const bf_higgs_ww = 0.2137;
pub const bf_higgs_gg = 0.0819;
pub const bf_higgs_tautau = 0.0627;
pub const bf_higgs_zz = 0.0262;
pub const bf_higgs_gammagamma = 0.00227;

/// Minimum CM budget (MeV) to allow bremsstrahlung / soft emission step.
pub const min_scatter_energy_mev = 1.0;
/// Soft-radiation fraction of pair kinetic budget (phenomenological).
pub const soft_radiation_fraction = 0.05;
