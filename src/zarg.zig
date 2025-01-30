// SPDX-FileCopyrightText: 2023 David Castañon Belloso <d4c7@proton.me>
// SPDX-License-Identifier: EUPL-1.2
// This file is part of zarg project (https://github.com/d4c7/zarg)

//! This module provides functions for command line parsing of
//! arguments

const std = @import("std");
const heap = std.heap;
const builtin = std.builtin;
pub const Parsers = @import("parsers.zig");
pub const Checks = @import("checks.zig");
pub const Autcomplete = @import("autocomplete/autocomplete.zig");
const ctrl = @import("argitem.zig");
const ComptimeHelp = @import("help.zig").ComptimeHelp;
const StringHashMap = @import("comptime_tools.zig").StringHashMap;

//const PositionalFieldName = "positional";
pub const AutoCompleteCommand = "__autocomplete:";

pub const CommandLineParserError = error{
    Internal,
    MalformedOption,
    UnrecognizedOption,
    UnrecognizedCommand,
    ExpectedOption,
    ExpectedOptionArg,
    ExpectedExeArg,
    ExpectedPositional,
    ExpectedCommand,
    UnexpectedPositional,
    UnexpectedOption,
    UnexpectedFlag,
    UnexpectedFlagArg,
    IgnoreOptionArg,
};

pub const MaxArgs = std.math.maxInt(usize);

pub const HelpParamTag = 1;

pub const Param = struct {
    kind: Kind,
    tag: usize = 0,
    help: []const u8 = "",
    check: ?*const Checks.Fn = null,

    pub fn fieldName(comptime self: Param) [:0]const u8 {
        comptime {
            switch (self.kind) {
                .option => |opt| {
                    return if (opt.long.len > 0) opt.long else opt.short;
                },
                .positional => |pos| return pos.name,
            }
        }
    }
};

pub const KindTag = enum {
    option,
    positional,
};

const Kind = union(KindTag) {
    option: Option,
    positional: Positional,
};

pub const Option = struct {
    format: Format = .flag,
    short: [:0]const u8 = "",
    long: [:0]const u8 = "",

    pub inline fn matches(comptime self: Option, v: ctrl.ArgItem) bool {
        switch (v.t) {
            .short => return std.mem.eql(u8, v.arg, self.short),
            .long => return std.mem.eql(u8, v.arg, self.long),
            else => return false,
        }
    }
};

pub const Positional = struct {
    name: [:0]const u8 = "",
    format: Format,
};

pub const FormatTag = enum {
    flag,
    single,
    multi,
};

const Format = union(FormatTag) {
    flag: void,
    single: Single,
    multi: Multi,
};

pub const Single = struct {
    parser: []const u8 = "STR",
    default: ?[]const u8 = null,
    must: bool = true,
};

pub const Multi = struct {
    parser: []const u8 = "STR",
    defaults: ?[]const []const u8 = null,
    min: usize = 1,
    max: usize = 1,
};

pub const Problem = struct {
    err: anyerror,
    arg: []const u8,
    num: usize,
    details: []const u8,
};

pub const DefaultMulti = struct {
    short: [:0]const u8 = "",
    long: [:0]const u8 = "",
    parser: []const u8 = "STR",
    defaults: ?[]const []const u8 = null,
    min: usize = 0,
    max: usize = 1,
    help: []const u8 = "",
    check: ?*const Checks.Fn = null,
};

pub fn multiOption(comptime opts: DefaultMulti) Param {
    return Param{
        .kind = .{ .option = .{
            .short = opts.short,
            .long = opts.long,
            .format = .{ .multi = .{
                .parser = opts.parser,
                .defaults = opts.defaults,
                .min = opts.min,
                .max = opts.max,
            } },
        } },
        .help = opts.help,
        .check = opts.check,
    };
}

pub const DefaultSingle = struct {
    short: [:0]const u8 = "",
    long: [:0]const u8 = "",
    parser: []const u8 = "STR",
    default: ?[]const u8 = null,
    help: []const u8 = "",
    check: ?*const Checks.Fn = null,
    must: bool = true,
};

pub fn option(comptime opts: DefaultSingle) Param {
    return Param{ .kind = .{ .option = .{
        .short = opts.short,
        .long = opts.long,
        .format = .{ .single = .{
            .must = opts.must,
            .parser = opts.parser,
            .default = opts.default,
        } },
    } }, .help = opts.help, .check = opts.check };
}

pub const DefaultFlag = struct {
    short: [:0]const u8 = "",
    long: [:0]const u8 = "",
    help: []const u8 = "",
};

pub fn flag(comptime opts: DefaultFlag) Param {
    return Param{
        .kind = .{ .option = .{
            .short = opts.short,
            .long = opts.long,
            .format = .flag,
        } },

        .help = opts.help,
    };
}

pub const DefaultHelpFlag = struct {
    short: [:0]const u8 = "",
    long: [:0]const u8 = "",
    help: []const u8 = ComptimeHelp.DefaultHelpFlagText,
};

pub fn flagHelp(comptime opts: DefaultHelpFlag) Param {
    return Param{
        .kind = .{ .option = .{
            .short = opts.short,
            .long = opts.long,
            .format = .flag,
        } },
        .tag = HelpParamTag,
        .help = opts.help,
    };
}

pub const DefaultSinglePositional = struct {
    parser: []const u8 = "STR",
    //default: ?[]const u8 = null,
    help: []const u8 = "Single positional", //TODO: to helps
    check: ?*const Checks.Fn = null,
    name: [:0]const u8 = "positional", //TODO: to helps
    must: bool = true,
};

pub fn singlePositional(comptime opts: DefaultSinglePositional) Param {
    return Param{
        .kind = .{
            .positional = .{
                .name = opts.name,
                .format = .{
                    .single = .{
                        .must = opts.must,
                        .parser = opts.parser,
                        //.default = opts.default,
                    },
                },
            },
        },
        .help = opts.help,
        .check = opts.check,
    };
}

pub const DefaultMultiPositional = struct {
    parser: []const u8 = "STR",
    //   defaults: ?[]const []const u8 = null,
    min: usize = 0,
    max: usize = MaxArgs,
    help: []const u8 = "Multiple positionals", //TODO: to helps
    check: ?*const Checks.Fn = null,
    name: [:0]const u8 = "positional", //TODO: to helps
};

pub fn multiPositional(comptime opts: DefaultMultiPositional) Param {
    return Param{ .kind = .{ .positional = .{ .name = opts.name, .format = .{ .multi = .{
        .parser = opts.parser,
        .min = opts.min,
        .max = opts.max,
    } } } }, .help = opts.help, .check = opts.check };
}

pub const DefaultCommandLineParser = struct {
    params: []const Param = &[_]Param{},
    desc: []const u8 = "",
    header: []const u8 = "",
    footer: []const u8 = "",
    parsers: []const Parsers.Parser = &Parsers.List,
    opts: Opts = .{},
};

pub const FieldStats = struct {
    count: usize = 0,
};

pub fn Args(comptime clp: CommandLineParser) type {
    var fields: [clp.params.len]builtin.Type.StructField = undefined;
    var stats_fields: [clp.params.len]builtin.Type.StructField = undefined;

    inline for (clp.params, 0..) |param, i| {
        const default_value = e: {
            const knd = switch (param.kind) {
                .option => |opt| opt.format,
                .positional => |pos| pos.format,
            };
            switch (knd) {
                .flag => |_| {
                    const v: bool = false;
                    break :e v;
                },
                .single => |p| {
                    const parser = comptime Parsers.select(p.parser, clp.parsers);
                    const T = parser.type;
                    if (p.default) |d| {
                        if (parser.isComptimeFriendly()) {
                            var v: T = undefined;
                            parser.parse(null, &v, d) catch |err| {
                                @compileError(std.fmt.comptimePrint("Unsupported default param '{s}' of type {s} for option '{s}': {}", .{ d, p.parser, param.fieldName(), err }));
                            };
                            break :e v;
                        }
                    }
                    break :e @as(?T, null);
                },
                .multi => |m| {
                    const parser = comptime Parsers.select(m.parser, clp.parsers);
                    const T = parser.type;
                    // defaults are oly checked, not assigned
                    if (parser.isComptimeFriendly()) {
                        if (m.defaults) |dlist| {
                            for (dlist, 0..) |d, idx| {
                                // if (!parser.useAllocator()) {
                                var v: T = undefined;
                                parser.parse(null, &v, d) catch |err| {
                                    @compileError(std.fmt.comptimePrint("Unsupported default param #{d} '{s}' of type {s} for option '{s}': {}", .{ idx, d, m.parser, param.fieldName(), err }));
                                };
                                //  }
                            }
                        }
                    }
                    break :e @as(std.ArrayList(T), undefined);
                },
            }
        };

        fields[i] = .{
            .name = param.fieldName(),
            .type = @TypeOf(default_value),
            .default_value = @ptrCast(&default_value),
            .is_comptime = false,
            .alignment = @alignOf(@TypeOf(default_value)),
        };

        {
            const field_stats = FieldStats{};
            stats_fields[i] = .{
                .name = param.fieldName(),
                .type = @TypeOf(field_stats),
                .default_value = @ptrCast(&field_stats),
                .is_comptime = false,
                .alignment = @alignOf(@TypeOf(field_stats)),
            };
        }
    }

    const T = @Type(.{ .Struct = .{
        .layout = .auto,
        .fields = fields[0..],
        .decls = &.{},
        .is_tuple = false,
    } });

    const TStats = @Type(.{ .Struct = .{
        .layout = .auto,
        .fields = stats_fields[0..],
        .decls = &.{},
        .is_tuple = false,
    } });

    return struct {
        exe: []const u8 = "",
        arg: T = .{},
        posIdx: usize = 0,
        stats: TStats = .{},
        allocator: std.mem.Allocator, //TODO:optional
        problems: std.ArrayList(Problem), // TODO:  fixed limited list and aflag allocator and print too many errors if more problems??

        const Self = @This();

        pub fn deinit(self: Self) void {
            inline for (clp.params) |param| {
                const knd = switch (param.kind) {
                    .option => |o| o.format,
                    .positional => |p| p.format,
                };

                switch (knd) {
                    .flag => {},
                    .single => |p| {
                        const parser = comptime Parsers.select(p.parser, clp.parsers);
                        parser.free(self.allocator, @field(&self.arg, param.fieldName()));
                    },
                    .multi => |m| {
                        const list = @field(&self.arg, param.fieldName());
                        const parser = comptime Parsers.select(m.parser, clp.parsers);
                        if (parser.useAllocator())
                            for (list.items) |i|
                                parser.free(self.allocator, i);
                        list.deinit();
                    },
                }
            }
            for (self.problems.items) |p|
                if (p.details.len > 0)
                    self.allocator.free(p.details);

            self.problems.deinit();
        }

        pub fn hasProblems(self: Self) bool {
            return self.problems.items.len > 0;
        }

        pub fn addProblem(self: *Self, err: anyerror, comptime fmt: []const u8, args: anytype) void {
            self.report_base("", 0, err, fmt, args);
        }

        fn report(self: *Self, err: anyerror, comptime fmt: []const u8, args: anytype, qarg: ctrl.ArgItem) void {
            self.report_base(qarg.argSrc, qarg.num, err, fmt, args);
        }

        fn report_base(self: *Self, arg: []const u8, num: usize, err: anyerror, comptime fmt: []const u8, args: anytype) void {
            // Try to dedup problems
            const p1 = Problem{
                .arg = arg,
                .num = num,
                .err = err,
                .details = std.fmt.allocPrint(self.allocator, fmt, args) catch "",
            };

            if (self.problems.items.len > 0) {
                const p2 = self.problems.getLast();
                if (p1.num == p2.num and p1.err == p2.err and std.mem.eql(u8, p1.arg, p2.arg) and std.mem.eql(u8, p1.details, p2.details)) {
                    self.allocator.free(p1.details);
                    return;
                }
            }
            self.problems.append(p1) catch |appendError| {
                std.debug.print("Unable to append problem: {}", .{appendError});
            };
        }

        pub fn printHelp(self: Args(clp), writer: anytype) !void {
            try ComptimeHelp.printHelp(clp, writer, self.exe);
        }

        pub fn printUsage(self: Args(clp), writer: anytype) !void {
            try ComptimeHelp.printUsage(clp, writer, self.exe);
        }

        pub fn printProblems(self: Args(clp), writer: anytype, mod: ComptimeHelp.PrintProblemMode) !void {
            try ComptimeHelp.printProblems(clp, self, writer, mod);
        }

        pub fn helpRequested(self: Args(clp)) bool {
            inline for (clp.params) |param| {
                switch (param.kind) {
                    .option => |opt| switch (opt.format) {
                        .flag => if (param.tag == HelpParamTag and @field(self.arg, param.fieldName())) return true,
                        else => {},
                    },
                    else => {},
                }
            }
            return false;
        }

        fn unquote(str: []const u8) []const u8 {
            const l = str.len;
            if (l > 1 and (str[0] == '"' or str[0] == '\'') and str[0] == str[l - 1]) {
                return str[1 .. l - 1];
            }
            return str;
        }

        pub const ProcessResult = enum { applied, applied_with_errors, not_found };

        fn processOption(t: *Args(clp), qarg: ctrl.ArgItem, argit: anytype) ProcessResult {
            var topts = &t.arg;
            var stats = &t.stats;

            const optionName = qarg.arg;

            inline for (clp.params) |param| {
                switch (param.kind) {
                    .option => |opt| {
                        if (opt.matches(qarg)) {
                            const fmt = opt.format;

                            const field_name = comptime param.fieldName();

                            @field(stats, field_name).count += 1;
                            // @field(stats, field_name).first_viewed_arg = qarg.num;
                            const count = @field(stats, field_name).count;

                            if (qarg.arglessReq and fmt != .flag) {
                                t.report(error.ExpectedOptionArg, "Expected argument for option '{s}', cannot use a not last option with argument in a multi-option argument", .{optionName}, qarg);
                                return .applied_with_errors;
                            }

                            if (fmt == .flag) {
                                if (argit.knownOptionArgument()) |oa| {
                                    t.report(error.UnexpectedFlagArg, "Unexpected flag argument '{s}' for '{s}'", .{ oa.arg, optionName }, oa);
                                    argit.skipKnownOptionArgument();
                                } else {
                                    @field(topts, field_name) = true;
                                    if (count > 1) {
                                        t.report(error.UnexpectedFlag, "Unexpected repeated flag '{s}'", .{optionName}, qarg);
                                    }
                                }
                            } else {
                                var unexpected = false;
                                switch (fmt) {
                                    .single => {
                                        if (count > 1) {
                                            t.report(error.UnexpectedFlag, "Unexpected repeated option '{s}'", .{optionName}, qarg);
                                            unexpected = true;
                                        }
                                    },
                                    .multi => |m| {
                                        if (count > m.max) {
                                            if (count == m.max + 1) {
                                                t.report(error.UnexpectedOption, "Unexpected option '{s}' options, more than {d} found", .{ optionName, m.max }, qarg);
                                            }
                                            unexpected = true;
                                        }
                                    },
                                    else => unreachable,
                                }

                                const parserId = switch (fmt) {
                                    .flag => "n/a",
                                    .single => |s| s.parser,
                                    .multi => |m| m.parser,
                                };

                                const qvalue = argit.next() orelse {
                                    t.report(error.ExpectedOptionArg, "Expected an option argument of type {s} for option '{s}'", .{ parserId, optionName }, qarg);
                                    return .applied_with_errors;
                                };

                                switch (qvalue.t) {
                                    .long, .short => {
                                        t.report(error.ExpectedOptionArg, "Expected option argument of type {s} for option '{s}' but found the option '{s}' instead", .{ parserId, optionName, qvalue.arg }, qarg);
                                        argit.rollback(); // so we can apply the unexpected option the next round and report more accurate problems
                                        return .applied_with_errors;
                                    },
                                    .value => {},
                                    .malformed_option => {
                                        t.report(error.MalformedOption, "Expected option argument of type {s} for option '{s}' but found the malformed option '{s}' instead", .{ parserId, optionName, qvalue.arg }, qarg);
                                        return .applied_with_errors;
                                    },
                                }

                                if (unexpected) {
                                    t.report(error.IgnoreOptionArg, "Ignore option argument '{s}'", .{qvalue.arg}, qvalue);
                                    return .applied_with_errors;
                                }

                                const parser = comptime Parsers.select(parserId, clp.parsers);

                                var value_receiver: parser.type = undefined;

                                const value = qvalue.arg;

                                parser.parse(t.allocator, &value_receiver, unquote(value)) catch |err| {
                                    t.report(err, "Unsupported value '{s}' of type {s} for option '{s}': {s}", .{ value, parserId, optionName, @errorName(err) }, qvalue);
                                    return .applied_with_errors;
                                };

                                if (param.check) |chk| {
                                    chk(value_receiver) catch |err| {
                                        t.report(err, "Unsupported value '{s}' of type {s} for option '{s}': {s}", .{ value, parserId, optionName, @errorName(err) }, qvalue);
                                        parser.free(t.allocator, value_receiver);
                                        return .applied_with_errors;
                                    };
                                }

                                if (fmt == .multi) {
                                    // pzig bug?:
                                    //list = @field(topts, field_name);
                                    //TODO: sec? append iif (list.items.len < fmt..max)
                                    @field(topts, field_name).append(value_receiver) catch |err| {
                                        t.report(err, "Unable to append value '{s}' of type {s} to option '{s}'", .{ value, parserId, optionName }, qvalue);
                                        parser.free(t.allocator, value_receiver);
                                        return .applied_with_errors;
                                    };
                                } else {
                                    @field(topts, field_name) = value_receiver;
                                }
                            }
                            return .applied;
                        }
                    },
                    .positional => {},
                }
            }

            return .not_found;
        }

        fn processPositional(t: *Args(clp), qarg: ctrl.ArgItem) ProcessResult {
            var topts = &t.arg;
            var stats = &t.stats;
            const value = qarg.arg;

            inline for (clp.params, 0..) |param, idx| {
                if (idx >= t.posIdx) {
                    switch (param.kind) {
                        .option => {},
                        .positional => |pos| {
                            if (pos.format == .single) {
                                t.posIdx = idx + 1;
                            }

                            @field(stats, pos.name).count += 1;
                            const count = @field(stats, pos.name).count;

                            const parserId = switch (pos.format) {
                                .flag => unreachable,
                                .single => |s| s.parser,
                                .multi => |m| m.parser,
                            };
                            const parser = comptime Parsers.select(parserId, clp.parsers);

                            const max_count = switch (pos.format) {
                                .single => 1,
                                .multi => |m| m.max,
                                else => unreachable,
                            };

                            if (count > max_count) {
                                if (count == max_count + 1) {
                                    t.report(error.UnexpectedPositional, "Unexpected positional, more than {d} positionals found", .{max_count}, qarg);
                                }
                                return .applied_with_errors;
                            }

                            var value_receiver: parser.type = undefined;
                            parser.parse(t.allocator, &value_receiver, unquote(value)) catch |err| {
                                t.report(err, "Unsupported value '{s}' of type {s} for positional arg: {s}", .{ value, parserId, @errorName(err) }, qarg);
                                return .applied_with_errors;
                            };

                            if (param.check) |chk| {
                                chk(value_receiver) catch |err| {
                                    parser.free(t.allocator, value_receiver);
                                    t.report(err, "Check failed for positional value '{s}' of type {s}: {s}", .{ value, parserId, @errorName(err) }, qarg);
                                    return .applied_with_errors;
                                };
                            }

                            if (pos.format == .multi) {
                                @field(topts, pos.name).append(value_receiver) catch |err| {
                                    parser.free(t.allocator, value_receiver);
                                    t.report(err, "Unable to append value '{s}' of type {s} to positionals: {s}", .{ value, parserId, @errorName(err) }, qarg);
                                    return .applied_with_errors;
                                };
                            } else {
                                @field(topts, pos.name) = value_receiver;
                            }
                            return .applied;
                        },
                    }
                }
            }
            return .not_found;
        }
    };
}

pub const ProcessMode = enum { //
    process_all_args,
    process_until_only_positionals,
    process_until_first_positional,
};

pub const ProblemMode = enum {
    continue_on_problem,
    stop_at_first_problem,
};
pub const OptionsMode = enum {
    options_in_any_position,
    options_honors_positionals,
};
pub const Opts = struct {
    optionArgSeparator: []const u8 = "=",
    processMode: ProcessMode = .process_all_args,
    problemMode: ProblemMode = .continue_on_problem,
    optionsMode: OptionsMode = .options_in_any_position,
    //optionArgsMode:OptionArgsMode=.SameOrSeparateToken,
};

pub const RunOpts = struct { //
    exe: ?[]const u8 = null,
    argOffset: usize = 0,
};

pub const CommandLineParser = struct {
    params: []const Param = &[_]Param{},
    header: []const u8 = "",
    desc: []const u8 = "",
    footer: []const u8 = "",
    parsers: []const Parsers.Parser = &Parsers.List,
    opts: Opts,

    pub fn init(comptime def: DefaultCommandLineParser) CommandLineParser {
        const clp = CommandLineParser{ //
            .params = def.params,
            .header = def.header,
            .desc = def.desc,
            .footer = def.footer,
            .parsers = def.parsers,
            .opts = def.opts,
        };
        comptime comptimeCheck(clp);
        return clp;
    }

    fn comptimeCheck(comptime clp: CommandLineParser) void {
        comptime { //check parser
            var namesMap = StringHashMap(usize, clp.params.len).init();
            var positionalMultiValueFound: bool = false;
            for (clp.params) |param1| {
                if (try namesMap.put(param1.fieldName(), 0)) {
                    @compileError(std.fmt.comptimePrint("duplicated param name {s}", .{param1.fieldName()}));
                }

                switch (param1.kind) {
                    .option => |opt1| {
                        if (opt1.short.len > 1) {
                            @compileError(std.fmt.comptimePrint("short param must be of len 1 but found {s}", .{opt1.short}));
                        }
                    },
                    .positional => {
                        if (positionalMultiValueFound) {
                            @compileError("multipositional must be the last positional param");
                        }

                        positionalMultiValueFound = param1.kind.positional.format == .multi;
                    },
                }

                const knd = switch (param1.kind) {
                    .option => |opt| opt.format,
                    .positional => |pos| pos.format,
                };

                switch (knd) {
                    .flag => {
                        if (param1.kind == .positional) {
                            @compileError("Positional cannot be flag kind");
                        }
                    },
                    .single => {},
                    .multi => |m| {
                        if (m.defaults) |def| {
                            if (def.len < m.min)
                                @compileError(std.fmt.comptimePrint("Too few default params for {s}, {d} provided, {d} expected", .{ param1.fieldName(), def.len, m.min }));
                        }
                    },
                }
            }
        }
    }

    pub fn parseArgs(comptime self: CommandLineParser, allocator: std.mem.Allocator) Args(self) {
        var it = try std.process.ArgIterator.initWithAllocator(allocator);
        defer it.deinit();
        return self.parse(&it, allocator, .{});
    }

    inline fn isOnlyPositionalsFromHereValue(qarg: ctrl.ArgItem) bool {
        return qarg.arg.len == 2 and qarg.arg[0] == '-' and qarg.arg[1] == '-';
    }

    pub fn processOnlyFlags(comptime self: CommandLineParser, t: *Args(self), argit: anytype) void {
        while (argit.next()) |qarg| {
            switch (qarg.t) {
                .long, .short => {
                    inline for (self.params) |param| {
                        if (param.Card == .flag and param.matches(qarg)) {
                            @field(&t.arg, param.fieldName()) = true;
                        }
                    }
                },
                .value => {
                    if (isOnlyPositionalsFromHereValue(qarg) or self.opts.processMode == .process_until_only_positionals) break;
                },
                else => {},
            }
        }
    }

    pub fn parse(comptime self: CommandLineParser, args: anytype, allocator: std.mem.Allocator, runopts: RunOpts) Args(self) {
        var argit = ctrl.ArgsController(@TypeOf(args)){ .argIterator = args, .optionArgSeparator = self.opts.optionArgSeparator };

        var t = Args(self){
            .allocator = allocator,
            .problems = std.ArrayList(Problem).init(allocator),
        };

        //init param things like lists for multi optional args
        inline for (self.params) |param| {
            const knd = switch (param.kind) {
                .option => |opt| opt.format,
                .positional => |pos| pos.format,
            };

            switch (knd) {
                .multi => |m| {
                    const parser = comptime Parsers.select(m.parser, self.parsers);
                    @field(&t.arg, param.fieldName()) = std.ArrayList(parser.type).init(allocator);
                },
                else => {},
            }
        }

        if (runopts.exe) |exe| {
            t.exe = exe;
            argit.num = runopts.argOffset;
        } else {
            t.exe = argit.rawNext() orelse {
                t.addProblem(error.ExpectedExeArg, "Expected executable name but not found!", .{});
                return t;
            };
            argit.num = 0;
        }
        var autocompleteIndex: i16 = -1;
        const autocompleteChar = 0;
        if (argit.next()) |first| {
            if (std.mem.startsWith(u8, first.arg, AutoCompleteCommand)) {
                autocompleteIndex = 1;
                //self.opts.problemMode = .continue_on_problem;
            } else {
                argit.rollback();
            }
        }

        var processOptions = true;

        out: while (argit.next()) |qarg| {
            if (autocompleteIndex == qarg.num) {
                if (autocompleteChar >= qarg.argSrcFrom and autocompleteChar <= qarg.argSrcFrom + qarg.arg.len) {
                    //autocomplete here
                    _ = 1;
                }
            }
            if (self.opts.problemMode == .stop_at_first_problem and t.hasProblems()) {
                argit.rollback();
                self.processOnlyFlags(&t, &argit);
                return t;
            }
            if (processOptions) {
                switch (qarg.t) {
                    .long, .short => {
                        if (t.processOption(qarg, &argit) == .not_found) {
                            t.report(error.UnrecognizedOption, "Unrecognized option '{s}'", .{qarg.arg}, qarg);
                            if (!qarg.arglessReq) {
                                if (argit.knownOptionArgument()) |oa| {
                                    t.report(error.IgnoreOptionArg, "Ignore option argument '{s}'", .{oa.arg}, oa);
                                    argit.skipKnownOptionArgument();
                                }
                            }
                        }
                        continue;
                    },
                    .value => {
                        if (isOnlyPositionalsFromHereValue(qarg)) {
                            processOptions = false;
                            argit.state = .only_values;
                            if (self.opts.processMode == .process_until_only_positionals) break :out;
                            continue;
                        }
                        //continue to process positionals, ojo no break!
                    },
                    .malformed_option => {
                        t.report(error.MalformedOption, "Malformed option '{s}'", .{qarg.arg}, qarg);
                        continue;
                    },
                }
            }
            if (t.processPositional(qarg) == .not_found) {
                t.report(error.UnexpectedPositional, "Unexpected positional argument", .{}, qarg);
            }
            if (self.opts.processMode == .process_until_first_positional) {
                break :out;
            }
        }
        self.check(&t);
        return t;
    }

    fn check(comptime self: CommandLineParser, t: *Args(self)) void {
        inline for (self.params) |param| {
            const name = comptime param.fieldName();
            const knd = switch (param.kind) {
                .option => |opt| opt.format,
                .positional => |pos| pos.format,
            };
            switch (knd) {
                .flag => {},
                .single => |s| {
                    var l = @field(t.stats, name).count;
                    if (@field(t.stats, name).count == 0) {
                        if (s.default) |def| {
                            const parser = comptime Parsers.select(s.parser, self.parsers);
                            var receiver: parser.type = undefined;
                            var ok = true;
                            parser.parse(t.allocator, &receiver, def) catch |err| {
                                t.addProblem(err, "Unsupported default value '{s}' of type {s} for {s}: {s}", .{ def, s.parser, name, @errorName(err) });
                                ok = false;
                            };

                            if (ok) {
                                if (param.check) |chk| {
                                    chk(receiver) catch |err| {
                                        t.addProblem(err, "check failed for default value '{s}' of type {s} for {s}: {s}", .{ def, s.parser, name, @errorName(err) });
                                        ok = false;
                                    };
                                }

                                if (ok) {
                                    @field(&t.arg, name) = receiver;
                                    @field(t.stats, name).count = 1;
                                    l = 1;
                                } else {
                                    parser.free(t.allocator, receiver);
                                }
                            }
                        }
                    }
                    if (l == 0 and s.must) {
                        t.addProblem(error.ExpectedPositional, "Expected {s}", .{comptime ComptimeHelp.argSpec(param)});
                    }
                },
                .multi => |m| {
                    var l = @field(t.stats, name).count;
                    if (l == 0) if (m.defaults) |defs| {
                        const parser = comptime Parsers.select(m.parser, self.parsers);
                        for (defs, 0..) |def, idx| {
                            var receiver: parser.type = undefined;
                            parser.parse(t.allocator, &receiver, def) catch |err| {
                                t.addProblem(err, "Unsupported default value #{d} '{s}' of type {s} for '{s}': {}", .{ idx, def, m.parser, comptime ComptimeHelp.argSpec(param), err });
                                continue;
                            };
                            if (param.check) |chk| {
                                chk(receiver) catch |err| {
                                    t.addProblem(err, "check failed for default value #{d} '{s}' of type {s} for {s}: {s}", .{ idx, def, m.parser, name, @errorName(err) });
                                    continue;
                                };
                            }
                            @field(&t.arg, name).append(receiver) catch |err| {
                                parser.free(t.allocator, receiver);
                                t.addProblem(err, "Unable to append value #{d} '{s}' of type {s} for '{s}': {s}", .{ idx, def, m.parser, comptime ComptimeHelp.argSpec(param), @errorName(err) });
                            };
                        }
                        @field(t.stats, name).count = defs.len;
                    };

                    l = @field(t.stats, name).count;

                    //note max is already checked on processing
                    if (l < m.min) {
                        const r = comptime ComptimeHelp.range(m.min, m.max);
                        t.addProblem(error.ExpectedOption, "Expected {s} {s}'s, but found {d}", .{ r, comptime ComptimeHelp.argSpec(param), l });
                    }
                },
            }
        }
    }
};
