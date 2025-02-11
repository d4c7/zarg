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
            help(.{ .long = "help", .short = "h", .help = "Shows this help." }),
            option(.{ .long = "echo", .short = "e", .parser = "STR", .default = "echo", .help = "Echo." }),
        }, //
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

    std.debug.print("echo: {s}\n", .{s.arg.echo});
}
