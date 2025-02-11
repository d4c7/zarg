// SPDX-FileCopyrightText: 2023-2025 David Castañon Belloso <d4c7@proton.me>
// SPDX-License-Identifier: EUPL-1.2
// This file is part of zarg project (https://github.com/d4c7/zarg)

const std = @import("std");

//Fragment / Item / Part / Component /chunk/ Section/ Segment  /element
pub const ArgItemType = enum { short, long, value, malformed_option };

pub const ArgItem = struct {
    arg: []const u8,
    num: usize = 0,
    t: ArgItemType,
    argSrc: []const u8,
    argSrcFrom: usize = 0,
    arglessReq: bool = false,
};

fn unquote(str: []const u8) []const u8 {
    const l = str.len;
    if (l > 1 and (str[0] == '"' or str[0] == '\'') and str[0] == str[l - 1]) {
        return str[1 .. l - 1];
    }
    return str;
}

pub fn ArgsController(comptime T: type) type {
    return struct {
        last: ?ArgItem = null,
        nxt: ?ArgItem = null,
        use_last: bool = false,
        rest: []const u8 = "",
        num: usize = 0,
        state: State = .normal,
        argIterator: T,
        optionArgSeparator: []const u8,

        const State = enum {
            normal,
            multi_short_option,
            only_values,
        };

        const Self = @This();

        pub fn knownOptionArgument(self: Self) ?ArgItem {
            return self.nxt;
        }

        pub fn skipKnownOptionArgument(self: *Self) void {
            self.nxt = null;
        }

        fn malformedOption(self: *Self, arg: []const u8, argSrc: []const u8) ?ArgItem {
            self.last = ArgItem{ .arg = arg, .num = self.num, .t = .malformed_option, .argSrc = argSrc };
            return self.last;
        }

        fn shortOption(self: *Self, arg: []const u8, argSrc: []const u8) ?ArgItem {
            self.last = ArgItem{ .arg = arg, .num = self.num, .t = .short, .argSrc = argSrc, .arglessReq = self.state == .multi_short_option };
            return self.last;
        }

        fn longOption(self: *Self, arg: []const u8, argSrc: []const u8) ?ArgItem {
            self.last = ArgItem{ .arg = arg, .num = self.num, .t = .long, .argSrc = argSrc };
            return self.last;
        }

        fn value(self: *Self, arg: []const u8, argSrc: []const u8) ?ArgItem {
            self.last = ArgItem{ .arg = arg, .num = self.num, .t = .value, .argSrc = argSrc };
            return self.last;
        }

        pub fn rawNext(self: *Self) ?[]const u8 {
            if (self.argIterator.next()) |n| {
                self.num += 1;
                return n;
            }
            return null;
        }

        pub fn next(self: *Self) ?ArgItem {
            if (self.use_last) {
                self.use_last = false;
                return self.last;
            }

            if (self.state == .multi_short_option) {
                const arg = self.rest[0..1];
                self.rest = self.rest[1..];
                if (self.rest.len == 0) {
                    self.state = .normal;
                }
                return self.shortOption(arg, self.last.?.argSrc);
            }

            if (self.nxt != null) {
                self.last = self.nxt;
                self.nxt = null;
                return self.last;
            }

            if (self.rawNext()) |raw| {
                if (self.state == .only_values) {
                    return self.value(raw, raw);
                }
                var arg = raw;
                if (arg.len > 1 and arg[0] == '-') {
                    const dbldash = arg[1] == '-';
                    if (dbldash and arg.len == 2) {
                        return self.value(arg, raw);
                    }
                    // starts with '-' but is not a single '-' and we're not processing optionals yet
                    {
                        var i: usize = if (dbldash) 2 else 1;
                        while (i < arg.len) : (i += 1) {
                            switch (arg[i]) {
                                '?', '@', '#', '!' => if (dbldash) return self.malformedOption(arg, raw),
                                '0'...'9', 'A'...'Z', 'a'...'z' => continue,
                                '-', '_' => if (!dbldash) return self.malformedOption(arg, raw),
                                else => {
                                    if ((!dbldash and i > 1) or (dbldash and i > 2)) {
                                        if (std.mem.startsWith(u8, arg[i..], self.optionArgSeparator)) {
                                            const n = i + self.optionArgSeparator.len;
                                            self.nxt = ArgItem{ .arg = unquote(arg[n..]), .num = self.num, .t = .value, .argSrc = raw, .argSrcFrom = n };
                                            arg = arg[0..i];
                                            //continue to check if long, short, or '--' arg
                                            break;
                                        }
                                    }
                                    return self.malformedOption(arg, raw);
                                },
                            }
                        }
                    }
                    // if starts with '--', maybe a long option
                    if (dbldash) {
                        //it's a long option
                        return self.longOption(arg[2..], raw);
                    } else {
                        //can be multi-short-option if len>2
                        if (arg.len > 2) {
                            self.state = .multi_short_option;
                            self.rest = arg[2..];
                        }
                        //return first (or full) part as short option
                        return self.shortOption(arg[1..2], raw);
                    }
                }
                return self.value(raw, raw);
            }
            self.last = null;
            return null;
        }

        pub fn rollback(self: *Self) void {
            self.use_last = true;
        }
    };
}

fn testGeneralCmdLine(input_cmd_line: []const u8, expected_args: []const ArgItem) !void {
    var it = try std.process.ArgIteratorGeneral(.{}).init(std.testing.allocator, input_cmd_line);
    defer it.deinit();

    var ctrl = ArgsController(*std.process.ArgIteratorGeneral(.{})){ .argIterator = &it, .optionArgSeparator = "=" };
    for (expected_args) |expected_arg| {
        const arg = ctrl.next().?;
        //std.debug.print("\n-> {any}\n", .{arg});
        try std.testing.expectEqualDeep(expected_arg, arg);
    }
    try std.testing.expect(ctrl.next() == null);
}

test "arg controller tokens" {
    try testGeneralCmdLine("-0 -x=1 -y= -abc=1 --de --fg=12 -- -  -= --= -=1 --=2 -vp 1234 -h='quoted' -i='q=1' -b='1'0'", &.{
        .{
            .arg = "0",
            .t = .short,
            .num = 1,
            .argSrc = "-0",
            .argSrcFrom = 0,
        },
        .{
            .arg = "x",
            .t = .short,
            .num = 2,
            .argSrc = "-x=1",
            .argSrcFrom = 0,
        },
        .{
            .arg = "1",
            .t = .value,
            .num = 2,
            .argSrc = "-x=1",
            .argSrcFrom = 3,
        },
        .{
            .arg = "y",
            .t = .short,
            .num = 3,
            .argSrc = "-y=",
            .argSrcFrom = 0,
        },
        .{
            .arg = "",
            .t = .value,
            .num = 3,
            .argSrc = "-y=",
            .argSrcFrom = 3,
        },
        .{
            .arg = "a",
            .t = .short,
            .num = 4,
            .argSrc = "-abc=1",
            .arglessReq = true,
            .argSrcFrom = 0,
        },
        .{
            .arg = "b",
            .t = .short,
            .num = 4,
            .argSrc = "-abc=1",
            .arglessReq = true,
            .argSrcFrom = 0,
        },
        .{
            .arg = "c",
            .t = .short,
            .num = 4,
            .argSrc = "-abc=1",
            .argSrcFrom = 0,
        },
        .{
            .arg = "1",
            .t = .value,
            .num = 4,
            .argSrc = "-abc=1",
            .argSrcFrom = 5,
        },
        .{
            .arg = "de",
            .t = .long,
            .num = 5,
            .argSrc = "--de",
            .argSrcFrom = 0,
        },
        .{
            .arg = "fg",
            .t = .long,
            .num = 6,
            .argSrc = "--fg=12",
            .argSrcFrom = 0,
        },
        .{
            .arg = "12",
            .t = .value,
            .num = 6,
            .argSrc = "--fg=12",
            .argSrcFrom = 5,
        },
        .{
            .arg = "--",
            .t = .value,
            .num = 7,
            .argSrc = "--",
            .argSrcFrom = 0,
        },
        .{
            .arg = "-",
            .t = .value,
            .num = 8,
            .argSrc = "-",
            .argSrcFrom = 0,
        },
        .{
            .arg = "-=",
            .t = .malformed_option,
            .num = 9,
            .argSrc = "-=",
            .argSrcFrom = 0,
        },
        .{
            .arg = "--=",
            .t = .malformed_option,
            .num = 10,
            .argSrc = "--=",
            .argSrcFrom = 0,
        },
        .{
            .arg = "-=1",
            .t = .malformed_option,
            .num = 11,
            .argSrc = "-=1",
            .argSrcFrom = 0,
        },
        .{
            .arg = "--=2",
            .t = .malformed_option,
            .num = 12,
            .argSrc = "--=2",
            .argSrcFrom = 0,
        },
        .{ .arg = "v", .t = .short, .num = 13, .argSrc = "-vp", .arglessReq = true },
        .{
            .arg = "p",
            .t = .short,
            .num = 13,
            .argSrc = "-vp",
            .argSrcFrom = 0,
        },
        .{
            .arg = "1234",
            .t = .value,
            .num = 14,
            .argSrc = "1234",
            .argSrcFrom = 0,
        },
        .{
            .arg = "h",
            .t = .short,
            .num = 15,
            .argSrc = "-h='quoted'",
            .argSrcFrom = 0,
        },
        .{
            .arg = "quoted",
            .t = .value,
            .num = 15,
            .argSrc = "-h='quoted'",
            .argSrcFrom = 3,
        },
        .{
            .arg = "i",
            .t = .short,
            .num = 16,
            .argSrc = "-i='q=1'",
            .argSrcFrom = 0,
        },
        .{
            .arg = "q=1",
            .t = .value,
            .num = 16,
            .argSrc = "-i='q=1'",
            .argSrcFrom = 3,
        },
        .{
            .arg = "b",
            .t = .short,
            .num = 17,
            .argSrc = "-b='1'0'",
            .argSrcFrom = 0,
        },
        .{
            .arg = "1'0",
            .t = .value,
            .num = 17,
            .argSrc = "-b='1'0'",
            .argSrcFrom = 3,
        },
    });
}
