pub const vec = @import("./mth/vec.zig");
pub const quat = @import("./mth/quat.zig");
pub const mat = @import("./mth/mat.zig");

pub const mat4 = mat.mat4;
pub const quat4 = quat.quat;
pub const vec2 = vec.v2f32;
pub const vec4 = vec.v4f32;

pub fn model(pos: vec.v4f32, rot: quat.quat, s: vec.v4f32) mat4 {
    const r = quat.to_mat4(rot);
    return .{
        r[0] * @as(vec.v4f32, @splat(s[0])) + vec.v4f32{ 0, 0, 0, pos[0] },
        r[1] * @as(vec.v4f32, @splat(s[1])) + vec.v4f32{ 0, 0, 0, pos[1] },
        r[2] * @as(vec.v4f32, @splat(s[2])) + vec.v4f32{ 0, 0, 0, pos[2] },
        .{ 0, 0, 0, 1 },
    };
}
