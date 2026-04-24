const std = @import("std");
const vec = @import("./vec.zig");
const mat = @import("./mat.zig");

// https://www.euclideanspace.com/maths/algebra/realNormedAlgebra/quaternions/index.htm
pub const quat = vec.v4f32;

// q = cos(θ/2) + sin(θ/2) * (xi + yj + zk)
pub fn from_axis_angle(axis: vec.v4f32, angle: f32) quat {
    const half: f32 = (std.math.pi / 180.0) * angle * 0.5;
    const s = @sin(half);
    const c = @cos(half);
    const k = vec.normalize(axis);
    return .{
        k[0] * s,
        k[1] * s,
        k[2] * s,
        c,
    };
}

pub fn mul(l: quat, r: quat) quat {
    return .{
        l[3] * r[0] + l[0] * r[3] + l[1] * r[2] - l[2] * r[1],
        l[3] * r[1] - l[0] * r[2] + l[1] * r[3] + l[2] * r[0],
        l[3] * r[2] + l[0] * r[1] - l[1] * r[0] + l[2] * r[3],
        l[3] * r[3] - l[0] * r[0] - l[1] * r[1] - l[2] * r[2],
    };
}

// v' = q * v * q⁻¹
pub fn rotate(q: quat, v4: vec.v4f32) vec.v4f32 {
    const v3 = v4 * vec.v3mask;
    const qv: vec.v4f32 = .{ q[0], q[1], q[2], 0 };
    const t = vec.cross(qv, v3) * @as(vec.v4f32, @splat(2.0));
    return v3 + t * @as(vec.v4f32, @splat(q[3])) + vec.cross(qv, t);
}

// v' = q * v * q⁻¹
pub fn to_mat4(q: quat) mat.mat4 {
    const x = q[0];
    const y = q[1];
    const z = q[2];
    const w = q[3];
    return .{
        .{ 1 - 2 * (y * y + z * z), 2 * (x * y + w * z), 2 * (x * z - w * y), 0 },
        .{ 2 * (x * y - w * z), 1 - 2 * (x * x + z * z), 2 * (y * z + w * x), 0 },
        .{ 2 * (x * z + w * y), 2 * (y * z - w * x), 1 - 2 * (x * x + y * y), 0 },
        .{ 0, 0, 0, 1 },
    };
}

pub fn normalize(q: quat) quat {
    return vec.normalize(q);
}

pub fn identity() quat {
    return .{ 0, 0, 0, 1 };
}

pub fn slerp(a: quat, b: quat, t: f32) quat {
    const dot = @reduce(.Add, a * b);

    const b_ = if (dot < 0.0) -b else b;
    const omega = std.math.acos(@abs(dot));

    if (omega < 0.0001) return a;

    const s: vec.v4f32 = @splat(1.0 / @sin(omega));
    const sa: vec.v4f32 = @splat(@sin((1.0 - t) * omega));
    const sb: vec.v4f32 = @splat(@sin(t * omega));
    return (a * sa + b_ * sb) * s;
}

pub fn rotate3(v: vec.v4f32, axis: vec.v4f32, angle: f32) vec.v4f32 {
    return rotate(from_axis_angle(axis, angle), v);
}
