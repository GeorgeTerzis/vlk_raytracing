const std = @import("std");

pub const Transform = struct {
    pos: [3]f32,
    rot: [3]f32,
    scale: [3]f32,
};
pub const Node = struct {
    geometry: []const u8,
    material: u32,
    transform: Transform,
};
pub const Geometry = struct {
    name: []const u8,
    path: []const u8,
};

pub const ZonConfig = struct {
    tile: [2]u32,
    geometry: []Geometry,
    nodes: []Node,
};

pub const Config = struct {
    tile: [2]u32,
    geometry: []Geometry,
    nodes: []Node,

    geometry_map: std.StringArrayHashMap(u32),
    node_map: std.StringArrayHashMap(u32),

    pub fn build(allocator: std.mem.Allocator, zon: ZonConfig) !Config {
        var geometry_map = std.StringArrayHashMap(u32).init(allocator);
        var node_map = std.StringArrayHashMap(u32).init(allocator);

        for (zon.geometry, 0..) |geo, i| {
            try geometry_map.put(geo.name, @intCast(i));
        }

        for (zon.nodes, 0..) |node, i| {
            if (!geometry_map.contains(node.geometry)) return error.UnknownGeometry;
            try node_map.put(node.geometry, @intCast(i));
        }

        return .{
            .tile = zon.tile,
            .geometry = zon.geometry,
            .nodes = zon.nodes,
            .geometry_map = geometry_map,
            .node_map = node_map,
        };
    }

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        self.geometry_map.deinit();
        self.node_map.deinit();
        std.zon.parse.free(allocator, @as(ZonConfig, .{
            .tile = self.tile,
            .geometry = self.geometry,
            .nodes = self.nodes,
        }));
    }
};

pub fn parse(allocator: std.mem.Allocator, src: [:0]const u8) !Config {
    const zon = try std.zon.parse.fromSlice(ZonConfig, allocator, src, null, .{ .free_on_error = true });
    return Config.build(allocator, zon);
}
