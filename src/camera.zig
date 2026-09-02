const mth = @import("mth");

const Self = @This();

pos: mth.float3 = .zero(),
rot: mth.quat = .identity(),
fov: f32 = 1,

pub const gpu = extern struct {
    pos: mth.gpu.float3 = .zero(),
    basis: mth.gpu.float3x3 = .identity(),
    fov: f32 = 0,
};

pub fn get_gpu(self: @This()) gpu {
    return .{
        .pos = .from(self.pos),
        .basis = .from(self.basis()),
        .fov = self.fov,
    };
}

pub fn forward(self: Self) mth.float3 {
    return self.rot.rotate(.init(.{ 0, 0, 1 }));
}

pub fn right(self: Self) mth.float3 {
    return self.rot.rotate(.init(.{ 1, 0, 0 }));
}

pub fn up(self: Self) mth.float3 {
    return self.rot.rotate(.init(.{ 0, 1, 0 }));
}

pub fn basis(self: Self) mth.float3x3 {
    const r = self.right();
    const u = self.up();
    const f = self.forward();

    return .{ .v = .{
        r, u, f,
    } };
}
