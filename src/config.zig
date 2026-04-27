const std = @import("std");

pub const Transform = struct {
    pos: [3]f32,
    rot: [3]f32,
    scale: [3]f32,
};

pub const Geometry = struct {
    name: []const u8,
    path: []const u8,
};

pub const Settings = struct {
    resolution: [2]u32,
    render_tile: [2]u32,
};

const ConfigNode = struct {
    geometry: []const u8,
    material: u32,
    transform: Transform,
};

const SerialScene = struct {
    geometry: []Geometry,
    nodes: []ConfigNode,
};

const SerialConfig = struct {
    settings: Settings,
    scene: SerialScene,
};

pub const Node = struct {
    geometry: u32,
    material: u32,
    transform: Transform,
};

pub const Config = struct {
    arena: *std.heap.ArenaAllocator,

    settings: Settings,
    geometry: []Geometry,
    nodes: []Node,

    geometry_map: std.StringArrayHashMap(u32),

    pub fn deinit(self: *Config) void {
        self.geometry_map.deinit();
        self.arena.deinit();
    }
};

pub fn parse(allocator: std.mem.Allocator, src: [:0]const u8) !Config {
    const arena = try allocator.create(std.heap.ArenaAllocator);
    errdefer allocator.destroy(arena);

    arena.* = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();

    const alloc = arena.allocator();
    const serial = try std.zon.parse.fromSlice(SerialConfig, alloc, src, null, .{});

    return build(alloc, arena, serial);
}

fn build(alloc: std.mem.Allocator, arena: *std.heap.ArenaAllocator, serial: SerialConfig) !Config {
    var geometry_map = std.StringArrayHashMap(u32).init(alloc);
    errdefer geometry_map.deinit();

    for (serial.scene.geometry, 0..) |geo, i| {
        try geometry_map.put(geo.name, @intCast(i));
    }

    const nodes = try alloc.alloc(Node, serial.scene.nodes.len);

    for (serial.scene.nodes, nodes) |cfg_node, *node| {
        const geo_idx = geometry_map.get(cfg_node.geometry) orelse
            return error.UnknownGeometry;
        node.* = .{
            .geometry = geo_idx,
            .material = cfg_node.material,
            .transform = cfg_node.transform,
        };
    }

    return .{
        .arena = arena,
        .settings = serial.settings,
        .geometry = serial.scene.geometry,
        .nodes = nodes,
        .geometry_map = geometry_map,
    };
}
