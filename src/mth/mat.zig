const std = @import("std");
const vec = @import("vec.zig");

pub const mat4 = [4]vec.v4f32;

pub fn identity() mat4 {
    return .{
        .{ 1, 0, 0, 0 },
        .{ 0, 1, 0, 0 },
        .{ 0, 0, 1, 0 },
        .{ 0, 0, 0, 1 },
    };
}

pub fn mul(m: mat4, n: mat4) mat4 {
    const nt = transpose(n);
    return .{
        .{
            @reduce(.Add, m[0] * nt[0]),
            @reduce(.Add, m[0] * nt[1]),
            @reduce(.Add, m[0] * nt[2]),
            @reduce(.Add, m[0] * nt[3]),
        },
        .{
            @reduce(.Add, m[1] * nt[0]),
            @reduce(.Add, m[1] * nt[1]),
            @reduce(.Add, m[1] * nt[2]),
            @reduce(.Add, m[1] * nt[3]),
        },
        .{
            @reduce(.Add, m[2] * nt[0]),
            @reduce(.Add, m[2] * nt[1]),
            @reduce(.Add, m[2] * nt[2]),
            @reduce(.Add, m[2] * nt[3]),
        },
        .{
            @reduce(.Add, m[3] * nt[0]),
            @reduce(.Add, m[3] * nt[1]),
            @reduce(.Add, m[3] * nt[2]),
            @reduce(.Add, m[3] * nt[3]),
        },
    };
}

pub fn mul_vec(m: mat4, v: vec.v4f32) vec.v4f32 {
    return .{
        @reduce(.Add, m[0] * v),
        @reduce(.Add, m[1] * v),
        @reduce(.Add, m[2] * v),
        @reduce(.Add, m[3] * v),
    };
}

pub fn transpose(m: mat4) mat4 {
    return .{
        .{ m[0][0], m[1][0], m[2][0], m[3][0] },
        .{ m[0][1], m[1][1], m[2][1], m[3][1] },
        .{ m[0][2], m[1][2], m[2][2], m[3][2] },
        .{ m[0][3], m[1][3], m[2][3], m[3][3] },
    };
}

pub fn translation(tx: f32, ty: f32, tz: f32) mat4 {
    return .{
        .{ 1, 0, 0, tx },
        .{ 0, 1, 0, ty },
        .{ 0, 0, 1, tz },
        .{ 0, 0, 0, 1 },
    };
}

pub fn scale_uniform(s: f32) mat4 {
    return .{
        .{ s, 0, 0, 0 },
        .{ 0, s, 0, 0 },
        .{ 0, 0, s, 0 },
        .{ 0, 0, 0, 1 },
    };
}
pub fn scale(sx: f32, sy: f32, sz: f32) mat4 {
    return .{
        .{ sx, 0, 0, 0 },
        .{ 0, sy, 0, 0 },
        .{ 0, 0, sz, 0 },
        .{ 0, 0, 0, 1 },
    };
}

pub fn perspective(fov_y_deg: f32, aspect: f32, near: f32, far: f32) mat4 {
    const f = 1.0 / @tan((std.math.pi / 180.0) * fov_y_deg * 0.5);
    const nf = 1.0 / (near - far);
    return .{
        .{ f / aspect, 0, 0, 0 },
        .{ 0, f, 0, 0 },
        .{ 0, 0, (far + near) * nf, -1 },
        .{ 0, 0, 2 * far * near * nf, 0 },
    };
}

pub fn ortho(left: f32, right: f32, bottom: f32, top: f32, near: f32, far: f32) mat4 {
    const rl = 1.0 / (right - left);
    const tb = 1.0 / (top - bottom);
    const fn_ = 1.0 / (far - near);
    return .{
        .{ 2 * rl, 0, 0, -(right + left) * rl },
        .{ 0, 2 * tb, 0, -(top + bottom) * tb },
        .{ 0, 0, -2 * fn_, -(far + near) * fn_ },
        .{ 0, 0, 0, 1 },
    };
}

pub fn look_at(eye: vec.v4f32, center: vec.v4f32, up: vec.v4f32) mat4 {
    const f = vec.normalize3(center - eye);
    const r = vec.normalize3(vec.cross(f, up));
    const u = vec.cross(r, f);
    return .{
        .{ r[0], r[1], r[2], -@reduce(.Add, r * eye) },
        .{ u[0], u[1], u[2], -@reduce(.Add, u * eye) },
        .{ -f[0], -f[1], -f[2], @reduce(.Add, f * eye) },
        .{ 0, 0, 0, 1 },
    };
}
