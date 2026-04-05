const std = @import("std");
const dvui = @import("dvui");
const host = @import("host/root.zig");
const options = @import("options");
const Particle = @import("ulib");

pub const dvui_app: dvui.App = .{
    .config = .{
        .options = .{
            .size = .{ .w = 1920.0, .h = 1080.0 },
            .min_size = .{ .w = 1920.0, .h = 1080.0 },
            .title = "uSim",
            .window_init_options = .{},
        },
    },
    .frameFn = AppFrame,
    .initFn = AppInit,
    .deinitFn = AppDeinit,
};
pub const main = dvui.App.main;
pub const panic = dvui.App.panic;
pub const std_options: std.Options = .{
    .logFn = dvui.App.logFn,
};

var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
var sim_host: host.SimHost = undefined;

pub fn AppInit(win: *dvui.Window) !void {
    Particle.setSimulationRngSeed(options.simulation_rng_seed);
    sim_host = try host.SimHost.init(win, gpa.allocator(), options.initial_particle_count);
}

pub fn AppDeinit() void {
    sim_host.deinit();
    if (gpa.deinit() != .ok) std.debug.panic("Leaked", .{});
}

pub fn AppFrame() !dvui.App.Result {
    return sim_host.appFrame();
}

test {
    _ = @import("host/sim_step.zig");
    _ = @import("host/timeline.zig");
}
