// SPDX-FileCopyrightText: 2023-2025 David Castañon Belloso <d4c7@proton.me>
// SPDX-License-Identifier: EUPL-1.2
// This file is part of zarg project (https://github.com/d4c7/zarg)

const std = @import("std");
const zarg = @import("zarg");
const Parsers = zarg.Parsers;
const Check = zarg.Checks;
const builtin = @import("builtin");
const option = zarg.option;
const multiOption = zarg.multiOption;
const flag = zarg.flag;
const flagHelp = zarg.flagHelp;
const singlePositional = zarg.singlePositional;
const multiPositional = zarg.multiPositional;
pub const AutocompleteShellEnum = enum {
    bash,
    zsh,
};

pub fn main() !void {
    const parsers = Parsers.List ++ [_]Parsers.Parser{ //
        Parsers.enumParser("AUTOCOMPLETE-SHELL", AutocompleteShellEnum, null),
    };
    //TODO: hidden params from regular help? no no
    const autocmplete_params = [_]zarg.Param{
        option(.{ //
            .long = "autocomplete-from",
            .parser = "SIZE",
            .help = "Autocomplete from absolute command line position",
            .must = false,
        }),
        option(.{ //
            .long = "autocomplete-script",
            .parser = "AUTOCOMPLETE-SHELL",
            .default = @tagName(AutocompleteShellEnum.bash),
            .help = "Autocomplete shell script language",
        }),
    };

    const clp = zarg.CommandLineParser.init(.{
        .parsers = &parsers,
        .params = &([_]zarg.Param{
            singlePositional(.{
                .name = "string",
                .parser = "STR",
                .help = "Any string.",
            }),
            flagHelp(.{ //
                .long = "help",
                .short = "h",
                .help = "Shows this help.",
            }),
            option(.{ //
                .long = "option",
                .short = "o",
                .parser = "STR",
                .default = "1",
                .help = "Any option.",
            }),
        } ++ autocmplete_params),
    });

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var args = std.process.args();

    var s = clp.parse(&args, allocator, .{});
    defer s.deinit();

    if (s.arg.@"autocomplete-from") |index| {
        std.debug.print("autocomplete from {d}\n", .{index});
        //const position = 1;
        //const p = s.getArgParser(index);
        //const res = clp.autocomplete(s, index, position);
        //std.debug.print("{s}", .{res});
        return;
    }

    if (s.helpRequested()) {
        try s.printHelp(std.io.getStdErr().writer());
        return;
    }
    if (s.hasProblems()) {
        try s.printProblems(std.io.getStdErr().writer(), .all_problems);
        return;
    }

    std.debug.print("{any}\n", .{s.arg.string});
}
