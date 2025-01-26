// SPDX-FileCopyrightText: 2023 David Castañon Belloso <d4c7@proton.me>
// SPDX-License-Identifier: EUPL-1.2
// This file is part of zarg project (https://github.com/d4c7/zarg)

const std = @import("std");
const zarg = @import("zarg");
const Checks = zarg.Checks;
const option = zarg.option;
const optionMulti = zarg.optionMulti;
const positionalsDef = zarg.positionalsDef;
const flag = zarg.flag;
const flagHelp = zarg.flagHelp;
const multiPositional = zarg.multiPositional;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const clp = comptime zarg.CommandLineParser.init(.{
        .params = &[_]zarg.Param{
            flagHelp(.{ .long = "help", .short = "h", .help = "Shows this help." }),
            multiPositional(.{ //
                .name = "Directory",
                .min = 1,
                .max = 5,
                .parser = "DIR",
                .defaults = &[_][]const u8{ ".", ".." },
                .check = Checks.Dir(.{ .mode = .read_only }).f,
            }),
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
    for (s.arg.positional.items) |i| {
        std.debug.print("readable dir: {s}\n", .{i});
    }
}
