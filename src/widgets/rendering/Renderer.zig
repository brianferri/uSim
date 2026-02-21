const std = @import("std");
const Camera = @import("Camera.zig");

pub const Vec3 = @Vector(3, f32);

pub const PixelCoord = struct {
    x: i32,
    y: i32,
};

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,
};

pub const Renderer = @This();

width: usize,
height: usize,
camera: Camera,

buf: []u8 = undefined,
focal_length: f32 = 0,

pub fn init(opts: Renderer) Renderer {
    var r = opts;
    r.updateFocal();
    return r;
}

pub fn updateFocal(self: *Renderer) void {
    self.focal_length = 0.5 * @as(f32, @floatFromInt(self.height)) / @tan(std.math.degreesToRadians(self.camera.fov * 0.5));
}

pub fn project(self: Renderer, world_pos: Vec3) ?PixelCoord {
    const rel = world_pos - self.camera.position;
    const rot = self.camera.rotationMatrix();

    const x = @reduce(.Add, rel * rot[0]);
    const y = @reduce(.Add, rel * rot[1]);
    const z = @reduce(.Add, rel * rot[2]);

    if (z <= self.camera.near) return null;

    const u = self.focal_length * (x / z) + @as(f32, @floatFromInt(self.width)) * 0.5;
    const v = -self.focal_length * (y / z) + @as(f32, @floatFromInt(self.height)) * 0.5;

    return PixelCoord{
        .x = @intFromFloat(u),
        .y = @intFromFloat(v),
    };
}

pub fn drawPoint(self: Renderer, x: i32, y: i32, color: Color) void {
    if (x < 0 or y < 0 or @as(usize, @intCast(x)) >= self.width or @as(usize, @intCast(y)) >= self.height) return;

    const idx = (y * @as(i32, @intCast(self.width)) + x) * 4;
    if (idx < 0 or @as(usize, @intCast(idx + 3)) >= self.buf.len) return;

    self.buf[@intCast(idx)] = color.r;
    self.buf[@intCast(idx + 1)] = color.g;
    self.buf[@intCast(idx + 2)] = color.b;
    self.buf[@intCast(idx + 3)] = color.a;
}

pub fn drawLine3D(self: Renderer, start_world: Vec3, end_world: Vec3, color: Color) void {
    const p0_opt = self.project(start_world);
    const p1_opt = self.project(end_world);

    if (p0_opt == null or p1_opt == null) return;

    self.drawLine(p0_opt.?, p1_opt.?, color);
}

pub fn drawLine(self: Renderer, p0: PixelCoord, p1: PixelCoord, color: Color) void {
    var x0 = p0.x;
    var y0 = p0.y;
    const x1 = p1.x;
    const y1 = p1.y;

    const dx: i32 = @intCast(@abs(x1 - x0));
    const sx = @as(i2, if (x0 < x1) 1 else -1);
    const dy = -@as(i32, @intCast(@abs(y1 - y0)));
    const sy = @as(i2, if (y0 < y1) 1 else -1);
    var err = dx + dy;

    while (true) {
        self.drawPoint(x0, y0, color);
        if (x0 == x1 and y0 == y1) break;
        const e2 = 2 * err;
        if (e2 >= dy) {
            err += dy;
            x0 += sx;
        }
        if (e2 <= dx) {
            err += dx;
            y0 += sy;
        }
    }
}

pub const Layer = struct {
    vtable: *const VTable,

    pub const VTable = struct {
        draw: *const fn (layer: *Layer, renderer: Renderer) void,
    };

    pub fn draw(layer: *Layer, renderer: Renderer) void {
        layer.vtable.draw(layer, renderer);
    }
};

pub fn Grid(
    size: f32,
    divisions: usize,
) type {
    return struct {
        const Self = @This();

        interface: Layer,

        size: f32 = size,
        divisions: usize = divisions,

        fn initInterface() Layer {
            return .{
                .vtable = &.{ .draw = draw },
            };
        }

        pub fn layer() Self {
            return .{
                .interface = initInterface(),
                .size = size,
                .divisions = divisions,
            };
        }

        fn draw(render_layer: *Layer, r: Renderer) void {
            const l: *Self = @alignCast(@fieldParentPtr("interface", render_layer));
            const half = l.size * 0.5;
            const step = l.size / @as(f32, @floatFromInt(l.divisions));

            for (0..l.divisions + 1) |i| {
                const offset = -half + @as(f32, @floatFromInt(i)) * step;
                const gray = Color{ .r = 100, .g = 100, .b = 100 };

                // Lines along X
                r.drawLine3D(.{ -half, 0, offset }, .{ half, 0, offset }, gray);
                // Lines along Z
                r.drawLine3D(.{ offset, 0, -half }, .{ offset, 0, half }, gray);
            }
        }
    };
}

pub fn Axes(scale: f32) type {
    return struct {
        const Self = @This();

        interface: Layer,

        scale: f32 = scale,

        fn initInterface() Layer {
            return .{
                .vtable = &.{ .draw = draw },
            };
        }

        pub fn layer() Self {
            return .{
                .interface = initInterface(),
                .scale = scale,
            };
        }

        fn draw(render_layer: *Layer, r: Renderer) void {
            const l: *Self = @alignCast(@fieldParentPtr("interface", render_layer));
            const s = l.scale;

            r.drawLine3D(.{ 0, 0, 0 }, .{ s, 0, 0 }, .{ .r = 255, .g = 0, .b = 0 });
            r.drawLine3D(.{ 0, 0, 0 }, .{ 0, s, 0 }, .{ .r = 0, .g = 255, .b = 0 });
            r.drawLine3D(.{ 0, 0, 0 }, .{ 0, 0, s }, .{ .r = 0, .g = 0, .b = 255 });
        }
    };
}

var Xoshiro = std.Random.DefaultPrng.init(0);
const random = Xoshiro.random();

pub fn Cube(size: f32, rotation_speed: f32) type {
    return struct {
        const Self = @This();

        interface: Layer,

        size: f32 = size,
        angle: f32 = 0,
        rotation_speed: f32 = rotation_speed,

        fn initInterface() Layer {
            return .{
                .vtable = &.{ .draw = draw },
            };
        }

        pub fn layer() Self {
            return .{
                .interface = initInterface(),
                .size = size,
                .rotation_speed = rotation_speed,
            };
        }

        fn rotateX(v: Vec3, a: f32) Vec3 {
            const s = @sin(a);
            const c = @cos(a);
            return .{
                v[0],
                v[1] * c - v[2] * s,
                v[1] * s + v[2] * c,
            };
        }

        fn rotateY(v: Vec3, a: f32) Vec3 {
            const s = @sin(a);
            const c = @cos(a);
            return .{
                v[0] * c + v[2] * s,
                v[1],
                -v[0] * s + v[2] * c,
            };
        }

        fn rotateZ(v: Vec3, a: f32) Vec3 {
            const s = @sin(a);
            const c = @cos(a);
            return .{
                v[0] * c - v[1] * s,
                v[0] * s + v[1] * c,
                v[2],
            };
        }

        fn draw(render_layer: *Layer, renderer: Renderer) void {
            const l: *Self = @alignCast(@fieldParentPtr("interface", render_layer));

            l.angle += l.rotation_speed;

            const r = random.intRangeAtMost(u8, 0x00, 0xff);
            const b = random.intRangeAtMost(u8, 0x00, 0xff);
            const g = random.intRangeAtMost(u8, 0x00, 0xff);

            const h = l.size * 0.5;

            const base = [_]Vec3{
                .{ -h, -h, -h }, .{ h, -h, -h },
                .{ h, h, -h },   .{ -h, h, -h },
                .{ -h, -h, h },  .{ h, -h, h },
                .{ h, h, h },    .{ -h, h, h },
            };

            const edges = [_][2]usize{
                .{ 0, 1 }, .{ 1, 2 }, .{ 2, 3 }, .{ 3, 0 },
                .{ 4, 5 }, .{ 5, 6 }, .{ 6, 7 }, .{ 7, 4 },
                .{ 0, 4 }, .{ 1, 5 }, .{ 2, 6 }, .{ 3, 7 },
            };

            for (edges) |e| {
                var edge1 = base[e[0]];
                var edge2 = base[e[1]];

                edge1 = rotateX(rotateY(edge1, l.angle * 1.3), l.angle * 0.7);
                edge2 = rotateX(rotateY(edge2, l.angle * 1.3), l.angle * 0.7);

                renderer.drawLine3D(edge1, edge2, .{ .r = r, .g = g, .b = b });
            }
        }
    };
}
