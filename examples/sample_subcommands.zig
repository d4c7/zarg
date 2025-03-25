// SPDX-FileCopyrightText: 2023-2025 David Castañon Belloso <d4c7@proton.me>
// SPDX-License-Identifier: EUPL-1.2
// This file is part of zarg project (https://github.com/d4c7/zarg)

const std = @import("std");
const zarg = @import("zarg");
const Parsers = zarg.Parsers;
const Check = zarg.Checks;
const builtin = @import("builtin");
const option = zarg.option;
const options = zarg.options;
const flag = zarg.flag;
const help = zarg.help;
const positional = zarg.positional;
const positionals = zarg.positionals;

pub const CommandEnum = enum {
    command1,
    command2,
};

pub fn main() !void {
    const parsers = Parsers.List ++ [_]Parsers.Parser{ //
        Parsers.enumParser("COMMAND", CommandEnum, null),
    };

    const clp = zarg.CommandLineParser.init(.{
        .desc = "ZARG Sample Command Line Parser",
        .parsers = &parsers,
        .params = &[_]zarg.Param{
            positional(.{
                .name = "command",
                .parser = "COMMAND",
                //.default = @tagName(CommandEnum.command1),
                .help = "A command",
            }),
            help(.{ .long = "help", .short = "h", .help = "Shows this help." }),
            option(.{ .long = "option", .short = "o", .parser = "STR", .default = "1", .help = "An option" }),
        },
        .footer = "Footer",
        .opts = .{ .processMode = .process_until_first_positional, .problemMode = .continue_on_problem },
    });

    const command1_clp = zarg.CommandLineParser.init(.{
        .desc = "Command 1",
        .params = &[_]zarg.Param{
            positional(.{
                .name = "Value",
                .parser = "STR",
                .help = "A value",
            }),
            help(.{ .long = "help", .short = "h", .help = "Shows this help." }),
            option(.{ .long = "option", .short = "o", .parser = "STR", .default = "2", .help = "An option" }),
        },
        .footer = "Footer Command 1",
        .opts = .{ //
            .processMode = .process_all_args,
            .problemMode = .continue_on_problem,
        },
    });

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var args = std.process.args();

    var s = clp.parse(&args, allocator, .{});
    defer s.deinit();

    if (s.helpRequested()) {
        try s.printHelp(std.io.getStdErr().writer());
        return;
    }
    if (s.hasProblems()) {
        try s.printProblems(std.io.getStdErr().writer(), .all_problems);
        return;
    }

    if (s.arg.command) |p| {
        switch (p) {
            .command1 => {
                var cmd1 = command1_clp.parse(&args, allocator, .{ .exe = s.exe, .argOffset = s.lastArgIndex+1 });
                defer cmd1.deinit();
                if (cmd1.helpRequested()) {
                    try cmd1.printHelp(std.io.getStdErr().writer());
                    return;
                }
                if (cmd1.hasProblems()) {
                    try cmd1.printProblems(std.io.getStdErr().writer(), .all_problems);
                    return;
                }
            },
            .command2 => { //...
            },
        }
    }
}
