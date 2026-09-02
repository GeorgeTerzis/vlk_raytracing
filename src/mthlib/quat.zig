const std = @import("std");
const vec = @import("./vec.zig");
const mat = @import("./mat.zig");

const Vec = vec.Vec;
const Mat = mat.Mat;

// https://www.euclideanspace.com/maths/algebra/realNormedAlgebra/quaternions/index.htm
// q = cos(θ/2) + sin(θ/2) * (xi + yj + zk)
pub fn Quat(comptime Scalar: type) type {
    comptime switch (@typeInfo(Scalar)) {
        .float => {},
        else => @compileError("Quat requires a floating-point scalar, found '" ++ @typeName(Scalar) ++ "'"),
    };

    return extern struct {
        pub const __mthquat: bool = true;

        pub const Vec4 = Vec(4, Scalar);
        pub const Vec3 = Vec(3, Scalar);
        pub const Mat4 = Mat(4, 4, Scalar);

        v: Vec4,

        const Self = @This();

        pub inline fn identity() Self {
            return .{ .v = Vec4.init(.{ 0, 0, 0, 1 }) };
        }

        /// angle in degrees, matching your original.
        pub inline fn from_axis_angle(axis: Vec3, angle_deg: Scalar) Self {
            const half: Scalar = (std.math.pi / 180.0) * angle_deg * 0.5;
            const s = @sin(half);
            const c = @cos(half);
            const k = axis.normalize();
            return .{ .v = Vec4.init(.{ k.x() * s, k.y() * s, k.z() * s, c }) };
        }

        pub inline fn mul(l: Self, r: Self) Self {
            const lx = l.v.x();
            const ly = l.v.y();
            const lz = l.v.z();
            const lw = l.v.w();
            const rx = r.v.x();
            const ry = r.v.y();
            const rz = r.v.z();
            const rw = r.v.w();
            return .{ .v = Vec4.init(.{
                lw * rx + lx * rw + ly * rz - lz * ry,
                lw * ry - lx * rz + ly * rw + lz * rx,
                lw * rz + lx * ry - ly * rx + lz * rw,
                lw * rw - lx * rx - ly * ry - lz * rz,
            }) };
        }

        /// v' = q * v * q⁻¹ (optimized form, same as your original)
        pub inline fn rotate(q: Self, v: Vec3) Vec3 {
            const qv = Vec3.init(.{ q.v.x(), q.v.y(), q.v.z() });
            const t = qv.cross(v).mul_scalar(2.0);
            return v.add(t.mul_scalar(q.v.w())).add(qv.cross(t));
        }

        /// Convenience: rotate a Vec4 by zeroing w before/after, matching
        /// your original's v4f32-in/v4f32-out signature if you need it.
        pub inline fn rotate4(q: Self, v: Vec4) Vec4 {
            const v3 = Vec3.init(.{ v.x(), v.y(), v.z() });
            const r = rotate(q, v3);
            return Vec4.init(.{ r.x(), r.y(), r.z(), v.w() });
        }

        /// Columns, since Mat is column-major (transpose of your old
        /// row-array layout, values are the same rotation matrix).
        pub inline fn to_mat4(q: Self) Mat4 {
            const x = q.v.x();
            const y = q.v.y();
            const z = q.v.z();
            const w = q.v.w();
            return Mat4.from_columns(.{
                Mat4.ColVec.init(.{ 1 - 2 * (y * y + z * z), 2 * (x * y - w * z), 2 * (x * z + w * y), 0 }),
                Mat4.ColVec.init(.{ 2 * (x * y + w * z), 1 - 2 * (x * x + z * z), 2 * (y * z - w * x), 0 }),
                Mat4.ColVec.init(.{ 2 * (x * z - w * y), 2 * (y * z + w * x), 1 - 2 * (x * x + y * y), 0 }),
                Mat4.ColVec.init(.{ 0, 0, 0, 1 }),
            });
        }

        pub inline fn normalize(q: Self) Self {
            return .{ .v = q.v.normalize() };
        }

        pub inline fn slerp(a: Self, b: Self, t: Scalar) Self {
            const d = a.v.dot(b.v);
            const b_ = if (d < 0.0) b.v.negate() else b.v;
            const dd = if (d < 0.0) -d else d;
            const omega = std.math.acos(@min(dd, 1.0));
            if (omega < 0.0001) return a;
            const s = 1.0 / @sin(omega);
            const sa = @sin((1.0 - t) * omega) * s;
            const sb = @sin(t * omega) * s;
            return .{ .v = a.v.mul_scalar(sa).add(b_.mul_scalar(sb)) };
        }

        pub inline fn rotate3(v: Vec3, axis: Vec3, angle_deg: Scalar) Vec3 {
            return rotate(from_axis_angle(axis, angle_deg), v);
        }
    };
}

pub const float = Quat(f32);
pub const double = Quat(f64);
