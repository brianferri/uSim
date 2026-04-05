//! Application host layer: timeline stepping, dvui shell, and 3D viewport wiring.
//! `usim` stays model-agnostic graph + layout helpers; `ulib` is the pluggable model; `vlib` is stock views.
pub const chrome = @import("chrome.zig");
pub const SimHost = @import("session.zig").SimHost;

/// Linear step cache + loop detection (pairwise passes over the active graph).
pub const LinearTimeline = @import("timeline.zig").LinearTimeline;

/// Shelved topologies removed from the frontier graph (e.g. isolates).
pub const DetachedTopologyShelf = @import("detached_shelf.zig").DetachedTopologyShelf;

/// One deterministic pairwise interaction pass (`ulib` rules + host edge policy).
pub const pairwiseInteractionPass = @import("sim_step.zig").pairwiseInteractionPass;
