//! **Simulation tick semantics** (framework-level; model implements physics inside `ulib`).
//!
//! - A **stored step** in the host timeline is one graph snapshot taken **after** one application of
//!   `pairwiseInteractionPass` on the previous frontier. That pass may append **topology-only** edges
//!   (a chain between weak-component representatives) so the graph tends to stay one weak component;
//!   then optional host policy may detach true isolates (zero degree). There is **no continuous
//!   coordinate time** in the engine; step index `s`
//!   orders states for the user and for loop detection (Wyhash fingerprint).
//! - **Reproducibility:** the standard model seeds its PRNG from build/runtime options (`sim_seed`);
//!   same seed and same step count yields the same sequence **given identical host iterator order**.
//! - **Integrity (standard model):** each pass must preserve **additive** gauge quantum numbers summed
//!   over all vertices still present in the graph after removals and emissions (`sumGlobalQuantumNumbers`).
//!   This does **not** assert energy--momentum covariance or color confinement; it catches gross bookkeeping bugs.

pub const framework_tick_is_one_pairwise_pass = true;
