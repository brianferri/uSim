pub const String = @import("./physics/String.zig");
pub const Graph = @import("./data_structures/Graph.zig").Graph;

test {
    const std = @import("std");

    std.testing.refAllDecls(@This());
}
