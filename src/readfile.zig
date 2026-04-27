const std = @import("std");

pub fn readfile_alloc(allocator: std.mem.Allocator, file: std.fs.File) ![]const u8 {
    var file_buffer: [1024]u8 = undefined;
    var reader = file.reader(&file_buffer);

    const stat = try file.stat();
    const size = stat.size;
    const contents = try reader.interface.readAlloc(allocator, size);

    return contents;
}
//devilish
pub fn readfile_allocZ(allocator: std.mem.Allocator, file: std.fs.File) ![:0]const u8 {
    const contents = try readfile_alloc(allocator, file);
    defer allocator.free(contents);

    return try allocator.dupeZ(u8, contents);
}
