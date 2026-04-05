//! `usim` package: **core** graph + layout + analysis (no dvui in these files); **widgets** (dvui-backed 3D); **app** is the exe shell under `src/app/` (not imported here).
pub const simulation_contract = @import("core/simulation_contract.zig");
pub const Graph = @import("core/graph.zig").Graph;
pub const cloneAutoIdGraph = @import("core/graph.zig").cloneAutoIdGraph;
pub const RelationalLayout = @import("core/RelationalLayout.zig");
pub const structure_analysis = @import("core/structure_analysis.zig");
pub const cluster_viz = @import("core/cluster_viz.zig");
pub const Widgets = @import("widgets/root.zig");

test {
    const std = @import("std");
    std.testing.refAllDecls(@This());
}
