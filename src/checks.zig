// SPDX-FileCopyrightText: 2023 David Castañon Belloso <d4c7@proton.me>
// SPDX-License-Identifier: EUPL-1.2
// This file is part of zig-argueando project (https://github.com/d4c7/zig-argueando)

const std = @import("std");

pub const Errors = error{
    ExpectedNonEmptyString,
};

pub const Fn = fn (rec: anytype) anyerror!void;

pub const DirOpts = struct {
    mode: std.fs.File.OpenMode = .read_only,
    access_sub_paths: bool = true,
    no_follow: bool = false,
};

pub fn Dir(comptime opt: DirOpts) type {
    return struct {
        pub fn f(rec: anytype) !void {
            const path = @as([]const u8, rec);
            var dir = try std.fs.cwd().openDir(path, .{ .access_sub_paths = opt.access_sub_paths, .no_follow = opt.no_follow });
            defer dir.close();
            try dir.access(".", .{ .mode = opt.mode });
        }
    };
}

pub const FileOpts = struct {
    mode: std.fs.File.OpenMode = .read_only,
};

pub fn File(comptime opt: FileOpts) type {
    return struct {
        pub fn f(rec: anytype) !void {
            const path = @as([]const u8, rec);
            try std.fs.cwd().access(path, .{ .mode = opt.mode });
        }
    };
}

pub fn NonEmptyString(rec: anytype) !void {
    const str = @as([]const u8, rec);
    if (str.len == 0) {
        return error.ExpectedNonEmptyString;
    }
}


//TODO:chain checks
