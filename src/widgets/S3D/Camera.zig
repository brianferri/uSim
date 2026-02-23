/// The Camera handles the math for World -> View transformation
const Vec3 = @import("Renderer.zig").Vec3;

pub const Camera = @This();

position: Vec3,
pitch: f32,
yaw: f32,
fov: f32,
near: f32,

pub const init: Camera = .{
    .position = .{ 0.0, 2.0, -4.0 },
    .pitch = 0.0,
    .yaw = 0.0,
    .fov = 60.0,
    .near = 0.1,
};

/// Returns a 3x3 rotation matrix (row-major for convenience in dot products)
pub fn rotationMatrix(self: Camera) [3]Vec3 {
    const cp = @cos(self.pitch);
    const sp = @sin(self.pitch);
    const cy = @cos(self.yaw);
    const sy = @sin(self.yaw);

    // Rx (Pitch)
    // 1  0   0
    // 0  cp -sp
    // 0  sp  cp

    // Ry (Yaw)
    // cy 0 sy
    // 0  1 0
    // -sy 0 cy

    // R = Rx * Ry
    // Right Vector (Row 0)
    const r0 = Vec3{ cy, 0.0, sy };
    // Up Vector (Row 1)
    const r1 = Vec3{ sp * sy, cp, -sp * cy };
    // Forward Vector (Row 2)
    const r2 = Vec3{ -cp * sy, sp, cp * cy };

    return .{ r0, r1, r2 };
}

pub fn forward(self: Camera) Vec3 {
    const m = self.rotationMatrix();
    return m[2]; // Z row
}

pub fn right(self: Camera) Vec3 {
    const m = self.rotationMatrix();
    return m[0]; // X row
}

pub fn up(self: Camera) Vec3 {
    const m = self.rotationMatrix();
    return m[1]; // Y row
}
