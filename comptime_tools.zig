// SPDX-FileCopyrightText: 2023 David Castañon Belloso <d4c7@proton.me>
// SPDX-License-Identifier: EUPL-1.2
// SPDX-License-Identifier: MIT
// This file is part of zig-argueando project (https://github.com/d4c7/zig-argueando)

// The following segments are a derivative work, based on code from ziglang project
// (https://github.com/ziglang/zig) under MIT license, which has been modified by me
// and does not necessarily reflect the original code pourpose or quality:
// - ComptimeFixedBufferAllocator derived from FixedBufferAllocator
//   (https://github.com/ziglang/zig/blob/master/lib/std/heap.zig)
//

const std = @import("std");

pub const ComptimeFixedBufferAllocator = struct {
    end_index: usize,
    buffer: []u8,

    pub fn init(buffer: []u8) ComptimeFixedBufferAllocator {
        return ComptimeFixedBufferAllocator{
            .buffer = buffer,
            .end_index = 0,
        };
    }

    pub fn allocator(self: *ComptimeFixedBufferAllocator) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .free = free,
            },
        };
    }

    pub fn isLastAllocation(self: *ComptimeFixedBufferAllocator, buf: []u8) bool {
        return buf.ptr + buf.len == self.buffer.ptr + self.end_index;
    }

    fn alloc(ctx: *anyopaque, n: usize, log2_ptr_align: u8, ra: usize) ?[*]u8 {
        const self = @as(ComptimeFixedBufferAllocator, @ptrCast(ctx));
        _ = ra;
        const ptr_align = @as(usize, 1) << @as(std.mem.Allocator.Log2Align, @intCast(log2_ptr_align));
        const adjust_off = std.mem.alignPointerOffset(self.buffer.ptr + self.end_index, ptr_align) orelse return null;
        const adjusted_index = self.end_index + adjust_off;
        const new_end_index = adjusted_index + n;
        if (new_end_index > self.buffer.len) return null;
        self.end_index = new_end_index;
        return self.buffer.ptr + adjusted_index;
    }

    fn resize(
        ctx: *anyopaque,
        buf: []u8,
        log2_buf_align: u8,
        new_size: usize,
        return_address: usize,
    ) bool {
        const self = @as(ComptimeFixedBufferAllocator, @ptrCast(ctx));
        _ = log2_buf_align;
        _ = return_address;

        if (!self.isLastAllocation(buf)) {
            if (new_size > buf.len) return false;
            return true;
        }

        if (new_size <= buf.len) {
            const sub = buf.len - new_size;
            self.end_index -= sub;
            return true;
        }

        const add = new_size - buf.len;
        if (add + self.end_index > self.buffer.len) return false;

        self.end_index += add;
        return true;
    }

    fn free(
        ctx: *anyopaque,
        buf: []u8,
        log2_buf_align: u8,
        return_address: usize,
    ) void {
        const self = @as(ComptimeFixedBufferAllocator, @ptrCast(ctx));
        _ = log2_buf_align;
        _ = return_address;

        if (self.isLastAllocation(buf)) {
            self.end_index -= buf.len;
        }
    }

    pub fn reset(self: *ComptimeFixedBufferAllocator) void {
        self.end_index = 0;
    }
};

pub const StringHashMapError = error{MaxCapacityReached};

pub fn StringHashMap(comptime V: type, comptime maxEntries: usize) type {
    const Entry = struct { key: []const u8 = "", value: V };
    return struct {
        data: [maxEntries]?Entry,
        len: usize,

        const Self = @This();

        pub fn init() Self {
            @setEvalBranchQuota(maxEntries * 2);
            var data: [maxEntries]?Entry = undefined;
            for (0..maxEntries) |i| {
                data[i] = null;
            }
            return .{
                .data = data,
                .len = 0,
            };
        }

        fn hash(s: []const u8) u64 {
            var h: u64 = 5381;
            for (s) |c| {
                h = (h *% 33) +% @as(u64, @intCast(c));
            }
            return h;
        }

        pub fn put(self: *Self, comptime key: []const u8, comptime value: V) !?V {
            const i = self.index(key);
            if (i < 0)
                return error.MaxCapacityReached;

            if (self.data[i]) |*e| {
                const old = e.value;
                e.value = value;
                return old;
            }
            self.len += 1;
            self.data[i] = .{
                .key = key,
                .value = value,
            };
            return null;
        }

        pub fn get(self: Self, comptime key: []const u8) ?V {
            const i = self.index(key);
            if (i >= 0) if (self.data[i]) |e| {
                return e.value;
            };
            return null;
        }

        fn index(self: Self, comptime key: []const u8) isize {
            const j = @mod(hash(key), maxEntries);
            var i = j;
            while (true) {
                if (self.data[i]) |e| {
                    if (std.mem.eql(u8, e.key, key)) return i;
                } else {
                    return i;
                }
                i = @mod(i + 1, maxEntries);
                if (i == j) {
                    return -1;
                }
            }
        }
    };
}

test "hash" {
    comptime {
        var map = StringHashMap(usize, 5).init();

        inline for (0..5) |i| {
            const k = std.fmt.comptimePrint("{d}", .{i});
            try std.testing.expect(null == try map.put(k, i));

            try std.testing.expect(i == try map.put(k, i * 3));

            try std.testing.expect(i * 3 == map.get(k));
        }
    }
}

test "hash_ptr" {
    comptime {
        var map = StringHashMap(*usize, 5).init();

        inline for (0..5) |i| {
            const k = std.fmt.comptimePrint("{d}", .{i});

            var v: usize = i;
            try std.testing.expect(null == try map.put(k, &v));

            try std.testing.expect(i == map.get(k).?.*);
        }
    }
}
