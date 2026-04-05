//! Comptime tuple of cluster **layer** modules. Each exports `pub fn layerPtr() *ClusterLayerInterface`.
//! Stock builds list only `ulib` exports (e.g. `Particle.clusters`); add entries here for extra layers.

const Particle = @import("ulib");

pub const cluster_layer_modules = .{
    Particle.clusters,
};

comptime {
    if (cluster_layer_modules.len == 0) {
        @compileError("cluster manifest: need at least one layer module");
    }
}
