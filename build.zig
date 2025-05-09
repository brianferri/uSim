const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const model = b.option([]const u8, "implementation", "The model to use for particles/interactions") orelse "naive";
    const model_path = try std.fmt.allocPrint(b.allocator, "src/models/{s}.zig", .{model});

    const stat = b.option(bool, "stat", "Use stat to keep track of usages (Linux)") orelse false;

    const options = b.addOptions();
    options.addOption(bool, "stat", stat);

    const lib_mod = b.createModule(.{
        .root_source_file = b.path(model_path),
        .target = target,
        .optimize = optimize,
    });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("universe_lib", lib_mod);
    exe_mod.addOptions("options", options);

    const exe = b.addExecutable(.{
        .name = "uSim",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const lib_unit_tests = b.addTest(.{ .root_module = lib_mod });
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const exe_unit_tests = b.addTest(.{ .root_module = exe_mod });
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);

    const asm_step = b.step("asm", "Emit assembly file");
    const awf = b.addWriteFiles();
    awf.step.dependOn(b.getInstallStep());
    // Path is relative to the cache dir in which it *would've* been placed in
    const asm_file_name = try std.fmt.allocPrint(b.allocator, "../../../zig-out/asm/{s}_{s}.s", .{ model, @tagName(optimize) });
    _ = awf.addCopyFile(exe.getEmittedAsm(), asm_file_name);
    asm_step.dependOn(&awf.step);
}
