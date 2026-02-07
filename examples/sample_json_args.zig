// SPDX-FileCopyrightText: 2023-2025 David Castañon Belloso <d4c7@proton.me>
// SPDX-License-Identifier: EUPL-1.2
// This file is part of zarg project (https://github.com/d4c7/zarg)

const std = @import("std");
const zarg = @import("zarg");
const Parsers = zarg.Parsers;
const option = zarg.option;
const options = zarg.options;
const flag = zarg.flag;
const help = zarg.help;
const positional = zarg.positional;
const positionals = zarg.positionals;

pub const ColorEnum = enum {
    red,
    green,
    blue,
    yellow,
    orange,
};

const E = enum {
    one,
    two,
    three,
    five,
};

const U = union(E) {
    one: i32,
    two: f32,
    three,
    five: struct {
        a: f32,
        b: i128,
    },
};

const Config = struct {
    vals: struct {
        testing: u8,
        testing2: u16,
        production: ColorEnum,
    },
    more: ?struct {
        list1: []u8,
        str: []const u8,
        list: []Config,
        ptr: *Config,
        t: U,
        x: struct { U, ColorEnum },
    },
    uptime: u64,
};

const my_json =
    \\
    \\{
    \\    "vals": {
    \\        "testing": 1,
    \\        "testing2": 2,
    \\        "production": "red"
    \\    },
    \\    "more": null,
    \\    "uptime": 9999
    \\}
;

pub fn main() !void {
    const parsers = Parsers.List ++ [_]Parsers.Parser{ //
        Parsers.jsonParser("JSON-CONFIG", Config, null),
    };

    const clp = zarg.CommandLineParser.init(.{
        .parsers = &parsers,
        .params = &[_]zarg.Param{
            help(.{ .long = "help", .short = "h", .help = "Shows this help." }),
            option(.{ .long = "json", .parser = "JSON", .default = my_json, .help = "This is a dynamic json object type" }),
            option(.{ .long = "json_config", .parser = "JSON-CONFIG", .default = my_json, .help = "This is a json object type" }),
        },
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

    if (s.hasProblems()) {
        try s.printProblems(stderr, .all_problems);
        try stderr.flush();
        return;
    }

    std.debug.print("--> {any}\n", .{s.arg.json});
    std.debug.print("--> {any}\n", .{s.arg.json_config});
}
