//! Active cluster layer + `cluster_layers` built from `manifest.zig`.

const std = @import("std");
const manifest = @import("manifest.zig");
const layer_set = @import("layer_set.zig");

pub const ClusterLayerIface = layer_set.ClusterLayerIface;

pub const cluster_layers = layer_set.layersFromModules(manifest.cluster_layer_modules);

pub const cluster_layer_active_index: usize = 0;

pub const partition_max_bruteforce_n =
    layer_set.firstPartitionMaxBruteforceN(manifest.cluster_layer_modules);

pub fn activeLayer() *ClusterLayerIface {
    if (cluster_layers.len == 0) @panic("cluster_layers must not be empty");
    const idx = if (cluster_layer_active_index < cluster_layers.len)
        cluster_layer_active_index
    else
        0;
    return cluster_layers[idx];
}

test "registry layers match manifest tuple" {
    try std.testing.expect(cluster_layers.len == manifest.cluster_layer_modules.len);
    inline for (0..cluster_layers.len) |i| {
        try std.testing.expect(std.mem.eql(
            u8,
            cluster_layers[i].layerId(),
            manifest.cluster_layer_modules[i].layerPtr().layerId(),
        ));
    }
}
