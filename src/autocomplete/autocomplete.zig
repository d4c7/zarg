// SPDX-FileCopyrightText: 2023-2025 David Castañon Belloso <d4c7@proton.me>
// SPDX-License-Identifier: EUPL-1.2
// This file is part of zarg project (https://github.com/d4c7/zarg)

const std = @import("std");

const bash_autocomplete = @embedFile("./bash_autocomplete.sh");

pub fn dumpAutoComplete() !void {
    std.debug.print("{s}", .{bash_autocomplete});
}
