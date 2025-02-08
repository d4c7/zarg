// SPDX-FileCopyrightText: 2023-2025 David Castañon Belloso <d4c7@proton.me>
// SPDX-License-Identifier: EUPL-1.2
// This file is part of zarg project (https://github.com/d4c7/zarg)

const std = @import("std");

const bash_autocomplete = @embedFile("./bash_autocomplete.sh");

fn replaceAndWrite(text: []const u8, map: anytype, writer: anytype) !void {
    var data = text[0..];
    while (true) {
        if (std.mem.indexOf(u8, data, "%{")) |i| {
            if (std.mem.indexOf(u8, data[i + 2 ..], "}%")) |j| {
                const k = data[i + 2 .. i + 2 + j];
                if (map.get(k)) |v| {
                    try writer.writeAll(data[0..i]);
                    try writer.writeAll(v);
                    data = data[i + 2 + j + 2 ..];
                    continue;
                }
                try writer.writeAll(data[0 .. j + 2]);
                data = data[j + 2 ..];
                continue;
            }
            try writer.writeAll(data[0 .. i + 2]);
            data = data[i + 2 ..];
            continue;
        }
        try writer.writeAll(data);
        break;
    }
}

pub const Args = struct {
    tokens: [][]const u8,
    word_idx: usize = 0,
    word_pos: usize = 0,
};

pub fn parseCommandLine(input: []const u8, cursor: usize, allocator: std.mem.Allocator) !Args {
    var tokens = std.ArrayList([]const u8).init(allocator);
    defer tokens.deinit();
    const optionArgSeparator = "=";

    var found = false;
    var word_idx: usize = 0;
    var word_pos: usize = 0;

    var i: usize = 0;
    while (i < input.len) {
        while (i < input.len and std.ascii.isWhitespace(input[i])) : (i += 1) {}

        if (i >= input.len) break;

        var in_quotes = false;
        var escape = false;
        var in_single_quotes = false;

        var token_buffer = std.ArrayList(u8).init(allocator);
        defer token_buffer.deinit();
        var offset: usize = 0;
        const start = i;
        while (i < input.len) {
            if (!found and i >= cursor) {
                found = true;
                word_idx = tokens.items.len;
                word_pos = i - start - offset;
            }
            const c = input[i];
            if (escape) {
                escape = false;
                try token_buffer.append(c);
                i += 1;
                continue;
            }

            if (c == '\\') {
                escape = true;
                i += 1;
                offset += 1;
                continue;
            }

            if (!in_single_quotes and c == '"') {
                in_quotes = !in_quotes;
                i += 1;
                offset += 1;
                continue;
            }
            if (!in_quotes and c == '\'') {
                in_single_quotes = !in_single_quotes;
                i += 1;
                offset += 1;
                continue;
            }

            if (!in_quotes and !in_single_quotes) {
                if (token_buffer.items.len > 1 and std.mem.startsWith(u8, input[i..], optionArgSeparator)) {
                    i += optionArgSeparator.len;
                    break;
                }
                if (std.ascii.isWhitespace(c)) {
                    break;
                }
            }
            try token_buffer.append(c);
            i += 1;
        }
        const tbil = token_buffer.items.len;

        if (tbil > 0) {
            try tokens.append(try token_buffer.toOwnedSlice());
        }
    }
    if (!found) {
        found = true;
        if (tokens.items.len == 0 or std.mem.endsWith(u8, input, optionArgSeparator) or (input.len > 0 and std.ascii.isWhitespace(input[input.len - 1]))) {
            try tokens.append("");
            word_idx = tokens.items.len - 1;
            word_pos = 0;
        } else {
            word_idx = tokens.items.len - 1;
            word_pos = tokens.items[word_idx].len;
        }
    }
    const t = try tokens.toOwnedSlice();
    return .{ .tokens = t, .word_idx = word_idx, .word_pos = word_pos };
}

pub const ArgIterator2 = struct {
    args: Args,
    idx: usize,
    allocator: std.mem.Allocator,

    /// You must deinitialize iterator's internal buffers by calling `deinit` when done.
    pub fn init(input: []const u8, cursor: usize, allocator: std.mem.Allocator) !ArgIterator2 {
        const args = try parseCommandLine(input, cursor, allocator);

        return ArgIterator2{ .args = args, .idx = 0, .allocator = allocator };
    }
    pub fn init2(args: Args, allocator: std.mem.Allocator) !ArgIterator2 {
        return ArgIterator2{ .args = args, .idx = 0, .allocator = allocator };
    }
    pub fn next(self: *ArgIterator2) ?([]const u8) {
        if (self.idx < self.args.tokens.len) {
            const token = self.args.tokens[self.idx];
            self.idx += 1;
            return token;
        }
        return null;
    }

    pub fn skip(self: *ArgIterator2) bool {
        if (self.idx < self.args.tokens.len) {
            self.idx += 1;
            return true;
        }
        return false;
    }

    pub fn deinit(self: *ArgIterator2) void {
        for (self.args.tokens) |token| {
            self.allocator.free(token);
        }
        self.allocator.free(self.args.tokens);
    }
};

const zarg = @import("../zarg.zig");
const Parsers = zarg.Parsers;
const Check = zarg.Checks;
const builtin = @import("builtin");
const option = zarg.option;
const multiOption = zarg.multiOption;
const flag = zarg.flag;
const flagHelp = zarg.flagHelp;
const singlePositional = zarg.singlePositional;
const multiPositional = zarg.multiPositional;
const ComptimeHelp = zarg.ComptimeHelp;

pub const AutocompleteShellEnum = enum {
    bash,
    zsh,
};

fn command_install(args0: anytype, exe: []const u8, allocator: std.mem.Allocator, _: usize) !void {
    const parsers = Parsers.List ++ [_]Parsers.Parser{ //
        Parsers.enumParser("SHELL", AutocompleteShellEnum, null),
    };

    const clp = zarg.CommandLineParser.init(.{
        .parsers = &parsers,
        .params = &([_]zarg.Param{
            option(.{ //
                .long = "shell",
                .short = "s",
                .parser = "SHELL",
                .help = "Shell",
                .must = true,
            }),
            option(.{ //
                .long = "target",
                .short = "t",
                .parser = "STR",
                .help = "Command name target if it's external",
                .must = false,
            }),
            flagHelp(.{ //
                .long = "help",
                .short = "h",
                .help = "Shows the help.",
            }),
        }),
    });
    var s = clp.parse(args0, allocator, .{ .exe = exe, .argOffset = 1 });
    defer s.deinit();

    if (s.helpRequested()) {
        try s.printHelp(std.io.getStdErr().writer());
        return;
    }
    if (s.hasProblems()) {
        try s.printProblems(std.io.getStdErr().writer(), .all_problems);
        return;
    }

    switch (s.arg.shell.?) {
        .bash => {
            var map = std.StringHashMap([]const u8).init(allocator);
            defer map.deinit();

            try map.put("TARGET", if (s.arg.target) |t| t else exe);
            try map.put("AUTOCOMPLETER", exe);

            try replaceAndWrite(bash_autocomplete, map, std.io.getStdOut().writer());
        },
        .zsh => {
            std.debug.print("TO DO", .{});
        },
    }
}

fn command_suggest(args0: anytype, allocator: std.mem.Allocator, _: usize, clp_target: zarg.CommandLineParser) !void {
    const aclp = zarg.CommandLineParser.init(.{
        .params = &([_]zarg.Param{
            option(.{ //
                .long = "cursor-pos",
                .short = "c",
                .parser = "SIZE",
                .default = "0",
                .help = "This is the cursor absolute position at the full command line from which the arg is autocompleted.",
                .must = false,
            }),
            singlePositional(.{ //
                .name = "command-line",
                .parser = "STR",
                .help = "Full raw command line.",
                .must = true,
            }),
            flagHelp(.{ //
                .long = "help",
                .short = "h",
                .help = "Shows the help.",
            }),
        }),
    });
    var s = aclp.parse(args0, allocator, .{ .exe = "exe + cmd", .argOffset = 1 });
    defer s.deinit();

    if (s.helpRequested()) {
        try s.printHelp(std.io.getStdErr().writer());
        return;
    }
    if (s.hasProblems()) {
        try s.printProblems(std.io.getStdErr().writer(), .all_problems);
        return;
    }

    const args = try parseCommandLine(s.arg.@"command-line".?, s.arg.@"cursor-pos", allocator);

    defer {
        for (args.tokens) |token| {
            allocator.free(token);
        }
        allocator.free(args.tokens);
    }

    if (args.tokens.len == 0)
        return;

    const arg = args.tokens[args.word_idx];
    const prx = arg[0..args.word_pos];
    const arl = arg.len;

    var out = std.io.getStdOut().writer();
    if (arl > 0 and arg[0] == '-') {
        if (arl > 1 and arg[1] == '-') {
            //suggest long options
            inline for (clp_target.params, 0..) |param, idx| {
                _ = idx;
                switch (param.kind) {
                    .option => |opt| {
                        if (opt.long.len > 0 and std.mem.startsWith(u8, "--" ++ opt.long, prx)) {
                            try out.print("{s}{s}\t{s}\n", .{ "--" ++ opt.long, if (opt.format != .flag) "=" else "", "online-help" });
                        }
                    },
                    .positional => |pos| {
                        _ = pos;
                    },
                }
            }
        } else {
            //suggest short options
            inline for (clp_target.params, 0..) |param, idx| {
                _ = idx;
                switch (param.kind) {
                    .option => |opt| {
                        if (opt.short.len > 0) {
                            try out.print("{s}{s}{s}\t{s}\n", .{ prx, opt.short, if (opt.format != .flag) "=" else "", "online-help" });
                        }
                    },
                    .positional => |pos| {
                        _ = pos;
                    },
                }
            }
        }
    } else {
        //suggest options args or positionals
        const optionArgSeparator = "=";
        const it = try ArgIterator2.init2(args, allocator);
        var argit = zarg.ctrl.ArgsController(@TypeOf(it)){ .argIterator = it, .optionArgSeparator = optionArgSeparator };
        var position_pos: usize = 0;
        //TODO: comptime problem here to select parser easily... maybe in next zig versions, review or change comptime data structures
        xx: while (argit.next()) |p| {
            switch (p.t) {
                .long => {
                    inline for (clp_target.params) |param| {
                        if (param.kind == .option and param.kind.option.long.len > 0) {
                            if (std.mem.eql(u8, param.kind.option.long, p.arg)) {
                                if (param.kind.option.format != .flag) {
                                    if (p.num == args.word_idx) {
                                        const parser = param.parser(clp_target);
                                        try outParamAutocomplete(parser, allocator, prx, out);
                                        break :xx;
                                    }
                                    if (argit.next()) |n| {
                                        if (n.t != .value) {
                                            argit.rollback();
                                        }
                                    }
                                }
                                break;
                            }
                        }
                    }
                },
                .short => {
                    inline for (clp_target.params) |param| {
                        if (param.kind == .option and param.kind.option.short.len > 0) {
                            if (std.mem.eql(u8, param.kind.option.short, p.arg)) {
                                if (param.kind.option.format != .flag) {
                                    if (p.num == args.word_idx) {
                                        const parser = param.parser(clp_target);
                                        try outParamAutocomplete(parser, allocator, prx, out);
                                        break :xx;
                                    }
                                    if (argit.next()) |n| {
                                        if (n.t != .value) {
                                            argit.rollback();
                                        }
                                    }
                                }
                                break;
                            }
                        }
                    }
                },
                .value => {
                    if (p.num - 1 == args.word_idx) {
                        inline for (clp_target.params) |param| {
                            if (param.kind == .positional) {
                                if (position_pos > 0) position_pos -= 1;
                                if (position_pos == 0 or param.kind.positional.format == .multi) {
                                    const parser = param.parser(clp_target);
                                    try outParamAutocomplete(parser, allocator, prx, out);
                                    break :xx;
                                }
                            }
                        }
                    } else {
                        position_pos += 1;
                    }
                },
                .malformed_option => {},
            }
        }
    }
}

pub fn outParamAutocomplete(parser: zarg.Parsers.Parser, allocator: std.mem.Allocator, prx: []const u8, out: anytype) !void {
    if (parser.autocompleteFn) |f| {
        var list = try f(parser, allocator, prx);
        defer list.deinit();
        for (list.items) |i| {
            try out.print("{s}\t{s}\n", .{ i.value, "help" });
        }
    } else {
        try out.print("{s}:{s}\n", .{ parser.name, prx });
    }
}
pub const CommandEnum = enum {
    install,
    suggest,
};

pub fn __main(clp_target: zarg.CommandLineParser, allocator: std.mem.Allocator) !void {
    const parsers = Parsers.List ++ [_]Parsers.Parser{ //
        Parsers.enumParser("COMMAND", CommandEnum, null),
    };

    const clp = zarg.CommandLineParser.init(.{
        .desc = "Autocomplete Command Line Parser",
        .parsers = &parsers,
        .params = &[_]zarg.Param{
            singlePositional(.{
                .name = "command",
                .parser = "COMMAND",
                .help = "A command",
            }),
            flagHelp(.{ .long = "help", .short = "h", .help = "Shows this help." }),
        },
        .footer = "Footer",
        .opts = .{ .processMode = .process_until_first_positional, .problemMode = .continue_on_problem },
    });

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
            .install => {
                try command_install(&args, s.exe, allocator, 1);
            },
            .suggest => { //...
                try command_suggest(&args, allocator, 1, clp_target);
            },
        }
    }
}
