const std = @import("std");

// https://plflib.org/colony.htm
pub fn Hive(comptime StorageElm: type, comptime SkipFieldElm: type) type {
    return struct {
        pub const H = @This();

        pub const FreeInfo = extern struct {
            const Index = SkipFieldElm;
            prev: Index,
            next: Index,

            pub fn index_max() Index {
                return std.math.maxInt(Index);
            }

            pub fn prev_or_null(self: @This()) ?Index {
                return if (self.prev != index_max()) self.prev else null;
            }
            pub fn next_or_null(self: @This()) ?Index {
                return if (self.next != index_max()) self.next else null;
            }
        };

        pub const Elm = StorageElm;

        pub const Variant = extern union {
            free_info: FreeInfo,
            elm: Elm,
        };
        pub const SkipElm = SkipFieldElm;
        pub const StorageType = []Variant;

        skip: []SkipElm,
        storage: StorageType,

        free_head: usize,
        live: usize,

        fn init_skip(skip: []SkipElm) void {
            const capacity = skip.len;
            @memset(skip, 0);
            skip[0] = @intCast(capacity);
            skip[capacity - 1] = @intCast(capacity);
        }

        pub fn init_capacity(allocator: std.mem.Allocator, capacity: usize) !H {
            const skip = try allocator.alloc(SkipElm, capacity);
            const storage = try allocator.alloc(Variant, capacity);
            return init_buffer(skip, storage);
        }

        pub fn init_buffer(
            skip: []SkipElm,
            buffer: []Variant,
        ) H {
            init_skip(skip);

            {
                @memset(std.mem.sliceAsBytes(buffer), 0);
                buffer[0].free_info = .{
                    .next = FreeInfo.index_max(),
                    .prev = FreeInfo.index_max(),
                };
                buffer[buffer.len - 1].free_info = .{
                    .next = FreeInfo.index_max(),
                    .prev = FreeInfo.index_max(),
                };
            }
            return .{
                .skip = skip,
                .storage = buffer,
                .free_head = 0,
                .live = 0,
            };
        }

        pub fn deinit(self: @This(), allocator: std.mem.Allocator) void {
            allocator.free(self.storage);
            allocator.free(self.skip);
        }

        pub fn remaining(self: H) usize {
            return (self.storage.len - self.live);
        }

        pub fn is_full(self: H) bool {
            return (self.storage.len - self.live) == 0;
        }

        pub fn is_empty(self: H) bool {
            return self.live == 0;
        }

        pub fn get(self: *H, slot: usize) *Elm {
            return &self.storage[slot].elm;
        }
        pub fn get_or_null(self: *H, slot: usize) ?*Elm {
            if (slot >= self.storage.len) return null;
            if (self.skip[slot] != 0) return null;
            return &self.storage[slot].elm;
        }

        pub fn get_val(self: *H, slot: usize) Elm {
            return self.storage[slot].elm;
        }
        pub fn get_val_or_null(self: *H, slot: usize) ?Elm {
            if (slot >= self.storage.len) return null;
            if (self.skip[slot] != 0) return null;
            return self.storage[slot].elm;
        }

        pub fn alloc(self: *H) ?usize {
            if (self.is_full())
                return null;
            self.live += 1;

            const skip = self.skip;

            const slot = blk: {
                std.debug.assert(self.free_head < skip.len);
                const s = self.free_head;

                std.debug.assert(skip[s] != 0);
                const len = skip[s];

                std.debug.assert(s + len <= skip.len);
                const span_end = s + len - 1;

                std.debug.assert(skip[span_end] != 0 and skip[span_end] == skip[s]);
                const data = self.storage[s].free_info;
                if (len > 1) {
                    // we just transfer ownership of the data to the next index if it exits
                    // if next_free is the max int value this means
                    const next_slot = s + 1;
                    std.debug.assert(next_slot <= span_end);

                    self.storage[next_slot].free_info = data;
                    self.skip[next_slot] = len - 1;
                    self.skip[span_end] = len - 1;
                    self.free_head = s + 1;
                } else {
                    // we have to get the next free slot (if it exists) and update it
                    // we shouldn't really have to do that for the prev but if we allow
                    // multi-element allocation we will have to
                    if (data.next != FreeInfo.index_max()) {
                        self.storage[data.next].free_info.prev = data.prev;
                        self.free_head = @intCast(data.next);
                    }

                    // this should exist only when we are doing multi element insert
                    if (data.prev != FreeInfo.index_max()) {
                        self.storage[data.prev].free_info.next = data.next;
                        self.free_head = @intCast(data.prev);
                    }
                }

                break :blk s;
            };

            return slot;
        }

        pub fn erase(self: *H, slot: usize) void {
            if (self.is_empty())
                return;

            self.live -= 1;

            const skip = self.skip;
            if (skip[slot] != 0)
                return;

            var start: usize = slot;
            var end: usize = slot;

            var prev_free: FreeInfo.Index = FreeInfo.index_max();
            var next_free: FreeInfo.Index = FreeInfo.index_max();

            var merged_left = false;
            var merged_right = false;

            if (slot > 0 and skip[slot - 1] != 0) {
                const span_len = skip[slot - 1];
                start = slot - span_len;

                const left_info = self.storage[start].free_info;
                prev_free = left_info.prev;
                next_free = left_info.next;
                merged_left = true;
            }

            if (slot < skip.len - 1 and skip[slot + 1] != 0) {
                const span_len = skip[slot + 1];
                end = slot + span_len;
                const right_info = self.storage[slot + 1].free_info;
                merged_right = true;

                if (merged_left) {
                    next_free = right_info.next;
                } else {
                    prev_free = right_info.prev;
                    next_free = right_info.next;
                }

                if (right_info.prev != FreeInfo.index_max()) {
                    self.storage[right_info.prev].free_info.next = @intCast(start);
                }
                if (right_info.next != FreeInfo.index_max()) {
                    self.storage[right_info.next].free_info.prev = @intCast(start);
                }
            }

            if (!merged_left) {
                if (self.free_head < self.storage.len) {
                    self.storage[self.free_head].free_info.prev = @intCast(start);
                }
                next_free = @intCast(self.free_head);
                prev_free = FreeInfo.index_max();
                self.free_head = start;
            }
            self.storage[start].free_info = .{
                .prev = prev_free,
                .next = next_free,
            };

            const len: SkipElm = @intCast(end - start + 1);
            skip[start] = len;
            skip[end] = len;
        }

        pub fn alloc_many(self: *H, count: usize) ?usize {
            if (count == 0 or self.remaining() < count) {
                return null;
            }
            if (count == 1) return self.alloc();

            const skip = self.skip;

            var current: usize = self.free_head;
            while (current < self.storage.len) {
                const span_len = skip[current];
                std.debug.assert(span_len != 0);

                if (span_len >= count) {
                    self.live += count;
                    const info = self.storage[current].free_info;
                    const span_end = current + span_len - 1;
                    var skip_end = span_end + 1;

                    if (span_len == count) {
                        //exact fit
                        //link the prev.next = info.next
                        if (info.prev_or_null()) |prev| {
                            self.storage[prev].free_info.next = info.next;
                        } else {
                            // list head
                            self.free_head =
                                if (info.next_or_null()) |next|
                                    @intCast(next)
                                else
                                    self.storage.len;
                        }

                        // next.prev = info.prev
                        if (info.next_or_null()) |next| {
                            self.storage[next].free_info.prev = info.prev;
                        }
                    } else {
                        const new_start = current + count;
                        skip_end = new_start;

                        const new_len = @as(SkipFieldElm, @intCast(span_len)) - count;
                        const end = current + self.skip[current] - 1;
                        self.storage[new_start].free_info = info;

                        //update skip
                        self.skip[new_start] = @intCast(new_len);
                        self.skip[end] = @intCast(new_len);

                        // update free list
                        {
                            if (info.prev_or_null()) |prev| {
                                self.storage[prev].free_info.next = @intCast(new_start);
                            } else {
                                self.free_head = new_start;
                            }

                            if (info.next_or_null()) |next| {
                                self.storage[next].free_info.prev = @intCast(new_start);
                            }
                        }
                    }

                    @memset(skip[current..skip_end], 0);
                    // @memset(std.mem.sliceAsBytes(self.storage[current .. current + count]), 0);

                    return current;
                }
                const next = self.storage[current].free_info.next;
                if (next == FreeInfo.index_max()) break;
                current = @intCast(next);
            }

            return null;
        }

        pub fn erase_many(self: *H, slot: usize, count: usize) void {
            if (count == 0) return;
            if (count == 1) return self.erase(slot);

            std.debug.assert(slot + count <= self.storage.len);

            var i = slot + count;
            while (i > slot) {
                i -= 1;
                self.erase(i);
            }
        }

        pub const SliceIterator = struct {
            const Self = @This();

            hive: *H,
            pos: SkipFieldElm,

            pub fn init(hive: *H) Self {
                return .{
                    .hive = hive,
                    .pos = 0,
                };
            }

            pub fn next(self: *Self) ?[]Elm {
                const s = self.hive.skip[self.pos];
                if (s != 0) {
                    const data: FreeInfo = @bitCast(self.hive.storage[self.pos]);
                    const jump = self.pos + s;
                    const slice_len = @min(data.next, self.hive.skip.len) - jump;

                    const slice = @as([]Elm, @ptrCast(self.hive.storage[jump..][0..slice_len]));
                    if (data.next == FreeInfo.index_max())
                        return null;
                    self.pos = data.next;
                    return slice;
                } else {
                    const pos = @min(self.hive.free_head, @as(FreeInfo.Index, @intCast(self.hive.storage.len)));
                    const slice = @as([]Elm, @ptrCast(self.hive.storage[self.pos..][0 .. pos - self.pos]));
                    self.pos = pos;
                    return slice;
                }
            }
        };
    };
}
