const std = @import("std");
const dvui = @import("dvui");
const uSim = @import("usim");
const Particle = @import("ulib");
const options = @import("options");
const builtin = @import("builtin");

const widgets = uSim.Widgets;
const Renderer = widgets.Renderer;
const ParticleGraph = Particle.Graph;

const time = std.time;
const ipc = options.initial_particle_count;

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

var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
const allocator = gpa.allocator();

var orig_content_scale: f32 = 1.0;
var warn_on_quit: bool = false;
var warn_on_quit_closing: bool = false;
var graph: ParticleGraph = undefined;
var prev_graph_state: ParticleGraph = undefined;
var show_stats_window: bool = false;

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
        const demo_label = if (dvui.Examples.show_demo_window) "Hide Demo Window" else "Show Demo Window";
        if (dvui.button(@src(), demo_label, .{}, .{ .tag = "show-demo-btn" })) {
            dvui.Examples.show_demo_window = !dvui.Examples.show_demo_window;
        }

        if (show_stats_window) {
            var stats = dvui.floatingWindow(@src(), .{ .open_flag = &show_stats_window }, .{
                .min_size_content = .{ .w = 400, .h = 400 },
                .max_size_content = .width(400),
            });
            defer stats.deinit();
            stats.dragAreaSet(dvui.windowHeader("Simulation Statistics", "", &show_stats_window));

            const sim_stats = try Particle.print(allocator, &graph);
            defer allocator.free(sim_stats);

            var stats_tl = dvui.textLayout(@src(), .{}, .{ .background = false, .expand = .horizontal });
            defer stats_tl.deinit();
            stats_tl.addText(sim_stats, .{});
        }
        const stats_label = if (show_stats_window) "Hide stats" else "Show stats";
        if (dvui.button(@src(), stats_label, .{}, .{ .tag = "show-sim-btn" })) {
            show_stats_window = !show_stats_window;
        }
    }

    var fps_tl = dvui.textLayout(@src(), .{}, .{ .background = false, .expand = .horizontal });
    defer fps_tl.deinit();

    const fps = try std.fmt.allocPrint(allocator, "FPS: {d}", .{dvui.FPS()});
    defer allocator.free(fps);
    fps_tl.addText(fps, .{ .style = .highlight });

    return frame();
}

fn processInteractions(alloc: std.mem.Allocator, g: *ParticleGraph) !void {
    // TODO(brianferri): Let the particle determine what should be the key type
    var particle_status: std.AutoArrayHashMap(u64, bool) = .init(alloc);
    defer particle_status.deinit();

    var iter = g.vertices.iterator();
    while (iter.next()) |entry| {
        const p1_key = entry.key_ptr.*;
        if ((try particle_status.getOrPutValue(p1_key, false)).found_existing) continue;
        const p1_value = entry.value_ptr.*;

        var adj_iter = p1_value.adjacency_set.iterator();
        while (adj_iter.next()) |adj_entry| {
            const p2_key = adj_entry.key_ptr.*;
            if ((try particle_status.getOrPutValue(p2_key, false)).found_existing) continue;
            const p2_value = g.getVertex(p2_key) orelse continue;

            var emission_buffer: std.ArrayList(Particle) = .empty;
            defer emission_buffer.deinit(alloc);

            const consumed = try Particle.interact(&p1_value.data, &p2_value.data, &emission_buffer, alloc);
            try particle_status.put(p1_key, consumed[0]);
            try particle_status.put(p2_key, consumed[1]);

            for (emission_buffer.items) |particle| {
                const next_key = try g.putVertexAuto(particle);
                try g.addEdge(p1_key, next_key);
                try g.addEdge(p2_key, next_key);
                try g.addEdge(next_key, p1_key);
                try g.addEdge(next_key, p2_key);
                try particle_status.put(next_key, false);
            }
        }
    }

    var status_iter = particle_status.iterator();
    while (status_iter.next()) |status| {
        if (status.value_ptr.*) _ = g.removeVertex(status.key_ptr.*);
    }
}

var frame_counter: u64 = 0;
pub fn frame() !dvui.App.Result {
    {
        var S3D = widgets.Software3D.Software3D(@src(), .{
            .camera_controls = handleInput,
            .width = 400,
            .height = 400,
        }, .{}).init();
        defer S3D.deinit(allocator);

        try S3D.addLayer(allocator, Renderer.Grid(5, 10));
        try S3D.addLayer(allocator, Renderer.Axes(1.0));
        try S3D.addLayer(allocator, Particle.render(&graph));

        S3D.render();
    }

    try processInteractions(allocator, &graph);
    if (graph.vertices.count() == 0) return .close;

    // if (std.meta.eql(prev_graph_state, graph) and frame_counter != 0) return .close;
    prev_graph_state = graph;
    frame_counter += 1;

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
