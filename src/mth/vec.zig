const std = @import("std");

pub const v2f32 = @Vector(2, f32);
pub const v4f32 = @Vector(4, f32);

pub const v2i32 = @Vector(2, i32);
pub const v4i32 = @Vector(4, i32);

const v3mask: v4f32 = .{ 1, 1, 1, 0 };

pub fn ione() v4i32 {
    return .{ 1, 1, 1, 1 };
}
pub fn fone() v4f32 {
    return .{ 1, 1, 1, 1 };
}

pub fn izero() v4i32 {
    return .{ 0, 0, 0, 0 };
}

pub fn fzero() v4f32 {
    return .{ 0, 0, 0, 0 };
}

pub fn fscalar(n: f32) v4f32 {
    return .{ n, n, n, n };
}

pub fn dot3(lhs: v4f32, rhs: v4f32) f32 {
    return @reduce(.Add, lhs * rhs * v3mask);
}

pub fn centroid(args: anytype) v4f32 {
    const fields = std.meta.fields(@TypeOf(args));
    comptime for (fields) |field| {
        std.debug.assert(field.type == v4f32);
    };
    const n = fields.len;

    var v: v4f32 = .{ 0, 0, 0, 0 };
    inline for (args) |arg| {
        v += arg;
    }
    return v * @as(v4f32, @splat(1.0 / @as(f32, @floatFromInt(n))));
}

pub fn normalize(v: v4f32) v4f32 {
    const len = @as(v4f32, @splat(1.0 / @sqrt(@reduce(.Add, v * v))));
    return v * len;
}

pub fn normalize3(v: v4f32) v4f32 {
    return normalize(v * v3mask);
}

pub fn cross(lhs: v4f32, rhs: v4f32) v4f32 {
    const lhs_yzx = @shuffle(f32, lhs, undefined, [4]i32{ 1, 2, 0, 3 });
    const rhs_yzx = @shuffle(f32, rhs, undefined, [4]i32{ 1, 2, 0, 3 });
    const c = lhs * rhs_yzx - lhs_yzx * rhs;
    return @shuffle(f32, c, undefined, [4]i32{ 1, 2, 0, 3 });
}
