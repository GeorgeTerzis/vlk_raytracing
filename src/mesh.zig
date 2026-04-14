const std = @import("std");
pub const obj = @import("obj");

pub const local_mesh = struct {
    const vert = [3]f32;
    const normal = [3][3]f32;
    const uv = [2]f32;

    const triangle = [3]vert;
    const quad = [4]vert;

    const index = u32;

    verts: []vert,
    normals: []vert,

    indices: []index,
    normal_indices: []index,

    pub fn from_obj(
        allocator: std.mem.Allocator,
        obj_data: *const obj.ObjData,
    ) !local_mesh {
        var verts = try std.ArrayList(vert).initCapacity(allocator, 512);
        try verts.resize(allocator, (obj_data.vertices.len) / 3);
        @memcpy(verts.items, std.mem.bytesAsSlice([3]f32, std.mem.sliceAsBytes(obj_data.vertices)));

        var normals = try std.ArrayList(vert).initCapacity(allocator, 512);
        try normals.resize(allocator, (obj_data.normals.len) / 3);
        @memcpy(normals.items, std.mem.bytesAsSlice([3]f32, std.mem.sliceAsBytes(obj_data.normals)));

        var indices = try std.ArrayList(index).initCapacity(allocator, 512);
        var normal_indices = try std.ArrayList(index).initCapacity(allocator, 512);

        for (obj_data.meshes) |mesh| {
            var i: usize = 0;

            while (i + 2 < mesh.indices.len) : (i += 3) {
                try indices.append(allocator, @intCast(mesh.indices[i + 0].vertex.?));
                try normal_indices.append(allocator, @intCast(mesh.indices[i + 0].normal.?));

                try indices.append(allocator, @intCast(mesh.indices[i + 1].vertex.?));
                try normal_indices.append(allocator, @intCast(mesh.indices[i + 1].normal.?));

                try indices.append(allocator, @intCast(mesh.indices[i + 2].vertex.?));
                try normal_indices.append(allocator, @intCast(mesh.indices[i + 2].normal.?));
            }
        }

        return .{
            .verts = verts.items,
            .normals = normals.items,
            .indices = indices.items,
            .normal_indices = normal_indices.items,
        };
    }

    pub fn deinit(self: @This(), allocator: std.mem.Allocator) void {
        allocator.free(self.verts);
        allocator.free(self.indices);
        allocator.free(self.normal_indices);
        allocator.free(self.normals);
    }
};
