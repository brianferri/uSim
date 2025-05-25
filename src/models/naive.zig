const std = @import("std");

const Self = @This();

tension: f64,
vibration_mode: f64,
phase: f64,

/// Simulates an interaction between two particles, potentially emitting new particles.
pub fn interact(self: *Self, other: *Self, allocator: std.mem.Allocator) ![]Self {
    var emitted = std.ArrayList(Self).init(allocator);
    const rand = std.crypto.random;

    // Compute the average vibration mode based on tensions.
    const avg_mode = (self.vibration_mode * other.tension +
        other.vibration_mode * self.tension) /
        (self.tension + other.tension);

    self.vibration_mode = avg_mode;
    other.vibration_mode = avg_mode;

    // Introduce slight random phase shifts.
    self.phase += rand.float(f64) * 0.1;
    other.phase += rand.float(f64) * 0.1;

    // Randomly select an interaction type.
    const interaction_type = rand.intRangeAtMost(u8, 0, 2);

    switch (interaction_type) {
        0 => { // Emission
            try emitted.append(self.emit());
            try emitted.append(other.emit());
        },
        1 => { // Absorption
            self.absorb(other);
        },
        2 => { // Annihilation
            if (self.annihilate(other)) {
                try emitted.append(Self{
                    .tension = (self.tension + other.tension) * 0.5,
                    .vibration_mode = avg_mode,
                    .phase = 0.0,
                });
            }
        },
        else => {},
    }

    return try emitted.toOwnedSlice();
}

/// Creates a new particle emitted from the current particle.
fn emit(self: *Self) Self {
    const rand = std.crypto.random;
    return Self{
        .tension = self.tension * 0.5,
        .vibration_mode = self.vibration_mode + rand.float(f64) * 0.1,
        .phase = rand.float(f64) * std.math.pi * 2.0,
    };
}

/// Modifies the current particle by absorbing properties from another particle.
fn absorb(self: *Self, other: *Self) void {
    const rand = std.crypto.random;
    self.tension += other.tension * 0.1;
    self.vibration_mode += other.vibration_mode * 0.1;
    self.phase += rand.float(f64) * 0.05;
}

/// Determines if two particles annihilate each other based on their properties.
pub fn annihilate(self: *Self, other: *Self) bool {
    const tension_diff = self.tension - other.tension;
    const mode_diff = self.vibration_mode - other.vibration_mode;
    const phase_diff = self.phase - other.phase;

    return tension_diff < 0.01 and mode_diff < 0.01 and phase_diff < 0.01;
}
