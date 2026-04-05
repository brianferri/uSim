const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const dvui = if (target.result.cpu.arch == .wasm32) b.dependency("dvui", .{
        .target = target,
        .optimize = optimize,
        .backend = .web,
    }) else b.dependency("dvui", .{
        .target = target,
        .optimize = optimize,
        .backend = .sdl3,
    });
    const dvui_mod = dvui.module(if (target.result.cpu.arch == .wasm32) "dvui_web" else "dvui_sdl3");

    const model = b.option([]const u8, "model", "The example model to use for particles/interactions") orelse "standard";
    const initial_particle_count = b.option(usize, "ipc", "The number of particles to have the simulation start with") orelse 100;
    const simulation_rng_seed = b.option(u64, "sim_seed", "Fixed RNG seed for the standard model (reproducible runs)") orelse 0xfeed_beef;

    const model_path = try std.fmt.allocPrint(b.allocator, "models/{s}/main.zig", .{model});

    const options = b.addOptions();
    options.addOption(usize, "initial_particle_count", initial_particle_count);
    options.addOption(u64, "simulation_rng_seed", simulation_rng_seed);

    const ulib_mod = b.createModule(.{
        .root_source_file = b.path(model_path),
        .target = target,
        .optimize = optimize,
    });

    const usim_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    ulib_mod.addImport("usim", usim_mod);
    usim_mod.addImport("dvui", dvui_mod);

    const vlib_mod = b.createModule(.{
        .root_source_file = b.path("visualizations/dispatch.zig"),
        .target = target,
        .optimize = optimize,
    });
    vlib_mod.addImport("usim", usim_mod);
    vlib_mod.addImport("ulib", ulib_mod);

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/app/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("usim", usim_mod);
    exe_mod.addImport("ulib", ulib_mod);
    exe_mod.addImport("vlib", vlib_mod);
    exe_mod.addImport("dvui", dvui_mod);
    exe_mod.addOptions("options", options);

    const bench_mod = b.createModule(.{
        .root_source_file = b.path("src/app/bench_sim.zig"),
        .target = target,
        .optimize = optimize,
    });
    bench_mod.addImport("usim", usim_mod);
    bench_mod.addImport("ulib", ulib_mod);
    bench_mod.addOptions("options", options);

    const exe = b.addExecutable(.{
        .name = if (target.result.cpu.arch == .wasm32) "web" else "uSim",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    if (target.result.cpu.arch != .wasm32) {
        const bench_exe = b.addExecutable(.{
            .name = "bench_sim",
            .root_module = bench_mod,
        });
        b.installArtifact(bench_exe);

        const run_bench = b.addRunArtifact(bench_exe);
        run_bench.step.dependOn(b.getInstallStep());
        if (b.args) |args| run_bench.addArgs(args);
        const bench_step = b.step("bench", "Headless sim: zig build bench -- [steps] (uses -Dipc/-Dmodel)");
        bench_step.dependOn(&run_bench.step);
    }

    if (target.result.cpu.arch == .wasm32) {
        const web_js = dvui.namedLazyPath("web.js");
        const web_html = dvui.path("src/backends/index.html");
        b.getInstallStep().dependOn(&b.addInstallFileWithDir(web_js, .bin, "web.js").step);
        b.getInstallStep().dependOn(&b.addInstallFileWithDir(web_html, .bin, "index.html").step);
    }
    const install_docs = b.addInstallDirectory(.{
        .source_dir = b.addLibrary(.{
            .name = model,
            .root_module = ulib_mod,
        }).getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const lib_unit_tests = b.addTest(.{ .root_module = ulib_mod });
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const exe_unit_tests = b.addTest(.{ .root_module = exe_mod });
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);

    const docs_step = b.step("docs", "Install docs into zig-out/docs");
    docs_step.dependOn(&install_docs.step);

    const asm_step = b.step("asm", "Emit assembly file");
    const awf = b.addWriteFiles();
    awf.step.dependOn(b.getInstallStep());
    // Path is relative to the cache dir in which it *would've* been placed in
    const asm_file_name = try std.fmt.allocPrint(b.allocator, "../../../zig-out/asm/{s}_{s}.s", .{ model, @tagName(optimize) });
    _ = awf.addCopyFile(exe.getEmittedAsm(), asm_file_name);
    asm_step.dependOn(&awf.step);
}
