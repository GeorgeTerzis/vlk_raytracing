const std = @import("std");
const builtin = @import("builtin");

pub fn HandleType(comptime Type: type) type {
    return struct {
        pub const T = Type;
        pub const Backing = u32;
        value: Backing,
    };
}
