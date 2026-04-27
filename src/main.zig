const std = @import("std");
const builtin = @import("builtin");
const emma = @import("emma");
const config = @import("config.zig");

const sdl = emma.sdl;
const vk = emma.vk;
const vma = emma.c_vma;

const MousePos = extern struct {
    x: f32,
    y: f32,
};

const PC = extern struct {
    const Buffers = struct {
        verts: u64,
        norms: u64,
        uvs: u64,
        indices: u64,
        normal_indices: u64,
    };

    const Geometry = extern struct {
        buffer_index: u32,
    };

    const Range = extern struct {
        geometry_indices: u64,
    };

    width: u32 = 0,
    height: u32 = 0,
    time: f32 = 0.0,
    frame: u32 = 0.0,

    posx: u32 = 0.0,
    posy: u32 = 0.0,

    mouse: MousePos = .{ .x = 0, .y = 0 },

    buffers: u64 = 0,
    geometries: u64 = 0,
    ranges: u64 = 0,
    materials: u64 = 0,
};

// fn Handle(comptime T: type) type {
//     const Self = struct {
//         data: u32 = 0,

//         pub const Type = T;
//         pub const __Handle_mark = void;

//         pub fn from_int(i: u32) @This() {
//             return .{ .data = i };
//         }
//     };

//     return Self;
// }

// fn is_Handle(comptime T: type) bool {
//     return @hasDecl(T, "__is_handle");
// }

// fn Allocator(comptime T: type) type {
//     const H = Handle(T);

//     const Self = struct {
//         const Self = @This();
//         pub const Handle = H;

//         data: std.ArrayList(T),
//         free: std.ArrayList(u32),

//         pub fn init_capacity(allocator: std.mem.Allocator, capacity: usize) Self {
//             return .{
//                 .data = std.ArrayList(T).initCapacity(allocator, capacity),
//                 .free = std.ArrayList(u32).initCapacity(allocator, capacity / 2),
//             };
//         }
//         pub fn init_from_buffers(allocator: std.mem.Allocator, list: std.ArrayList(T)) Self {
//             return .{
//                 .data = list,
//                 .free = std.ArrayList(u32).init(allocator, list.items.len / 2),
//             };
//         }

//         pub fn deinit(self: *Self) void {
//             self.data.deinit();
//             self.free.deinit();
//         }

//         pub fn add(self: *Self, value: T) !H {
//             if (self.free.items.len > 0) {
//                 const index = self.free.pop();
//                 self.data.items[index] = value;
//                 return .{ .index = index };
//             }

//             const index: u32 = @intCast(self.data.items.len);
//             try self.data.append(value);
//             return .{ .index = index };
//         }

//         pub fn remove(self: *Self, handle: H) !void {
//             const index = handle.index;
//             if (index >= self.data.items.len) return error.InvalidIndex;

//             try self.free.append(index);
//             self.data.items[index] = undefined;
//         }

//         pub fn get_val(self: *Self, handle: H) T {
//             return self.data.items[handle.index];
//         }

//         pub fn get_ptr(self: *Self, handle: H) *T {
//             return &self.data.items[handle.index];
//         }
//     };

//     return Self;
// }

const Resources = struct {
    local: []emma.local_geometry.geometry,
    device: []emma.device_geometry,
};

const ThreadContext = struct {
    allocator: std.mem.Allocator,
    path: []const u8,
    result: ?emma.local_geometry.geometry = null,
    err: ?anyerror = null,
    duration_ns: u64 = 0,
};

fn load_geometry_thread(ctx: *ThreadContext) void {
    var timer = std.time.Timer.start() catch {
        ctx.err = error.TimerUnsupported;
        return;
    };
    ctx.result = load_geometry(ctx.allocator, ctx.path) catch |e| {
        ctx.err = e;
        return;
    };
    ctx.duration_ns = timer.lap();
}

fn load_geometry(allocator: std.mem.Allocator, filepath: []const u8) !emma.local_geometry.geometry {
    const file = try std.fs.cwd().openFile(filepath, .{});
    defer file.close();

    const d = try emma.readfile_alloc(allocator, file);
    defer allocator.free(d);

    var obj_model = try emma.obj.parseObj(allocator, d);
    defer obj_model.deinit(allocator);

    return emma.local_geometry.geometry.from_obj(allocator, &obj_model);
}

fn build_local_geometry(
    allocator: std.mem.Allocator,
    list: []const config.Geometry,
) ![]emma.local_geometry.geometry {
    var total_timer = try std.time.Timer.start();

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
        thread.* = try std.Thread.spawn(.{}, load_geometry_thread, .{ctx});
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

    const total_ns = total_timer.read();
    std.debug.print("geometry total wall time: {d:.3}ms\n", .{
        @as(f64, @floatFromInt(total_ns)) / std.time.ns_per_ms,
    });

    return local_geometries;
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

    return device_geometries.items;
}

pub fn main() !void {
    // const resource_manager = Resources{};
    // _ = resource_manager;

    try emma.sdl_init();
    defer emma.sdl_deinit();

    const allocator: std.mem.Allocator = std.heap.c_allocator;
    var key_state = std.mem.zeroes([sdl.c.SDL_SCANCODE_COUNT]bool);

    var conf = blk: {
        const file = try std.fs.cwd().openFile("./scene.zon", .{});
        defer file.close();

        const src = try emma.readfile_allocZ(allocator, file);
        const result = try config.parse(allocator, src);

        break :blk result;
    };
    defer conf.deinit();

    const width: usize = 1440;
    const height: usize = 1440;

    var u = try emma.vlk_unit.init(allocator, width, height);
    defer u.deinit(allocator);

    const cmd_pool = try emma.vlk_command_pool.init(&u.device);
    defer cmd_pool.deinit(u.device.logical_device);

    const command_buffers = try emma.vlk_command_buffer_allocation.init(
        allocator,
        u.device.logical_device,
        cmd_pool.handle,
        10,
    );

    const is = try emma.ImediateSubmit.init(
        &u.device,
        command_buffers.buffers[0],
    );

    const local_geometry_storage = try build_local_geometry(allocator, conf.geometry);
    const device_geometry_storage = try build_device_geometry(allocator, &u, local_geometry_storage, is);

    const re = Resources{
        .local = local_geometry_storage,
        .device = device_geometry_storage,
    };
    _ = re;

    defer is.deinit(&u.device);
    defer allocator.free(local_geometry_storage);
    defer {
        for (device_geometry_storage) |mesh| {
            mesh.deinit(&u.vma);
        }
        allocator.free(device_geometry_storage);
    }

    var blas_geometry_storage = std.MultiArrayList(emma.raytracing_geometry_data){};
    try blas_geometry_storage.ensureTotalCapacity(allocator, 5);
    var materials_storage = try std.ArrayList(u32).initCapacity(allocator, 5);

    defer materials_storage.deinit(allocator);

    var blas_ranges = try std.ArrayList(emma.blas_geometry_range).initCapacity(allocator, 5);
    var materials = try std.ArrayList(u32).initCapacity(allocator, 5);
    var instance_transforms = try std.ArrayList(vk.TransformMatrixKHR).initCapacity(allocator, 5);
    for (conf.nodes) |node| {
        const begin = blas_geometry_storage.len;
        {
            const len = 1;
            {
                {
                    {
                        const geometry_handle: u32 = node.geometry;
                        const geometry = emma.raytracing_geometry_data.init(device_geometry_storage, geometry_handle, &u.device);
                        try blas_geometry_storage.append(allocator, geometry);
                    }
                    {
                        const pos = emma.mth.vec.from_arr3(node.transform.pos, 0);
                        //for now we will skip the rotation
                        // it needs to be converted to quat
                        // which needs to be it's own type
                        // const rot = node.transform.rot;
                        const rot = emma.mth.vec.fzero();
                        const scale = emma.mth.vec.from_arr3(node.transform.scale, 1);

                        const mat = emma.mth.model(pos, rot, scale);
                        const vk_trans = emma.mth_to_vk_transform_matrix(mat);
                        try instance_transforms.append(allocator, vk_trans);
                    }
                    {
                        const material = node.material;
                        try materials_storage.append(allocator, material);
                        try materials.append(allocator, material);
                    }
                }

                try blas_ranges.append(allocator, .{ .begin = @intCast(begin), .len = @intCast(len) });
            }
        }
    }
    defer materials.deinit(allocator);

    var blas_list = try std.ArrayList(emma.raytracing_acceleration_structure).initCapacity(allocator, 10);
    {
        var timer = try std.time.Timer.start();
        for (blas_ranges.items) |range| {
            const begin = range.begin;
            const len = range.len;
            const end = begin + len;

            const geometries = blas_geometry_storage.items(.geometry)[begin..end];
            const ranges = blas_geometry_storage.items(.range)[begin..end];

            const blas = try emma.raytracing_acceleration_structure.init_blas(
                allocator,
                &u.vma,
                &u.device,
                geometries,
                ranges,
                .{},
                is,
            );
            try blas_list.append(allocator, blas);
        }
        std.debug.print("created BLAS structures in {d:.2}ms\n", .{emma.ns_to_ms(timer.lap())});
    }
    defer {
        for (blas_list.items) |b| {
            b.deinit(&u.vma, &u.device);
        }
        allocator.free(blas_list.items);
    }

    try is.begin();
    var staging_pool = try std.ArrayList(emma.vlk_vma_buffer).initCapacity(allocator, 10);
    defer {
        for (staging_pool.items) |buffer| {
            buffer.deinit(&u.vma);
        }
        staging_pool.deinit(allocator);
    }

    const device_materials = blk: {
        try staging_pool.append(allocator, try emma.vlk_upload_buffer_with_data(
            &u.vma,
            std.mem.sliceAsBytes(materials.items),
        ));
        const buffer = try emma.vlk_vma_buffer.init(
            &u.vma,
            staging_pool.getLast().size,
            emma.c_vma.VK_BUFFER_USAGE_TRANSFER_DST_BIT |
                emma.c_vma.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT |
                emma.c_vma.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
            emma.c_vma.VMA_MEMORY_USAGE_AUTO,
            0,
        );
        staging_pool.getLast().cmd_copy_to(&buffer, is.cmd);

        break :blk buffer;
    };

    defer device_materials.deinit(&u.vma);

    const buffers = blk: {
        var buffers_info = try std.ArrayList(PC.Buffers).initCapacity(allocator, device_geometry_storage.len);

        for (device_geometry_storage) |mesh| {
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
            emma.c_vma.VK_BUFFER_USAGE_TRANSFER_DST_BIT |
                emma.c_vma.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
            emma.c_vma.VMA_MEMORY_USAGE_AUTO,
            0,
        );

        staging_pool.getLast().cmd_copy_to(&buffer, is.cmd);

        break :blk buffer;
    };
    defer buffers.deinit(&u.vma);

    const geometry_buffer = blk: {
        const items = blas_geometry_storage.items(.index);
        const slice = std.mem.sliceAsBytes(items);
        try staging_pool.append(allocator, try emma.vlk_upload_buffer_with_data(&u.vma, slice));

        const buffer = try emma.vlk_vma_buffer.init(
            &u.vma,
            staging_pool.getLast().size,
            emma.c_vma.VK_BUFFER_USAGE_TRANSFER_DST_BIT |
                emma.c_vma.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
            emma.c_vma.VMA_MEMORY_USAGE_AUTO,
            0,
        );

        staging_pool.getLast().cmd_copy_to(&buffer, is.cmd);

        break :blk buffer;
    };
    defer geometry_buffer.deinit(&u.vma);

    const range_buffer = blk: {
        const items = blas_ranges.items;
        const slice = std.mem.sliceAsBytes(items);
        try staging_pool.append(allocator, try emma.vlk_upload_buffer_with_data(&u.vma, slice));

        const buffer = try emma.vlk_vma_buffer.init(
            &u.vma,
            staging_pool.getLast().size,
            emma.c_vma.VK_BUFFER_USAGE_TRANSFER_DST_BIT |
                emma.c_vma.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
            emma.c_vma.VMA_MEMORY_USAGE_AUTO,
            0,
        );

        staging_pool.getLast().cmd_copy_to(&buffer, is.cmd);

        break :blk buffer;
    };
    defer range_buffer.deinit(&u.vma);
    try is.submit_and_wait(u.queue(), u.device.logical_device);

    var mouse = MousePos{ .x = 0, .y = 0 };

    var pc2 = PC{
        .height = 0,
        .width = 0,
        .time = 0,
        .frame = 0,
        .posx = 0,
        .posy = 0,
        .mouse = mouse,
        .buffers = buffers.address(&u.device),
        .geometries = geometry_buffer.address(&u.device),
        .ranges = range_buffer.address(&u.device),
        .materials = device_materials.address(&u.device),
    };

    const tlas = try emma.raytracing_acceleration_structure.init_tlas(
        allocator,
        &u.vma,
        &u.device,
        blas_list.items,
        instance_transforms.items,
        .{},
        is,
    );
    defer tlas.deinit(&u.vma, &u.device);

    const rt_props = emma.vlk_get_raytracing_properties(&u.vki, &u.device);

    const file = try std.fs.cwd().openFile("./src/shaders/hw_raytracing/shader.spv", .{});
    defer file.close();

    const spirv = try emma.readfile_alloc(allocator, file);
    defer allocator.free(spirv);

    const raygen_module = try emma.vlk_shader_module.init(
        &u.device,
        spirv,
        .{ .raygen_bit_khr = true },
        "raygen_entry",
    );
    const miss_module = try emma.vlk_shader_module.init(
        &u.device,
        spirv,
        .{ .miss_bit_khr = true },
        "miss_entry",
    );
    const closest_hit_module = try emma.vlk_shader_module.init(
        &u.device,
        spirv,
        .{ .closest_hit_bit_khr = true },
        "closest_hit_entry",
    );
    defer raygen_module.deinit(&u.device);
    defer miss_module.deinit(&u.device);
    defer closest_hit_module.deinit(&u.device);

    const rt_modules = [_]emma.vlk_shader_module{
        raygen_module, miss_module, closest_hit_module,
    };

    var pipeline = try emma.vlk_raytracing_pipeline.init(
        PC,
        allocator,
        &rt_props,
        &u.vma,
        &u.device,
        is,
        &rt_modules,
    );
    defer pipeline.deinit(&u.vma, &u.device);
    std.debug.print("Created pipeline successfully \n", .{});
    //

    {
        const descriptor_sizes = [_]vk.DescriptorPoolSize{
            .{ .descriptor_count = 10, .type = .combined_image_sampler },
            .{ .descriptor_count = 10, .type = .storage_image },
            .{ .descriptor_count = 10, .type = .acceleration_structure_khr },
        };
        const descriptor_pool = try emma.vlk_descriptor_pool.init(
            &u.device,
            &descriptor_sizes,
            1,
            .{ .update_after_bind_bit = true },
        );
        defer descriptor_pool.deinit(u.device.logical_device);

        //create texture
        const render_texture_width = conf.settings.resolution[0];
        const render_texture_height = conf.settings.resolution[1];

        const render_texture = try emma.vlk_image.init(
            &u.vma,
            &u.device,
            .r32g32b32a32_sfloat,
            .{
                .transfer_dst_bit = true,
                .transfer_src_bit = true,
                .sampled_bit = true,
                .storage_bit = true,
            },
            .{
                .color_bit = true,
            },
            .{
                .width = render_texture_width,
                .height = render_texture_height,
                .depth = 1,
            },
            false,
        );
        {
            try is.begin();

            render_texture.cmd_transition(
                is.cmd,
                .{ .top_of_pipe_bit = true },
                .{ .top_of_pipe_bit = true },
                .{},
                .{},
                .undefined,
                .general,
                null,
            );

            is.cmd.clearColorImage(
                render_texture.handle,
                .general,
                @ptrCast(&vk.ClearColorValue{ .float_32 = .{ 0, 0, 0, 0 } }),
                1,
                @ptrCast(&render_texture.full_subresource_range()),
            );

            const clear_barrier = vk.ImageMemoryBarrier2{
                .src_stage_mask = .{ .clear_bit = true },
                .src_access_mask = .{ .transfer_write_bit = true },
                .dst_stage_mask = .{ .ray_tracing_shader_bit_khr = true },
                .dst_access_mask = .{ .shader_write_bit = true, .shader_read_bit = true },
                .old_layout = .general,
                .new_layout = .general,
                .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
                .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
                .image = render_texture.handle,
                .subresource_range = render_texture.full_subresource_range(),
            };

            is.cmd.pipelineBarrier2(&.{
                .image_memory_barrier_count = 1,
                .p_image_memory_barriers = @ptrCast(&clear_barrier),
            });

            try is.submit_and_wait(u.device.queue, u.device.logical_device);
        }
        defer render_texture.deinit(&u.vma, &u.device);

        const alloc_info = vk.DescriptorSetAllocateInfo{
            .descriptor_pool = descriptor_pool.handle,
            .descriptor_set_count = 1,
            .p_set_layouts = &[_]vk.DescriptorSetLayout{
                pipeline.pipeline.descriptor_set_layout.handle,
            },
        };
        var descriptor_set: vk.DescriptorSet = undefined;
        try u.device.logical_device.allocateDescriptorSets(&alloc_info, @ptrCast(&descriptor_set));
        var sets = [_]vk.DescriptorSet{
            descriptor_set,
        };
        const tlas_descriptor_info = vk.WriteDescriptorSetAccelerationStructureKHR{
            .acceleration_structure_count = 1,
            .p_acceleration_structures = &[_]vk.AccelerationStructureKHR{tlas.handle},
        };
        const image_info = vk.DescriptorImageInfo{
            .image_view = render_texture.view,
            .image_layout = vk.ImageLayout.general,
            .sampler = u.samplers.linear_clamp,
        };
        const writes = [_]vk.WriteDescriptorSet{
            .{
                .dst_set = descriptor_set,
                .dst_binding = 0,
                .descriptor_count = 1,
                .dst_array_element = 0,
                .p_texel_buffer_view = undefined,
                .descriptor_type = .acceleration_structure_khr,
                .p_image_info = undefined,
                .p_buffer_info = undefined,
                .p_next = &tlas_descriptor_info,
            },
            .{
                .dst_set = descriptor_set,
                .dst_binding = 1,
                .descriptor_count = 1,
                .dst_array_element = 0,
                .descriptor_type = .storage_image,
                .p_texel_buffer_view = undefined,
                .p_image_info = @ptrCast(&.{image_info}),
                .p_buffer_info = undefined,
            },
        };
        u.device.logical_device.updateDescriptorSets(writes.len, &writes, 0, null);

        const rt_pipeline_instance = pipeline.pipeline.instance(sets[0..]);
        _ = rt_pipeline_instance;

        {
            var swapchain = try emma.vlk_swapchain.init(
                allocator,
                &u,
                @intCast(width),
                @intCast(height),
            );
            defer swapchain.deinit(&u.device);

            var frames = try emma.vlk_frames.init(
                allocator,
                &u.device,
                cmd_pool.handle,
                emma.max_frames_in_flight,
            );
            defer frames.deinit(u.device.logical_device);

            var quit = false;
            const render_begin = std.time.milliTimestamp();

            var time_ms = std.time.milliTimestamp() - render_begin;
            var time_sec: f32 = @as(f32, @floatFromInt(time_ms)) / 1000;

            var samples: i32 = 0;

            const image_available = try allocator.alloc(vk.Semaphore, swapchain.images.len);
            @memset(image_available, .null_handle);
            const render_finished = try allocator.alloc(vk.Semaphore, swapchain.images.len);

            defer {
                for (image_available) |s| {
                    if (s != .null_handle) u.device.logical_device.destroySemaphore(s, null);
                }
                allocator.free(image_available);
            }
            defer {
                for (render_finished) |s| u.device.logical_device.destroySemaphore(s, null);
                allocator.free(render_finished);
            }

            for (render_finished) |*s| {
                s.* = try u.device.logical_device.createSemaphore(&.{}, null);
            }

            var acquire_semaphore = try u.device.logical_device.createSemaphore(&.{}, null);
            defer u.device.logical_device.destroySemaphore(acquire_semaphore, null);

            var frame_counter: u32 = 0;
            var flush_render_texture: bool = true;
            var accumilation_frame_counter: u32 = 0;

            const tile_pixel_strides = conf.settings.render_tile;
            var tiles = [2]emma.TileElm{
                emma.TileElm.init(tile_pixel_strides[0], render_texture_width),
                emma.TileElm.init(tile_pixel_strides[1], render_texture_height),
            };

            var last_present_ms: i64 = 0;
            var avg_ms: f64 = 0.0;
            var avg_n: f64 = 0.0;

            var done = false;
            while (!quit) {
                // Event handling
                {
                    while (sdl.events.poll()) |event| {
                        switch (event) {
                            .quit => quit = true,
                            .terminating => quit = true,
                            .mouse_motion => |mm| {
                                mouse = .{ .x = mm.x, .y = mm.y };
                            },
                            .key_down => |key| key_state[@intFromEnum(key.scancode.?)] = true,
                            .key_up => |key| key_state[@intFromEnum(key.scancode.?)] = false,
                            .window_resized => |e| swapchain.resize(&u, @intCast(e.width), @intCast(e.height)),
                            else => {},
                        }
                    }
                }

                if (key_state[@intFromEnum(sdl.Scancode.func5)]) {
                    flush_render_texture = true;
                }

                // Frame  setup
                const frame = frames.current();
                try frame.fence.wait_and_reset(u.device.logical_device);

                const now_time_ms = std.time.milliTimestamp() - render_begin;
                const now_time_sec = @as(f32, @floatFromInt(now_time_ms)) / 1000;
                const dt = now_time_ms - time_ms;
                _ = dt;

                time_ms = now_time_ms;
                time_sec = now_time_sec;

                //Commands
                {
                    try emma.vlk_cmd_begin_one(frame.cmd);

                    if (flush_render_texture) {
                        accumilation_frame_counter = 0;
                        flush_render_texture = false;
                        frame.cmd.clearColorImage(
                            render_texture.handle,
                            .general,
                            @ptrCast(&vk.ClearColorValue{ .float_32 = .{ 0, 0, 0, 0 } }),
                            1,
                            @ptrCast(&render_texture.full_subresource_range()),
                        );

                        const clear_barrier = vk.ImageMemoryBarrier2{
                            .src_stage_mask = .{ .clear_bit = true },
                            .src_access_mask = .{ .transfer_write_bit = true },
                            .dst_stage_mask = .{ .ray_tracing_shader_bit_khr = true },
                            .dst_access_mask = .{ .shader_write_bit = true, .shader_read_bit = true },
                            .old_layout = .general,
                            .new_layout = .general,
                            .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
                            .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
                            .image = render_texture.handle,
                            .subresource_range = render_texture.full_subresource_range(),
                        };
                        frame.cmd.pipelineBarrier2(&.{
                            .image_memory_barrier_count = 1,
                            .p_image_memory_barriers = @ptrCast(&clear_barrier),
                        });
                    }
                    // rendering
                    if (!done) {
                        frame.cmd.bindPipeline(.ray_tracing_khr, pipeline.pipeline.pipeline);
                        frame.cmd.bindDescriptorSets(
                            .ray_tracing_khr,
                            pipeline.pipeline.layout,
                            0,
                            1,
                            @ptrCast(&descriptor_set),
                            0,
                            null,
                        );

                        {
                            pc2.width = @intCast(render_texture_width);
                            pc2.height = @intCast(render_texture_height);
                            pc2.time = time_sec;
                            pc2.posx = tiles[0].pos;
                            pc2.posy = tiles[1].pos;
                            pc2.mouse = mouse;
                            pc2.frame = accumilation_frame_counter;
                        }
                        frame.cmd.pushConstants(
                            pipeline.pipeline.layout,
                            .{
                                .raygen_bit_khr = true,
                                .miss_bit_khr = true,
                                .closest_hit_bit_khr = true,
                            },
                            0,
                            @sizeOf(@TypeOf(pc2)),
                            &pc2,
                        );
                        frame.cmd.traceRaysKHR(
                            &pipeline.sbt.raygen_region,
                            &pipeline.sbt.miss_region,
                            &pipeline.sbt.hit_region,
                            &pipeline.sbt.callable_region,
                            @intCast(tiles[0].len),
                            @intCast(tiles[1].len),
                            1,
                        );

                        {
                            tiles[0] = emma.next_tile(tiles[0].pos, tile_pixel_strides[0], render_texture_width);
                            if (tiles[0].pos == 0)
                                tiles[1] = emma.next_tile(tiles[1].pos, tile_pixel_strides[1], render_texture_height);
                        }
                    } else {
                        // quit = true;
                    }

                    const frame_done = (tiles[0].pos == 0 and tiles[1].pos == 0);

                    if (frame_done and !done) {
                        const last_present_diff = now_time_ms - last_present_ms;
                        samples += 1;
                        frame_counter += 1;
                        accumilation_frame_counter += 1;

                        last_present_ms = now_time_ms;

                        avg_n += 1;
                        avg_ms += (@as(f64, @floatFromInt(last_present_diff)) - avg_ms) / avg_n;

                        const result = try u.device.logical_device.acquireNextImageKHR(
                            swapchain.handle,
                            std.math.maxInt(u64),
                            acquire_semaphore,
                            .null_handle,
                        );

                        const image_index = result.image_index;
                        const prev = image_available[image_index];
                        image_available[image_index] = acquire_semaphore;
                        acquire_semaphore = if (prev != .null_handle) prev else try u.device.logical_device.createSemaphore(&.{}, null);
                        const wait_semaphore = image_available[image_index];
                        const swapchain_image = swapchain.images[image_index];

                        // Blit
                        {
                            render_texture.cmd_transition(
                                frame.cmd,
                                .{ .ray_tracing_shader_bit_khr = true },
                                .{ .all_transfer_bit = true },
                                .{ .shader_write_bit = true },
                                .{ .transfer_read_bit = true },
                                .general, //from
                                .transfer_src_optimal, //to
                                null,
                            );
                            swapchain_image.cmd_transition(
                                frame.cmd,
                                .{},
                                .{ .all_transfer_bit = true },
                                .{},
                                .{ .transfer_write_bit = true },
                                .undefined,
                                .transfer_dst_optimal,
                                null,
                            );
                            {
                                const blit_region = vk.ImageBlit2{
                                    .src_subresource = .{
                                        .aspect_mask = .{ .color_bit = true },
                                        .mip_level = 0,
                                        .base_array_layer = 0,
                                        .layer_count = 1,
                                    },
                                    .src_offsets = .{
                                        .{ .x = 0, .y = 0, .z = 0 },
                                        .{
                                            .x = @intCast(render_texture.extent.width),
                                            .y = @intCast(render_texture.extent.height),
                                            .z = 1,
                                        },
                                    },
                                    .dst_subresource = .{
                                        .aspect_mask = .{ .color_bit = true },
                                        .mip_level = 0,
                                        .base_array_layer = 0,
                                        .layer_count = 1,
                                    },
                                    .dst_offsets = .{
                                        .{ .x = 0, .y = 0, .z = 0 },
                                        .{
                                            .x = @intCast(swapchain.extent.width),
                                            .y = @intCast(swapchain.extent.height),
                                            .z = 1,
                                        },
                                    },
                                };
                                frame.cmd.blitImage2(
                                    &.{
                                        .src_image = render_texture.handle,
                                        .src_image_layout = .transfer_src_optimal,
                                        .dst_image = swapchain_image.handle,
                                        .dst_image_layout = .transfer_dst_optimal,
                                        .region_count = 1,
                                        .p_regions = @ptrCast(&blit_region),
                                        .filter = .linear,
                                    },
                                );
                            }
                            swapchain_image.cmd_transition(
                                frame.cmd,
                                .{ .all_transfer_bit = true },
                                .{ .bottom_of_pipe_bit = true },
                                .{ .transfer_write_bit = true },
                                .{},
                                .transfer_dst_optimal,
                                .present_src_khr,
                                null,
                            );
                            render_texture.cmd_transition(
                                frame.cmd,
                                .{ .all_transfer_bit = true },
                                .{ .ray_tracing_shader_bit_khr = true },
                                .{ .transfer_read_bit = true },
                                .{ .shader_write_bit = true },
                                .transfer_src_optimal,
                                .general,
                                null,
                            );
                        }
                        try frame.cmd.endCommandBuffer();
                        // Submit
                        {
                            const wait_stage = vk.PipelineStageFlags{ .all_commands_bit = true };
                            const submit_info = [_]vk.SubmitInfo{
                                .{
                                    .p_command_buffers = @ptrCast(&frame.cmd.handle),
                                    .command_buffer_count = 1,
                                    .wait_semaphore_count = 1,
                                    .p_wait_semaphores = @ptrCast(&wait_semaphore),
                                    .p_wait_dst_stage_mask = @ptrCast(&wait_stage),
                                    .signal_semaphore_count = 1,
                                    .p_signal_semaphores = @ptrCast(&render_finished[image_index]),
                                },
                            };
                            try u.device.queue.submit(submit_info.len, &submit_info, frame.fence.handle);
                        }

                        //Present
                        {
                            _ = try u.device.queue.presentKHR(&.{
                                .wait_semaphore_count = 1,
                                .p_wait_semaphores = @ptrCast(&render_finished[image_index]),
                                .swapchain_count = 1,
                                .p_swapchains = @ptrCast(&swapchain.handle),
                                .p_image_indices = @ptrCast(&image_index),
                            });
                        }
                        // frame_counter += 1;
                    } else {
                        try frame.cmd.endCommandBuffer();
                        const submit_info = vk.SubmitInfo{
                            .command_buffer_count = 1,
                            .p_command_buffers = @ptrCast(&frame.cmd.handle),
                            // no wait/signal semaphores
                        };
                        try u.device.queue.submit(1, &[1]vk.SubmitInfo{submit_info}, frame.fence.handle);
                    }
                }
                frames.advance();

                if (accumilation_frame_counter > 5000) {
                    done = true;
                } else {
                    done = false;
                }
            }

            {
                time_ms = std.time.milliTimestamp() - render_begin;
                time_sec = @as(f32, @floatFromInt(time_ms)) / 1000;
                std.debug.print("ran for {d} with avg ms per full frame {d:.2}\n", .{ time_sec, avg_ms });
            }

            //dump texture
            {
                var readback = try emma.vlk_readback_buffer(&u.vma, render_texture.extent.width * render_texture.extent.height * 4 * @sizeOf(f32));
                defer readback.deinit(&u.vma);

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
                    .image_extent = render_texture.extent,
                };

                {
                    try is.begin();
                    // try emma.vlk_cmd_begin_one(cmd);
                    render_texture.cmd_transition(
                        is.cmd,
                        .{ .ray_tracing_shader_bit_khr = true },
                        .{ .all_transfer_bit = true },
                        .{ .shader_write_bit = true },
                        .{ .transfer_read_bit = true },
                        .general,
                        .transfer_src_optimal,
                        render_texture.full_subresource_range(),
                    );
                    is.cmd.copyImageToBuffer(
                        render_texture.handle,
                        .transfer_src_optimal,
                        readback.handle,
                        1,
                        @ptrCast(&region),
                    );
                    render_texture.cmd_transition(
                        is.cmd,
                        .{ .all_transfer_bit = true },
                        .{ .ray_tracing_shader_bit_khr = true },
                        .{ .transfer_read_bit = true },
                        .{ .shader_write_bit = true },
                        .transfer_src_optimal,
                        .general,
                        render_texture.full_subresource_range(),
                    );
                    try is.cmd.endCommandBuffer();
                    const dump_fence = try emma.vlk_fence.init(&u.device, .{});
                    defer dump_fence.deinit(u.device.logical_device);

                    try u.device.queue.submit(1, &[1]vk.SubmitInfo{.{
                        .command_buffer_count = 1,
                        .p_command_buffers = @ptrCast(&is.cmd.handle),
                    }}, dump_fence.handle);

                    try dump_fence.wait_and_reset(u.device.logical_device);

                    const mapped = readback.info.pMappedData orelse return error.MapFailed;
                    const pixels: [*][4]f32 = @ptrCast(@alignCast(mapped));
                    try emma.write_exr_rgba(allocator, pixels, render_texture_width, render_texture_height, "render.exr");
                }
            }

            try u.device.logical_device.deviceWaitIdle();
        }
    }
}
