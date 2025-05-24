pub const Particle = @import("universe_lib");
pub const Graph = @import("./structs/Graph.zig").Graph;

test {
    const std = @import("std");

    std.testing.refAllDecls(@This());
}
