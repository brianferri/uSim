//! Cluster **layer** objects: embedded `vtable` + `@fieldParentPtr`, same shape as
//! `Widgets.Renderer.Layer` (see `Renderer.Grid`). Concrete layers wrap `interface: Iface` and
//! recover `*Self` inside vtable callbacks.

const std = @import("std");

pub const ClusterVizColor = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,
};

pub const ClusterLayerPiece = struct {
    keys: []u64,
    class_id: u16,
};

pub const ClusterLayerPartitionResult = struct {
    pieces: []ClusterLayerPiece,
    residual: []u64,

    pub fn deinit(self: *ClusterLayerPartitionResult, allocator: std.mem.Allocator) void {
        for (self.pieces) |*p| allocator.free(p.keys);
        allocator.free(self.pieces);
        allocator.free(self.residual);
        self.pieces = &.{};
        self.residual = &.{};
    }
};

/// Object + vtable: first argument to every hook is `*Iface` (address of the embedded field).
pub fn ClusterLayerInterface(comptime G: type, comptime Vertex: type) type {
    return struct {
        const Iface = @This();
        vtable: *const VTable,

        pub const VTable = struct {
            id: []const u8,
            partition_weak_component: *const fn (
                iface: *Iface,
                std.mem.Allocator,
                *G,
                []const u64,
            ) anyerror!ClusterLayerPartitionResult,
            class_name: *const fn (iface: *Iface, class_id: u16) []const u8,
            class_color: *const fn (iface: *Iface, class_id: u16) ClusterVizColor,
            include_particle: *const fn (iface: *Iface, p: *const Vertex) bool,
            unites_edge: *const fn (iface: *Iface, graph: *G, u: u64, v: u64) bool,
            /// Optional whole-set class for multi-vertex residual (hub color, hints); null if unknown.
            classify_residual: *const fn (
                iface: *Iface,
                graph: *G,
                members: []const u64,
            ) ?u16,
        };

        pub fn layerId(self: *const Iface) []const u8 {
            return self.vtable.id;
        }

        pub fn partitionWeakComponent(
            self: *Iface,
            allocator: std.mem.Allocator,
            graph: *G,
            members: []const u64,
        ) !ClusterLayerPartitionResult {
            return self.vtable.partition_weak_component(self, allocator, graph, members);
        }

        pub fn className(self: *Iface, class_id: u16) []const u8 {
            return self.vtable.class_name(self, class_id);
        }

        pub fn classColor(self: *Iface, class_id: u16) ClusterVizColor {
            return self.vtable.class_color(self, class_id);
        }

        pub fn includeParticle(self: *Iface, p: *const Vertex) bool {
            return self.vtable.include_particle(self, p);
        }

        pub fn unitesEdge(self: *Iface, graph: *G, u: u64, v: u64) bool {
            return self.vtable.unites_edge(self, graph, u, v);
        }

        pub fn classifyResidual(
            self: *Iface,
            graph: *G,
            members: []const u64,
        ) ?u16 {
            return self.vtable.classify_residual(self, graph, members);
        }
    };
}

/// Adapts `structure_analysis.weaklyConnectedRootPerKeyFilteredDyn` to `unitesEdge` on a layer.
pub fn WeakUnifyContext(comptime Iface: type, comptime G: type) type {
    return struct {
        layer: *Iface,
        pub fn unify(ctx: *@This(), graph: *G, u: u64, v: u64) bool {
            return ctx.layer.unitesEdge(graph, u, v);
        }
    };
}

/// Stock weak-edge rule: merge if either endpoint has `has_color` (vertex payload field).
pub fn weakEdgeColoredEndpointsUnite(comptime G: type, graph: *G, u: u64, v: u64) bool {
    const nu = graph.getVertex(u) orelse return false;
    const nv = graph.getVertex(v) orelse return false;
    return nu.data.has_color or nv.data.has_color;
}
