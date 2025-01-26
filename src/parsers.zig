// SPDX-FileCopyrightText: 2023 David Castañon Belloso <d4c7@proton.me>
// SPDX-License-Identifier: EUPL-1.2
// This file is part of zarg project (https://github.com/d4c7/zarg)

const std = @import("std");
const json = std.json;
const ComptimeHelper = @import("comptime_tools.zig");
const Check = @import("checks.zig");

pub const ParseFn = fn (comptime parser: Parser, allocator: anytype, rec: anytype, str: []const u8) anyerror!void;
pub const FreeFn = fn (comptime parser: Parser, allocator: anytype, rec: anytype) void;

//TODO:-- split parsers

pub const Parser = struct {
    name: []const u8,
    help: []const u8,
    type: type,
    //TODO:vtable?
    parseFn: ParseFn = basicParse,
    freeFn: ?FreeFn = null,
    checkFn: ?Check.Fn = null,
    comptimeFriendly: bool = true,

    inline fn asOptional(comptime T: type, t: anytype) ?T {
        const ParserInfo = @typeInfo(@TypeOf(t));
        switch (ParserInfo) {
            .Optional => return t,
            else => return @as(?T, t),
        }
    }

    // TODO:optional or ptr allocator

    pub fn parse(comptime self: Parser, allocator: anytype, value_receiver: anytype, value: []const u8) !void {
        try self.parseFn(self, allocator, value_receiver, value);
        errdefer self.free(allocator, value_receiver);
        if (self.checkFn) |chk| {
            try chk(value_receiver.*);
        }
    }

    pub fn free(comptime self: Parser, allocator: anytype, value: anytype) void {
        if (self.freeFn) |f| {
            if (asOptional(self.type, value)) |v|
                f(self, allocator, v);
        }
    }

    pub fn useAllocator(comptime self: Parser) bool {
        return self.freeFn != null;
    }

    pub fn isComptimeFriendly(comptime self: Parser) bool {
        return self.comptimeFriendly and !self.useAllocator();
    }
};

pub const List = [_]Parser{
    .{ .parseFn = jsonParse, .freeFn = jsonFree, .name = "JSON", .type = json.Parsed(json.Value), .help = "A JSON conforming to RFC 8259.\nhttps://datatracker.ietf.org/doc/html/rfc8259" }, //
    .{ .name = "STR", .type = []const u8, .help = "A non empty string value. UTF-8", .checkFn = Check.NonEmptyString },
    .{ .name = "BOOL", .type = bool, .help = "Boolean value true/false yes/no or y/n" },
    .{ .name = "SIZE", .type = usize, .help = std.fmt.comptimePrint(
        \\Unsigned {d}bit integer with optional base prefix (0x,0o,0b) and 
        \\optional unit postfix (K,M,G,T,P,E,Z,Y,Q,T) followed by iB or B.
        \\
        \\Examples: 10K   is 10*1000
        \\          0xaKiB is 10*1024
    , .{@sizeOf(usize) * 8}) },
    .{ .name = "TCP_PORT", .type = u16, .help = 
    \\TCP port value between 0 and 65535. Use port 0 to dynamically assign a port
    \\Can use base prefix (0x,0o,0b). 
    },
    .{ .name = "TCP_HOST", .type = []const u8, .help = 
    \\TCP host name or IP. 
    } //add check to host names
    ,
    .{ .name = "FILE", .type = []const u8, .help = 
    \\File 
    , .checkFn = Check.NonEmptyString },
    .{ .name = "DIR", .type = []const u8, .help = 
    \\Directory path
    , .checkFn = Check.NonEmptyString },
};

fn basicParse(comptime parser: Parser, allocator: anytype, recv: anytype, str: []const u8) !void {
    _ = allocator;
    const T = parser.type;
    const rec = @as(*T, recv);
    const value = switch (T) {
        bool => try parseBool(str),
        u16 => try std.fmt.parseInt(u16, str, 0),
        usize => try std.fmt.parseIntSizeSuffix(str, 0),
        isize => try std.fmt.parseInt(isize, str, 0),
        []const u8 => str,
        else => @compileError(std.fmt.comptimePrint("unsupported type {}")),
    };

    rec.* = value;
}

const BoolMap = std.StaticStringMap(bool).initComptime(.{
    .{ "true", true },
    .{ "false", false },
    .{ "yes", true },
    .{ "no", false },
    .{ "y", true },
    .{ "n", false },
});

fn parseBool(str: []const u8) !bool {
    if (BoolMap.get(str)) |v| {
        return v;
    }
    return error.NotABooleanValue;
}

fn enumParse(comptime parser: Parser, allocator: anytype, recv: anytype, str: []const u8) !void {
    _ = allocator;
    const T = parser.type;
    const info = @typeInfo(T);
    if (info != .Enum) {
        @compileError(std.parsermt.comptimePrint("Required enum, found {s}", .{@tagName(info)}));
    }
    const rec = @as(*T, recv);
    inline for (info.Enum.fields) |field| {
        if (std.mem.eql(u8, field.name, str)) {
            const key = @as(T, @enumFromInt(field.value));
            rec.* = key;
            return;
        }
    }
    return error.InvalidEnum;
}

pub fn enumParser(comptime name: []const u8, comptime e: anytype, comptime help: ?[]const u8) Parser {
    const h = help orelse e: {
        var auto: []const u8 = "Possible values:";
        for (@typeInfo(e).Enum.fields, 0..) |field, i| {
            auto = auto ++ if (i == 0) " " else ", ";
            auto = auto ++ @tagName(@as(e, @enumFromInt(field.value)));
        }
        break :e auto;
    };
    return Parser{ .parseFn = enumParse, .name = name, .type = e, .help = h };
}

const JsonContext = struct {
    const MaxEntries = 10;

    map: ComptimeHelper.StringHashMap(*TypeCtr, MaxEntries),
    ref_ctr: usize,
    bla: usize = 0,

    const TypeCtr = struct {
        ctr: usize = 0,
        used: bool = false,
    };

    fn init() JsonContext {
        return JsonContext{
            .map = ComptimeHelper.StringHashMap(*TypeCtr, MaxEntries).init(),
            .ref_ctr = 0,
        };
    }

    fn registerType(self: *JsonContext, comptime T: type) !bool {
        const key = @typeName(T);
        if (self.map.get(key)) |e| {
            e.ctr += 1;
            return false;
        } else {
            var v = TypeCtr{ .ctr = 1 };
            _ = try self.map.put(key, &v);
            return true;
        }
    }

    pub fn analyze(self: *JsonContext, comptime T: type) !void {
        switch (@typeInfo(T)) {
            .Struct => |i| {
                if (try self.registerType(T)) {
                    inline for (i.fields) |j| {
                        try self.analyze(j.type);
                    }
                }
            },
            .Vector => |i| try self.analyze(i.child),
            .Pointer => |i| try self.analyze(i.child),
            .Array => |i| try self.analyze(i.child),
            .Optional => |i| try self.analyze(i.child),
            else => {},
        }
    }

    fn typeRef(self: *JsonContext, comptime T: type) !?*TypeCtr {
        const key = @typeName(T);
        if (self.map.get(key)) |c| {
            return c;
        }
        return null;
    }

    pub fn schemaText(self: *JsonContext, prefix: []const u8, comptime T: type) ![]const u8 {
        var typeName: []const u8 = "";
        if (try self.typeRef(T)) |ctr| {
            if (ctr.ctr > 1) {
                typeName = @typeName(T);
                if (std.mem.lastIndexOfLinear(u8, @typeName(T), ".")) |i| {
                    typeName = typeName[i + 1 ..];
                }
                if (ctr.used) {
                    return typeName;
                }
                ctr.used = true;
            }
        }

        const tab = "   ";
        var schema: []const u8 = "";
        switch (@typeInfo(T)) {
            .Bool => {
                return "\"true\" | \"false\"";
            },
            .Float, .ComptimeFloat => {
                return std.fmt.comptimePrint("float{d}", .{@sizeOf(T) * 8});
            },
            .Int, .ComptimeInt => {
                return std.fmt.comptimePrint("int{d}", .{@sizeOf(T) * 8});
            },
            .Optional => |optionalInfo| {
                return "null | " ++ try self.schemaText(prefix ++ tab, optionalInfo.child);
            },
            .Enum => |e| {
                schema = schema ++ "(";
                for (e.fields, 0..) |field, i| {
                    schema = schema ++ if (i == 0) "" else " | ";
                    schema = schema ++ "\"" ++ @tagName(@as(T, @enumFromInt(field.value))) ++ "\"";
                }
                schema = schema ++ ")";
                return schema;
            },
            .Union => |unionInfo| {
                if (unionInfo.tag_type == null) @compileError("Unable to parse into untagged union '" ++ @typeName(T) ++ "'");
                schema = schema ++ std.fmt.comptimePrint("{s}(", .{typeName});
                inline for (unionInfo.fields, 0..) |u_field, i| {
                    const prt = (if (i == 0) "    " else "  | ");

                    if (u_field.type == void) {
                        schema = schema ++ std.fmt.comptimePrint("\n{s}{s}\"{s}\": {{}}", .{ prefix, prt, u_field.name });
                    } else {
                        schema = schema ++ std.fmt.comptimePrint("\n{s}{s}\"{s}\": ", .{ prefix, prt, u_field.name });
                        schema = schema ++ try self.schemaText(prefix ++ tab, u_field.type);
                    }
                }
                schema = schema ++ std.fmt.comptimePrint("\n{s})", .{prefix});

                return schema;
            },

            .Struct => |structInfo| {
                schema = schema ++ std.fmt.comptimePrint("{s}{s}\n", .{ typeName, if (structInfo.is_tuple) "[" else "{" });
                inline for (structInfo.fields, 0..) |field, i| {
                    if (i == 0) {
                        schema = schema ++ std.fmt.comptimePrint("{s}{s}", .{ prefix, tab });
                    } else {
                        schema = schema ++ std.fmt.comptimePrint(",\n{s}{s}", .{ prefix, tab });
                    }
                    if (!structInfo.is_tuple) {
                        schema = schema ++ "\"" ++ field.name ++ "\"" ++ ": ";
                    }

                    self.bla += 1;
                    if (self.bla > 100) {
                        @compileError("too much recursion");
                    }
                    schema = schema ++ try self.schemaText(prefix ++ tab, field.type);
                }

                schema = schema ++ std.fmt.comptimePrint("\n{s}{s}", .{ prefix, if (structInfo.is_tuple) "]" else "}" });

                return schema;
            },

            .Vector, .Array => |item| {
                schema = schema ++ std.fmt.comptimePrint("[", .{});
                schema = schema ++ try self.schemaText(prefix ++ tab, item.child);
                schema = schema ++ std.fmt.comptimePrint("]", .{});
                return schema;
            },
            .Pointer => |ptrInfo| {
                switch (ptrInfo.size) {
                    .One => {
                        return self.schemaText(prefix ++ tab, ptrInfo.child);
                    },
                    .Slice, .Many => {
                        schema = schema ++ std.fmt.comptimePrint("[", .{});
                        schema = schema ++ try self.schemaText(prefix ++ tab, ptrInfo.child);
                        schema = schema ++ std.fmt.comptimePrint("]", .{});
                        return schema;
                    },

                    else => {
                        @compileError("Unable to parse into ptr type '" ++ @typeName(T) ++ "'");
                    },
                }
            },

            else => {
                @compileError("Unable to parse into type --  '" ++ @typeName(T) ++ "'");
            },
        }
        unreachable;
    }
};

pub fn jsonParser(comptime name: []const u8, comptime e: anytype, comptime help: ?[]const u8) Parser {
    const h = help orelse e: {
        var auto: []const u8 = "A JSON conforming to RFC 8259 with this syntax:\n";
        var ctx = JsonContext.init(); //TODO:rename to json schema
        ctx.analyze(e) catch @compileError("unable to analyze type");
        const z = ctx.schemaText("", e) catch @compileError("unable to gen schema text");
        auto = auto ++ z;
        break :e auto;
    };
    return Parser{ .parseFn = jsonParse, .freeFn = jsonFree, .name = name, .type = json.Parsed(e), .help = h };
}

fn jsonParse(comptime parser: Parser, allocator: anytype, recv: anytype, str: []const u8) !void {
    const T = parser.type;
    const rec = @as(*T, recv);
    const j = try json.parseFromSlice(@TypeOf(rec.value), allocator, str, .{});
    rec.* = j;
}

fn jsonFree(comptime parser: Parser, allocator: anytype, rec: anytype) void {
    _ = parser;
    _ = allocator;
    rec.deinit();
}

pub inline fn select(comptime stype: []const u8, comptime parsers: []const Parser) Parser {
    inline for (parsers) |parser| if (std.mem.eql(u8, parser.name, stype)) return parser;
    @compileError(std.fmt.comptimePrint("unsupported param type {s}", .{stype}));
}
