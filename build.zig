const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const target = b.resolveTargetQuery(.{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .gnu });
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{ .name = "bme688_sensor", .root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    }) });

    // BSEC headers
    exe.addIncludePath(b.path("lib/bsec"));

    // BME68x driver headers
    exe.addIncludePath(b.path("lib/bme68x"));

    // Compile BME68x C driver
    exe.addCSourceFile(.{
        .file = b.path("lib/bme68x/bme68x.c"),
        .flags = &.{"-std=c99"},
    });

    // Link BSEC static library
    exe.addObjectFile(b.path("lib/libalgobsec.a"));

    // Link libc and math
    exe.linkLibC();

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
