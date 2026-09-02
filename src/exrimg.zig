const std = @import("std");
const c_libs = @import("c_libs");

pixels: []f32,
width: u32 = 0,
height: u32 = 0,

pub fn from_mem(mem: []const u8) !@This() {
    var out: [*c]f32 = null;
    var width: c_int = 0;
    var height: c_int = 0;
    var err: [*c]const u8 = null;

    const ret = c_libs.LoadEXRFromMemory(&out, &width, &height, mem.ptr, mem.len, &err);
    if (ret != c_libs.TINYEXR_SUCCESS) {
        defer if (err != null) c_libs.FreeEXRErrorMessage(err);
        std.log.err("tinyexr load failed: {s}", .{err});
        return error.ExrLoadFailed;
    }

    return .{
        .pixels = out[0..@intCast(width * height * 4)],
        .width = @intCast(width),
        .height = @intCast(height),
    };
}
