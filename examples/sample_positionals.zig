// SPDX-FileCopyrightText: 2023-2025 David Castañon Belloso <d4c7@proton.me>
// SPDX-License-Identifier: EUPL-1.2
// This file is part of zarg project (https://github.com/d4c7/zarg)

const std = @import("std");
const zarg = @import("zarg");
const Checks = zarg.Checks;
const option = zarg.option;
const options = zarg.options;
const flag = zarg.flag;
const help = zarg.help;
const positional = zarg.positional;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const clp = comptime zarg.CommandLineParser.init(.{
        .params = &[_]zarg.Param{
            positional(.{ //
                .name = "src",
                .parser = "DIR",
                .check = Checks.Dir(.{ .mode = .read_only }).f,
            }),
            positional(.{ //
                .name = "dst",
                .parser = "DIR",
                .check = Checks.Dir(.{ .mode = .read_only }).f,
            }),
            flag(.{ .long = "flag", .short = "f", .help = "This is a flag." }),
            help(.{ .long = "help", .short = "h", .help = "Shows this help." }),
        },
    });

    var s = clp.parseArgs(allocator);
    defer s.deinit();

    if (s.helpRequested()) {
        try s.printHelp(std.io.getStdErr().writer());
        return;
    }

    if (s.hasProblems()) {
        try s.printProblems(std.io.getStdErr().writer(), .all_problems);
        return;
    }
    std.debug.print("src: {any}\n", .{s.arg.src});
    std.debug.print("dst: {any}\n", .{s.arg.dst});
}
