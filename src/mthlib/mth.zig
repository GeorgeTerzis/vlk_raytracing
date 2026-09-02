const vecmod = @import("./vec.zig");
const matmod = @import("./mat.zig");
const quatmod = @import("./quat.zig");
pub const gpu = @import("./gpu.zig");

pub const float = f32;
pub const float2 = vecmod.float2;
pub const float3 = vecmod.float3;
pub const float4 = vecmod.float4;
pub const float4x4 = matmod.float4x4;
pub const float3x3 = matmod.float3x3;

pub const double = f64;
pub const double2 = vecmod.double2;
pub const double3 = vecmod.double3;
pub const double4 = vecmod.double4;

pub const int = i32;
pub const int2 = vecmod.int2;
pub const int3 = vecmod.int3;
pub const int4 = vecmod.int4;

pub const uint = u32;
pub const uint2 = vecmod.uint2;
pub const uint3 = vecmod.uint3;
pub const uint4 = vecmod.uint4;

pub const quat = quatmod.float;
pub const dquat = quatmod.double;

pub const proj = struct {
    pub fn prespective(fov: f32, aspect: f32, near: f32, far: f32) float4x4 {
        const f = 1.0 / @tan(fov / 2.0);

        return .{ .v = .{
            .{ f / aspect, 0, 0, 0 },
            .{ 0, -f, 0, 0 },
            .{ 0, 0, far / (near - far), (far * near) / (near - far) },
            .{ 0, 0, -1, 0 },
        } };
    }

    pub fn ortho(
        left: f32,
        right: f32,
        bottom: f32,
        top: f32,
        near: f32,
        far: f32,
    ) float4x4 {
        return .{ .v = .{
            .{ 2.0 / (right - left), 0, 0, -(right + left) / (right - left) },
            .{ 0, -2.0 / (top - bottom), 0, -(top + bottom) / (top - bottom) },
            .{ 0, 0, 1.0 / (near - far), near / (near - far) },
            .{ 0, 0, 0, 1 },
        } };
    }
};

pub fn is_base(comptime Type: type) bool {
    if (@hasDecl(Type, "__mthquat") or
        @hasDecl(Type, "__mthvec") or
        @hasDecl(Type, "__mthmat"))
    {
        return true;
    } else {
        @compileError("is_base: expected a mth type, got '" ++ @typeName(Type) ++ "'");
    }
}

pub fn is_gpu(comptime Type: type) bool {
    if (@hasDecl(Type, "__mthgpuvec") or
        @hasDecl(Type, "__mthgpumat"))
    {
        return true;
    } else {
        @compileError("is_gpu: expected a mth gpu type, got '" ++ @typeName(Type) ++ "'");
    }
}

pub fn is_mth(comptime Type: type) bool {
    if (is_gpu(Type) or is_base(Type)) {
        return true;
    } else {
        @compileError("to_gpu: expected a mth Vec or Mat, got '" ++ @typeName(Type) ++ "'");
    }
}

pub fn to_gpu(comptime Type: type) type {
    if (@hasDecl(Type, "__mthquat")) {
        return gpu.Vec(Type.Vec4.length, Type.T);
    } else if (@hasDecl(Type, "__mthvec")) {
        return gpu.Vec(Type.length, Type.T);
    } else if (@hasDecl(Type, "__mthmat")) {
        return gpu.Mat(Type.rows, Type.cols, Type.T);
    } else {
        @compileError("to_gpu: expected a mth Vec or Mat, got '" ++ @typeName(Type) ++ "'");
    }
}
