// SPDX-FileCopyrightText: 2023 David Castañon Belloso <d4c7@proton.me>
// SPDX-License-Identifier: EUPL-1.2
// This file is part of zarg project (https://github.com/d4c7/zarg)

const std = @import("std");
const Module = std.build.Module;
const FileSource = std.build.FileSource;
const process = std.process;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // tests
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // zarg module
    const zargModule = b.addModule("zarg", .{
        .root_source_file = b.path("src/zarg.zig"),
        .target = target,
        .optimize = optimize,
    });

    // zarg examples
    const examples_step = b.step("examples", "Build examples");
    for ([_][]const u8{
        "sample_complete",
        "sample_head_and_foot",
        "sample_json_args",
        "sample_multipositional",
    }) |exe_name| {
        const exe = b.addExecutable(.{
            .name = exe_name,
            .root_source_file = b.path(b.fmt("examples/{s}.zig", .{exe_name})),
            .target = target,
            .optimize = optimize,
        });
        const install_exe = b.addInstallArtifact(exe, .{});
        exe.root_module.addImport("zarg", zargModule);
        examples_step.dependOn(&exe.step);
        examples_step.dependOn(&install_exe.step);
    }

    // cover
    const binPath = b.pathJoin(&.{ b.install_path, "bin" });
    std.fs.cwd().makePath(binPath) catch std.process.exit(1);
    const coverExePath = b.pathJoin(&.{ binPath, "cover-test" });
    const mk_cover = b.addSystemCommand(&.{ "zig", "test", "--test-no-exec", b.fmt("-femit-bin={s}", .{coverExePath}), "src/tests.zig" });
    const run_cover = b.addSystemCommand(&.{
        "kcov",
        "--clean",
        "--include-pattern=src/",
        b.pathJoin(&.{ b.install_path, "coverture-report" }),
        coverExePath,
    });

    const cover_step = b.step("cover", "Generate test coverage report");
    cover_step.dependOn(&mk_cover.step);
    cover_step.dependOn(&run_cover.step);
}
