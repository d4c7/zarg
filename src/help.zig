// SPDX-FileCopyrightText: 2023 David Castañon Belloso <d4c7@proton.me>
// SPDX-License-Identifier: EUPL-1.2
// This file is part of zarg project (https://github.com/d4c7/zarg)

const std = @import("std");
const Parsers = @import("parsers.zig");
const zarg = @import("zarg.zig");

pub const ComptimeHelp = struct {
    pub const DefaultHelpFlagText = "Display the help and exit.";

    const HelpStrings = struct {
        usage: []const u8,
        details: []const u8,
    };

    fn comptimeLines(comptime fmt: []const u8, comptime first: anytype, comptime next: anytype, comptime multiline: []const u8) []const u8 {
        comptime {
            var res: []const u8 = "";
            var it = std.mem.splitSequence(u8, multiline, "\n");
            if (it.next()) |line| {
                res = res ++ std.fmt.comptimePrint(fmt, first ++ .{line});
            } else {
                res = res ++ std.fmt.comptimePrint(fmt, first ++ .{""});
            }
            while (it.next()) |line| {
                res = res ++ std.fmt.comptimePrint(fmt, next ++ .{line});
            }
            return res;
        }
    }

    fn comptTimeRangeHelps(comptime param: []const u8, comptime min: usize, comptime max: usize) HelpStrings {
        var usage: []const u8 = "";
        var res: []const u8 = "";
        if (min == 0) {
            if (max == 1) {
                //  res = res ++ std.fmt.comptimePrint("It's optional", .{});
                usage = usage ++ std.fmt.comptimePrint("[{s}]", .{param});
            } else if (max == zarg.MaxArgs) {
                res = res ++ std.fmt.comptimePrint("Can be repeated.", .{});
                usage = usage ++ std.fmt.comptimePrint("[{s}]...", .{param});
            } else {
                res = res ++ std.fmt.comptimePrint("Can be repeated up to {d} times.", .{max});
                usage = usage ++ std.fmt.comptimePrint("[{s}]{{0..{d}}}", .{ param, max });
            }
        } else if (min == max) {
            if (min == 1) {
                res = res ++ std.fmt.comptimePrint("It's required and can be repeated.", .{});
                usage = usage ++ " " ++ param;
            } else {
                res = res ++ std.fmt.comptimePrint("Must be repeated {d} times.", .{min});
                usage = usage ++ std.fmt.comptimePrint("({s}){{{d}}}", .{ param, min });
            }
        } else if (max == zarg.MaxArgs) {
            res = res ++ std.fmt.comptimePrint("Must be repeated at least {d} times.", .{min});
            if (min == 1) {
                usage = usage ++ std.fmt.comptimePrint("({s})...", .{param});
            } else {
                usage = usage ++ std.fmt.comptimePrint("({s}){{{d}...}}", .{ param, min });
            }
        } else {
            res = res ++ std.fmt.comptimePrint("Must be repeated from {d} to {d} times.", .{ min, max });
            usage = usage ++ std.fmt.comptimePrint("({s}){{{d}..{d}}}", .{ param, min, max });
        }
        return .{
            .usage = usage,
            .details = res,
        };
    }

    //TODO: split options, posisitonals, so can insert commands and others
    //TODO: usage style - detailed, simple
    fn comptimeHelp(comptime self: zarg.CommandLineParser) HelpStrings {
        comptime {
            var res: []const u8 = "";
            var usage: []const u8 = "";

            if (self.desc.len > 0) {
                res = res ++ std.fmt.comptimePrint("\n{s}\n", .{self.desc});
            }

            const maxOptSz = e: {
                var mx: usize = 0;
                for (self.params) |param| {
                    switch (param.kind) {
                        .option => |opt| {
                            mx = @max(mx, opt.long.len + 2);
                            mx = @max(mx, opt.short.len + 1);
                        },
                        else => {},
                    }
                }
                break :e mx;
            };
            const maxTypeNameSz = e: {
                var mx: usize = 0;
                for (self.parsers) |parser| {
                    mx = @max(mx, parser.name.len);
                }
                break :e mx;
            };

            const maxOptSize = std.fmt.comptimePrint("{d}", .{maxOptSz + maxTypeNameSz + 5});
            const maxTypeNameSize = std.fmt.comptimePrint("{d}", .{maxTypeNameSz + 3});

            var positional: ?zarg.Positional = null;

            for (self.params, 0..) |param, pidx| {
                _ = pidx;
                switch (param.kind) {
                    .option => |opt| {
                        const short = opt.short.len > 0;
                        const long = opt.long.len > 0;
                        const both = short and long;

                        const optArg = switch (opt.format) {
                            .flag => "",
                            .single => |s| self.opts.optionArgSeparator ++ s.parser,
                            .multi => |m| self.opts.optionArgSeparator ++ m.parser,
                        };

                        const shortParam = if (short) ("-" ++ (opt.short ++ (if (long) ", " else (if (optArg.len > 0) optArg else " ")))) else "    ";
                        const longParam = if (long) ("--" ++ opt.long ++ optArg) else "";

                        const usageParam: []const u8 = (if (both) "(" else "") ++
                            (if (short) ("-" ++ opt.short) else "") ++
                            (if (short and long) "|" else "") ++
                            (if (long) ("--" ++ opt.long) else "") ++
                            (if (both) ")" else "") ++ optArg;

                        res = res ++ comptimeLines("\n  {s: <" ++ maxOptSize ++ "} {s}", .{shortParam ++ longParam}, .{""}, param.help);

                        switch (opt.format) {
                            .flag => {
                                usage = usage ++ " [" ++ usageParam ++ "]";
                            },
                            .single => |p| {
                                if (p.default) |def| {
                                    usage = usage ++ " [" ++ usageParam ++ "]";
                                    res = res ++ comptimeLines("\n  {s: <" ++ maxOptSize ++ "} {s}", .{""}, .{""}, "Default value: " ++ if (def.len == 0) "\"\"" else def);
                                } else {
                                    usage = usage ++ usageParam;
                                }
                            },
                            .multi => |m| {
                                if (m.defaults) |defs| {
                                    usage = usage ++ " [" ++ usageParam ++ "]";
                                    res = res ++ comptimeLines("\n  {s: <" ++ maxOptSize ++ "} {s}", .{""}, .{""}, "Default values: ");
                                    for (defs) |def| {
                                        res = res ++ comptimeLines("\n  {s: <" ++ maxOptSize ++ "} {s}", .{""}, .{""}, " - " ++ if (def.len == 0) "\"\"" else def);
                                    }
                                }
                                const helps = comptTimeRangeHelps(usageParam, m.min, m.max);
                                res = res ++ std.fmt.comptimePrint("\n  {s: <" ++ maxOptSize ++ "} {s}", .{ "", helps.details });
                                usage = usage ++ " " ++ helps.usage;
                            },
                        }

                        // if (@mod(pidx, 4) == 0) {
                        //    usage = usage ++ "\n   ";//TOOD: until width auto adjust available
                        //}
                    },
                    .positional => |p| positional = p,
                }
            }

            var first = true;
            for (self.parsers) |parser| {
                const used = e: {
                    for (self.params) |param| {
                        const strType = switch (param.kind) {
                            .option => |o| o.format,
                            .positional => |p| p.format,
                        };
                        switch (strType) {
                            .flag => {},
                            .single => |s| if (std.mem.eql(u8, s.parser, parser.name)) break :e true,
                            .multi => |m| if (std.mem.eql(u8, m.parser, parser.name)) break :e true,
                        }
                    }
                    break :e false;
                };

                if (used) {
                    if (first) {
                        res = res ++ "\n";
                        first = false;
                    }
                    res = res ++ comptimeLines("\n  {s: <" ++ maxTypeNameSize ++ "} {s}", .{parser.name}, .{""}, parser.help);
                }
            }

            if (positional) |a| {
                switch (a.format) {
                    .flag => {},
                    .single => |s| {
                        if (s.default) |def| {
                            _ = def;
                            usage = usage ++ " [" ++ s.parser ++ "]";
                        } else {
                            usage = usage ++ s.parser;
                        }
                    },
                    .multi => |m| {
                        const helps = comptTimeRangeHelps(m.parser, m.min, m.max);
                        usage = usage ++ " " ++ helps.usage;
                    },
                }
            }

            if (self.footer.len > 0) {
                res = res ++ std.fmt.comptimePrint("\n\n{s}", .{self.footer});
            }
            res = res ++ std.fmt.comptimePrint("\n", .{});
            return HelpStrings{ .usage = usage, .details = res };
        }
    }

    pub fn printUsage(comptime self: zarg.CommandLineParser, writer: anytype, exe: []const u8) !void {
        const baseName = std.fs.path.basename(exe);
        const help = comptime comptimeHelp(self);
        try writer.print("Usage: {s}{s}\n", .{ baseName, help.usage });
    }

    pub fn printHelp(comptime self: zarg.CommandLineParser, writer: anytype, exe: []const u8) !void {
        const baseName = std.fs.path.basename(exe);
        const help = comptime comptimeHelp(self);

        if (self.header.len > 0) {
            try writer.print("{s}\n", .{self.header});
        }

        try writer.print("Usage: {s}{s}\n", .{ baseName, help.usage });

        var t = help.details;

        while (std.mem.indexOf(u8, t, "$exe")) |p| {
            try writer.print("{s}", .{t[0..p]});
            try writer.print("{s}", .{baseName});
            t = t[p + 4 ..];
        }
        try writer.print("{s}", .{t});
    }

    fn printProblem(writer: anytype, p: zarg.Problem) !void {
        try writer.print("{s}", .{p.details});
        if (p.num > 0) {
            try writer.print(" ({s}) at arg #{d}", .{ p.arg, p.num });
        }
    }

    pub const PrintProblemMode = enum {
        first_problem,
        first_and_count_problems,
        all_problems,
    };

    fn printProblemsList(writer: anytype, problems: std.ArrayList(zarg.Problem), exe: []const u8, mod: PrintProblemMode) !void {
        const l = problems.items.len;
        if (exe.len > 0) {
            const baseName = std.fs.path.basename(exe);
            try writer.print("{s}: ", .{baseName});
        }
        if (l == 0) {
            try writer.print("No problems found", .{});
        } else {
            if (.all_problems == mod) {
                try writer.print("\n * ", .{});
            }
            try printProblem(writer, problems.items[0]);
            if (.all_problems == mod) {
                for (problems.items[1..]) |p2| {
                    try writer.print("\n * ", .{});
                    try printProblem(writer, p2);
                }
            }
        }
    }

    pub fn printProblems(comptime clp: zarg.CommandLineParser, s: zarg.Args(clp), writer: anytype, mod: ComptimeHelp.PrintProblemMode) !void {
        try printProblemsList(writer, s.problems, s.exe, mod);

        const bestHelpFlag = comptime e: {
            var name: []const u8 = "";

            for (clp.params) |param| {
                switch (param.kind) {
                    .option => |opt| switch (opt.format) {
                        .flag => if (param.tag == zarg.HelpParamTag) {
                            if (opt.long.len + 2 > name.len) {
                                name = "--" ++ opt.long;
                            }
                            if (opt.short.len + 1 > name.len) {
                                name = "-" ++ opt.short;
                            }
                        },
                        else => {},
                    },
                    else => {},
                }
            }
            break :e name;
        };

        try writer.print("\n", .{});
        if (bestHelpFlag.len > 0) {
            try writer.print("Try '{s} {s}' for more information.\n", .{ s.exe, bestHelpFlag });
        }
    }

    pub fn argSpec(comptime self: zarg.Param) []const u8 {
        switch (self.kind) {
            .option => |opt| {
                const name1 = if (opt.long.len > 0) ("--" ++ opt.long) else "";
                const name2 = if (opt.short.len == 0) "" else (if (name1.len > 0) " or " else "") ++ "-" ++ opt.short;
                return name1 ++ name2;
            },
            .positional => |pos| {
                switch (pos.format) {
                    .single => |s| return std.fmt.comptimePrint("{s}", .{s.parser}),
                    .multi => |m| return std.fmt.comptimePrint("{s}...", .{m.parser}),
                    .flag => return "",
                }
            },
        }
    }

    pub fn range(comptime min: usize, comptime max: usize) []const u8 {
        if (max == min) return std.fmt.comptimePrint("{d}", .{min});
        if (min == 0) {
            if (max == zarg.MaxArgs) return "any number";
            return std.fmt.comptimePrint("at most {d}", .{max});
        }
        if (max == zarg.MaxArgs) return std.fmt.comptimePrint("at least {d}", .{max});
        return std.fmt.comptimePrint("between {d} and {d}", .{ min, max });
    }
};
