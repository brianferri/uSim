//! Build `[*]cluster_viz.ClusterLayerInterface` from modules that export `layerPtr()`.

const std = @import("std");
const uSim = @import("usim");
const Particle = @import("ulib");

pub const ClusterLayerIface =
    uSim.cluster_viz.ClusterLayerInterface(Particle.Graph, Particle);

fn assertTuple(comptime T: type) void {
    const info = @typeInfo(T).@"struct";
    if (!info.is_tuple) {
        @compileError("cluster layers: expected tuple of layer modules");
    }
}

pub fn layersFromModules(comptime modules: anytype) [modules.len]*ClusterLayerIface {
    assertTuple(@TypeOf(modules));
    comptime var out: [modules.len]*ClusterLayerIface = undefined;
    inline for (0..modules.len) |i| {
        const mod = modules[i];
        // `mod` is the namespace type; `@TypeOf(mod)` is builtin `type`, which
        // `@hasDecl` rejects — pass `mod` as the container.
        if (!@hasDecl(mod, "layerPtr")) {
            @compileError(std.fmt.comptimePrint(
                "cluster layer module at index {d} missing `pub fn layerPtr()`",
                .{i},
            ));
        }
        out[i] = mod.layerPtr();
    }
    return out;
}

pub fn firstPartitionMaxBruteforceN(comptime modules: anytype) usize {
    assertTuple(@TypeOf(modules));
    comptime var n: usize = 0;
    inline for (0..modules.len) |i| {
        const mod = modules[i];
        if (@hasDecl(mod, "partition_max_bruteforce_n")) {
            if (n == 0) n = mod.partition_max_bruteforce_n;
        }
    }
    return n;
}
