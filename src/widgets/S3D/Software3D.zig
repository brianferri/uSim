const std = @import("std");
const dvui = @import("dvui");
const Renderer = @import("Renderer.zig").Renderer;
const Camera = @import("Camera.zig");

pub fn Software3D(
    src: std.builtin.SourceLocation,
    comptime init_opts: struct {
        width: usize = 400,
        height: usize = 400,
        target_fps: usize = 60,
        camera_controls: ?fn (*Camera) void,
        /// Left click inside the image: framebuffer pixel coords and current camera (after `camera_controls`).
        on_left_press: ?*const fn (?*anyopaque, Camera, f32, f32) void = null,
    },
    opts: dvui.Options,
) type {
    return struct {
        const Self = @This();

        const frame_len = init_opts.width * init_opts.height * 4;
        comptime {
            // TODO(brianferri): eventually check the correct size of the `render` function https://github.com/ziglang/zig/issues/157 https://github.com/ziglang/zig/issues/23367 https://github.com/ziglang/zig/issues/23446
            if (@import("builtin").cpu.arch == .wasm32) {
                if (frame_len >= 7654321 - 1024) @compileError("Reduce the frame_len");
            }
        }

        const State = struct {
            camera: Camera = .init,
        };

        state: State = .{},
        widget_data: dvui.WidgetData = undefined,
        layers: std.ArrayList(*Renderer.Layer) = .empty,
        /// Ignored unless `init_opts.on_left_press` is non-null. Set each frame before `render`.
        left_press_ctx: ?*anyopaque = null,

        pub fn init() Self {
            var defaults: dvui.Options = .{
                .name = "Software3D",
                .min_size_content = .{
                    .w = @floatFromInt(init_opts.width),
                    .h = @floatFromInt(init_opts.height),
                },
            };
            const options = defaults.override(opts);
            var widget_data: dvui.WidgetData = .init(src, .{}, options);
            widget_data.register();
            widget_data.minSizeSetAndRefresh();
            widget_data.minSizeReportToParent();

            return .{
                .widget_data = widget_data,
            };
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            self.layers.deinit(allocator);
        }

        pub fn addLayer(self: *Self, allocator: std.mem.Allocator, layer_type: type) !void {
            const layer_fn = @field(layer_type, "layer")();
            var layer = dvui.dataGetPtrDefault(null, self.widget_data.id, @typeName(layer_type), @TypeOf(layer_fn), layer_fn);
            const interface = &@field(layer, "interface");
            try self.layers.append(allocator, interface);
        }

        pub fn render(self: *Self, allocator: std.mem.Allocator) std.mem.Allocator.Error!void {
            if (self.widget_data.rect.empty()) return;

            const rect_scale = self.widget_data.contentRectScale();
            // Stack frame this large (~3.5 MiB at 1280x720) overflows typical 8 MiB threads with dvui/SDL above it.
            const frame_buffer = try allocator.alloc(u8, frame_len);
            defer allocator.free(frame_buffer);

            const image_source: dvui.ImageSource = .{ .pixels = .{
                .rgba = frame_buffer,
                .width = init_opts.width,
                .height = init_opts.height,
            } };

            const state = dvui.dataGetPtrDefault(null, self.widget_data.id, "state", State, self.state);
            if (init_opts.camera_controls) |handle| handle(&state.camera);

            if (init_opts.on_left_press) |on_press| {
                if (self.left_press_ctx) |ctx| {
                    const pr = self.widget_data.contentRectScale().r;
                    if (pr.w > 0 and pr.h > 0) {
                        for (dvui.events()) |*ev| {
                            if (ev.handled) continue;
                            switch (ev.evt) {
                                .mouse => |me| {
                                    if (me.action != .press or me.button != .left) continue;
                                    if (!dvui.eventMatch(ev, .{ .id = self.widget_data.id, .r = pr })) continue;
                                    const rel_x = me.p.x - pr.x;
                                    const rel_y = me.p.y - pr.y;
                                    const fw: f32 = @floatFromInt(init_opts.width);
                                    const fh: f32 = @floatFromInt(init_opts.height);
                                    const fb_x = rel_x / pr.w * fw;
                                    const fb_y = rel_y / pr.h * fh;
                                    on_press(ctx, state.camera, fb_x, fb_y);
                                    ev.handle(@src(), &self.widget_data);
                                },
                                else => {},
                            }
                        }
                    }
                }
            }

            if (dvui.timerDoneOrNone(self.widget_data.id)) {
                @memset(frame_buffer, 0);

                for (self.layers.items) |layer| layer.draw(.init(.{
                    .buf = frame_buffer,
                    .width = init_opts.width,
                    .height = init_opts.height,
                    .camera = state.camera,
                }));

                dvui.textureInvalidateCache(image_source.hash());
                const wait_us = std.time.us_per_s / init_opts.target_fps;
                dvui.timer(self.widget_data.id, wait_us);
            }

            dvui.renderImage(image_source, rect_scale, .{}) catch unreachable;
        }
    };
}
