const std = @import("std");

pub const Transform = struct {
    pos: [3]f32,
    rot: [3]f32,
    scale: [3]f32,
};

pub const Primitive = struct {
    name: []const u8,
    path: []const u8,
};

pub const Settings = struct {
    resolution: [2]u32,
    render_tile: [2]u32,
};

const ConfigAsset = struct {
    name: []const u8,
    primitive: []const u8,
    material: u32,
    transform: Transform,
};

const SerialScene = struct {
    primitive: []Primitive,
    assets: []ConfigAsset,
};

const SerialConfig = struct {
    settings: Settings,
    scene: SerialScene,
};

pub const Asset = struct {
    primitive: u32,
    material: u32,
    transform: Transform,
};

pub const Config = struct {
    arena: *std.heap.ArenaAllocator,

    settings: Settings,
    primitive: []Primitive,
    assets: []Asset,

    primitive_map: std.StringArrayHashMap(u32),
    asset_map: std.StringArrayHashMap(u32),

    pub fn deinit(self: *Config) void {
        self.primitive_map.deinit();
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
    var primitive_map = std.StringArrayHashMap(u32).init(alloc);
    errdefer primitive_map.deinit();

    var asset_map = std.StringArrayHashMap(u32).init(alloc);
    errdefer asset_map.deinit();

    for (serial.scene.primitive, 0..) |elm, i| {
        try primitive_map.put(elm.name, @intCast(i));
    }
    for (serial.scene.assets, 0..) |elm, i| {
        try asset_map.put(elm.name, @intCast(i));
    }

    const assets = try alloc.alloc(Asset, serial.scene.assets.len);

    for (serial.scene.assets, assets) |cfg_asset, *asset| {
        const p_idx = primitive_map.get(cfg_asset.primitive) orelse
            return error.UnknownGeometry;
        asset.* = .{
            .primitive = p_idx,
            .material = cfg_asset.material,
            .transform = cfg_asset.transform,
        };
    }

    return .{
        .arena = arena,
        .settings = serial.settings,
        .primitive = serial.scene.primitive,
        .assets = assets,
        .primitive_map = primitive_map,
        .asset_map = asset_map,
    };
}
