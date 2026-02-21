pub const Graph = @import("./structs/Graph.zig").Graph;
pub const Widgets = @import("./widgets/root.zig");

test {
    const std = @import("std");
    std.testing.refAllDecls(@This());
}
