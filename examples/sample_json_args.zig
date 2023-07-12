// SPDX-FileCopyrightText: 2023 David Castañon Belloso <d4c7@proton.me>
// SPDX-License-Identifier: EUPL-1.2
// This file is part of zig-argueando project (https://github.com/d4c7/zig-argueando)

const std = @import("std");
const Argueando = @import("argueando");
const Parsers = Argueando.Parsers;
const option = Argueando.option;
const multiOption = Argueando.multiOption;
const flag = Argueando.flag;
const flagHelp = Argueando.flagHelp;
const singlePositional = Argueando.singlePositional;
const multiPositional = Argueando.multiPositional;

pub const ColorEnum = enum {
    Red,
    Green,
    Blue,
    Yellow,
    Orange,
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
    \\        "production": "Red"
    \\    },
    \\    "more": null,
    \\    "uptime": 9999
    \\}
;

pub fn main() !void {
    const parsers = Parsers.List ++ [_]Parsers.Parser{ //
        Parsers.jsonParser("JSON-CONFIG", Config, null),
    };

    const clp = Argueando.CommandLineParser.init(.{
        .parsers = &parsers,
        .params = &[_]Argueando.Param{
            flagHelp(.{ .long = "help", .short = "h", .help = "Shows this help." }),
            option(.{ .long = "json", .parser = "JSON", .default = my_json, .help = "This is a dynamic json object type" }),
            option(.{ .long = "json_config", .parser = "JSON-CONFIG", .default = my_json, .help = "This is a json object type" }),
        },
    });

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var args = std.process.args();

    var s = clp.parse(&args, allocator);
    defer s.deinit();

    if (s.helpRequested()) {
        try s.printHelp(std.io.getStdErr().writer());
        return;
    }

    if (s.hasProblems()) {
        try s.printProblems(std.io.getStdErr().writer(), .AllProblems);
        return;
    }

    std.debug.print("--> {any}\n", .{s.arg.json});
    std.debug.print("--> {any}\n", .{s.arg.json_config});
}
