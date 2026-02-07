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

pub const MyTypeError = error{InvalidMyTypeValue};

pub fn myParseAllocFn(comptime parser: Parsers.Parser, allocator: anytype, recv: anytype, str: []const u8) !void {
    const T = parser.type;
    const result = try allocator.alloc(u8, str.len);
    @memcpy(result, str);
    const rec = @as(*T, recv);
    rec.* = result;
}

pub fn myParseFreeFn(comptime parser: Parsers.Parser, allocator: anytype, rec: anytype) void {
    _ = parser;
    allocator.free(rec);
}

pub fn myParserFn(comptime parser: Parsers.Parser, allocator: anytype, recv: anytype, str: []const u8) !void {
    _ = allocator;
    const T = parser.type;
    const rec = @as(*T, recv);
    const value = if (std.mem.eql(u8, "A", str)) "A" else if (std.mem.eql(u8, "B", str)) "B" else return MyTypeError.InvalidMyTypeValue;
    rec.* = value;
}

pub const ColorEnum = enum {
    red,
    green,
    blue,
    yellow,
    orange,
};

pub fn main() !void {
    const parsers = Parsers.List ++ [_]Parsers.Parser{ //
        .{ .parseFn = myParserFn, .name = "MY_TYPE", .type = []const u8, .help = "My custom type is A or B" }, //
        .{ .parseFn = myParseAllocFn, .freeFn = myParseFreeFn, .name = "MY_TYPE_ALLOC", .type = []const u8, .help = "My custom type with alloc mem" }, //
        Parsers.enumParser("COLOR", ColorEnum, null),
    };

    @setEvalBranchQuota(2000);
    const clp = zarg.CommandLineParser.init(.{
        .desc = "Sample Command Line Parser zarg",
        .parsers = &parsers,
        .params = &[_]zarg.Param{
            positionals(.{ //
                .name = "Directory",
                .min = 1,
                .max = 5,
                .parser = "DIR",
                .check = Check.Dir(.{ .mode = .read_only }).f,
                .help = "Directory path with read permission",
            }),
            help(.{ .long = "help", .short = "h", .help = "Shows this help." }),
            help(.{ .short = "?", .help = "Shows this help too." }),
            flag(.{ .long = "verbose", .short = "v", .help = "Enable verbose output." }),

            flag(.{ .long = "version", .help = "Output version and exit." }),

            option(.{ .long = "alloc", .parser = "MY_TYPE_ALLOC", .default = "ONE", .help = "This is a custom type with allocation\nUse it with care." }),
            option(.{ .long = "alloc_opt", .parser = "MY_TYPE_ALLOC", .help = "This is a custom type with allocation but optional\nUse it with care." }),
            options(.{ .long = "color", .min = 1, .max = 10, .short = "c", .parser = "COLOR", .help = "A color for your life." }),
            option(.{ .long = "🧘", .parser = "MY_TYPE", .default = "A", .help = "This is a custom type optional argument\nUse it with care." }),
            option(.{ .long = "port", .short = "p", .parser = "TCP_PORT", .default = "1234", .help = "Server listen port." }),
            option(.{ .long = "size", .parser = "SIZE", .default = "3K", .help = "Size for something." }),
            option(.{ .long = "size2", .parser = "SIZE", .default = "8K", .help = "Size 2 for something." }),
            options(.{
                .long = "header",
                .short = "H",
                .parser = "STR",
                .help = "HTTP header param.",
                .min = 1,
                .max = 3,
                .defaults = &[_][]const u8{ "A", "B" },
            }),
            flag(.{
                .long = "flag",
            }),
            options(.{ .long = "array0a1", .parser = "STR", .help = "Help lines", .min = 0, .max = 1 }),
            options(.{ .long = "array0a2", .parser = "STR", .help = "Help lines", .min = 0, .max = 2 }),
            options(.{ .long = "array0aN", .parser = "STR", .help = "Help lines", .min = 0 }),
            options(.{ .long = "array1a1", .parser = "STR", .help = "Help lines", .min = 1, .max = 1 }),
            options(.{ .long = "array1a2", .parser = "STR", .help = "Help lines", .min = 1, .max = 2 }),
            options(.{ .long = "array1aN", .parser = "STR", .help = "Help lines", .min = 1 }),
        },
        .footer =
        \\Exit status:
        \\  0  if OK,
        \\  1  if minor problems (e.g., cannot access subdirectory),
        \\  2  if serious trouble (e.g., cannot access command-line argument).
        \\
        \\More info: <https://d4c7.github.io/zig-zagueando/>.
        ,
        .opts = .{ .processMode = .process_all_args, .problemMode = .continue_on_problem },
    });

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var args = std.process.args();

    var s = clp.parse(&args, allocator, .{});
    defer s.deinit();

    var stderr_buffer: [1024]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);
    const stderr = &stderr_writer.interface;

    if (s.helpRequested()) {
        try s.printHelp(stderr);
        try stderr.flush();
        return;
    }

    if (s.arg.version) {
        std.debug.print("Version: {s} α {s}\n", .{ std.fs.path.basename(s.exe), @tagName(builtin.target.cpu.arch) });
        std.process.exit(0);
    }

    if (s.hasProblems()) {
        try s.printProblems(stderr, .all_problems);
        try stderr.flush();
        return;
    }
}
