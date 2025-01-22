// SPDX-FileCopyrightText: 2023 David Castañon Belloso <d4c7@proton.me>
// SPDX-License-Identifier: EUPL-1.2
// This file is part of zig-argueando project (https://github.com/d4c7/zig-argueando)

const std = @import("std");
const Module = std.build.Module;
const FileSource = std.build.FileSource;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/argueando_test.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    const argueandoModule = b.addModule("argueando", .{
        .root_source_file = b.path("src/argueando.zig"),
        .target = target,
        .optimize = optimize,
    });

    const examples_step = b.step("examples", "Build examples");
    for ([_][]const u8{
        "sample_complete",
        "sample_head_and_foot",
        "sample_json_args",
    }) |exe_name| {
        const exe = b.addExecutable(.{
            .name = exe_name,
            .root_source_file = b.path(b.fmt("examples/{s}.zig", .{exe_name})),
            .target = target,
            .optimize = optimize,
        });
        const install_exe = b.addInstallArtifact(exe, .{});
        exe.root_module.addImport("argueando", argueandoModule);
        examples_step.dependOn(&exe.step);
        examples_step.dependOn(&install_exe.step);
    }
}
