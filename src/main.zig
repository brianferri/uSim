const std = @import("std");
const dvui = @import("dvui");
const uSim = @import("usim");
const Particle = @import("ulib");
const options = @import("options");
const builtin = @import("builtin");

const stat = @import("./util/stat.zig").stat;

const widgets = uSim.Widgets;
const Renderer = widgets.Renderer;
const ParticleGraph = Particle.Graph;

const time = std.time;
const ipc = options.initial_particle_count;


pub const dvui_app: dvui.App = .{
    .config = .{
        .options = .{
            .size = .{ .w = 800.0, .h = 600.0 },
            .min_size = .{ .w = 250.0, .h = 350.0 },
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

var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
const allocator = gpa.allocator();

var orig_content_scale: f32 = 1.0;
var warn_on_quit: bool = false;
var warn_on_quit_closing: bool = false;
var graph: ParticleGraph = undefined;

pub fn AppInit(win: *dvui.Window) !void {
    orig_content_scale = win.content_scale;
    const theme = switch (win.backend.preferredColorScheme() orelse .light) {
        .light => dvui.Theme.builtin.adwaita_light,
        .dark => dvui.Theme.builtin.adwaita_dark,
    };

    win.themeSet(theme);

    graph = try Particle.initializeGraph(allocator, ipc);
}

pub fn AppDeinit() void {
    defer if (gpa.deinit() != .ok) std.debug.panic("Leaked", .{});
    defer graph.deinit();
}

pub fn AppFrame() !dvui.App.Result {
    if (@import("builtin").mode == .Debug) {
        var box = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal });
        defer box.deinit();

        if (dvui.button(@src(), "Debug Window", .{}, .{})) dvui.toggleDebugWindow();

        dvui.Examples.demo();
        const label = if (dvui.Examples.show_demo_window) "Hide Demo Window" else "Show Demo Window";
        if (dvui.button(@src(), label, .{}, .{ .tag = "show-demo-btn" })) {
            dvui.Examples.show_demo_window = !dvui.Examples.show_demo_window;
        }

        var fps_tl = dvui.textLayout(@src(), .{}, .{ .background = false, .expand = .horizontal });
        defer fps_tl.deinit();

        const fps = try std.fmt.allocPrint(allocator, "FPS: {d}", .{dvui.FPS()});
        defer allocator.free(fps);
        fps_tl.addText(fps, .{ .style = .highlight });
    }

    return frame();
}

pub fn frame() !dvui.App.Result {
    {
        var S3D = widgets.Software3D.Software3D(@src(), .{
            .camera_controls = handleInput,
        }, .{}).init();
        defer S3D.deinit(allocator);

        try S3D.addLayer(allocator, Renderer.Grid(5, 10));
        try S3D.addLayer(allocator, Renderer.Axes(1.0));

        S3D.render();
    }

    return .ok;
}

fn handleInput(camera: *widgets.Camera) void {
    const move_speed: f32 = 0.1;
    const look_speed: f32 = 0.05;

    for (dvui.events()) |event| {
        if (event.evt == .key) {
            const key_event = event.evt.key;
            if (event.handled) continue;

            if (key_event.action == .down or key_event.action == .repeat) {
                switch (key_event.code) {
                    .w => camera.position += camera.forward() * @as(Renderer.Vec3, @splat(move_speed)),
                    .s => camera.position -= camera.forward() * @as(Renderer.Vec3, @splat(move_speed)),
                    .a => camera.position -= camera.right() * @as(Renderer.Vec3, @splat(move_speed)),
                    .d => camera.position += camera.right() * @as(Renderer.Vec3, @splat(move_speed)),
                    .space => camera.position[1] += move_speed,
                    .left_shift => camera.position[1] -= move_speed,
                    .j, .left => camera.yaw += look_speed,
                    .l, .right => camera.yaw -= look_speed,
                    .i, .up => camera.pitch += look_speed,
                    .k, .down => camera.pitch -= look_speed,
                    else => {},
                }
            }
        }
    }
}
