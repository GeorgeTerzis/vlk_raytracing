const std = @import("std");
const vec_import = @import("./vec.zig");
const mat_import = @import("./mat.zig");

const MathVec = vec_import.Vec;
pub fn Vec(comptime len: usize, comptime Scalar: type) type {
    return extern struct {
        const __mthgpuvec: bool = true;

        raw: [len]Scalar,

        pub const SourceVec = MathVec(len, Scalar);
        const Self = @This();

        pub inline fn init(components: anytype) Self {
            comptime if (components.len != len)
                @compileError("Vec.init: wrong number of components");
            var out: Self = undefined;
            inline for (components, 0..) |c, i| {
                out.raw[i] = c;
            }
            return out;
        }
        pub inline fn zero() Self {
            return .{ .raw = [_]Scalar{0} ** len };
        }

        pub inline fn one() Self {
            return .{ .raw = [_]Scalar{1} ** len };
        }

        pub inline fn from(v: SourceVec) Self {
            return .{ .raw = v.to_array() };
        }

        pub inline fn to(self: Self) SourceVec {
            return SourceVec.from_array(self.raw);
        }
    };
}

pub const float2 = Vec(2, f32);
pub const float3 = Vec(3, f32);
pub const float4 = Vec(4, f32);

pub const double2 = Vec(2, f64);
pub const double3 = Vec(3, f64);
pub const double4 = Vec(4, f64);

pub const int2 = Vec(2, i32);
pub const int3 = Vec(3, i32);
pub const int4 = Vec(4, i32);

pub const uint2 = Vec(2, u32);
pub const uint3 = Vec(3, u32);
pub const uint4 = Vec(4, u32);

const MathMat = mat_import.Mat;
pub fn Mat(comptime rows: usize, comptime cols: usize, comptime Scalar: type) type {
    return extern struct {
        const __mthgpumat: bool = true;

        raw: [cols][rows]Scalar,

        pub const SourceMat = MathMat(rows, cols, Scalar);
        const Self = @This();

        pub inline fn identity() Self {
            comptime if (rows != cols) @compileError("identity requires a square matrix");
            return from(SourceMat.identity());
        }

        pub inline fn from(m: SourceMat) Self {
            return .{ .raw = m.to_array() };
        }

        pub inline fn to(self: Self) SourceMat {
            return SourceMat.fromColumns(blk: {
                var cols_arr: [cols]SourceMat.ColVec = undefined;
                inline for (0..cols) |c| {
                    cols_arr[c] = SourceMat.ColVec.from_array(self.raw[c]);
                }
                break :blk cols_arr;
            });
        }
    };
}

pub const float3x3 = Mat(3, 3, f32);
pub const float4x4 = Mat(4, 4, f32);
pub const double4x4 = Mat(4, 4, f64);
