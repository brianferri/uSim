//! Hadron cluster viz class tags and partition structs (model-local).

const std = @import("std");

pub const ClusterVizClass = enum {
    proton_like,
    neutron_like,
    other_baryon,
    antibaryon,
    meson,
    /// Lone charged pion vertex (colorless hadron in the particle table).
    single_meson_vertex,
};

pub const HadronVizPiece = struct {
    keys: []u64,
    class: ClusterVizClass,
};

pub const ClusterVizPartitionResult = struct {
    pieces: []HadronVizPiece,
    residual: []u64,

    pub fn deinit(self: *ClusterVizPartitionResult, allocator: std.mem.Allocator) void {
        for (self.pieces) |*p| allocator.free(p.keys);
        allocator.free(self.pieces);
        allocator.free(self.residual);
        self.pieces = &.{};
        self.residual = &.{};
    }
};
