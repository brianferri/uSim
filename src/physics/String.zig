const std = @import("std");

const Self = @This();

tension: f64,
vibration_mode: f64,
phase: f64,

pub fn interact(self: *Self, other: *Self) void {
    const avg_mode = (self.vibration_mode * other.tension +
        other.vibration_mode * self.tension) /
        (self.tension + other.tension);

    self.vibration_mode = avg_mode;
    other.vibration_mode = avg_mode;

    const rand = std.crypto.random;
    self.phase += rand.float(f64) * 0.1;
    other.phase += rand.float(f64) * 0.1;
}
