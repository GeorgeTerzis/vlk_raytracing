const std = @import("std");

pub const Render = struct {
    resolution: [2]u32,
    tile: [2]u32,
};
pub const Settings = struct {
    render: Render,
};
