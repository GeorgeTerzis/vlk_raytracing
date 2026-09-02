const std = @import("std");
const builtin = @import("builtin");
const emma = @import("emma");
const config = @import("config.zig");

const sdl = emma.sdl;
const vk = emma.vk;

const mth = @import("mth");
const containers = @import("containers");
const Camera = @import("camera.zig");

const Sparse = containers.Sparse;
const Hive = containers.Hive;
const Handle = containers.Handle;

fn load_files(allocator: std.mem.Allocator, io: std.Io, paths: []const []const u8) ![][]const u8 {
    const out = try allocator.alloc([]const u8, paths.len);
    errdefer allocator.free(out);

    for (out, paths) |*slot, path| {
        const file = try std.Io.Dir.cwd().openFile(io, path, .{});
        defer file.close(io);
        slot.* = try emma.readfile_alloc(allocator, io, file);
    }

    return out;
}

fn free_files(allocator: std.mem.Allocator, spirvs: [][]const u8) void {
    for (spirvs) |data| {
        allocator.free(data);
    }
    allocator.free(spirvs);
}

pub const FileCache = struct {
    const Data = []const u8;

    const AsyncResult = union(enum) {
        data: Data,
        future: std.Io.Future(anyerror!Data),
    };

    const Storage = std.StringHashMap(Data);

    allocator: std.mem.Allocator,
    storage: Storage,
    mutex: std.Io.Mutex = .init,

    pub fn init(allocator: std.mem.Allocator) !@This() {
        return .{ .allocator = allocator, .storage = .init(allocator) };
    }

    pub fn deinit(self: *@This(), io: std.Io) void {
        self.mutex.lock(io) catch {};
        defer self.mutex.unlock(io);

        var it = self.storage.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.storage.deinit();
    }

    fn fetch_and_store(self: *@This(), io: std.Io, path: []const u8) anyerror!Data {
        const file = try std.Io.Dir.cwd().openFile(io, path, .{});
        defer file.close(io);
        const data = try emma.readfile_alloc(self.allocator, io, file);

        try self.mutex.lock(io);
        defer self.mutex.unlock(io);
        try self.storage.put(path, data);

        return data;
    }

    pub fn get_one(self: *@This(), io: std.Io, path: []const u8) !AsyncResult {
        {
            try self.mutex.lock(io);
            defer self.mutex.unlock(io);
            if (self.storage.get(path)) |data| return .{ .data = data };
        }

        const owned_path = try self.allocator.dupe(u8, path);
        errdefer self.allocator.free(owned_path);

        const future = io.async(fetch_and_store, .{ self, io, owned_path });
        return .{ .future = future };
    }

    pub fn get_one_sync(self: *@This(), io: std.Io, path: []const u8) !Data {
        var result = try self.get_one(io, path);
        return switch (result) {
            .data => |d| d,
            .future => |*f| try f.await(io),
        };
    }

    pub fn get_many(self: *@This(), io: std.Io, allocator: std.mem.Allocator, paths: []const []const u8) ![]Data {
        var results = try allocator.alloc(AsyncResult, paths.len);
        defer allocator.free(results);

        for (paths, 0..) |path, i| {
            results[i] = try self.get_one(io, path);
        }

        var data = try allocator.alloc(Data, paths.len);
        for (results, 0..) |*r, i| {
            data[i] = switch (r.*) {
                .data => |d| d,
                .future => |*f| try f.await(io),
            };
        }
        return data;
    }

    pub fn get_many_hetero(
        self: *@This(),
        io: std.Io,
        allocator: std.mem.Allocator,
        objs: anytype,
        get_path: fn (*const anyopaque) []const u8,
    ) ![]Data {
        var results = try allocator.alloc(AsyncResult, objs.len);
        defer allocator.free(results);

        for (objs, 0..) |obj, i| {
            const path = get_path(&obj);
            results[i] = try self.get_one(
                io,
                path,
            );
        }

        var data = try allocator.alloc(Data, objs.len);
        for (results, 0..) |*r, i| {
            data[i] = switch (r.*) {
                .data => |d| d,
                .future => |*f| try f.await(io),
            };
        }
        return data;
    }
};

pub fn Bindless(comptime _kind: vk.DescriptorType) type {
    return struct {
        pub const Self = @This();
        pub const Kind = _kind;
        pub const Info = emma.desc.Info(Kind);
        pub const Comp = struct { index: u32 };

        max_count: u32,

        info_list: []Info = undefined,
        free_list: []u32 = undefined,

        free_len: u32 = 0,
        len: u32 = 0,

        pub fn init(allocator: std.mem.Allocator, max_count: u32) !@This() {
            return .{
                .max_count = max_count,
                .info_list = try allocator.alloc(Info, max_count),
                .free_list = try allocator.alloc(u32, max_count),
            };
        }
        pub fn deinit(self: @This(), allocator: std.mem.Allocator) void {
            allocator.free(self.info_list);
            allocator.free(self.free_list);
        }

        pub fn register_one(self: *Self, info: Info) u32 {
            if (self.free_len > 0) {
                self.free_len -= 1;
                const idx = self.free_list[self.free_len];
                self.info_list[idx] = info;
                return idx;
            }
            std.debug.assert(self.len < self.max_count);
            const idx = self.len;
            self.info_list[idx] = info;
            self.len += 1;
            return idx;
        }
        pub fn erase(self: *Self, idx: u32) void {
            std.debug.assert(idx < self.len);
            self.free_list[self.free_len] = idx;
            self.free_len += 1;
        }
        pub fn update(self: *Self, idx: u32, info: Info) void {
            self.info_list[idx] = info;
        }
        pub fn build_write_single(self: Self, idx: u32, set: vk.DescriptorSet, bind: u32) vk.WriteDescriptorSet {
            return emma.desc.build_writes(Kind, set, bind, idx, self.info_list[idx .. idx + 1]);
        }
    };
}

pub const DescriptorLayoutCache = struct {
    const Entry = struct {
        layout: vk.DescriptorSetLayout,
    };

    const Key = struct {
        bindings: []const vk.DescriptorSetLayoutBinding,
        flags: []const vk.DescriptorBindingFlags,
    };

    const KeyContext = struct {
        pub fn hash(_: @This(), key: DescriptorLayoutCache.Key) u64 {
            var hasher = std.hash.Wyhash.init(0);
            std.hash.autoHashStrat(&hasher, key.bindings, .Deep);
            std.hash.autoHashStrat(&hasher, key.flags, .Deep);
            return hasher.final();
        }
        pub fn eql(_: @This(), a: DescriptorLayoutCache.Key, b: DescriptorLayoutCache.Key) bool {
            return emma.desc.eql_bindings(a.bindings, b.bindings) and
                emma.desc.eql_flags(a.flags, b.flags);
        }
    };

    device: *emma.vlk_device,
    map: std.HashMap(Key, Entry, KeyContext, std.hash_map.default_max_load_percentage),

    pub fn init(allocator: std.mem.Allocator, device: *emma.vlk_device) @This() {
        return .{
            .device = device,
            .map = .init(allocator),
        };
    }

    pub fn deinit(self: *@This()) void {
        var it = self.map.valueIterator();
        while (it.next()) |entry| {
            self.device.logical_device.destroyDescriptorSetLayout(entry.layout, null);
        }
        self.map.deinit();
    }

    pub fn get(self: *@This(), comptime Set: type) !vk.DescriptorSetLayout {
        const key = Key{
            .bindings = &Set.vlk_bindings,
            .flags = &Set.vlk_flags,
        };
        if (self.map.get(key)) |entry| return entry.layout;

        const layout = try Set.Layout.init(self.device);
        try self.map.put(key, .{ .layout = layout.handle });
        return layout.handle;
    }
};

const TemporalTexturesGpu = extern struct {
    const Temporal = extern struct {
        col: u32 = 0,
        norm: u32 = 0,
        pos: u32 = 0,
    };

    curr: Temporal = .{},
    hist: Temporal = .{},
};

// const TextureEnv2 = struct {
//     const Tag = extern struct { gen: u32 = 0 };
//     const RegistryHandle = emma.TextureRegistry.Handle;
//     const StorageHive = containers.Hive(Tag, u32);

//     const GraphComp = emma.sync.Graph.ResourceHandle;

//     const StorageImageSparse = Sparse(Tag, u32, u32);
//     const SampledImageSparse = Sparse(Tag, u32, u32);
//     const GraphSparse = Sparse(Tag, GraphComp, u32);
// };

const Env = struct {
    const TextureRegistryHandle = emma.TextureRegistry.Handle;

    const TextureTag = extern struct { gen: u32 = 0 };
    const TextureHandle = Handle(TextureTag);
    const TextureHive = containers.Hive(TextureTag, u32);

    pub const Sampler2DComp = u32;
    pub const StorageComp = u32;
    pub const GraphComp = emma.sync.Graph.ResourceHandle;

    pub const Sampler2DStorage = Sparse(TextureTag, Sampler2DComp, u32);
    pub const StorageImageStorage = Sparse(TextureTag, StorageComp, u32);
    pub const GraphSparse = Sparse(TextureTag, GraphComp, u32);

    pub const TextureInfo = struct {
        registry: TextureRegistryHandle,
        sampler2d: ?Sampler2DComp,
        storage: ?StorageComp,
        graph: ?GraphComp,
    };

    const TextureEnv = struct {
        handles: TextureHive,

        texture_registry: *emma.TextureRegistry,
        registry: []TextureRegistryHandle,

        sampled_img: Sampler2DStorage,
        storage_img: StorageImageStorage,
        graph_handles: GraphSparse,

        pub fn init(allocator: std.mem.Allocator, texture_registry: *emma.TextureRegistry, capacity: u16) !@This() {
            return .{
                .texture_registry = texture_registry,
                .handles = try .init_capacity(allocator, capacity),
                .registry = try allocator.alloc(TextureRegistryHandle, capacity),
                .sampled_img = try .init_alloc(allocator, capacity),
                .storage_img = try .init_alloc(allocator, capacity),
                .graph_handles = try .init_alloc(allocator, capacity),
            };
        }

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            self.handles.deinit(allocator);
            allocator.free(self.registry);
            self.sampled_img.deinit(allocator);
            self.storage_img.deinit(allocator);
            self.graph_handles.deinit(allocator);
        }

        pub fn create(self: *@This(), reg_handle: TextureRegistryHandle) TextureHandle {
            const slot = self.handles.alloc().?;
            const prev_gen = self.handles.get(slot).gen;
            const gen = prev_gen +% 1;

            self.handles.get(slot).* = .{ .gen = gen };
            self.registry[slot] = reg_handle;
            return .{ .slot = @intCast(slot), .gen = gen };
        }

        pub fn destroy(self: *@This(), id: TextureHandle) void {
            if (self.sampled_img.contains(id)) self.sampled_img.erase(id);
            if (self.storage_img.contains(id)) self.storage_img.erase(id);
            self.handles.erase(id.slot);
        }

        pub fn attach_sampler2d(self: *@This(), allocator: std.mem.Allocator, id: TextureHandle, idx: Sampler2DComp) !void {
            try self.sampled_img.insert(allocator, id, .{ .val = idx });
        }

        pub fn attach_storage(self: *@This(), allocator: std.mem.Allocator, id: TextureHandle, idx: StorageComp) !void {
            try self.storage_img.insert(allocator, id, .{ .val = idx });
        }

        pub fn attach_graph(self: *@This(), allocator: std.mem.Allocator, id: TextureHandle, idx: GraphComp) !void {
            try self.graph_handles.insert(allocator, id, .{ .val = idx });
        }

        pub fn get_all(self: *const @This(), id: TextureHandle) TextureInfo {
            return .{
                .registry = self.registry[id.slot],
                .sampler2d = if (self.sampled_img.get(id)) |c| c.val else null,
                .storage = if (self.storage_img.get(id)) |c| c.val else null,
                .graph = if (self.graph_handles.get(id)) |c| c.val else null,
            };
        }
    };
};

const EnvSets = struct {
    pub const Set = emma.desc.TypedSet(&.{
        .{ .kind = .sampler, .count = emma.vlk_samplers.mem_count(), .flags = emma.update_after_bind, .stages = emma.all_shader_stages },
        .{ .kind = .sampled_image, .count = 4096, .flags = emma.partialy_bound, .stages = emma.all_shader_stages },
        .{ .kind = .storage_image, .count = 4096, .flags = emma.partialy_bound, .stages = emma.all_shader_stages },
    });
};

fn count(comptime T: type) usize {
    const info = @typeInfo(T);
    return if (info == .@"struct" and info.@"struct".is_tuple) info.@"struct".fields.len else 1;
}
fn from_instances(sets: anytype) [count(@TypeOf(sets))]vk.DescriptorSet {
    const T = @TypeOf(sets);
    const is_tuple = @typeInfo(T) == .@"struct" and @typeInfo(T).@"struct".is_tuple;

    if (is_tuple) {
        var vk_sets: [sets.len]vk.DescriptorSet = undefined;
        inline for (0..sets.len) |i| {
            vk_sets[i] = sets[i].handle;
        }
        return vk_sets;
    } else {
        return .{sets.handle};
    }
}

pub fn Pipeline(
    comptime PCinfo: struct {
        Type: ?type,
        stages: vk.ShaderStageFlags,
        pub fn ranges_or_empty(self: @This()) vk.PushConstantRange {
            return if (self.Type) |T|
                vk.PushConstantRange{
                    .offset = 0,
                    .size = @sizeOf(T),
                    .stage_flags = self.stages,
                }
            else
                vk.PushConstantRange{};
        }
    },
    comptime _Sets: anytype,
) type {
    return struct {
        fn construct_set_layouts(comptime sets: anytype, desc_layouts: *DescriptorLayoutCache) ![sets.len]vk.DescriptorSetLayout {
            var layouts: [sets.len]vk.DescriptorSetLayout = undefined;
            inline for (0..sets.len) |i| {
                layouts[i] = try desc_layouts.get(sets[i]);
            }
            return layouts;
        }

        pub fn Compute(comptime group_x: u32, comptime group_y: u32, comptime group_z: u32) type {
            return struct {
                pub const Sets = _Sets;
                pub const PC = PCinfo.Type;

                pipeline: emma.vlk_compute_pipeline,

                pub fn init(
                    allocator: std.mem.Allocator,
                    u: *emma.vlk_unit,
                    desc_layouts: *DescriptorLayoutCache,
                    stage: vk.PipelineShaderStageCreateInfo,
                ) !@This() {
                    const pc_range = PCinfo.ranges_or_empty();
                    var layouts = try construct_set_layouts(Sets, desc_layouts);

                    return .{
                        .pipeline = try .init(
                            allocator,
                            u,
                            &.{pc_range},
                            &layouts,
                            stage,
                        ),
                    };
                }

                pub fn deinit(self: @This(), u: *emma.vlk_unit) void {
                    self.pipeline.deinit(&u.device);
                }

                pub fn record(
                    self: @This(),
                    cmd: vk.CommandBufferProxy,
                    set_instances: anytype,
                    pc: if (PC) |T| T else void,
                    extent: vk.Extent3D,
                ) void {
                    const sets = from_instances(set_instances);
                    cmd.bindPipeline(.compute, self.pipeline.pipeline.handle);
                    cmd.bindDescriptorSets(
                        .compute,
                        self.pipeline.pipeline.layout,
                        0,
                        &sets,
                        null,
                    );

                    if (PC) |T| {
                        cmd.pushConstants(
                            self.pipeline.pipeline.layout,
                            .{ .compute_bit = true },
                            0,
                            @sizeOf(T),
                            &pc,
                        );
                    }

                    const gx = (extent.width + (group_x - 1)) / group_x;
                    const gy = (extent.height + (group_y - 1)) / group_y;
                    const gz = (extent.depth + (group_z - 1)) / group_z;
                    cmd.dispatch(gx, gy, gz);
                }
            };
        }

        pub fn RayTracing(comptime _groups: []const vk.RayTracingShaderGroupCreateInfoKHR) type {
            return struct {
                pub const Sets = _Sets;
                pub const PC = PCinfo.Type;
                pub const groups = _groups;

                pipeline: emma.vlk_rt_pipeline,

                pub fn init(
                    allocator: std.mem.Allocator,
                    u: *emma.vlk_unit,
                    desc_layouts: *DescriptorLayoutCache,
                    rt_props: *const vk.PhysicalDeviceRayTracingPipelinePropertiesKHR,
                    shader_stages: []const vk.PipelineShaderStageCreateInfo,
                    is: emma.ImediateSubmit,
                ) !@This() {
                    const pc_range = PCinfo.ranges_or_empty();

                    var layouts = try construct_set_layouts(Sets, desc_layouts);

                    const pipeline = try emma.vlk_rt_pipeline.init(
                        allocator,
                        u,
                        rt_props,
                        &.{pc_range},
                        &layouts,
                        shader_stages,
                        groups,
                        is,
                    );

                    return .{ .pipeline = pipeline };
                }

                pub fn deinit(self: @This(), u: *emma.vlk_unit) void {
                    // descriptor set layouts belong to DescriptorLayoutCache, not here
                    self.pipeline.deinit(&u.vma, &u.device);
                }

                pub fn record(
                    self: @This(),
                    cmd: vk.CommandBufferProxy,
                    set_instances: anytype,
                    pc: if (PC) |T| T else void,
                    width: u32,
                    height: u32,
                ) void {
                    const sets = from_instances(set_instances);

                    cmd.bindPipeline(.ray_tracing_khr, self.pipeline.pipeline.handle);
                    cmd.bindDescriptorSets(
                        .ray_tracing_khr,
                        self.pipeline.pipeline.layout,
                        0,
                        &sets,
                        null,
                    );
                    if (PC) |T| {
                        cmd.pushConstants(
                            self.pipeline.pipeline.layout,
                            PCinfo.stages,
                            0,
                            @sizeOf(T),
                            &pc,
                        );
                    }
                    cmd.traceRaysKHR(
                        &self.pipeline.sbt.raygen_region,
                        &self.pipeline.sbt.miss_region,
                        &self.pipeline.sbt.closest_hit_region,
                        &self.pipeline.sbt.callable_region,
                        width,
                        height,
                        1,
                    );
                }
            };
        }

        pub fn Graphics(
            comptime color_formats: []const vk.Format,
            comptime depth_format: ?vk.Format,
        ) type {
            return struct {
                pub const Sets = _Sets;
                pub const PC = PCinfo.Type;

                pipeline: emma.vlk_graphics_pipeline,

                pub fn init(
                    device: *emma.vlk_device,
                    desc_layouts: *DescriptorLayoutCache,
                    stages: []const vk.PipelineShaderStageCreateInfo,
                ) !@This() {
                    const pc_range = PCinfo.ranges_or_empty();

                    var layouts = try construct_set_layouts(Sets, desc_layouts);

                    const pipeline = try emma.vlk_graphics_pipeline.init(
                        device,
                        &.{pc_range},
                        &layouts,
                        stages,
                        color_formats,
                        depth_format,
                    );

                    return .{ .pipeline = pipeline };
                }

                pub fn deinit(self: @This(), device: *emma.vlk_device) void {
                    self.pipeline.deinit(device);
                }

                fn bind_for_draw(
                    self: @This(),
                    cmd: vk.CommandBufferProxy,
                    set_instances: anytype,
                    pc: if (PC) |T| T else void,
                    viewport: vk.Viewport,
                    scissor: vk.Rect2D,
                ) void {
                    const sets = from_instances(set_instances);
                    cmd.bindPipeline(.graphics, self.pipeline.pipeline.handle);
                    cmd.bindDescriptorSets(.graphics, self.pipeline.pipeline.layout, 0, &sets, null);
                    if (PC) |T| {
                        cmd.pushConstants(self.pipeline.pipeline.layout, PCinfo.stages, 0, @sizeOf(T), &pc);
                    }
                    cmd.setViewport(0, &.{viewport});
                    cmd.setScissor(0, &.{scissor});
                }

                pub fn record(
                    self: @This(),
                    cmd: vk.CommandBufferProxy,
                    set_instances: anytype,
                    pc: if (PC) |T| T else void,
                    viewport: vk.Viewport,
                    scissor: vk.Rect2D,
                    vertex_count: u32,
                    instance_count: u32,
                ) void {
                    self.bind_for_draw(cmd, set_instances, pc, viewport, scissor);
                    cmd.draw(vertex_count, instance_count, 0, 0);
                }

                pub fn record_indexed(
                    self: @This(),
                    cmd: vk.CommandBufferProxy,
                    set_instances: anytype,
                    pc: if (PC) |T| T else void,
                    viewport: vk.Viewport,
                    scissor: vk.Rect2D,
                    index_buffer: emma.vlk_vma_buffer_view,
                    index_type: vk.IndexType,
                    index_count: u32,
                    instance_count: u32,
                    first_index: u32,
                    vertex_offset: i32,
                    first_instance: u32,
                ) void {
                    self.bind_for_draw(cmd, set_instances, pc, viewport, scissor);
                    cmd.bindIndexBuffer(index_buffer.buffer.handle, index_buffer.offset, index_type);
                    cmd.drawIndexed(index_count, instance_count, first_index, vertex_offset, first_instance);
                }

                pub fn record_indirect(
                    self: @This(),
                    cmd: vk.CommandBufferProxy,
                    set_instances: anytype,
                    pc: if (PC) |T| T else void,
                    viewport: vk.Viewport,
                    scissor: vk.Rect2D,
                    indirect_buffer: emma.vlk_vma_buffer_view,
                    draw_count: u32,
                    stride: u32,
                ) void {
                    self.bind_for_draw(cmd, set_instances, pc, viewport, scissor);
                    cmd.drawIndirect(indirect_buffer.buffer.handle, indirect_buffer.offset, draw_count, stride);
                }

                pub fn record_indexed_indirect(
                    self: @This(),
                    cmd: vk.CommandBufferProxy,
                    set_instances: anytype,
                    pc: if (PC) |T| T else void,
                    viewport: vk.Viewport,
                    scissor: vk.Rect2D,
                    index_buffer: emma.vlk_vma_buffer_view,
                    index_type: vk.IndexType,
                    indirect_buffer: emma.vlk_vma_buffer_view,
                    draw_count: u32,
                    stride: u32,
                ) void {
                    self.bind_for_draw(cmd, set_instances, pc, viewport, scissor);
                    cmd.bindIndexBuffer(index_buffer.buffer.handle, index_buffer.offset, index_type);
                    cmd.drawIndexedIndirect(indirect_buffer.buffer.handle, indirect_buffer.offset, draw_count, stride);
                }
            };
        }
    };
}

pub const Pathtracing = struct {
    const Buffers = struct {
        verts: vk.DeviceAddress,
        norms: vk.DeviceAddress,
        uvs: vk.DeviceAddress,
        indices: vk.DeviceAddress,
        normal_indices: vk.DeviceAddress,
    };

    const Geometry = extern struct {
        buffer_index: u32,
    };

    const PC = extern struct {
        res: mth.gpu.uint2 = .zero(),
        time: f32 = 0.0,
        frame: u32 = 0,
        pos: mth.gpu.uint2 = .zero(),

        cam: Camera.gpu = .{},
        prev_cam: Camera.gpu = .{},

        skybox: u32,
        temporal_textures: TemporalTexturesGpu = .{},
        raw: u32,

        buffers: vk.DeviceAddress = 0,
        geometries: vk.DeviceAddress = 0,
        ranges: vk.DeviceAddress = 0,
        materials: vk.DeviceAddress = 0,
    };

    pub const set0 = EnvSets.Set;
    pub const Set1 = emma.desc.TypedSet(&.{
        .{
            .kind = .acceleration_structure_khr,
            .count = 1,
            .flags = emma.update_after_bind,
            .stages = emma.shader_stages.all(),
        },
    });
    pub const Sets = .{ set0, Set1 };

    const groups = [_]vk.RayTracingShaderGroupCreateInfoKHR{
        emma.rt_group_info.general(0),
        emma.rt_group_info.general(1),
        emma.rt_group_info.general(4),
        emma.rt_group_info.triangles_hit(2),
        emma.rt_group_info.triangles_hit(3),
    };
    pub const pipeline = Pipeline(.{ .Type = PC, .stages = emma.shader_stages.raygen().miss().closest_hit().val() }, Sets).RayTracing(&groups);
};

const AA = struct {
    pub const PC = extern struct {
        col_input: u32,
        norm_input: u32,
        pos_input: u32,
        output: u32,
        stepwidth: f32,
        do_tonemap: u32,
    };
    const pipeline = Pipeline(.{ .Type = PC, .stages = emma.shader_stages.compute().val() }, .{EnvSets.Set}).Compute(8, 8, 1);
};

const TA = struct {
    pub const PC = extern struct {
        cam: Camera.gpu,
        prev_cam: Camera.gpu,
        temporal_textures: TemporalTexturesGpu,
        raw: u32,
    };
    const pipeline = Pipeline(.{ .Type = PC, .stages = emma.shader_stages.compute().val() }, .{EnvSets.Set}).Compute(8, 8, 1);
};

const ThreadContext = struct {
    allocator: std.mem.Allocator,
    path: []const u8,
    result: ?emma.local_geometry.geometry = null,
    err: ?anyerror = null,
    duration_ns: i64 = 0,
};

fn load_geometry(allocator: std.mem.Allocator, io: std.Io, filepath: []const u8) !emma.local_geometry.geometry {
    const file = try std.Io.Dir.cwd().openFile(io, filepath, .{});
    defer file.close(io);

    const d = try emma.readfile_alloc(allocator, io, file);
    defer allocator.free(d);

    var obj_model = try emma.obj.parseObj(allocator, d);
    defer obj_model.deinit(allocator);

    return emma.local_geometry.geometry.from_obj(allocator, &obj_model);
}

fn load_geometry_thread(ctx: *ThreadContext, io: std.Io, clock: std.Io.Clock) void {
    const start = clock.now(io);
    ctx.result = load_geometry(ctx.allocator, io, ctx.path) catch |e| {
        ctx.err = e;
        return;
    };
    const end = clock.now(io);
    const dur = start.durationTo(end);
    ctx.duration_ns = dur.toMicroseconds();
}

fn build_local_geometry(
    allocator: std.mem.Allocator,
    io: std.Io,
    clock: std.Io.Clock,
    list: []const config.Primitive,
) ![]emma.local_geometry.geometry {
    const local_geometries = try allocator.alloc(emma.local_geometry.geometry, list.len);
    errdefer allocator.free(local_geometries);

    const contexts = try allocator.alloc(ThreadContext, list.len);
    defer allocator.free(contexts);

    const threads = try allocator.alloc(std.Thread, list.len);
    defer allocator.free(threads);

    for (list, contexts) |geo, *ctx| {
        ctx.* = .{ .allocator = allocator, .path = geo.path };
    }

    for (contexts, threads) |*ctx, *thread| {
        thread.* = try std.Thread.spawn(.{}, load_geometry_thread, .{ ctx, io, clock });
    }

    for (threads) |thread| {
        thread.join();
    }

    for (contexts, local_geometries, 0..) |ctx, *geo, i| {
        if (ctx.err) |e| return e;
        geo.* = ctx.result.?;
        std.debug.print("geometry:{d} {s}: {d:.3}ms\n", .{
            i,
            list[i].name,
            @as(f64, @floatFromInt(ctx.duration_ns)) / std.time.ns_per_ms,
        });
    }
    return local_geometries;
}

fn upload_skybox(
    allocator: std.mem.Allocator,
    u: *emma.vlk_unit,
    is: emma.ImediateSubmit,
    staging_pool: *std.ArrayList(emma.vlk_vma_buffer),
    graph: *emma.sync.Graph,
    handle: emma.sync.Graph.ResourceHandle,
    texture: emma.vlk_image,
    pixels: emma.exrimg,
) !void {
    try staging_pool.append(allocator, try emma.vlk_upload_buffer_with_data(
        &u.vma,
        std.mem.sliceAsBytes(pixels.pixels),
    ));

    try is.begin();
    {
        _ = try graph.use(is.cmd, handle, .{
            .access = .w,
            .state = .{ .layout = .transfer_dst_optimal },
            .stage_mask = .{ .copy_bit = true },
            .access_mask = .{ .transfer_write_bit = true },
        });

        const region = vk.BufferImageCopy{
            .buffer_offset = 0,
            .buffer_row_length = 0,
            .buffer_image_height = 0,
            .image_subresource = .{
                .aspect_mask = .{ .color_bit = true },
                .mip_level = 0,
                .base_array_layer = 0,
                .layer_count = 1,
            },
            .image_offset = .{ .x = 0, .y = 0, .z = 0 },
            .image_extent = texture.extent,
        };

        const regions = [_]emma.vk.BufferImageCopy{region};
        is.cmd.copyBufferToImage(
            staging_pool.getLast().handle,
            texture.handle,
            .transfer_dst_optimal,
            &regions,
        );
    }
    try is.submit_and_wait(u.queue(), u.device.logical_device);

    graph.advance_submission();
}

fn build_device_geometry(
    allocator: std.mem.Allocator,
    u: *emma.vlk_unit,
    local_geometries: []emma.local_geometry.geometry,
    is: emma.ImediateSubmit,
) ![]emma.device_geometry {
    var device_geometries = try std.ArrayList(emma.device_geometry).initCapacity(allocator, 10);
    var staging_buffers = try std.ArrayList(emma.vlk_vma_buffer).initCapacity(allocator, 4);
    defer {
        for (staging_buffers.items) |sb| {
            sb.deinit(&u.vma);
        }
        staging_buffers.deinit(allocator);
    }
    try is.begin();
    for (local_geometries) |mesh| {
        const result = try emma.device_geometry.init_from_mesh(
            allocator,
            &staging_buffers,
            &u.vma,
            is.cmd,
            &mesh,
        );
        try device_geometries.append(allocator, result);
    }
    try is.submit_and_wait(u.queue(), u.device.logical_device);

    return device_geometries.toOwnedSlice(allocator);
}

fn register_rw_sampled(
    allocator: std.mem.Allocator,
    texture_registry: *emma.TextureRegistry,
    env: *Env.TextureEnv,
    graph: *emma.sync.Graph,
    storage_bindless: *Bindless(.storage_image),
    sampled_image_bindless: *Bindless(.sampled_image),
    format: vk.Format,
    usage: vk.ImageUsageFlags,
    extent: vk.Extent3D,
) !Env.TextureHandle {
    const reg_handle = try texture_registry.register(format, usage, .{ .color_bit = true }, extent, false);
    const texture = texture_registry.get(reg_handle);
    const id = env.create(reg_handle);

    const sampled_image = sampled_image_bindless.register_one(.{
        .image_view = texture.view,
        .image_layout = .shader_read_only_optimal,
        .sampler = .null_handle,
    });
    try env.attach_sampler2d(allocator, id, sampled_image);

    const storage = storage_bindless.register_one(.{
        .image_view = texture.view,
        .image_layout = .general,
        .sampler = .null_handle,
    });
    try env.attach_storage(allocator, id, storage);

    const resource = try graph.register_image(texture.handle, texture.full_subresource_range(), .{});
    try env.attach_graph(allocator, id, resource);

    return id;
}

const BindlessRegistries = struct {
    storage_images: Bindless(.storage_image),
    sampled_images: Bindless(.sampled_image),

    pub fn register(self: *@This()) void {
        self.sampled_images.register_one();
        self.storage_images.register_one();
    }
};

pub const PerFrameData = struct {
    pub const Gbuffer = struct {
        col: Env.TextureHandle = .{},
        pos: Env.TextureHandle = .{},
        norm: Env.TextureHandle = .{},
        id: Env.TextureHandle = .{},
    };

    gbuffers: Gbuffer = .{},
    output: Env.TextureHandle = .{},
};

const RenderState = struct {
    cam: Camera = .{},
    prev_cam: Camera = .{},

    frame: usize = 0,
    mouse: mth.float2 = .zero(),
    flush: bool = false,
    delta: f64 = 0.0,

    pfd: std.MultiArrayList(PerFrameData),

    pub fn init(allocator: std.mem.Allocator, frames_in_flight: u32, cam: Camera) !@This() {
        var pfd = std.MultiArrayList(PerFrameData).empty;

        try pfd.resize(allocator, frames_in_flight);

        return .{ .cam = cam, .pfd = pfd };
    }
    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        self.pfd.deinit(allocator);
    }
};

pub fn main(init: std.process.Init) !void {
    const clock = std.Io.Clock.awake;
    var args = init.minimal.args;
    const args_slice = try args.toSlice(init.arena.allocator());

    const scene_filepath = if (args_slice.len < 2) "./scene.zon" else args_slice[1];
    std.log.info("Using scene from \"{s}\"", .{scene_filepath});

    try emma.sdl_init();
    defer emma.sdl_deinit();

    const DebugAllocator = std.heap.DebugAllocator(.{ .thread_safe = true });
    var debug_allocator = DebugAllocator.init;

    const allocator: std.mem.Allocator = if (builtin.mode == .Debug)
        debug_allocator.allocator()
    else
        std.heap.smp_allocator;

    var io_ctx = std.Io.Threaded.init(allocator, .{});
    const io = io_ctx.io();
    {
        var key_state = std.mem.zeroes([sdl.c.SDL_SCANCODE_COUNT]bool);

        var scene_config = blk: {
            const file = try std.Io.Dir.cwd().openFile(io, scene_filepath, .{});
            defer file.close(io);

            const src = try emma.readfile_allocZ(allocator, io, file);
            defer allocator.free(src);
            const result = try config.parse(allocator, src);

            break :blk result;
        };

        defer scene_config.deinit();

        const width: usize = 1440;
        const height: usize = 1440;

        var u = try emma.vlk_unit.init(allocator, width, height);
        defer u.deinit(allocator);
        std.log.info("{s}", .{u.props.device_name});
        std.log.info("Max push constant size {}", .{u.props.limits.max_push_constants_size});

        var file_cache = try FileCache.init(allocator);
        defer file_cache.deinit(io);

        const files = try file_cache.get_many(io, allocator, &.{
            "./src/shaders/hw_raytracing/shader.spv",
            "./src/shaders/aa/shader.spv",
            "./src/shaders/ta/shader.spv",
            "./enviroments/sky.exr",
        });
        const hwrt_spirv = files[0];
        const aa_spirv = files[1];
        const ta_spirv = files[2];
        const skybox_bytes = files[3];

        allocator.free(files);
        const hetero_begin = std.Io.Timestamp.now(io, clock);
        const hetero = try file_cache.get_many_hetero(
            io,
            allocator,
            scene_config.primitive,
            struct {
                fn getPath(any: *const anyopaque) []const u8 {
                    const obj: *const config.Primitive = @ptrCast(@alignCast(any));
                    return obj.path;
                }
            }.getPath,
        );
        const hetero_dur = hetero_begin.untilNow(io, clock);
        std.debug.print("get_many_hetero loaded {d} primitive files in {d:.2}ms\n", .{ hetero.len, hetero_dur.toMilliseconds() });
        allocator.free(hetero);

        const local_geometry_storage = try build_local_geometry(allocator, io, clock, scene_config.primitive);

        defer {
            for (local_geometry_storage) |*elm| {
                elm.deinit(allocator);
            }
            allocator.free(local_geometry_storage);
        }

        var command_buffers = try emma.vlk_command_buffer_allocation.init(
            allocator,
            u.device.logical_device,
            u.cmd_pool.handle,
            10,
        );
        defer command_buffers.deinit(allocator);

        const is = try emma.ImediateSubmit.init(
            &u.device,
            command_buffers.buffers[0],
        );
        defer is.deinit(&u.device);

        const device_geometry_storage = try build_device_geometry(allocator, &u, local_geometry_storage, is);
        defer {
            for (device_geometry_storage) |mesh| {
                mesh.deinit(&u.vma);
            }
            allocator.free(device_geometry_storage);
        }

        var blas_geometry_storage = std.MultiArrayList(emma.raytracing_geometry_data){};
        try blas_geometry_storage.ensureTotalCapacity(allocator, 5);
        defer blas_geometry_storage.deinit(allocator);

        var blas_ranges = try std.ArrayList(emma.blas_geometry_range).initCapacity(allocator, scene_config.assets.len);
        defer blas_ranges.deinit(allocator);

        var materials = try std.ArrayList(u32).initCapacity(allocator, scene_config.assets.len);
        defer materials.deinit(allocator);

        var instance_transforms = try std.ArrayList(vk.TransformMatrixKHR).initCapacity(allocator, scene_config.assets.len);
        defer instance_transforms.deinit(allocator);

        var staging_pool = try std.ArrayList(emma.vlk_vma_buffer).initCapacity(allocator, 10);
        defer {
            for (staging_pool.items) |buffer| {
                buffer.deinit(&u.vma);
            }
            staging_pool.deinit(allocator);
        }

        for (scene_config.assets) |node| {
            const begin = blas_geometry_storage.len;
            {
                const len = 1;
                {
                    {
                        {
                            const geometry_handle: u32 = node.primitive;
                            const geometry = emma.raytracing_geometry_data.init(device_geometry_storage, geometry_handle, &u.device);
                            try blas_geometry_storage.append(allocator, geometry);
                        }
                        {
                            const pos = mth.float3.from_array(node.transform.pos);
                            const scale = mth.float3.from_array(node.transform.scale);

                            const angles = node.transform.rot;
                            const qx = mth.quat.from_axis_angle(mth.float3.init(.{ 1, 0, 0 }), angles[0]);
                            const qy = mth.quat.from_axis_angle(mth.float3.init(.{ 0, 1, 0 }), angles[1]);
                            const qz = mth.quat.from_axis_angle(mth.float3.init(.{ 0, 0, 1 }), angles[2]);

                            const rot = mth.quat.mul(mth.quat.mul(qz, qy), qx);

                            const t = mth.float4x4.translation(pos);
                            const r = rot.to_mat4();
                            const s = mth.float4x4.scaling(scale);
                            const mat = t.mul_mat(4, r).mul_mat(4, s);

                            const vk_trans = emma.mat4_to_vk_transform(mat);
                            try instance_transforms.append(allocator, vk_trans);
                        }
                        {
                            const material = node.material;
                            try materials.append(allocator, material);
                        }
                    }

                    try blas_ranges.append(allocator, .{
                        .begin = @intCast(begin),
                        .len = @intCast(len),
                    });
                }
            }
        }

        var blas_list = try std.ArrayList(emma.rt_acceleration_structure).initCapacity(allocator, 10);
        {
            const begin_time = std.Io.Timestamp.now(io, clock);
            try is.begin();
            for (blas_ranges.items) |range| {
                const begin = range.begin;
                const len = range.len;
                const end = begin + len;

                const geometries = blas_geometry_storage.items(.geometry)[begin..end];
                const ranges = blas_geometry_storage.items(.range)[begin..end];

                const blas = try emma.rt_acceleration_structure.init_blas(
                    allocator,
                    &u.vma,
                    &u.device,
                    geometries,
                    ranges,
                    .{ .prefer_fast_trace_bit_khr = true },
                    &staging_pool,
                    is.cmd,
                );
                try blas_list.append(allocator, blas);
            }
            try is.submit_and_wait(u.queue(), u.device.logical_device);

            const duration = begin_time.untilNow(io, clock);
            std.debug.print("created BLAS structures in {d:.2}ms\n", .{duration.toMilliseconds()});
        }
        defer {
            for (blas_list.items) |b| {
                b.deinit(&u.vma, &u.device);
            }
            blas_list.deinit(allocator);
        }

        try is.begin();
        var device_materials = blk: {
            try staging_pool.append(allocator, try emma.vlk_upload_buffer_with_data(
                &u.vma,
                std.mem.sliceAsBytes(materials.items),
            ));
            const buffer = try emma.vlk_vma_buffer.init(
                &u.vma,
                staging_pool.getLast().size,
                emma.c_libs.VK_BUFFER_USAGE_TRANSFER_DST_BIT |
                    emma.c_libs.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT |
                    emma.c_libs.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
                emma.c_libs.VMA_MEMORY_USAGE_AUTO,
                0,
            );
            staging_pool.getLast().cmd_copy_to(&buffer, is.cmd);

            break :blk buffer;
        };
        defer device_materials.deinit(&u.vma);

        var buffers = blk: {
            var buffers_info = try std.ArrayList(Pathtracing.Buffers).initCapacity(allocator, device_geometry_storage.len);
            defer buffers_info.deinit(allocator);

            for (device_geometry_storage) |*mesh| {
                buffers_info.appendAssumeCapacity(
                    .{
                        .verts = mesh.vertex_buffer.address(&u.device),
                        .norms = mesh.normal_buffer.address(&u.device),
                        .uvs = 0,
                        .indices = mesh.index_buffer.address(&u.device),
                        .normal_indices = mesh.normal_index_buffer.address(&u.device),
                    },
                );
            }

            try staging_pool.append(allocator, try emma.vlk_upload_buffer_with_data(
                &u.vma,
                std.mem.sliceAsBytes(buffers_info.items),
            ));

            const buffer = try emma.vlk_vma_buffer.init(
                &u.vma,
                staging_pool.getLast().size,
                emma.c_libs.VK_BUFFER_USAGE_TRANSFER_DST_BIT |
                    emma.c_libs.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
                emma.c_libs.VMA_MEMORY_USAGE_AUTO,
                0,
            );

            staging_pool.getLast().cmd_copy_to(&buffer, is.cmd);

            break :blk buffer;
        };
        defer buffers.deinit(&u.vma);

        var geometry_buffer = blk: {
            const items = blas_geometry_storage.items(.index);
            const slice = std.mem.sliceAsBytes(items);
            try staging_pool.append(allocator, try emma.vlk_upload_buffer_with_data(&u.vma, slice));

            const buffer = try emma.vlk_vma_buffer.init(
                &u.vma,
                staging_pool.getLast().size,
                emma.c_libs.VK_BUFFER_USAGE_TRANSFER_DST_BIT |
                    emma.c_libs.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
                emma.c_libs.VMA_MEMORY_USAGE_AUTO,
                0,
            );

            staging_pool.getLast().cmd_copy_to(&buffer, is.cmd);

            break :blk buffer;
        };
        defer geometry_buffer.deinit(&u.vma);

        var range_buffer = blk: {
            const items = blas_ranges.items;
            const slice = std.mem.sliceAsBytes(items);
            try staging_pool.append(allocator, try emma.vlk_upload_buffer_with_data(&u.vma, slice));

            const buffer = try emma.vlk_vma_buffer.init(
                &u.vma,
                staging_pool.getLast().size,
                emma.c_libs.VK_BUFFER_USAGE_TRANSFER_DST_BIT |
                    emma.c_libs.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
                emma.c_libs.VMA_MEMORY_USAGE_AUTO,
                0,
            );

            staging_pool.getLast().cmd_copy_to(&buffer, is.cmd);

            break :blk buffer;
        };
        defer range_buffer.deinit(&u.vma);
        try is.submit_and_wait(u.queue(), u.device.logical_device);

        const tlas = try emma.rt_acceleration_structure.init_tlas(
            allocator,
            &u.vma,
            &u.device,
            blas_list.items,
            instance_transforms.items,
            .{ .prefer_fast_trace_bit_khr = true },
            &staging_pool,
            is,
        );
        defer tlas.deinit(&u.vma, &u.device);

        var desc_layouts = DescriptorLayoutCache.init(allocator, &u.device);
        defer desc_layouts.deinit();

        const hwrt_mod = try emma.ShaderModule.init(&u.device, hwrt_spirv);
        defer hwrt_mod.deinit(&u.device);

        const hwrt_stages = [_]vk.PipelineShaderStageCreateInfo{
            hwrt_mod.get_stage("raygen_entry", emma.shader_stages.raygen().val()),
            hwrt_mod.get_stage("miss_entry", emma.shader_stages.miss().val()),
            hwrt_mod.get_stage("closest_hit_entry", emma.shader_stages.closest_hit().val()),
            hwrt_mod.get_stage("shadow_closest_hit_entry", emma.shader_stages.closest_hit().val()),
            hwrt_mod.get_stage("shadow_miss_entry", emma.shader_stages.miss().val()),
        };

        var hwrt = try Pathtracing.pipeline.init(
            allocator,
            &u,
            &desc_layouts,
            &u.rtprops,
            &hwrt_stages,
            is,
        );
        defer hwrt.deinit(&u);

        const aa_mod = try u.device.logical_device.createShaderModule(
            &.{
                .code_size = aa_spirv.len,
                .p_code = @ptrCast(@alignCast(aa_spirv.ptr)),
            },
            null,
        );
        defer u.device.logical_device.destroyShaderModule(aa_mod, null);
        const aa_stage = emma.vlk_shader_stage.init(.{ .compute_bit = true }, "main", aa_mod, null);
        var aa = try AA.pipeline.init(allocator, &u, &desc_layouts, aa_stage);
        defer aa.deinit(&u);

        const ta_mod = try u.device.logical_device.createShaderModule(
            &.{
                .code_size = ta_spirv.len,
                .p_code = @ptrCast(@alignCast(ta_spirv.ptr)),
            },
            null,
        );
        defer u.device.logical_device.destroyShaderModule(ta_mod, null);
        const ta_stage = emma.vlk_shader_stage.init(.{ .compute_bit = true }, "main", ta_mod, null);
        var ta = try TA.pipeline.init(allocator, &u, &desc_layouts, ta_stage);
        defer ta.deinit(&u);

        {
            var texture_registry = emma.TextureRegistry.init(&u, allocator);
            defer texture_registry.deinit();

            var semaphore_pool = emma.sync.SemaphorePool.init(allocator, &u);
            defer semaphore_pool.deinit();

            var graph = emma.sync.Graph.init(allocator, &semaphore_pool);
            defer graph.deinit();

            var bindless_registries = BindlessRegistries{
                .sampled_images = try .init(allocator, 4096),
                .storage_images = try .init(allocator, 4096),
            };
            defer bindless_registries.sampled_images.deinit(allocator);
            defer bindless_registries.storage_images.deinit(allocator);
            var env: Env.TextureEnv = try .init(allocator, &texture_registry, 4096 * 2);
            defer env.deinit(allocator);

            const desc_pool = try emma.vlk_descriptor_pool.init(&u.device, &.{
                emma.desc.pool_size(.combined_image_sampler, 8192),
                emma.desc.pool_size(.storage_image, 8192),
                emma.desc.pool_size(.acceleration_structure_khr, 8192),
                emma.desc.pool_size(.sampled_image, 8192),
                emma.desc.pool_size(.sampler, 64),
            }, 20, .{ .update_after_bind_bit = true });
            defer desc_pool.deinit(u.device.logical_device);

            const skybox_img = try emma.exrimg.from_mem(skybox_bytes);
            const skybox_extent = vk.Extent3D{
                .width = skybox_img.width,
                .height = skybox_img.height,
                .depth = 1,
            };
            const output_extent = vk.Extent3D{
                .width = scene_config.settings.resolution[0],
                .height = scene_config.settings.resolution[1],
                .depth = 1,
            };

            const output_id = try register_rw_sampled(
                allocator,
                &texture_registry,
                &env,
                &graph,
                &bindless_registries.storage_images,
                &bindless_registries.sampled_images,
                emma.vlk_format.rgb10a2,
                .{ .transfer_dst_bit = true, .transfer_src_bit = true, .sampled_bit = true, .storage_bit = true },
                output_extent,
            );

            var atrous: [2]Env.TextureHandle = undefined;
            for (0..atrous.len) |i| {
                atrous[i] = try register_rw_sampled(
                    allocator,
                    &texture_registry,
                    &env,
                    &graph,
                    &bindless_registries.storage_images,
                    &bindless_registries.sampled_images,
                    emma.vlk_format.rgba32f,
                    .{ .transfer_dst_bit = true, .transfer_src_bit = true, .sampled_bit = true, .storage_bit = true },
                    output_extent,
                );
            }

            const raw_id = try register_rw_sampled(
                allocator,
                &texture_registry,
                &env,
                &graph,
                &bindless_registries.storage_images,
                &bindless_registries.sampled_images,
                emma.vlk_format.rgba32f,
                .{ .transfer_dst_bit = true, .transfer_src_bit = true, .sampled_bit = true, .storage_bit = true },
                output_extent,
            );

            const skybox_id = try register_rw_sampled(
                allocator,
                &texture_registry,
                &env,
                &graph,
                &bindless_registries.storage_images,
                &bindless_registries.sampled_images,
                emma.vlk_format.rgba32f,
                .{ .transfer_dst_bit = true, .sampled_bit = true, .storage_bit = true },
                skybox_extent,
            );

            const MAX_FRAMES_IN_FLIGHT = 3;

            var temporal_ids: [MAX_FRAMES_IN_FLIGHT][3]Env.TextureHandle = undefined;
            {
                for (0..temporal_ids.len) |i| {
                    for (0..temporal_ids[i].len) |k| {
                        temporal_ids[i][k] = try register_rw_sampled(
                            allocator,
                            &texture_registry,
                            &env,
                            &graph,
                            &bindless_registries.storage_images,
                            &bindless_registries.sampled_images,
                            if (k == 2) emma.vlk_format.rgba32f else emma.vlk_format.rgba16f,
                            .{ .transfer_dst_bit = true, .transfer_src_bit = true, .sampled_bit = true, .storage_bit = true },
                            output_extent,
                        );
                    }
                }
            }
            {
                try is.begin();
                for (0..temporal_ids.len) |slot| {
                    inline for (0..3) |i| {
                        const info = env.get_all(temporal_ids[slot][i]);
                        _ = try graph.use(is.cmd, info.graph.?, .{
                            .access = .w,
                            .state = .{ .layout = .transfer_dst_optimal },
                            .stage_mask = .{ .clear_bit = true },
                            .access_mask = .{ .transfer_write_bit = true },
                        });
                        const img = texture_registry.get(info.registry);
                        is.cmd.clearColorImage(img.handle, .transfer_dst_optimal, @ptrCast(&vk.ClearColorValue{ .float_32 = .{ 0, 0, 0, 0 } }), &.{img.full_subresource_range()});
                    }
                }
                try is.submit_and_wait(u.queue(), u.device.logical_device);
                graph.advance_submission();
            }
            const output_info = env.get_all(output_id);
            const skybox_info = env.get_all(skybox_id);

            try upload_skybox(
                allocator,
                &u,
                is,
                &staging_pool,
                &graph,
                skybox_info.graph.?,
                texture_registry.get(skybox_info.registry),
                skybox_img,
            );

            {
                try is.begin();
                inline for (0..3) |i| {
                    const info = env.get_all(temporal_ids[0][i]);
                    _ = try graph.use(is.cmd, info.graph.?, .{
                        .access = .w,
                        .state = .{ .layout = .transfer_dst_optimal },
                        .stage_mask = .{ .clear_bit = true },
                        .access_mask = .{ .transfer_write_bit = true },
                    });
                    const img = texture_registry.get(info.registry);
                    is.cmd.clearColorImage(
                        img.handle,
                        .transfer_dst_optimal,
                        @ptrCast(&vk.ClearColorValue{ .float_32 = .{ 0, 0, 0, 0 } }),
                        &.{img.full_subresource_range()},
                    );
                }
                try is.submit_and_wait(u.queue(), u.device.logical_device);
                graph.advance_submission();
            }

            //Bindless sets
            const env_layout = try EnvSets.Set.Layout.init(&u.device);
            defer env_layout.deinit(&u.device);
            const envset = try env_layout.alloc(&u.device, desc_pool.handle, null);

            envset.write_many(&u.device, 0, 0, &.{
                emma.desc.write_sampler(u.samplers.linear_repeat),
                emma.desc.write_sampler(u.samplers.linear_clamp),
                emma.desc.write_sampler(u.samplers.nearest_repeat),
                emma.desc.write_sampler(u.samplers.nearest_clamp),
                emma.desc.write_sampler(u.samplers.shadow),
                emma.desc.write_sampler(u.samplers.equirect),
            });
            envset.write_many(&u.device, 1, 0, bindless_registries.sampled_images.info_list[0..bindless_registries.sampled_images.len]);
            envset.write_many(&u.device, 2, 0, bindless_registries.storage_images.info_list[0..bindless_registries.storage_images.len]);

            const pt_layout1 = try Pathtracing.Set1.Layout.init(&u.device);
            defer pt_layout1.deinit(&u.device);

            const pt_set1 = try pt_layout1.alloc(&u.device, desc_pool.handle, null);
            pt_set1.write_one(&u.device, 0, 0, &.{ .acceleration_structure_count = 1, .p_acceleration_structures = &.{tlas.handle}, .p_next = null });

            {
                var swapchain = try emma.vlk_swapchain.init(allocator, &u, @intCast(width), @intCast(height));
                defer swapchain.deinit(&u.device);

                var frames = try emma.vlk_frames.init(allocator, &u.device, &u.cmd_pool, MAX_FRAMES_IN_FLIGHT);
                defer frames.deinit(allocator, u.device.logical_device);

                var quit = false;

                const render_begin_ms = std.Io.Timestamp.now(io, clock).toMilliseconds();
                var time_ms = render_begin_ms;
                var time_sec: f32 = @as(f32, @floatFromInt(time_ms)) / 1000;

                var swapchain_texture_handles = try allocator.alloc(emma.TextureRegistry.Handle, swapchain.images.len);
                defer allocator.free(swapchain_texture_handles);
                var swapchain_graph_handles = try allocator.alloc(emma.sync.Graph.ResourceHandle, swapchain.images.len);
                defer allocator.free(swapchain_graph_handles);

                for (swapchain.images, 0..) |img, i| {
                    swapchain_texture_handles[i] = try texture_registry.register_external(img);
                    const texture = texture_registry.get(swapchain_texture_handles[i]);
                    swapchain_graph_handles[i] = try graph.register_image(texture.handle, texture.full_subresource_range(), .{});
                }

                const img_acquired_semaphores = try semaphore_pool.acquire_binary_many(allocator, frames.max_frames_in_flight());
                defer allocator.free(img_acquired_semaphores);

                const render_finished = try allocator.alloc(vk.Semaphore, swapchain.images.len);
                for (render_finished) |*s| {
                    s.* = try u.device.logical_device.createSemaphore(&.{}, null);
                }
                defer {
                    for (render_finished) |s| {
                        u.device.logical_device.destroySemaphore(s, null);
                    }
                    allocator.free(render_finished);
                }

                var frame_counter: u32 = 0;
                var ammassed_frames: u32 = 0;

                const tile_pixel_strides = scene_config.settings.render_tile;
                const tiles = [2]emma.TileElm{
                    emma.TileElm.init(tile_pixel_strides[0], output_extent.width),
                    emma.TileElm.init(tile_pixel_strides[1], output_extent.height),
                };

                var last_present_ms: i64 = 0;
                var avg_ms: f64 = 0.0;
                var avg_n: f64 = 0.0;

                var middle_mouse_down = false;

                var key_bindings = try emma.KeyBindings.init(allocator);
                defer key_bindings.deinit(allocator);

                var state = try RenderState.init(allocator, MAX_FRAMES_IN_FLIGHT, .{ .pos = .init(.{ 0, 2, 8 }) });
                defer state.deinit(allocator);

                //callbacks
                {
                    const SPEED: f32 = 0.01;
                    try key_bindings.bind(allocator, .one, &state, struct {
                        fn set(s: *RenderState) void {
                            s.flush = true;
                            s.cam.fov = std.math.clamp(s.cam.fov - (0.001) * @as(f32, @floatCast(s.delta)), 0, 120);
                        }
                    }.set, false);
                    try key_bindings.bind(allocator, .two, &state, struct {
                        fn set(s: *RenderState) void {
                            s.flush = true;
                            s.cam.fov = std.math.clamp(s.cam.fov + (0.001) * @as(f32, @floatCast(s.delta)), 0, 120);
                        }
                    }.set, false);
                    try key_bindings.bind(allocator, .func5, &state, struct {
                        fn set(s: *RenderState) void {
                            s.flush = true;
                        }
                    }.set, false);

                    try key_bindings.bind(allocator, .w, &state, struct {
                        fn move(s: *RenderState) void {
                            s.flush = true;
                            const d = -SPEED * @as(f32, @floatCast(s.delta));
                            s.cam.pos = s.cam.pos.add(s.cam.forward().mul_scalar(d));
                        }
                    }.move, false);
                    try key_bindings.bind(allocator, .s, &state, struct {
                        fn move(s: *RenderState) void {
                            s.flush = true;
                            const d = SPEED * @as(f32, @floatCast(s.delta));
                            s.cam.pos = s.cam.pos.add(s.cam.forward().mul_scalar(d));
                        }
                    }.move, false);
                    try key_bindings.bind(allocator, .a, &state, struct {
                        fn move(s: *RenderState) void {
                            s.flush = true;
                            const d = -SPEED * @as(f32, @floatCast(s.delta));
                            s.cam.pos = s.cam.pos.add(s.cam.right().mul_scalar(d));
                        }
                    }.move, false);
                    try key_bindings.bind(allocator, .d, &state, struct {
                        fn move(s: *RenderState) void {
                            s.flush = true;
                            const d = SPEED * @as(f32, @floatCast(s.delta));
                            s.cam.pos = s.cam.pos.add(s.cam.right().mul_scalar(d));
                        }
                    }.move, false);

                    try key_bindings.bind(allocator, .space, &state, struct {
                        fn move(s: *RenderState) void {
                            s.flush = true;
                            const d = SPEED * @as(f32, @floatCast(s.delta));
                            s.cam.pos = s.cam.pos.add(.init(.{ 0, d, 0 }));
                        }
                    }.move, false);
                    try key_bindings.bind(allocator, .c, &state, struct {
                        fn move(s: *RenderState) void {
                            s.flush = true;
                            const d = -SPEED * @as(f32, @floatCast(s.delta));
                            s.cam.pos = s.cam.pos.add(.init(.{ 0, d, 0 }));
                        }
                    }.move, false);
                    try key_bindings.bind(allocator, .r, &state, struct {
                        fn move(s: *RenderState) void {
                            s.flush = true;
                            s.cam.pos = mth.float3.zero();
                            s.cam.rot = .identity();
                        }
                    }.move, false);
                }

                // rendering loop
                {
                    var loop_allocator_ctx = std.heap.ArenaAllocator.init(allocator);
                    defer loop_allocator_ctx.deinit();

                    const loop_allocator = loop_allocator_ctx.allocator();
                    _ = try loop_allocator.create(u32);

                    var last_frame_ms: i64 = 0;

                    var pt_pc = Pathtracing.PC{
                        .skybox = 0,
                        .temporal_textures = .{},
                        .raw = env.storage_img.get(raw_id).?.val,
                        .buffers = buffers.address(&u.device),
                        .geometries = geometry_buffer.address(&u.device),
                        .ranges = range_buffer.address(&u.device),
                        .materials = device_materials.address(&u.device),
                    };

                    while (!quit) {
                        // for (frames.frames, 0..) |*frame, i| {
                        //     const status = try u.device.logical_device.getFenceStatus(frame.fence.handle);
                        //     std.debug.print("{}: {s}\n\n", .{ i, @tagName(status) });
                        // }

                        state.prev_cam = state.cam;
                        {
                            while (sdl.events.poll()) |event| {
                                switch (event) {
                                    .quit => quit = true,
                                    .terminating => quit = true,
                                    .mouse_motion => |mm| {
                                        if (middle_mouse_down) {
                                            state.flush = true;
                                            const sensitivity: f32 = 0.1;
                                            const yaw = mth.quat.from_axis_angle(mth.float3.init(.{ 0, 1, 0 }), -mm.x_rel * sensitivity);
                                            const pitch = mth.quat.from_axis_angle(state.cam.right(), -mm.y_rel * sensitivity);
                                            state.cam.rot = mth.quat.mul(pitch, mth.quat.mul(yaw, state.cam.rot)).normalize();
                                        }
                                    },
                                    .key_down => |key| key_state[@intFromEnum(key.scancode.?)] = true,
                                    .key_up => |key| key_state[@intFromEnum(key.scancode.?)] = false,
                                    .mouse_button_down => |mb| if (mb.button == .middle) {
                                        middle_mouse_down = true;
                                    },
                                    .mouse_button_up => |mb| if (mb.button == .middle) {
                                        middle_mouse_down = false;
                                    },
                                    .window_resized => |e| {
                                        swapchain.resize(&u, @intCast(e.width), @intCast(e.height));
                                        for (swapchain.images, 0..) |img, i| {
                                            texture_registry.replace_external(swapchain_texture_handles[i], img);
                                            graph.update_resource(swapchain_graph_handles[i], .{
                                                .image = .{ .handle = img.handle, .subresource_range = img.full_subresource_range() },
                                            });
                                            graph.update_state(
                                                swapchain_graph_handles[i],
                                                .{
                                                    .last_submission_id = graph.current_submission,
                                                    .stage_mask = .{ .top_of_pipe_bit = true },
                                                    .access_mask = .{},
                                                    .ustate = .{ .layout = .undefined },
                                                },
                                            );
                                        }
                                    },
                                    else => {},
                                }
                            }
                        }

                        key_bindings.tick(&key_state);

                        const frame_slot = frames.index;
                        const frame = frames.current();
                        const acquire_sem = img_acquired_semaphores[frame_slot].semaphore;

                        try frame.fence.wait_and_reset(u.device.logical_device);
                        const next_swapchain_image = try u.device.logical_device.acquireNextImageKHR(
                            swapchain.handle,
                            std.math.maxInt(u64),
                            acquire_sem,
                            .null_handle,
                        );
                        const image_index = next_swapchain_image.image_index;
                        const swapchain_image = swapchain.images[image_index];
                        const swapchain_graph_handle = swapchain_graph_handles[image_index];
                        {
                            const inow_time_ms = std.Io.Timestamp.now(io, clock).toMilliseconds() - render_begin_ms;
                            const idelta_time_ms = inow_time_ms - last_frame_ms;
                            state.delta = @as(f64, @floatFromInt(idelta_time_ms));

                            last_frame_ms = inow_time_ms;
                            time_ms = inow_time_ms;
                            time_sec = @as(f32, @floatFromInt(inow_time_ms)) / 1000;
                        }

                        {
                            try frame.cmd.beginCommandBuffer(&.{});
                            const temporal_index = frame_counter % temporal_ids.len;
                            const temporal_curr = temporal_ids[temporal_index];
                            const temporal_hist = temporal_ids[(temporal_index + temporal_ids.len - 1) % temporal_ids.len];
                            const curr_temporal = TemporalTexturesGpu.Temporal{
                                .col = env.storage_img.get(temporal_curr[0]).?.val,
                                .norm = env.storage_img.get(temporal_curr[1]).?.val,
                                .pos = env.storage_img.get(temporal_curr[2]).?.val,
                            };
                            const hist_temporal = TemporalTexturesGpu.Temporal{
                                .col = env.sampled_img.get(temporal_hist[0]).?.val,
                                .norm = env.sampled_img.get(temporal_hist[1]).?.val,
                                .pos = env.sampled_img.get(temporal_hist[2]).?.val,
                            };
                            const temporal_textures = TemporalTexturesGpu{
                                .curr = curr_temporal,
                                .hist = hist_temporal,
                            };
                            {
                                {
                                    // Pathtracing
                                    {
                                        try graph.use_batch(frame.cmd, &.{
                                            .{ .handle = env.get_all(temporal_curr[0]).graph.?, .next = .{ .access = .w, .state = .{ .layout = .general }, .stage_mask = .{ .ray_tracing_shader_bit_khr = true }, .access_mask = .{ .shader_write_bit = true } } },
                                            .{ .handle = env.get_all(temporal_curr[1]).graph.?, .next = .{ .access = .w, .state = .{ .layout = .general }, .stage_mask = .{ .ray_tracing_shader_bit_khr = true }, .access_mask = .{ .shader_write_bit = true } } },
                                            .{ .handle = env.get_all(temporal_curr[2]).graph.?, .next = .{ .access = .w, .state = .{ .layout = .general }, .stage_mask = .{ .ray_tracing_shader_bit_khr = true }, .access_mask = .{ .shader_write_bit = true } } },

                                            .{ .handle = env.get_all(temporal_hist[0]).graph.?, .next = .{ .access = .r, .state = .{ .layout = .shader_read_only_optimal }, .stage_mask = .{ .ray_tracing_shader_bit_khr = true }, .access_mask = .{ .shader_read_bit = true } } },
                                            .{ .handle = env.get_all(temporal_hist[1]).graph.?, .next = .{ .access = .r, .state = .{ .layout = .shader_read_only_optimal }, .stage_mask = .{ .ray_tracing_shader_bit_khr = true }, .access_mask = .{ .shader_read_bit = true } } },
                                            .{ .handle = env.get_all(temporal_hist[2]).graph.?, .next = .{ .access = .r, .state = .{ .layout = .shader_read_only_optimal }, .stage_mask = .{ .ray_tracing_shader_bit_khr = true }, .access_mask = .{ .shader_read_bit = true } } },

                                            .{ .handle = env.get_all(raw_id).graph.?, .next = .{ .access = .w, .state = .{ .layout = .general }, .stage_mask = .{ .ray_tracing_shader_bit_khr = true }, .access_mask = .{ .shader_write_bit = true } } },

                                            .{ .handle = skybox_info.graph.?, .next = .{ .access = .r, .state = .{ .layout = .shader_read_only_optimal }, .stage_mask = .{ .ray_tracing_shader_bit_khr = true }, .access_mask = .{ .shader_read_bit = true } } },
                                        });

                                        {
                                            pt_pc.skybox = env.sampled_img.get(skybox_id).?.val;
                                            pt_pc.temporal_textures = temporal_textures;

                                            pt_pc.res = .init(.{ output_extent.width, output_extent.height });
                                            pt_pc.cam = state.cam.get_gpu();
                                            pt_pc.prev_cam = state.prev_cam.get_gpu();
                                            pt_pc.time = time_sec;
                                            pt_pc.frame = ammassed_frames;
                                        }

                                        pt_pc.pos = .init(.{ 0, 0 });
                                        hwrt.record(frame.cmd, .{ envset, pt_set1 }, pt_pc, tiles[0].len, tiles[1].len);
                                    }
                                    // TA
                                    {
                                        try graph.use_batch(frame.cmd, &.{
                                            .{ .handle = env.get_all(temporal_curr[0]).graph.?, .next = .{ .access = .w, .state = .{ .layout = .general }, .stage_mask = .{ .compute_shader_bit = true }, .access_mask = .{ .shader_write_bit = true } } },
                                            .{ .handle = env.get_all(temporal_curr[1]).graph.?, .next = .{ .access = .r, .state = .{ .layout = .general }, .stage_mask = .{ .compute_shader_bit = true }, .access_mask = .{ .shader_read_bit = true } } },
                                            .{ .handle = env.get_all(temporal_curr[2]).graph.?, .next = .{ .access = .r, .state = .{ .layout = .general }, .stage_mask = .{ .compute_shader_bit = true }, .access_mask = .{ .shader_read_bit = true } } },

                                            .{ .handle = env.get_all(temporal_hist[0]).graph.?, .next = .{ .access = .r, .state = .{ .layout = .shader_read_only_optimal }, .stage_mask = .{ .compute_shader_bit = true }, .access_mask = .{ .shader_read_bit = true } } },
                                            .{ .handle = env.get_all(temporal_hist[1]).graph.?, .next = .{ .access = .r, .state = .{ .layout = .shader_read_only_optimal }, .stage_mask = .{ .compute_shader_bit = true }, .access_mask = .{ .shader_read_bit = true } } },
                                            .{ .handle = env.get_all(temporal_hist[2]).graph.?, .next = .{ .access = .r, .state = .{ .layout = .shader_read_only_optimal }, .stage_mask = .{ .compute_shader_bit = true }, .access_mask = .{ .shader_read_bit = true } } },

                                            .{ .handle = env.get_all(raw_id).graph.?, .next = .{ .access = .r, .state = .{ .layout = .general }, .stage_mask = .{ .compute_shader_bit = true }, .access_mask = .{ .shader_read_bit = true } } },
                                        });

                                        ta.record(frame.cmd, envset, .{
                                            .cam = state.cam.get_gpu(),
                                            .prev_cam = state.prev_cam.get_gpu(),
                                            .temporal_textures = temporal_textures,
                                            .raw = env.storage_img.get(raw_id).?.val,
                                        }, output_extent);
                                    }

                                    // AA
                                    {
                                        const ATROUS_ITERATIONS = 1;

                                        const norm_sampled = env.sampled_img.get(temporal_curr[1]).?.val;
                                        const pos_sampled = env.sampled_img.get(temporal_curr[2]).?.val;

                                        var input_col_sampled = env.sampled_img.get(temporal_curr[0]).?.val;
                                        var ping_pong_slot: usize = 0;

                                        var iter: u32 = 0;
                                        while (iter < ATROUS_ITERATIONS) : (iter += 1) {
                                            const is_last = iter == ATROUS_ITERATIONS - 1;
                                            const out_id = if (is_last) output_id else atrous[ping_pong_slot];
                                            const out_info = env.get_all(out_id);
                                            const out_storage = env.storage_img.get(out_id).?.val;

                                            try graph.use_batch(frame.cmd, &.{
                                                .{ .handle = out_info.graph.?, .next = .{
                                                    .access = .w,
                                                    .state = .{ .layout = .general },
                                                    .stage_mask = .{ .compute_shader_bit = true },
                                                    .access_mask = .{ .shader_write_bit = true },
                                                } },
                                            });

                                            aa.record(frame.cmd, envset, .{
                                                .col_input = input_col_sampled,
                                                .norm_input = norm_sampled,
                                                .pos_input = pos_sampled,
                                                .output = out_storage,
                                                .stepwidth = @floatFromInt(@as(u32, 1) << @intCast(iter)), // 1,2,4,8,16
                                                .do_tonemap = if (is_last) @as(u32, 1) else 0,
                                            }, output_extent);

                                            if (!is_last) {
                                                input_col_sampled = env.sampled_img.get(out_id).?.val;
                                                ping_pong_slot = 1 - ping_pong_slot;
                                            }
                                        }
                                    }
                                    // {
                                    //     try graph.use_batch(frame.cmd, &.{
                                    //         .{ .handle = env.get_all(temporal_curr[0]).graph.?, .next = .{ .access = .r, .state = .{ .layout = .general }, .stage_mask = .{ .compute_shader_bit = true }, .access_mask = .{ .shader_read_bit = true } } },
                                    //         .{ .handle = env.get_all(temporal_curr[1]).graph.?, .next = .{ .access = .r, .state = .{ .layout = .general }, .stage_mask = .{ .compute_shader_bit = true }, .access_mask = .{ .shader_read_bit = true } } },
                                    //         .{ .handle = env.get_all(temporal_curr[2]).graph.?, .next = .{ .access = .r, .state = .{ .layout = .general }, .stage_mask = .{ .compute_shader_bit = true }, .access_mask = .{ .shader_read_bit = true } } },
                                    //         .{ .handle = output_info.graph.?, .next = .{ .access = .w, .state = .{ .layout = .general }, .stage_mask = .{ .compute_shader_bit = true }, .access_mask = .{ .shader_write_bit = true } } },
                                    //     });

                                    //     const output = env.sampled_img.get(output_id).?.val;
                                    //     aa.record(frame.cmd, envset, .{
                                    //         .temporal_textures = temporal_textures,
                                    //         .output = output,
                                    //     }, output_extent);
                                    // }

                                    ammassed_frames += 1;
                                    frame_counter += 1;
                                }

                                // Blit
                                {
                                    const from_handle = output_info.registry;
                                    const from = texture_registry.get(from_handle);
                                    try graph.use_batch(frame.cmd, &.{
                                        .{ .handle = output_info.graph.?, .next = .{
                                            .access = .r,
                                            .state = .{ .layout = .transfer_src_optimal },
                                            .stage_mask = .{ .blit_bit = true },
                                            .access_mask = .{ .transfer_read_bit = true },
                                        } },
                                        .{ .handle = swapchain_graph_handle, .next = .{
                                            .access = .w,
                                            .state = .{ .layout = .transfer_dst_optimal },
                                            .stage_mask = .{ .blit_bit = true },
                                            .access_mask = .{ .transfer_write_bit = true },
                                        } },
                                    });

                                    const subrange = from.full_subresource_range();
                                    const subrange_swapchain = swapchain_image.full_subresource_range();
                                    const blit_region = vk.ImageBlit2{
                                        .src_subresource = .{
                                            .aspect_mask = subrange.aspect_mask,
                                            .mip_level = 0,
                                            .base_array_layer = 0,
                                            .layer_count = subrange.layer_count,
                                        },
                                        .src_offsets = .{
                                            .{ .x = 0, .y = 0, .z = 0 },
                                            .{ .x = @intCast(from.extent.width), .y = @intCast(from.extent.height), .z = 1 },
                                        },
                                        .dst_subresource = .{
                                            .aspect_mask = subrange_swapchain.aspect_mask,
                                            .mip_level = 0,
                                            .base_array_layer = 0,
                                            .layer_count = subrange_swapchain.layer_count,
                                        },
                                        .dst_offsets = .{
                                            .{ .x = 0, .y = 0, .z = 0 },
                                            .{ .x = @intCast(swapchain.extent.width), .y = @intCast(swapchain.extent.height), .z = 1 },
                                        },
                                    };
                                    frame.cmd.blitImage2(&.{
                                        .src_image = from.handle,
                                        .src_image_layout = .transfer_src_optimal,
                                        .dst_image = swapchain_image.handle,
                                        .dst_image_layout = .transfer_dst_optimal,
                                        .region_count = 1,
                                        .p_regions = @ptrCast(&blit_region),
                                        .filter = .nearest,
                                    });
                                }

                                _ = try graph.use(frame.cmd, swapchain_graph_handle, .{
                                    .access = .none,
                                    .state = .{ .layout = .present_src_khr },
                                    .stage_mask = .{ .bottom_of_pipe_bit = true },
                                    .access_mask = .{},
                                });
                            }
                            try frame.cmd.endCommandBuffer();
                            {
                                const wait_stage = vk.PipelineStageFlags{ .all_commands_bit = true };
                                const submit_info = [_]vk.SubmitInfo{.{
                                    .p_command_buffers = @ptrCast(&frame.cmd.handle),
                                    .command_buffer_count = 1,
                                    .wait_semaphore_count = 1,
                                    .p_wait_semaphores = @ptrCast(&acquire_sem),
                                    .p_wait_dst_stage_mask = @ptrCast(&wait_stage),
                                    .p_signal_semaphores = @ptrCast(&render_finished[image_index]),
                                    .signal_semaphore_count = 1,
                                }};
                                try u.device.queue.submit(&submit_info, frame.fence.handle);
                                graph.advance_submission();
                            }
                        }

                        _ = try u.device.queue.presentKHR(&.{
                            .wait_semaphore_count = 1,
                            .p_wait_semaphores = @ptrCast(&render_finished[image_index]),
                            .swapchain_count = 1,
                            .p_swapchains = @ptrCast(&swapchain.handle),
                            .p_image_indices = @ptrCast(&image_index),
                        });

                        {
                            const present_time_ms = std.Io.Timestamp.now(io, clock).toMilliseconds() - render_begin_ms;
                            const last_present_diff = present_time_ms - last_present_ms;
                            last_present_ms = present_time_ms;
                            avg_n += 1;
                            avg_ms += (@as(f64, @floatFromInt(last_present_diff)) - avg_ms) / avg_n;
                        }

                        frames.advance();
                        _ = loop_allocator_ctx.reset(.retain_capacity);
                    }
                    {
                        time_ms = std.Io.Timestamp.now(io, clock).toMilliseconds() - render_begin_ms;
                        time_sec = @as(f32, @floatFromInt(time_ms)) / 1000;
                        std.debug.print("ran for {d} with avg ms per full frame {d:.3} avg fps {d:.3}\n", .{ time_sec, avg_ms, 1000.0 / avg_ms });
                    }

                    try u.device.logical_device.deviceWaitIdle();
                }

                try u.device.logical_device.deviceWaitIdle();
            }
        }
    }

    _ = debug_allocator.deinit();
}
