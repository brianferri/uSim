const std = @import("std");

const Self = @This();

tension: f64,
vibrational_modes: f64,
length: f64,

const CouplingType = enum {
    None,
    Gravity,
    Gauge,
};

pub fn mutate(self: *Self, rng: *std.rand.Random) !?[]Self {
    const allocator = std.heap.page_allocator;

    switch (rng.uintAtMost(u2, 3)) {
        0 => {
            // Change properties
            self.tension *= 1.1;
            self.vibrational_modes *= 0.9;
        },
        1 => {
            // Emit a new string
            const new_strings = try allocator.alloc(Self, 1);
            new_strings[0] = Self{
                .tension = self.tension * 0.5,
                .vibrational_modes = self.vibrational_modes * 1.5,
                .length = self.length * 0.5,
            };
            return new_strings;
        },
        2 => {
            // Double itself
            const new_strings = try allocator.alloc(Self, 2);
            new_strings[0] = self.*;
            new_strings[1] = Self{
                .tension = self.tension,
                .vibrational_modes = self.vibrational_modes,
                .length = self.length,
            };
            return new_strings;
        },
        3 => {
            // Reabsorb (reduce itself)
            self.tension *= 0.8;
            self.vibrational_modes *= 0.8;
            self.length *= 0.8;
        },
    }
    return null;
}
