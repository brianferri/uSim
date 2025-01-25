const std = @import("std");
const UniverseLib = @import("root.zig");

const Graph = UniverseLib.Graph;
const String = UniverseLib.String;

pub fn main() !void {
    var prng = std.rand.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    var rng = prng.random();
    var my_string = String{
        .tension = 1.0,
        .vibrational_modes = 10.0,
        .length = 1.0,
    };

    const stdout = std.io.getStdOut().writer();

    for (0..10) |i| {
        try stdout.print("Step {}\n", .{i});
        try stdout.print("  String: tension={:.2}, vibrational_modes={:.2}, length={:.2}\n", .{ my_string.tension, my_string.vibrational_modes, my_string.length });

        const result = my_string.mutate(&rng);
        if (try result) |new_strings| {
            for (new_strings, 0..new_strings.len) |new_string, si| {
                try stdout.print("  Emitted String {}: tension={:.2}, vibrational_modes={:.2}, length={:.2}\n", .{ si, new_string.tension, new_string.vibrational_modes, new_string.length });
            }
            std.heap.page_allocator.free(new_strings);
        }
    }
}
