const std = @import("std");

pub fn readfile_alloc(allocator: std.mem.Allocator, file: std.fs.File) ![]const u8 {
    var file_buffer: [1024]u8 = undefined;
    var reader = file.reader(&file_buffer);

    const stat = try file.stat();
    const size = stat.size;
    const contents = try reader.interface.readAlloc(allocator, size);

    // const buffer = allocator.alloc(u8, size+1);
    // const contents = try reader.interface.readSliceAll(buffer);
    // buffer[buffer.len - 1] = 0;

    return contents;
}

pub fn readfile_allocZ(
    allocator: std.mem.Allocator,
    file: std.fs.File,
) ![:0]const u8 {
    var file_buffer: [1024]u8 = undefined;
    var reader = file.reader(&file_buffer);

    const stat = try file.stat();
    const size = stat.size;

    var contents = try allocator.alloc(u8, size + 1);
    try reader.interface.readSliceAll(contents[0..size]);

    contents[size] = 0;

    return contents[0..size :0];
}
