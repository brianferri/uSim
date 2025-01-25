const std = @import("std");
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const options = .{
        .name = "UniverseLib",
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    };

    const lib_options: std.Build.StaticLibraryOptions = options;
    var exe_options: std.Build.ExecutableOptions = options;
    const test_options: std.Build.TestOptions = options;

    const lib = b.addStaticLibrary(lib_options);
    b.installArtifact(lib);

    exe_options.root_source_file = b.path("src/main.zig");
    const exe = b.addExecutable(exe_options);
    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_exe = b.addRunArtifact(exe);
    run_exe.step.dependOn(b.getInstallStep());
    run_step.dependOn(&run_exe.step);

    const test_step = b.step("test", "Run unit tests");
    const lib_tests = b.addTest(test_options);
    const run_lib_tests = b.addRunArtifact(lib_tests);
    test_step.dependOn(&run_lib_tests.step);

    const asm_step = b.step("asm", "Emit assembly file");
    const awf = b.addWriteFiles();
    awf.step.dependOn(b.getInstallStep());
    awf.addCopyFileToSource(lib.getEmittedAsm(), "main.asm");
    asm_step.dependOn(&awf.step);

    const exe_check = b.addStaticLibrary(lib_options);
    const check = b.step("check", "Check if zuws compiles");
    check.dependOn(&exe_check.step);
}
