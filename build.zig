const std = @import("std");

pub fn build(b: *std.Build) void {
    // Build Configuration
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .aarch64,
        .os_tag = .linux,
        .abi = .musl,
    });
    const optimize = b.standardOptimizeOption(.{});

    // Dependencies
    const httpz = b.dependency("httpz", .{
        .target = target,
        .optimize = optimize,
    });

    // Main Executable
    const exe = b.addExecutable(.{
        .name = "bme688_sensor",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "httpz", .module = httpz.module("httpz") },
            },
        }),
    });

    configureC(b, exe);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Test Executable
    const test_module = b.createModule(.{
        .root_source_file = b.path("src/test.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "httpz", .module = httpz.module("httpz") },
        },
    });

    const test_exe = b.addTest(.{
        .root_module = test_module,
    });

    configureC(b, test_exe);

    const run_tests = b.addRunArtifact(test_exe);
    run_tests.stdio = .inherit;
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);

    // Build Steps
    const test_and_run = b.step("test-and-run", "Run tests then execute the app");
    test_and_run.dependOn(&run_tests.step);
    test_and_run.dependOn(&run_cmd.step);
}

/// Configure C dependencies (BSEC, BME68x driver, libc)
/// Tries local lib/ first, falls back to pkg-config
fn configureC(b: *std.Build, exe: *std.Build.Step.Compile) void {
    const local_bsec = b.path("lib/bsec");
    const local_bme68x = b.path("lib/bme68x");
    const local_lib = b.path("lib/libalgobsec.a");

    // Check if local files exist
    const has_local_bsec = if (std.fs.cwd().access(local_bsec.getPath(b), .{})) true else |_| false;
    const has_local_lib = if (std.fs.cwd().access(local_lib.getPath(b), .{})) true else |_| false;

    if (has_local_bsec and has_local_lib) {
        // Use bundled libraries
        exe.addIncludePath(local_bsec);
        exe.addIncludePath(local_bme68x);
        exe.addCSourceFile(.{
            .file = b.path("lib/bme68x/bme68x.c"),
            .flags = &.{"-std=c99"},
        });
        exe.addObjectFile(local_lib);
    } else {
        // Fallback to pkg-config / system libraries
        exe.linkSystemLibrary("bsec");
        exe.linkSystemLibrary("bme68x");
    }

    exe.linkLibC();
}
