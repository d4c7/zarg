// SPDX-FileCopyrightText: 2023-2025 David Castañon Belloso <d4c7@proton.me>
// SPDX-License-Identifier: EUPL-1.2
// This file is part of zarg project (https://github.com/d4c7/zarg)

const std = @import("std");
const zarg = @import("./zarg.zig");
const builtin = std.builtin;
const expectError = std.testing.expectError;

const option = zarg.option;
const options = zarg.options;
const flag = zarg.flag;
const help = zarg.help;
const positional = zarg.positional;
const positionals = zarg.positionals;

fn expectEquiStructs(expected: anytype, actual: anytype) !void {
    switch (@typeInfo(@TypeOf(actual))) {
        .@"struct" => |structType| {
            inline for (structType.fields) |field| {
                switch (@typeInfo(field.type)) {
                    .@"struct" => {
                        expectEquiStructs(@field(expected, field.name), @field(actual, field.name));
                    },
                    else => try std.testing.expectEqual(@field(expected, field.name), @field(actual, field.name)),
                }
            }
        },
        else => {
            try std.testing.expectEqual(expected, actual);
        },
    }
}

const TestIterator = struct {
    sequence: []const [:0]const u8,
    index: usize = 0,

    pub fn init(tuple: anytype) TestIterator {
        return TestIterator{ .sequence = &tuple };
    }

    pub fn next(self: *@This()) ?[:0]const u8 {
        if (self.index >= self.sequence.len)
            return null;
        const result = self.sequence[self.index];
        self.index += 1;
        return result;
    }
};

fn parse(comptime opts: []const zarg.Param, comptime args: anytype, comptime expected_args: anytype) !void {
    try parseFull(opts, args, expected_args, .{});
}

fn parseFull(
    comptime opts: []const zarg.Param,
    comptime args: anytype,
    comptime expected_args: anytype,
    comptime cfg: zarg.Opts,
) !void {
    const parser = zarg.CommandLineParser.init(.{ .params = opts, .opts = cfg });
    var it = TestIterator.init(args);
    var s = parser.parse(&it, std.testing.allocator, .{});
    defer s.deinit();
    if (s.hasProblems()) {
        return s.problems.items[0].err;
    }
    try expectEquiStructs(expected_args, s.arg);
    // try std.testing.expectEqualDeep(expected_args, s.option);
    // try std.testing.expectEqualSlices([]const u8, expected_positionals, s.positionals);
}

test "invalid empty optional argument" {
    try expectError(error.MalformedOption, parse(&[_]zarg.Param{flag(.{
        .long = "flag",
    })}, .{ "exe", "--=" }, struct {
        flag: bool = false,
    }{}));
}

test "end of optional arguments" {
    try parse(
        &[_]zarg.Param{ flag(.{
            .long = "flag",
        }), positional(.{}) },
        .{ "exe", "--", "--flag" },
        struct {
            flag: bool = false,
            positional: ?[]const u8 = "--flag",
        }{},
    );
}

test "multi-options" {
    try parse(&[_]zarg.Param{
        flag(.{
            .short = "a",
        }),
        flag(.{
            .short = "b",
        }),
    }, .{ "exe", "-ab" }, struct {
        a: bool = true,
        b: bool = true,
    }{});
}

test "flag with arg cannot be multi option when it's not the lastone" {
    try expectError(error.ExpectedOptionArg, parse(&[_]zarg.Param{
        option(.{
            .short = "a",
            .parser = "SIZE",
        }),
        flag(.{
            .short = "b",
        }),
    }, .{ "exe", "-ab" }, struct {
        a: ?usize = null,
        b: bool = false,
    }{}));
}

test "flag with arg can be multi option when it's the lastone" {
    try parse(&[_]zarg.Param{
        option(.{
            .short = "a",
            .parser = "SIZE",
        }),
        flag(.{
            .short = "b",
        }),
    }, .{ "exe", "-ba", "32" }, struct {
        a: ?usize = 32,
        b: bool = true,
    }{});
}

test "incomplete option name without collision is not allowed" {
    try expectError(error.UnrecognizedOption, parse(&[_]zarg.Param{flag(.{
        .long = "flag",
    })}, .{ "exe", "--f" }, struct {
        flag: bool = true,
    }{}));
}

test "flag with argument after space is positional" {
    try parse(
        &[_]zarg.Param{ flag(.{
            .long = "flag",
        }), positional(.{}) },
        .{ "exe", "--flag", "false" },
        struct { flag: bool = true, positional: ?[]const u8 = "false" }{},
    );
}

test "flag with argument after equals is the option argument" {
    try parse(&[_]zarg.Param{option(.{ .long = "bool", .parser = "BOOL" })}, .{ "exe", "--bool=false" }, struct {
        bool: ?bool = false,
    }{});
}

test "flag with valid bool arguments" {
    const map = .{
        .{ "true", true },
        .{ "false", false },
        .{ "yes", true },
        .{ "no", false },
        .{ "y", true },
        .{ "n", false },
    };
    inline for (map) |k| {
        try parse(
            &[_]zarg.Param{option(.{
                .long = "flag",
                .parser = "BOOL",
            })},
            .{ "exe", "--flag=" ++ k[0] },
            struct { flag: ?bool = k[1] }{},
        );
    }
}

test "flag with invalid bool argument" {
    const map = .{
        .{ "True", true },
        .{ "False", false },
        .{ "Yes", true },
        .{ "No", false },
        .{ "Y", true },
        .{ "N", false },
    };
    inline for (map) |k| {
        try expectError(error.NotABooleanValue, parse(
            &[_]zarg.Param{option(.{
                .long = "flag",
                .parser = "BOOL",
            })},
            .{ "exe", "--flag=" ++ k[0] },
            struct { flag: ?bool = k[1] }{},
        ));
    }
}

test "short option with arg" {
    try parse(&[_]zarg.Param{
        option(.{
            .short = "a",
            .parser = "SIZE",
        }),
    }, .{ "exe", "-a", "32" }, struct {
        a: ?usize = 32,
    }{});
}

test "short option with required arg" {
    try expectError(error.ExpectedOptionArg, parse(&[_]zarg.Param{option(.{
        .short = "a",
        .parser = "SIZE",
    })}, .{ "exe", "-a" }, struct {
        a: ?usize = 32,
    }{}));
}

test "use short or long option with arg using short" {
    try parse(&[_]zarg.Param{option(.{
        .long = "int",
        .short = "i",
        .parser = "SIZE",
    })}, .{ "exe", "-i", "32" }, struct {
        int: ?usize = 32,
    }{});
}

test "use short or long option with arg usign long" {
    try parse(&[_]zarg.Param{
        option(.{
            .long = "int",
            .short = "i",
            .parser = "SIZE",
        }),
    }, .{ "exe", "--int", "32" }, struct {
        int: ?usize = 32,
    }{});
}

test "required option value" {
    try parse(&[_]zarg.Param{
        option(.{ .long = "int", .short = "i", .parser = "SIZE", .default = "32" }),
    }, .{ "exe", "--int", "16" }, struct {
        int: usize = 16,
    }{});
}

test "custom option-arg separator fail" {
    try expectError(error.MalformedOption, parse(&[_]zarg.Param{option(.{ .long = "int", .short = "i", .parser = "SIZE", .default = "32" })}, .{ "exe", "--int:=16" }, struct { int: usize = 16 }{}));
}

test "custom option-arg separator" {
    try parseFull(&[_]zarg.Param{option(.{ .long = "int", .short = "i", .parser = "SIZE", .default = "32" })}, .{ "exe", "--int:=16" }, struct { int: usize = 16 }{}, .{ .optionArgSeparator = ":=" });
}

test "get error details" {
    try parse(&[_]zarg.Param{option(.{ .long = "int", .short = "i", .parser = "SIZE", .default = "32" })}, .{ "exe", "--int=16" }, struct { int: usize = 16 }{});
}
