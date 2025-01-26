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
const singlePositional = zarg.singlePositional;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const clp = comptime zarg.CommandLineParser.init(.{
        .header =
        \\  ______ _ _ __ __ _ 
        \\ |_  / _` | '__/ _` |
        \\  / / (_| | | | (_| |
        \\ /___\__,_|_|  \__, |
        \\               |___/ 
        ,
        .params = &[_]zarg.Param{
            flagHelp(.{ .long = "help", .short = "h", .help = "Shows this help." }),
            flag(.{ .long = "version", .help = "Output version information and exit." }),
            flag(.{ .long = "verbose", .short = "v", .help = "Enable verbose output." }),
            option(.{ .long = "port", .short = "p", .parser = "TCP_PORT", .default = "1234", .help = "Listening Port." }),
            option(.{ .long = "host", .short = "H", .parser = "TCP_HOST", .default = "localhost", .help = "Host name" }),
            singlePositional(.{ .parser = "DIR", .default = ".", .check = &Checks.Dir(.{ .mode = .read_only }).f }),
        }, //
        .desc = "This command starts an HTTP Server and serves static content from directory DIR.", //
        .footer = "More info: <https://d4c7.github.io/zig-zagueando/>.",
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

    std.debug.print("dir: {s}\n", .{s.arg.positional});
    std.debug.print("port: {d}\n", .{s.arg.port});
    std.debug.print("host: {s}\n", .{s.arg.host});
}
