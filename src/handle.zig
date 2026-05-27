const std = @import("std");
const builtin = @import("builtin");

pub fn HandleType(comptime Type: type) type {
    const BackingType = u32;
    return struct {
        const T = Type;
        value: BackingType,
    };
}
