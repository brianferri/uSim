const std = @import("std");
const dvui = @import("dvui");
const Renderer = @import("rendering/Renderer.zig").Renderer;
const Camera = @import("rendering/Camera.zig");

pub fn Software3D(
    src: std.builtin.SourceLocation,
    comptime init_opts: struct {
        width: usize = 400,
        height: usize = 400,
        target_fps: usize = 60,
        camera_controls: ?fn (*Camera) void,
    },
    opts: dvui.Options,
) type {
    return struct {
        const Self = @This();

        const frame_len = init_opts.width * init_opts.height * 4;

        const State = struct {
            camera: Camera = .init,
        };

        state: State = .{},
        widget_data: dvui.WidgetData = undefined,
        layers: std.ArrayList(*Renderer.Layer) = .empty,

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

        pub fn render(
            self: Self,
        ) void {
            if (self.widget_data.rect.empty()) return;

            const rect_scale = self.widget_data.contentRectScale();
            var frame_buffer: [frame_len]u8 = undefined;
            const image_source: dvui.ImageSource = .{ .pixels = .{
                .rgba = &frame_buffer,
                .width = init_opts.width,
                .height = init_opts.height,
            } };

            const state = dvui.dataGetPtrDefault(null, self.widget_data.id, "state", State, self.state);
            if (init_opts.camera_controls) |handle| handle(&state.camera);

            if (dvui.timerDoneOrNone(self.widget_data.id)) {
                @memset(&frame_buffer, 0);

                for (self.layers.items) |layer| layer.draw(.init(.{
                    .buf = &frame_buffer,
                    .width = init_opts.width,
                    .height = init_opts.height,
                    .camera = state.camera,
                }));

                dvui.textureInvalidateCache(image_source.hash());
                const wait_us = std.time.us_per_s / init_opts.target_fps;
                dvui.timer(self.widget_data.id, wait_us);
            }

            dvui.renderImage(image_source, rect_scale, .{}) catch std.debug.print("Render Error", .{});
        }
    };
}
