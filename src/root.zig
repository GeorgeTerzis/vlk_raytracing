const std = @import("std");
const builtin = @import("builtin");

// pub const mth = @import("mth");
pub const obj = @import("obj");
// pub const zigimg = @import("zigimg");
pub const sdl = @import("sdl3");
pub const vk = @import("vulkan");

pub const mesh = @import("mesh.zig");

pub const c_vma = @cImport({
    @cInclude("vma.h");
});

pub const tinyexr = @cImport({
    @cInclude("tinyexr.h");
});

pub fn ns_to_ms(now: u64) f32 {
    return @as(f32, @floatFromInt(now)) / 1_000_000.0;
}

pub fn to_enum(comptime T: type, in: anytype) T {
    const int_val = @intFromPtr(in);
    return @as(T, @enumFromInt(int_val));
}
pub fn to_ptr(comptime T: type, in: anytype) T {
    return @ptrFromInt(@intFromEnum(in));
}

const validation_layers: []const [*:0]const u8 = &.{
    "VK_LAYER_KHRONOS_validation",
};
const required_device_extensions: []const [*:0]const u8 = &.{
    vk.extensions.khr_swapchain.name,
    vk.extensions.khr_ray_tracing_pipeline.name,
    vk.extensions.khr_acceleration_structure.name,
    vk.extensions.khr_deferred_host_operations.name,
    vk.extensions.ext_mesh_shader.name,
    vk.extensions.khr_compute_shader_derivatives.name,
};
const required_features = .{
    vk.PhysicalDeviceAccelerationStructureFeaturesKHR{
        .acceleration_structure = vk.Bool32.true,
    },
    vk.PhysicalDeviceRayTracingPipelineFeaturesKHR{
        .ray_tracing_pipeline = vk.Bool32.true,
    },
    vk.PhysicalDeviceComputeShaderDerivativesFeaturesKHR{
        .compute_derivative_group_quads = vk.Bool32.true,
        .compute_derivative_group_linear = vk.Bool32.true,
    },
    vk.PhysicalDeviceBufferDeviceAddressFeatures{
        .buffer_device_address = vk.Bool32.true,
    },
    vk.PhysicalDeviceDynamicRenderingFeatures{
        .dynamic_rendering = vk.Bool32.true,
    },
    vk.PhysicalDeviceSynchronization2Features{
        .synchronization_2 = vk.Bool32.true,
    },
    vk.PhysicalDeviceDescriptorIndexingFeatures{
        .shader_sampled_image_array_non_uniform_indexing = vk.Bool32.true,
        .shader_storage_buffer_array_non_uniform_indexing = vk.Bool32.true,
        .shader_storage_image_array_non_uniform_indexing = vk.Bool32.true,
        .shader_uniform_buffer_array_non_uniform_indexing = vk.Bool32.true,
        .descriptor_binding_sampled_image_update_after_bind = vk.Bool32.true,
        .descriptor_binding_storage_image_update_after_bind = vk.Bool32.true,
        .descriptor_binding_storage_buffer_update_after_bind = vk.Bool32.true,
        .descriptor_binding_uniform_buffer_update_after_bind = vk.Bool32.true,
        .descriptor_binding_partially_bound = vk.Bool32.true,
        .descriptor_binding_update_unused_while_pending = vk.Bool32.true,
        .descriptor_binding_variable_descriptor_count = vk.Bool32.true,
        .runtime_descriptor_array = vk.Bool32.true,
    },
};

pub const max_frames_in_flight = 3;

pub const AppError = error{
    MissingValidationLayers,
    MissingsExtensions,
    NoVulkanGPU,
    NoSuitableMemeoryType,
};

pub const log = struct {
    fn major_version(version: u32) u32 {
        return version >> 22;
    }

    fn minor_version(version: u32) u32 {
        return (version >> 12) & 0x3ff;
    }

    fn patch_version(version: u32) u32 {
        return version & 0xfff;
    }

    pub fn physical_device(
        device: vk.PhysicalDevice,
        properties: vk.PhysicalDeviceProperties,
        features: vk.PhysicalDeviceFeatures,
    ) void {
        _ = device; // autofix
        _ = features; // autofix
        std.debug.print("physical device:\n\tname={s}\n\tdevice_type={s}\n\tapi_version={}.{}.{}\n", .{
            properties.device_name,
            @tagName(properties.device_type),
            major_version(properties.api_version),
            minor_version(properties.api_version),
            patch_version(properties.api_version),
        });
    }

    pub fn queue_properties(index: u32, prop: vk.QueueFamilyProperties) void {
        const bits = prop.queue_flags;
        std.debug.print("Queue Family {}:\n\tcount={}\n\tgraphics={}\n\tcompute={}\n\ttransfer={}\n", .{
            index,
            prop.queue_count,
            bits.graphics_bit,
            bits.compute_bit,
            bits.transfer_bit,
        });
    }
};

pub const vlk_instance = struct {
    vkb: vk.BaseWrapper,
    instance: vk.InstanceProxy,

    fn init_instance_proxy(allocator: std.mem.Allocator, vkb: vk.BaseWrapper, instance: vk.Instance) !vk.InstanceProxy {
        const vki = try allocator.create(vk.InstanceWrapper);
        errdefer allocator.destroy(vki);

        vki.* = vk.InstanceWrapper.load(instance, vkb.dispatch.vkGetInstanceProcAddr.?);
        return vk.InstanceProxy.init(instance, vki);
    }

    fn init_instance(allocator: std.mem.Allocator, vkb: vk.BaseWrapper) !vk.InstanceProxy {
        const app_info: vk.ApplicationInfo = .{
            .p_application_name = "emma",
            .application_version = @bitCast(vk.makeApiVersion(0, 1, 0, 0)),
            .p_engine_name = "emma",
            .engine_version = @bitCast(vk.makeApiVersion(0, 1, 0, 0)),
            .api_version = @bitCast(vk.API_VERSION_1_4),
        };

        const extensions = try sdl.vulkan.getInstanceExtensions();
        // if (builtin.mode == .Debug) try vki_check_validation_layer_support(allocator, vkb);
        const create_info: vk.InstanceCreateInfo = .{
            .p_application_info = &app_info,
            .enabled_extension_count = @intCast(extensions.len),
            .pp_enabled_extension_names = extensions.ptr,

            .enabled_layer_count = count: switch (builtin.mode) {
                .Debug => break :count @intCast(validation_layers.len),
                else => break :count 0,
            },
            .pp_enabled_layer_names = layers: switch (builtin.mode) {
                .Debug => break :layers validation_layers.ptr,
                else => break :layers null,
            },
        };

        const instance = try vkb.createInstance(&create_info, null);
        return try init_instance_proxy(allocator, vkb, instance);
    }

    pub fn init(allocator: std.mem.Allocator) !vlk_instance {
        const vkb = vk.BaseWrapper.load(
            @as(vk.PfnGetInstanceProcAddr, @ptrCast(try sdl.vulkan.getVkGetInstanceProcAddr())),
        );

        const instance = try init_instance(allocator, vkb);

        return .{
            .vkb = vkb,
            .instance = instance,
        };
    }

    pub fn deinit(self: @This(), allocator: std.mem.Allocator) void {
        self.instance.destroyInstance(null);
        allocator.destroy(self.instance.wrapper);
    }
};

pub const sdl_instance = struct {
    w: sdl.Window,
};

pub fn sdl_init() !void {
    const init_flags = sdl.InitFlags{ .video = true, .events = true };
    try sdl.init(init_flags);
    try sdl.vulkan.loadLibrary(null);
}

pub fn sdl_deinit() void {
    sdl.shutdown();
    sdl.vulkan.unloadLibrary();
}

pub fn pnext_chain(allocator: std.mem.Allocator, args: anytype) !*anyopaque {
    var cursor: ?*anyopaque = null;
    inline for (args) |arg| {
        const feature = try allocator.create(@TypeOf(arg));
        feature.* = arg;
        feature.*.p_next = cursor;
        cursor = feature;
    }
    return cursor.?;
}

pub const vlk_device = struct {
    physical_device: vk.PhysicalDevice,
    logical_device: vk.DeviceProxy,

    queue: vk.QueueProxy,
    queue_family_index: u32,

    allocator: std.mem.Allocator,

    fn get_physical_device(allocator: std.mem.Allocator, vki: *vlk_instance, window: *vlk_window) !vk.PhysicalDevice {
        const physical_devices = try vki.instance.enumeratePhysicalDevicesAlloc(allocator);
        if (physical_devices.len == 0)
            return error.NoVulkanGPU;

        var score_buffer = try allocator.alloc(i32, physical_devices.len);
        defer allocator.free(score_buffer);

        {
            for (physical_devices, 0..) |physical_device, index| {
                var score: i32 = 0;
                const properties = vki.instance.getPhysicalDeviceProperties(physical_device);

                var deriv_support = vk.PhysicalDeviceComputeShaderDerivativesFeaturesKHR{
                    .compute_derivative_group_quads = vk.Bool32.false,
                    .compute_derivative_group_linear = vk.Bool32.false,
                    .p_next = null,
                };
                var features2 = vk.PhysicalDeviceFeatures2{
                    .features = .{},
                    .p_next = &deriv_support,
                };
                vki.instance.getPhysicalDeviceFeatures2(physical_device, &features2);
                if (deriv_support.compute_derivative_group_quads == vk.Bool32.true and deriv_support.compute_derivative_group_linear == vk.Bool32.true) {
                    score += 10;
                } else {
                    score -= 20;
                }
                const features = vki.instance.getPhysicalDeviceFeatures(physical_device);

                // log.physical_device(physical_device, properties, features);

                score += if (properties.device_type == vk.PhysicalDeviceType.discrete_gpu) 5 else 0;
                score += if (features.geometry_shader == vk.Bool32.true) 1 else 0;
                score += if (features.tessellation_shader == vk.Bool32.true) 1 else 0;
                {
                    const surface_capabilities = try vki.instance.getPhysicalDeviceSurfaceCapabilitiesKHR(physical_device, window.surface_khr());
                    score += if (surface_capabilities.supported_usage_flags.transfer_dst_bit) 10 else -20;
                }

                score_buffer[index] = score;
            }
        }

        var result: vk.PhysicalDevice = undefined;
        {
            var index: usize = 0;
            var max: i32 = 0;
            var max_index: usize = 0;

            for (score_buffer) |score| {
                if (score > max) {
                    result = physical_devices[index];
                    max = score;
                    max_index = index;
                }
                index = index + 1;
            }

            if (score_buffer[max_index] <= 0)
                return error.NoVulkanGPU;
        }
        return result;
    }

    fn find_queue_indecies(allocator: std.mem.Allocator, device: vk.PhysicalDevice, vki: *vlk_instance) !u32 {
        const queue_family_properties = try vki.instance.getPhysicalDeviceQueueFamilyPropertiesAlloc(device, allocator);
        defer allocator.free(queue_family_properties);

        var selected_queue_family_index: usize = undefined;

        for (queue_family_properties, 0..) |queue_prop, i| {
            // log.queue_properties(@intCast(i), queue_prop);
            const flags = queue_prop.queue_flags;
            if (flags.graphics_bit and flags.compute_bit) {
                selected_queue_family_index = i;
            }
        }

        return @intCast(selected_queue_family_index);
    }

    pub fn init(allocator: std.mem.Allocator, vki: *vlk_instance, window: *vlk_window) !vlk_device {
        const physical_device = try get_physical_device(allocator, vki, window);
        const queue_index = try find_queue_indecies(allocator, physical_device, vki);

        var features_arena = std.heap.ArenaAllocator.init(allocator);
        defer features_arena.deinit();
        const features_arena_proxy = features_arena.allocator();

        const logical_device = blk: {
            const qprio: [1]f32 = .{1.0};
            const qc_info = [1]vk.DeviceQueueCreateInfo{.{
                .s_type = vk.StructureType.device_queue_create_info,
                .queue_family_index = queue_index,
                .queue_count = 1,
                .p_queue_priorities = &qprio,
            }};

            const features = try pnext_chain(
                features_arena_proxy,
                required_features,
            );

            const device_features = vk.PhysicalDeviceFeatures{
                .multi_draw_indirect = vk.Bool32.true,
                .sparse_binding = vk.Bool32.true,
            };

            const ld_info = vk.DeviceCreateInfo{
                .s_type = vk.StructureType.device_create_info,

                .queue_create_info_count = qc_info.len,
                .p_queue_create_infos = &qc_info,

                .p_enabled_features = &device_features,

                .enabled_layer_count = 0,
                .pp_enabled_layer_names = null,

                .enabled_extension_count = @intCast(required_device_extensions.len),
                .pp_enabled_extension_names = required_device_extensions.ptr,

                .p_next = features,
            };

            const ldevice = try vki.instance.createDevice(physical_device, &ld_info, null);
            const vkd = try allocator.create(vk.DeviceWrapper);
            vkd.* = vk.DeviceWrapper.load(ldevice, vki.instance.wrapper.dispatch.vkGetDeviceProcAddr.?);
            const deviceProxy = vk.DeviceProxy.init(ldevice, vkd);

            break :blk deviceProxy;
        };

        const queue = try vlk_queue.init(logical_device, queue_index, 0);

        return .{
            .physical_device = physical_device,
            .logical_device = logical_device,
            .allocator = allocator,

            .queue = queue,
            .queue_family_index = queue_index,
        };
    }

    pub fn deinit(self: @This()) void {
        self.logical_device.destroyDevice(null);
        self.allocator.destroy(self.logical_device.wrapper);
    }
};

pub const vlk_queue = struct {
    pub fn init(device: vk.DeviceProxy, family_index: u32, index: u32) !vk.QueueProxy {
        const queue = device.getDeviceQueue(family_index, index);
        const proxy = vk.QueueProxy.init(queue, device.wrapper);
        return proxy;
    }
};

pub const vlk_command_pool = struct {
    handle: vk.CommandPool,

    pub fn init(device: *vlk_device) !vlk_command_pool {
        const info = vk.CommandPoolCreateInfo{
            .queue_family_index = device.queue_family_index,
            .flags = .{ .reset_command_buffer_bit = true },
        };

        const pool = try device.logical_device.createCommandPool(&info, null);

        return .{
            .handle = pool,
        };
    }

    pub fn deinit(self: vlk_command_pool, device: vk.DeviceProxy) void {
        device.destroyCommandPool(self.handle, null);
    }
};

pub const vlk_command_buffer_allocation = struct {
    buffers: []vk.CommandBufferProxy,

    pub fn init(
        allocator: std.mem.Allocator,
        device: vk.DeviceProxy,
        pool: vk.CommandPool,
        count: usize,
    ) !vlk_command_buffer_allocation {
        const alloc_info = vk.CommandBufferAllocateInfo{
            .command_pool = pool,
            .level = .primary,
            .command_buffer_count = @intCast(count),
        };

        const handles = try allocator.alloc(vk.CommandBuffer, count);
        try device.allocateCommandBuffers(&alloc_info, handles.ptr);
        defer allocator.free(handles);

        var proxys = try allocator.alloc(vk.CommandBufferProxy, count);
        for (handles, 0..) |handle, i| {
            proxys[i] = vk.CommandBufferProxy.init(handle, device.wrapper);
        }

        return .{
            .buffers = proxys,
        };
    }

    pub fn deinit(self: *vlk_command_buffer_allocation, allocator: std.mem.Allocator) void {
        allocator.free(self.buffers);
    }
};

pub const vlk_window = struct {
    sdl_window: sdl.video.Window,
    surface: sdl.vulkan.Surface,

    pub fn surface_khr(self: @This()) vk.SurfaceKHR {
        return to_enum(vk.SurfaceKHR, self.surface.surface);
    }

    pub fn init(vki: *vlk_instance, screen_width: usize, screen_height: usize) !vlk_window {
        var self: vlk_window = undefined;
        self.sdl_window = try sdl.video.Window.init("EMMA", screen_width, screen_height, .{ .vulkan = true, .resizable = false });

        const handle = to_ptr(sdl.vulkan.Instance, vki.instance.handle);
        self.surface = try sdl.vulkan.Surface.init(self.sdl_window, handle, null);

        return self;
    }

    pub fn deinit(self: @This()) void {
        sdl.vulkan.Surface.deinit(self.surface);
        self.sdl_window.deinit();
    }
};

pub fn create_swapchain_images(
    allocator: std.mem.Allocator,
    device: *vlk_device,
    swapchain: vk.SwapchainKHR,
    format: vk.Format,
    extent: vk.Extent3D,
) ![]vlk_image {
    // Get the images from the swapchain
    const images = try device.logical_device.getSwapchainImagesAllocKHR(swapchain, allocator);

    const mip_levels = 1;
    const count = images.len;

    // Allocate array for vlk_image wrappers
    const vimages = try allocator.alloc(vlk_image, count);

    for (images, 0..) |image, i| {
        const view = try create_image_view(
            device,
            image,
            format,
            vk.ImageViewType.@"2d",
            mip_levels,
            1,
            .{ .color_bit = true },
        );

        vimages[i] = vlk_image{
            .handle = image,
            .view = view,
            .allocation = null,
            .extent = extent,
            .format = format,
            .mip_levels = mip_levels,
        };
    }
    return vimages[0..];
}

pub const vlk_swapchain = struct {
    handle: vk.SwapchainKHR,

    images: []vlk_image,

    format: vk.Format,
    extent: vk.Extent2D,

    present_mode: vk.PresentModeKHR,
    allocator: std.mem.Allocator,

    pub fn resize(self: *@This(), vki: *vlk_instance, device: *vlk_device, window: *vlk_window, width: u32, height: u32) void {
        self.rebuild(
            vki,
            device,
            window,
            width,
            height,
        ) catch |err| switch (err) {
            error.SurfaceLostKHR => {},
            else => std.debug.panic("swapchain rebuild failed: {}", .{err}),
        };
    }

    fn create(
        allocator: std.mem.Allocator,
        vki: *vlk_instance,
        device: *vlk_device,
        window: *vlk_window,
        width: u32,
        height: u32,
        old: ?*vlk_swapchain,
    ) !vlk_swapchain {
        const caps = try vki.instance.getPhysicalDeviceSurfaceCapabilitiesKHR(device.physical_device, window.surface_khr());

        const extent: vk.Extent2D = if (caps.current_extent.width != std.math.maxInt(u32))
            caps.current_extent
        else
            .{
                .width = std.math.clamp(width, caps.min_image_extent.width, caps.max_image_extent.width),
                .height = std.math.clamp(height, caps.min_image_extent.height, caps.max_image_extent.height),
            };

        const format, const present_mode = if (old) |o|
            .{ o.format, o.present_mode }
        else blk: {
            const formats = try vki.instance.getPhysicalDeviceSurfaceFormatsAllocKHR(device.physical_device, window.surface_khr(), allocator);
            defer allocator.free(formats);
            var chosen_format = formats[0];
            for (formats) |f| {
                if (f.format == .b8g8r8a8_srgb and f.color_space == .srgb_nonlinear_khr) {
                    chosen_format = f;
                    break;
                }
            }

            const present_modes = try vki.instance.getPhysicalDeviceSurfacePresentModesAllocKHR(device.physical_device, window.surface_khr(), allocator);
            defer allocator.free(present_modes);
            var chosen_present_mode = vk.PresentModeKHR.immediate_khr;
            for (present_modes) |pm| {
                if (pm == .shared_continuous_refresh_khr) {
                    chosen_present_mode = pm;
                    break;
                }
            }
            break :blk .{ chosen_format.format, chosen_present_mode };
        };

        const image_count = blk: {
            var count = caps.min_image_count + 1;
            if (caps.max_image_count > 0)
                count = @min(count, caps.max_image_count);
            break :blk count;
        };
        const queue_family_indices = [1]u32{device.queue_family_index};

        const handle = try device.logical_device.createSwapchainKHR(&.{
            .surface = window.surface_khr(),

            .min_image_count = image_count,
            .image_format = format,
            .image_color_space = .srgb_nonlinear_khr,
            .image_extent = extent,
            .image_array_layers = 1,
            .image_usage = .{ .color_attachment_bit = true, .transfer_dst_bit = true },
            .image_sharing_mode = .exclusive,

            .queue_family_index_count = queue_family_indices.len,
            .p_queue_family_indices = &queue_family_indices,

            .pre_transform = caps.current_transform,
            .composite_alpha = .{ .opaque_bit_khr = true },
            .present_mode = present_mode,

            .clipped = vk.Bool32.true,

            .old_swapchain = if (old) |o| o.handle else .null_handle,
        }, null);

        const vimages = try create_swapchain_images(
            allocator,
            device,
            handle,
            format,
            .{ .width = extent.width, .height = extent.height, .depth = 1 },
        );

        return .{
            .handle = handle,
            .images = vimages,
            .format = format,
            .extent = extent,
            .present_mode = present_mode,
            .allocator = allocator,
        };
    }

    pub fn init(
        allocator: std.mem.Allocator,
        instance: *vlk_instance,
        device: *vlk_device,
        window: *vlk_window,
        width: u32,
        height: u32,
    ) !vlk_swapchain {
        return create(allocator, instance, device, window, width, height, null);
    }

    pub fn rebuild(
        self: *vlk_swapchain,
        instance: *vlk_instance,
        device: *vlk_device,
        window: *vlk_window,
        width: u32,
        height: u32,
    ) !void {
        try device.logical_device.deviceWaitIdle();
        const new = try create(self.allocator, instance, device, window, width, height, self);
        self.deinit(device);
        self.* = new;
    }

    pub fn deinit(self: @This(), device: *vlk_device) void {
        for (self.images) |image| image.deinit(null, device);
        self.allocator.free(self.images);
        device.logical_device.destroySwapchainKHR(self.handle, null);
    }
};

pub const vlk_frame = struct {
    cmd: vk.CommandBufferProxy,
    fence: vlk_fence,

    pub fn init(
        device: *vlk_device,
        pool: vk.CommandPool,
    ) !vlk_frame {
        var handle: vk.CommandBuffer = undefined;
        try device.logical_device.allocateCommandBuffers(&.{
            .command_pool = pool,
            .level = .primary,
            .command_buffer_count = 1,
        }, @ptrCast(&handle));
        errdefer device.logical_device.freeCommandBuffers(pool, 1, @ptrCast(&handle));

        const fence = try vlk_fence.init(device, .{ .signaled_bit = true });

        return .{
            .cmd = vk.CommandBufferProxy.init(handle, device.logical_device.wrapper),
            .fence = fence,
        };
    }

    pub fn deinit(self: @This(), device: vk.DeviceProxy) void {
        self.fence.deinit(device);
    }
};

pub const vlk_frames = struct {
    frames: []vlk_frame,
    index: usize,
    allocator: std.mem.Allocator,

    pub fn init(
        allocator: std.mem.Allocator,
        device: *vlk_device,
        pool: vk.CommandPool,
        count: usize,
    ) !vlk_frames {
        const frames = try allocator.alloc(vlk_frame, count);
        errdefer allocator.free(frames);

        var initialized: usize = 0;
        errdefer for (frames[0..initialized]) |f| f.deinit(device.logical_device);

        for (frames) |*f| {
            f.* = try vlk_frame.init(device, pool);
            initialized += 1;
        }

        return .{
            .frames = frames,
            .index = 0,
            .allocator = allocator,
        };
    }

    pub fn current(self: *vlk_frames) *vlk_frame {
        return &self.frames[self.index];
    }

    pub fn advance(self: *vlk_frames) void {
        self.index = (self.index + 1) % self.frames.len;
    }

    pub fn deinit(self: *vlk_frames, device: vk.DeviceProxy) void {
        for (self.frames) |f| f.deinit(device);
        self.allocator.free(self.frames);
    }
};

pub const vlk_samplers = struct {
    linear_repeat: vk.Sampler, // most 3D textures
    linear_clamp: vk.Sampler, // render targets, UI, decals
    nearest_repeat: vk.Sampler, // pixel art, data textures
    nearest_clamp: vk.Sampler, // shadow maps, lookup tables
    shadow: vk.Sampler, // depth compare, clamp to white border

    pub fn init(device: *vlk_device) !vlk_samplers {
        return .{
            .linear_repeat = try create(
                device,
                .linear,
                .linear,
                .repeat,
                false,
                0,
                12,
            ),
            .linear_clamp = try create(
                device,
                .linear,
                .linear,
                .clamp_to_edge,
                false,
                0,
                12,
            ),
            .nearest_repeat = try create(
                device,
                .nearest,
                .nearest,
                .repeat,
                false,
                0,
                0,
            ),
            .nearest_clamp = try create(
                device,
                .nearest,
                .nearest,
                .clamp_to_edge,
                false,
                0,
                0,
            ),
            .shadow = try create(
                device,
                .linear,
                .linear,
                .clamp_to_border,
                true,
                0,
                12,
            ),
        };
    }

    fn create(
        device: *vlk_device,
        mag: vk.Filter,
        min: vk.Filter,
        address: vk.SamplerAddressMode,
        compare: bool,
        min_lod: f32,
        max_lod: f32,
    ) !vk.Sampler {
        return device.logical_device.createSampler(&.{
            .mag_filter = mag,
            .min_filter = min,
            .mipmap_mode = if (max_lod > 0) .linear else .nearest,
            .address_mode_u = address,
            .address_mode_v = address,
            .address_mode_w = address,
            .mip_lod_bias = 0,
            .anisotropy_enable = vk.Bool32.false,
            .max_anisotropy = 1,
            .compare_enable = if (compare) vk.Bool32.true else vk.Bool32.false,
            .compare_op = if (compare) .less_or_equal else .always,
            .min_lod = min_lod,
            .max_lod = max_lod,
            .border_color = if (compare) .float_opaque_white else .int_opaque_black,
            .unnormalized_coordinates = vk.Bool32.false,
        }, null);
    }

    pub fn deinit(self: @This(), device: vk.DeviceProxy) void {
        device.destroySampler(self.linear_repeat, null);
        device.destroySampler(self.linear_clamp, null);
        device.destroySampler(self.nearest_repeat, null);
        device.destroySampler(self.nearest_clamp, null);
        device.destroySampler(self.shadow, null);
    }
};

pub const vlk_unit = struct {
    vki: vlk_instance,
    window: vlk_window,
    device: vlk_device,
    vma: vlk_vma,
    samplers: vlk_samplers,

    pub fn queue(self: @This()) vk.QueueProxy {
        return self.device.queue;
    }

    pub fn init(allocator: std.mem.Allocator, screen_width: usize, screen_height: usize) !vlk_unit {
        var vki = try vlk_instance.init(allocator);
        var window = try vlk_window.init(&vki, screen_width, screen_height);
        var device = try vlk_device.init(allocator, &vki, &window);
        const vma = try vlk_vma.init(&device, &vki);
        const samplers = try vlk_samplers.init(&device);

        return .{
            .vki = vki,
            .window = window,
            .device = device,
            .vma = vma,
            .samplers = samplers,
        };
    }

    pub fn deinit(self: @This(), allocator: std.mem.Allocator) void {
        self.samplers.deinit(self.device.logical_device);
        self.window.deinit();
        self.vma.deinit();
        self.device.deinit();
        self.vki.deinit(allocator);
    }
};

pub const vlk_vma = struct {
    allocator: c_vma.VmaAllocator,

    pub fn init(device: *vlk_device, vki: *vlk_instance) !vlk_vma {
        const vma_info = c_vma.VmaAllocatorCreateInfo{
            .physicalDevice = @ptrFromInt(@intFromEnum(device.physical_device)),
            .device = @ptrFromInt(@intFromEnum(device.logical_device.handle)),
            .instance = @ptrFromInt(@intFromEnum(vki.instance.handle)),
            .flags = c_vma.VMA_ALLOCATOR_CREATE_BUFFER_DEVICE_ADDRESS_BIT,
        };

        var vma: c_vma.VmaAllocator = undefined;
        const result = c_vma.vmaCreateAllocator(&vma_info, &vma);
        if (result != c_vma.VK_SUCCESS) {
            return error.VmaInitFailed;
        }

        return .{ .allocator = vma };
    }

    pub fn deinit(self: @This()) void {
        c_vma.vmaDestroyAllocator(self.allocator);
    }

    pub fn alloc_buffer_aligned(
        self: @This(),
        size: vk.DeviceSize,
        usage: c_vma.VkBufferUsageFlags,
        mem_usage: c_vma.VmaMemoryUsage,
        alloc_flags: c_vma.VmaAllocationCreateFlags,
        alignment: u64,
    ) !struct { buffer: c_vma.VkBuffer, allocation: c_vma.VmaAllocation, allocation_info: c_vma.VmaAllocationInfo } {
        const buffer_info = c_vma.VkBufferCreateInfo{
            .sType = c_vma.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
            .size = size,
            .usage = usage,
            .sharingMode = c_vma.VK_SHARING_MODE_EXCLUSIVE,
        };
        const alloc_create_info = c_vma.VmaAllocationCreateInfo{
            .usage = mem_usage,
            .flags = alloc_flags,
        };

        var buffer: c_vma.VkBuffer = undefined;
        var allocation: c_vma.VmaAllocation = undefined;
        var allocation_info: c_vma.VmaAllocationInfo = undefined;

        const result = c_vma.vmaCreateBufferWithAlignment(
            self.allocator,
            &buffer_info,
            &alloc_create_info,
            alignment,
            &buffer,
            &allocation,
            &allocation_info,
        );
        if (result != c_vma.VK_SUCCESS) return error.AllocationFailed;
        return .{
            .buffer = buffer,
            .allocation = allocation,
            .allocation_info = allocation_info,
        };
    }
    pub fn alloc_buffer(
        self: @This(),
        size: vk.DeviceSize,
        usage: c_vma.VkBufferUsageFlags,
        mem_usage: c_vma.VmaMemoryUsage,
        alloc_flags: c_vma.VmaAllocationCreateFlags,
    ) !struct { buffer: c_vma.VkBuffer, allocation: c_vma.VmaAllocation, allocation_info: c_vma.VmaAllocationInfo } {
        const buffer_info = c_vma.VkBufferCreateInfo{
            .sType = c_vma.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
            .size = size,
            .usage = usage,
            .sharingMode = c_vma.VK_SHARING_MODE_EXCLUSIVE,
        };

        const alloc_create_info = c_vma.VmaAllocationCreateInfo{
            .usage = mem_usage,
            .flags = alloc_flags,
        };

        var buffer: c_vma.VkBuffer = undefined;
        var allocation: c_vma.VmaAllocation = undefined;
        var allocation_info: c_vma.VmaAllocationInfo = undefined;

        const result = c_vma.vmaCreateBuffer(
            self.allocator,
            &buffer_info,
            &alloc_create_info,
            &buffer,
            &allocation,
            &allocation_info,
        );
        if (result != c_vma.VK_SUCCESS) return error.AllocationFailed;
        return .{
            .buffer = buffer,
            .allocation = allocation,
            .allocation_info = allocation_info,
        };
    }
};

pub const buffer_usage = struct {
    // intended uses
    vertex: bool = false,
    index: bool = false,
    storage: bool = false,
    indirect: bool = false,
    transfer_src: bool = false,
    transfer_dst: bool = false,

    // extra capabilities
    device_address: bool = false,
    acceleration_structure_input: bool = false,
    acceleration_structure_storage: bool = false,

    pub fn bits(self: @This()) c_vma.VkBufferUsageFlags {
        var flags: c_vma.VkBufferUsageFlags = 0;
        if (self.vertex) flags |= c_vma.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT;
        if (self.index) flags |= c_vma.VK_BUFFER_USAGE_INDEX_BUFFER_BIT;
        if (self.storage) flags |= c_vma.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT;
        if (self.indirect) flags |= c_vma.VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT;
        if (self.transfer_src) flags |= c_vma.VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
        if (self.transfer_dst) flags |= c_vma.VK_BUFFER_USAGE_TRANSFER_DST_BIT;
        if (self.device_address) flags |= c_vma.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT;
        if (self.acceleration_structure_input) flags |= c_vma.VK_BUFFER_USAGE_ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_BIT_KHR;
        if (self.acceleration_structure_storage) flags |= c_vma.VK_BUFFER_USAGE_ACCELERATION_STRUCTURE_STORAGE_BIT_KHR;
        return flags;
    }
};

pub const buffer_usage_presets = struct {
    pub const mesh = buffer_usage{
        .vertex = true,
        .index = true,
        .transfer_dst = true,
        .device_address = true,
        .acceleration_structure_input = true,
    };

    pub const scratch = buffer_usage{
        .storage = true,
        .device_address = true,
    };

    pub const as_storage = buffer_usage{
        .acceleration_structure_storage = true,
        .device_address = true,
    };

    pub const staging_upload = buffer_usage{
        .transfer_src = true,
    };

    pub const staging_readback = buffer_usage{
        .transfer_dst = true,
    };

    pub const tlas_instances = buffer_usage{
        .transfer_dst = true,
        .device_address = true,
        .acceleration_structure_input = true,
    };
};

pub const vlk_vma_buffer = struct {
    handle: vk.Buffer,
    allocation: c_vma.VmaAllocation,
    info: c_vma.VmaAllocationInfo,
    size: usize,

    pub fn init_aligned(
        vma_alloc: *vlk_vma,
        size: vk.DeviceSize,
        usage: c_vma.VkBufferUsageFlags,
        mem_usage: c_vma.VmaMemoryUsage,
        alloc_flags: c_vma.VmaAllocationCreateFlags,
        alignment: u64,
    ) !vlk_vma_buffer {
        const result = try vma_alloc.alloc_buffer_aligned(size, usage, mem_usage, alloc_flags, alignment);
        return .{
            .handle = @enumFromInt(@intFromPtr(result.buffer)),
            .allocation = result.allocation,
            .info = result.allocation_info,
            .size = size,
        };
    }
    pub fn init(
        vma_alloc: *vlk_vma,
        size: vk.DeviceSize,
        usage: c_vma.VkBufferUsageFlags,
        mem_usage: c_vma.VmaMemoryUsage,
        alloc_flags: c_vma.VmaAllocationCreateFlags,
    ) !vlk_vma_buffer {
        const result = try vma_alloc.alloc_buffer(size, usage, mem_usage, alloc_flags);
        return .{
            .handle = @enumFromInt(@intFromPtr(result.buffer)),
            .allocation = result.allocation,
            .info = result.allocation_info,
            .size = size,
        };
    }

    pub fn address(self: @This(), device: *vlk_device) vk.DeviceAddress {
        const info = vk.BufferDeviceAddressInfo{
            .buffer = self.handle,
        };
        return device.logical_device.getBufferDeviceAddress(&info);
    }

    pub fn deinit(self: @This(), vma: *vlk_vma) void {
        c_vma.vmaDestroyBuffer(vma.allocator, @ptrFromInt(@intFromEnum(self.handle)), self.allocation);
    }

    pub fn map(self: @This(), vma_alloc: *vlk_vma) !*anyopaque {
        if (self.info.pMappedData) |p| return p;
        var mapped: ?*anyopaque = undefined;
        const result = c_vma.vmaMapMemory(vma_alloc.allocator, self.allocation, &mapped);
        if (result != c_vma.VK_SUCCESS) return error.MapFailed;
        return mapped.?;
    }

    pub fn unmap(self: @This(), vma: *vlk_vma) void {
        if (self.info.pMappedData) {
            return;
        } else {
            c_vma.vmaUnmapMemory(vma.allocator, self.allocation);
        }
    }

    pub fn descriptor_buffer_info(self: @This()) vk.DescriptorBufferInfo {
        return .{
            .buffer = self.handle,
            .offset = 0,
            .range = self.info.size,
        };
    }

    pub fn mapped_slice(self: @This(), comptime T: type, vma: *vlk_vma) ![]T {
        const ptr = try self.map(vma);
        const count = self.info.size / @sizeOf(T);
        return @as([*]T, @ptrCast(@alignCast(ptr)))[0..count];
    }

    pub fn map_memcpy(self: @This(), vma: *vlk_vma, data: []const u8, offset: usize) !void {
        const ptr = try self.map(vma);
        const bytes: [*]u8 = @ptrCast(ptr);
        @memcpy(bytes[offset..][0..data.len], data);
    }
    pub fn cmd_copy_to(self: @This(), dst: *const vlk_vma_buffer, cmd: vk.CommandBufferProxy) void {
        const region = vk.BufferCopy{
            .src_offset = 0,
            .dst_offset = 0,
            .size = self.size,
        };
        cmd.copyBuffer(self.handle, dst.handle, 1, @ptrCast(&region));
    }
};

pub const vlk_descriptor_pool = struct {
    handle: vk.DescriptorPool,

    pub fn init(
        device: *vlk_device,
        pool_sizes: []const vk.DescriptorPoolSize,
        max_sets: u32,
        flags: vk.DescriptorPoolCreateFlags,
    ) !vlk_descriptor_pool {
        const handle = try device.logical_device.createDescriptorPool(&.{
            .flags = flags,
            .max_sets = max_sets,
            .pool_size_count = @intCast(pool_sizes.len),
            .p_pool_sizes = pool_sizes.ptr,
        }, null);
        return .{ .handle = handle };
    }

    pub fn deinit(self: @This(), device: vk.DeviceProxy) void {
        device.destroyDescriptorPool(self.handle, null);
    }
};

pub const vlk_descriptor_set_layout = struct {
    handle: vk.DescriptorSetLayout,

    pub fn init(
        device: *vlk_device,
        bindings: []const vk.DescriptorSetLayoutBinding,
        binding_flags: []const vk.DescriptorBindingFlags,
    ) !vlk_descriptor_set_layout {
        const flags_info = vk.DescriptorSetLayoutBindingFlagsCreateInfo{
            .binding_count = @intCast(binding_flags.len),
            .p_binding_flags = binding_flags.ptr,
        };

        const handle = try device.logical_device.createDescriptorSetLayout(&.{
            .flags = .{ .update_after_bind_pool_bit = true },
            .binding_count = @intCast(bindings.len),
            .p_bindings = bindings.ptr,
            .p_next = &flags_info,
        }, null);

        return .{ .handle = handle };
    }

    pub fn deinit(self: @This(), device: vk.DeviceProxy) void {
        device.destroyDescriptorSetLayout(self.handle, null);
    }
};

pub const vlk_pc_layout = struct {
    range: vk.PushConstantRange,

    pub fn init(comptime T: type, offset: usize) vlk_pc_layout {
        return .{
            .range = .{
                .stage_flags = .{ .compute_bit = true },
                .offset = @intCast(offset),
                .size = @sizeOf(T),
            },
        };
    }
};

pub const vlk_shader_module = struct {
    module: vk.ShaderModule,
    stage: vk.ShaderStageFlags,
    entry: [*:0]const u8,

    pub fn init(
        device: *vlk_device,
        spirv: []const u8,
        stage: vk.ShaderStageFlags,
        entry: ?[*:0]const u8,
    ) !vlk_shader_module {
        const module = try device.logical_device.createShaderModule(&.{
            .code_size = spirv.len,
            .p_code = @ptrCast(@alignCast(spirv.ptr)),
        }, null);
        errdefer device.logical_device.destroyShaderModule(module, null);

        return .{
            .module = module,
            .stage = stage,
            .entry = if (entry) |e| e else "main",
        };
    }
    pub fn deinit(self: @This(), device: *vlk_device) void {
        device.logical_device.destroyShaderModule(self.module, null);
    }

    pub fn stageInfo(self: @This()) vk.PipelineShaderStageCreateInfo {
        return .{
            .stage = self.stage,
            .module = self.module,
            .p_name = self.entry,
        };
    }
};

pub const vlk_pipeline = struct {
    pipeline: vk.Pipeline,
    layout: vk.PipelineLayout,
    descriptor_set_layout: vlk_descriptor_set_layout,

    pub fn instance(self: *@This(), sets: ?[]vk.DescriptorSet) vlk_pipeline_instance {
        var inst = vlk_pipeline_instance{
            .pipeline = self,
            .descriptor_sets = undefined,
            .descriptor_set_count = 0,
        };
        if (sets) |s| {
            @memcpy(inst.descriptor_sets[0..s.len], s);
            inst.descriptor_set_count = @intCast(s.len);
        }
        return inst;
    }

    pub fn deinit(self: @This(), device: vk.DeviceProxy) void {
        device.destroyPipeline(self.pipeline, null);
        device.destroyPipelineLayout(self.layout, null);
        self.descriptor_set_layout.deinit(device);
    }
};

pub const vlk_pipeline_instance = struct {
    pipeline: *vlk_pipeline,
    descriptor_sets: [4]vk.DescriptorSet,
    descriptor_set_count: u32,

    pub fn cmd_bind_compute(self: @This(), cmd: vk.CommandBufferProxy) void {
        cmd.bindPipeline(.compute, self.pipeline.pipeline);
    }

    pub fn cmd_bind_graphics(self: @This(), cmd: vk.CommandBufferProxy) void {
        cmd.bindPipeline(.graphics, self.pipeline.pipeline);
    }

    pub fn cmd_bind_descriptor_sets_compute(self: @This(), cmd: vk.CommandBufferProxy) void {
        cmd.bindDescriptorSets(
            .compute,
            self.pipeline.layout,
            0,
            @intCast(self.descriptor_set_count),
            &self.descriptor_sets,
            0,
            null,
        );
    }

    pub fn cmd_bind_descriptor_sets_graphics(self: @This(), cmd: vk.CommandBufferProxy) void {
        cmd.bindDescriptorSets(
            .graphics,
            self.pipeline.layout,
            0,
            @intCast(self.descriptor_set_count),
            self.descriptor_sets.ptr,
            0,
            null,
        );
    }
};

pub fn vlk_get_raytracing_properties(vki: *vlk_instance, device: *vlk_device) vk.PhysicalDeviceRayTracingPipelinePropertiesKHR {
    var rt_props = vk.PhysicalDeviceRayTracingPipelinePropertiesKHR{
        .shader_group_handle_size = 0,
        .max_ray_recursion_depth = 0,
        .max_shader_group_stride = 0,
        .shader_group_base_alignment = 0,
        .shader_group_handle_capture_replay_size = 0,
        .max_ray_dispatch_invocation_count = 0,
        .shader_group_handle_alignment = 0,
        .max_ray_hit_attribute_size = 0,
    };
    var props2 = vk.PhysicalDeviceProperties2{
        .properties = undefined,
        .p_next = &rt_props,
    };
    vki.instance.getPhysicalDeviceProperties2(device.physical_device, &props2);
    return rt_props;
}

pub const vlk_raytracing_pipeline = struct {
    pub const shader_binding_table = struct {
        buffer: vlk_vma_buffer,
        raygen_region: vk.StridedDeviceAddressRegionKHR,
        miss_region: vk.StridedDeviceAddressRegionKHR,
        hit_region: vk.StridedDeviceAddressRegionKHR,
        callable_region: vk.StridedDeviceAddressRegionKHR,

        pub fn init(
            allocator: std.mem.Allocator,
            vma: *vlk_vma,
            device: *vlk_device,
            pipeline: vk.Pipeline,
            rt_props: *const vk.PhysicalDeviceRayTracingPipelinePropertiesKHR,
            pipeline_info: vk.RayTracingPipelineCreateInfoKHR,
            gp: general_purpose,
        ) !shader_binding_table {

            //do not touch these for now
            const raygen_count = 1;
            const miss_count = 1;
            const hit_count = 1;
            const callable_count = 0;

            //get properties
            const handle_size = rt_props.shader_group_handle_size;
            const handle_alignment = rt_props.shader_group_handle_alignment;
            const base_alignment = rt_props.shader_group_base_alignment;

            //group count
            const group_count = pipeline_info.group_count;

            //handles
            const handle_list_size: usize = handle_size * group_count;
            const handles = try allocator.alloc(u8, handle_list_size);
            try device.logical_device.getRayTracingShaderGroupHandlesKHR(
                pipeline,
                0,
                group_count,
                handle_list_size,
                @ptrCast(handles.ptr),
            );

            //size
            const raygen_size = std.mem.alignForward(u64, raygen_count * handle_size, handle_alignment);
            const miss_size = std.mem.alignForward(u64, miss_count * handle_size, handle_alignment);
            const hit_size = std.mem.alignForward(u64, hit_count * handle_size, handle_alignment);
            const callable_size = std.mem.alignForward(u64, callable_count * handle_size, handle_alignment);

            const raygen_offset: u64 = 0;
            const miss_offset: u64 = std.mem.alignForward(u64, raygen_size, base_alignment);
            const hit_offset: u64 = std.mem.alignForward(u64, miss_offset + miss_size, base_alignment);
            const callable_offset: u64 = std.mem.alignForward(u64, hit_offset + hit_size, base_alignment);

            const buffer_size = callable_offset + callable_size;

            const region_buffer = try vlk_vma_buffer.init_aligned(
                vma,
                buffer_size,
                c_vma.VK_BUFFER_USAGE_2_SHADER_BINDING_TABLE_BIT_KHR |
                    c_vma.VK_BUFFER_USAGE_2_SHADER_DEVICE_ADDRESS_BIT |
                    c_vma.VK_BUFFER_USAGE_2_TRANSFER_DST_BIT,
                c_vma.VMA_MEMORY_USAGE_AUTO_PREFER_DEVICE,
                0,
                handle_alignment,
            );
            errdefer region_buffer.deinit(vma);

            const staging = try vlk_upload_buffer(vma, buffer_size);
            const mapping_ptr: [*]u8 = @ptrCast(try staging.map(vma));
            const mapping: []u8 = mapping_ptr[0..buffer_size];
            {
                //build staging buffer
                {
                    const handle_size_u: usize = @intCast(handle_size);
                    const ray_offset_u: usize = @intCast(raygen_offset);
                    const miss_offset_u: usize = @intCast(miss_offset);
                    const hit_offset_u: usize = @intCast(hit_offset);

                    {
                        // raygen (g0)
                        @memcpy(
                            mapping[ray_offset_u .. ray_offset_u + handle_size_u],
                            handles[0 * handle_size_u .. 1 * handle_size_u],
                        );

                        // miss (g1)
                        @memcpy(
                            mapping[miss_offset_u .. miss_offset_u + handle_size_u],
                            handles[1 * handle_size_u .. 2 * handle_size_u],
                        );

                        // hit (g2)
                        @memcpy(
                            mapping[hit_offset_u .. hit_offset_u + handle_size_u],
                            handles[2 * handle_size_u .. 3 * handle_size_u],
                        );
                        // callable shaders we do not support them
                        {}
                    }
                }

                //upload staging buffer
                {
                    try gp.begin();
                    staging.cmd_copy_to(&region_buffer, gp.cmd);
                    try gp.submit_and_wait(device.queue, device.logical_device);
                }
            }
            const region_buffer_address = region_buffer.address(device);
            // Build the strided address regions
            const raygen_region = vk.StridedDeviceAddressRegionKHR{
                .device_address = region_buffer_address + raygen_offset,
                .stride = std.mem.alignForward(u64, handle_size, base_alignment),
                .size = raygen_size,
            };

            const miss_region = vk.StridedDeviceAddressRegionKHR{
                .device_address = region_buffer_address + miss_offset,
                .stride = std.mem.alignForward(u64, handle_size, handle_alignment),
                .size = miss_size,
            };

            const hit_region = vk.StridedDeviceAddressRegionKHR{
                .device_address = region_buffer_address + hit_offset,
                .stride = std.mem.alignForward(u64, handle_size, handle_alignment),
                .size = hit_size,
            };

            const callable_region = vk.StridedDeviceAddressRegionKHR{
                .device_address = 0,
                .stride = 0,
                .size = 0,
            };

            return .{
                .buffer = region_buffer,
                .raygen_region = raygen_region,
                .miss_region = miss_region,
                .hit_region = hit_region,
                .callable_region = callable_region,
            };
        }
    };

    pipeline: vlk_pipeline,
    sbt: shader_binding_table,

    pub fn init(
        comptime PushConstant: type,
        allocator: std.mem.Allocator,
        rt_props: *const vk.PhysicalDeviceRayTracingPipelinePropertiesKHR,
        vma: *vlk_vma,
        device: *vlk_device,
        gp: general_purpose,
        shader_modules: []const vlk_shader_module,
    ) !vlk_raytracing_pipeline {

        // push constants
        const push_constants = [_]vk.PushConstantRange{
            .{
                .offset = 0,
                .size = @sizeOf(PushConstant),
                .stage_flags = .{
                    .raygen_bit_khr = true,
                    .miss_bit_khr = true,
                    .closest_hit_bit_khr = true,
                },
            },
        };
        //

        // Sets
        // set 0
        const set0_bindings = [_]vk.DescriptorSetLayoutBinding{
            .{
                .binding = 0,
                .descriptor_type = .acceleration_structure_khr,
                .descriptor_count = 1,
                .stage_flags = .{ .raygen_bit_khr = true },
            },
            .{
                .binding = 1,
                .descriptor_type = .storage_image,
                .descriptor_count = 1,
                .stage_flags = .{ .raygen_bit_khr = true },
            },
        };
        const set0_bindings_layout = try device.logical_device.createDescriptorSetLayout(&.{
            .binding_count = set0_bindings.len,
            .p_bindings = &set0_bindings,
        }, null);
        //

        const descriptor_sets = [_]vk.DescriptorSetLayout{
            set0_bindings_layout,
        };
        const pipeline_layout_info = vk.PipelineLayoutCreateInfo{
            .push_constant_range_count = push_constants.len,
            .p_push_constant_ranges = &push_constants,

            .set_layout_count = descriptor_sets.len,
            .p_set_layouts = &descriptor_sets,
        };
        //
        const layout = try device.logical_device.createPipelineLayout(&pipeline_layout_info, null);
        const stages = [_]vk.PipelineShaderStageCreateInfo{
            //raygen
            .{
                .p_name = "raygen_entry",
                .stage = .{ .raygen_bit_khr = true },
                .module = shader_modules[0].module,
            },
            //miss
            .{
                .p_name = "miss_entry",
                .stage = .{ .miss_bit_khr = true },
                .module = shader_modules[1].module,
            },
            //hit
            .{
                .p_name = "closest_hit_entry",
                .stage = .{ .closest_hit_bit_khr = true },
                .module = shader_modules[2].module,
            },
        };
        const groups = [_]vk.RayTracingShaderGroupCreateInfoKHR{
            //raygen
            vk.RayTracingShaderGroupCreateInfoKHR{
                .any_hit_shader = vk.SHADER_UNUSED_KHR,
                .intersection_shader = vk.SHADER_UNUSED_KHR,
                .closest_hit_shader = vk.SHADER_UNUSED_KHR,
                .type = .general_khr,
                .general_shader = 0,
            },
            //miss
            vk.RayTracingShaderGroupCreateInfoKHR{
                .any_hit_shader = vk.SHADER_UNUSED_KHR,
                .intersection_shader = vk.SHADER_UNUSED_KHR,
                .closest_hit_shader = vk.SHADER_UNUSED_KHR,
                .type = .general_khr,
                .general_shader = 1,
            },
            //hit
            vk.RayTracingShaderGroupCreateInfoKHR{
                .type = .triangles_hit_group_khr,
                .any_hit_shader = vk.SHADER_UNUSED_KHR,
                .intersection_shader = vk.SHADER_UNUSED_KHR,
                .general_shader = vk.SHADER_UNUSED_KHR,
                .closest_hit_shader = 2,
            },
        };
        //

        const pipeline_info = [_]vk.RayTracingPipelineCreateInfoKHR{
            .{
                .base_pipeline_handle = .null_handle,
                .base_pipeline_index = 0,
                .stage_count = stages.len,
                .p_stages = &stages,
                .group_count = groups.len,
                .p_groups = &groups,
                .max_pipeline_ray_recursion_depth = rt_props.max_ray_recursion_depth,
                .layout = layout,
            },
        };

        var pipelines = [_]vk.Pipeline{.null_handle};
        _ = try device.logical_device.createRayTracingPipelinesKHR(
            .null_handle,
            .null_handle,

            pipeline_info.len,
            &pipeline_info,

            null,
            &pipelines,
        );

        const sbt = try shader_binding_table.init(
            allocator,
            vma,
            device,
            pipelines[0],
            rt_props,
            pipeline_info[0],
            gp,
        );

        return .{
            .pipeline = .{
                .pipeline = pipelines[0],
                .descriptor_set_layout = .{
                    .handle = set0_bindings_layout,
                },
                .layout = layout,
            },
            .sbt = sbt,
        };
    }
};

pub const gpu_mesh = struct {
    vertex_buffer: vlk_vma_buffer,
    index_buffer: vlk_vma_buffer,

    normal_buffer: vlk_vma_buffer,
    normal_index_buffer: vlk_vma_buffer,

    vertex_count: u32,
    index_count: u32,

    pub fn triangle_count(self: @This()) u32 {
        return self.index_count / 3;
    }

    pub fn init_from_mesh(
        allocator: std.mem.Allocator,
        staging_buffers: *std.ArrayList(vlk_vma_buffer),
        vma: *vlk_vma,
        cmd: vk.CommandBufferProxy,
        m: *const mesh.local_mesh,
    ) !gpu_mesh {
        const vertex_bytes = std.mem.sliceAsBytes(m.verts);
        const index_bytes = std.mem.sliceAsBytes(m.indices);

        var vertex_buffer = try vlk_vma_buffer.init(
            vma,
            vertex_bytes.len,
            c_vma.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT |
                c_vma.VK_BUFFER_USAGE_2_SHADER_DEVICE_ADDRESS_BIT |
                c_vma.VK_BUFFER_USAGE_2_TRANSFER_DST_BIT |
                c_vma.VK_BUFFER_USAGE_ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_BIT_KHR,
            c_vma.VMA_MEMORY_USAGE_AUTO,
            0,
        );
        try staging_buffers.append(allocator, try vlk_upload_buffer_with_data(vma, vertex_bytes));
        staging_buffers.getLast().cmd_copy_to(&vertex_buffer, cmd);

        var index_buffer = try vlk_vma_buffer.init(
            vma,
            index_bytes.len,
            c_vma.VK_BUFFER_USAGE_INDEX_BUFFER_BIT |
                c_vma.VK_BUFFER_USAGE_TRANSFER_DST_BIT |
                c_vma.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT |
                c_vma.VK_BUFFER_USAGE_ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_BIT_KHR,
            c_vma.VMA_MEMORY_USAGE_AUTO,
            0,
        );
        try staging_buffers.append(allocator, try vlk_upload_buffer_with_data(vma, index_bytes));
        staging_buffers.getLast().cmd_copy_to(&index_buffer, cmd);

        const normal_bytes = std.mem.sliceAsBytes(m.normals);
        const normal_buffer = try vlk_vma_buffer.init(
            vma,
            normal_bytes.len,
            c_vma.VK_BUFFER_USAGE_TRANSFER_DST_BIT |
                c_vma.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT |
                c_vma.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
            c_vma.VMA_MEMORY_USAGE_AUTO,
            0,
        );
        try staging_buffers.append(allocator, try vlk_upload_buffer_with_data(vma, normal_bytes));
        staging_buffers.getLast().cmd_copy_to(&normal_buffer, cmd);

        const normal_index_bytes = std.mem.sliceAsBytes(m.normal_indices);
        const normal_index_buffer = try vlk_vma_buffer.init(
            vma,
            normal_index_bytes.len,
            c_vma.VK_BUFFER_USAGE_TRANSFER_DST_BIT |
                c_vma.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT |
                c_vma.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
            c_vma.VMA_MEMORY_USAGE_AUTO,
            0,
        );
        try staging_buffers.append(allocator, try vlk_upload_buffer_with_data(vma, normal_index_bytes));
        staging_buffers.getLast().cmd_copy_to(&normal_index_buffer, cmd);

        return .{
            .vertex_buffer = vertex_buffer,
            .index_buffer = index_buffer,
            .normal_buffer = normal_buffer,
            .normal_index_buffer = normal_index_buffer,
            .vertex_count = @intCast(m.verts.len),
            .index_count = @intCast(m.indices.len),
        };
    }

    pub fn deinit(self: @This(), vma: *vlk_vma) void {
        self.vertex_buffer.deinit(vma);
        self.index_buffer.deinit(vma);
    }
};

pub const blas_geometry_range = struct {
    begin: u32,
    len: u32,
};

pub const raytracing_acceleration_structure = struct {
    handle: vk.AccelerationStructureKHR,
    buffer: vlk_vma_buffer,

    pub fn address(self: @This(), device: *vlk_device) vk.DeviceAddress {
        const info = vk.AccelerationStructureDeviceAddressInfoKHR{
            .acceleration_structure = self.handle,
        };
        return device.logical_device.getAccelerationStructureDeviceAddressKHR(&info);
    }

    pub fn init(
        allocator: std.mem.Allocator,
        vma: *vlk_vma,
        device: *vlk_device,
        as_type: vk.AccelerationStructureTypeKHR,
        geometry: []const vk.AccelerationStructureGeometryKHR,
        geometry_range: []const vk.AccelerationStructureBuildRangeInfoKHR,
        flags: vk.BuildAccelerationStructureFlagsKHR,
        gp: general_purpose,
    ) !raytracing_acceleration_structure {
        var primitive_counts = try std.ArrayList(u32).initCapacity(allocator, geometry_range.len);
        defer primitive_counts.deinit(allocator);

        var build_info = vk.AccelerationStructureBuildGeometryInfoKHR{
            .type = as_type,
            .flags = flags,
            .mode = .build_khr,
            .geometry_count = @intCast(geometry.len),
            .p_geometries = geometry.ptr,
            .scratch_data = .{ .device_address = 0 },
        };

        for (geometry_range) |range| {
            try primitive_counts.append(allocator, range.primitive_count);
        }

        var build_size = vk.AccelerationStructureBuildSizesInfoKHR{
            .acceleration_structure_size = 0,
            .build_scratch_size = 0,
            .update_scratch_size = 0,
        };
        device.logical_device.getAccelerationStructureBuildSizesKHR(
            .device_khr,
            &build_info,
            primitive_counts.items.ptr,
            &build_size,
        );

        const as_buffer = try vlk_vma_buffer.init(
            vma,
            build_size.acceleration_structure_size,
            c_vma.VK_BUFFER_USAGE_ACCELERATION_STRUCTURE_STORAGE_BIT_KHR | c_vma.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
            c_vma.VMA_MEMORY_USAGE_AUTO,
            0,
        );

        const as_create_info = vk.AccelerationStructureCreateInfoKHR{
            .type = as_type,
            .buffer = as_buffer.handle,
            .size = build_size.acceleration_structure_size,
            .offset = 0,
            .create_flags = .{},
            .device_address = 0,
        };

        const scratch = try vlk_vma_buffer.init_aligned(
            vma,
            build_size.build_scratch_size,
            c_vma.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | c_vma.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
            c_vma.VMA_MEMORY_USAGE_AUTO_PREFER_DEVICE,
            0,
            256,
        );
        defer scratch.deinit(vma);

        const as = try device.logical_device.createAccelerationStructureKHR(&as_create_info, null);

        build_info.dst_acceleration_structure = as;
        build_info.scratch_data = .{
            .device_address = scratch.address(device),
        };

        {
            const range_ptr = [_][*]const vk.AccelerationStructureBuildRangeInfoKHR{geometry_range.ptr};

            try gp.begin();
            gp.cmd.buildAccelerationStructuresKHR(1, @ptrCast(&build_info), &range_ptr);
            try gp.submit_and_wait(device.queue, device.logical_device);
        }

        return .{
            .handle = as,
            .buffer = as_buffer,
        };
    }

    // pub fn init_blas2(
    //     allocator: std.mem.Allocator,
    //     vma: *vlk_vma,
    //     device: *vlk_device,
    //     geometry: []raytracing_acceleration_structure,
    //     grange: blas_geometry_range,
    //     flags: vk.BuildAccelerationStructureFlagsKHR,
    //     gp: general_purpose,
    // ) !raytracing_acceleration_structure {
    //     return init(allocator, vma, device, .bottom_level_khr, geometry, geometry_range, flags, gp);
    // }
    pub fn init_blas(
        allocator: std.mem.Allocator,
        vma: *vlk_vma,
        device: *vlk_device,
        geometry: []const vk.AccelerationStructureGeometryKHR,
        geometry_range: []const vk.AccelerationStructureBuildRangeInfoKHR,
        flags: vk.BuildAccelerationStructureFlagsKHR,
        gp: general_purpose,
    ) !raytracing_acceleration_structure {
        return init(allocator, vma, device, .bottom_level_khr, geometry, geometry_range, flags, gp);
    }

    pub fn init_tlas(
        allocator: std.mem.Allocator,
        vma: *vlk_vma,
        device: *vlk_device,
        children: []raytracing_acceleration_structure,
        transforms: []vk.TransformMatrixKHR,
        flags: vk.BuildAccelerationStructureFlagsKHR,
        gp: general_purpose,
    ) !raytracing_acceleration_structure {
        // build instance array
        var instances = try std.ArrayList(vk.AccelerationStructureInstanceKHR)
            .initCapacity(allocator, children.len);
        defer instances.deinit(allocator);

        for (children, 0..) |blas, i| {
            const bb = vk.GeometryInstanceFlagsKHR{
                .triangle_facing_cull_disable_bit_khr = true,
            };
            try instances.append(allocator, .{
                .transform = transforms[i],
                .instance_custom_index_and_mask = .{
                    .instance_custom_index = @intCast(i),
                    .mask = 0xFF,
                },
                .instance_shader_binding_table_record_offset_and_flags = .{
                    .instance_shader_binding_table_record_offset = 0,
                    .flags = @intCast(bb.toInt()),
                },
                .acceleration_structure_reference = blas.address(device),
            });
        }

        // upload instance buffer
        const instance_buf_size = instances.items.len * @sizeOf(vk.AccelerationStructureInstanceKHR);
        const instance_buf = try vlk_vma_buffer.init(
            vma,
            instance_buf_size,
            c_vma.VK_BUFFER_USAGE_ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_BIT_KHR |
                c_vma.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT |
                c_vma.VK_BUFFER_USAGE_TRANSFER_DST_BIT,
            c_vma.VMA_MEMORY_USAGE_AUTO_PREFER_DEVICE,
            0,
        );
        defer instance_buf.deinit(vma);

        {
            const staging = try vlk_upload_buffer_with_data(vma, std.mem.sliceAsBytes(instances.items));
            defer staging.deinit(vma);
            try gp.begin();
            staging.cmd_copy_to(&instance_buf, gp.cmd);
            try gp.submit_and_wait(device.queue, device.logical_device);
        }

        var geometry = vk.AccelerationStructureGeometryKHR{
            .geometry_type = .instances_khr,
            .geometry = .{
                .instances = .{
                    .array_of_pointers = vk.Bool32.false,
                    .data = .{ .device_address = instance_buf.address(device) },
                },
            },
            .flags = .{ .opaque_bit_khr = true },
        };

        var range = vk.AccelerationStructureBuildRangeInfoKHR{
            .primitive_count = @intCast(instances.items.len),
            .primitive_offset = 0,
            .first_vertex = 0,
            .transform_offset = 0,
        };

        return init(
            allocator,
            vma,
            device,
            .top_level_khr,
            @ptrCast(&geometry),
            @ptrCast(&range),
            flags,
            gp,
        );
    }
};

pub const raytracing_geometry_data = struct {
    geometry: vk.AccelerationStructureGeometryKHR,
    range: vk.AccelerationStructureBuildRangeInfoKHR,
    index: u32,

    pub fn init(
        meshes: []gpu_mesh,
        index: u32,
        device: *vlk_device,
    ) raytracing_geometry_data {
        const m = &meshes[index];
        const tri_count: u32 = m.index_count / 3;

        const triangles = vk.AccelerationStructureGeometryTrianglesDataKHR{
            .vertex_format = .r32g32b32_sfloat,
            .vertex_data = .{ .device_address = m.vertex_buffer.address(device) },
            .vertex_stride = @sizeOf(f32) * 3,
            .max_vertex = m.vertex_count - 1,
            .index_type = .uint32,
            .index_data = .{ .device_address = m.index_buffer.address(device) },
            .transform_data = .{ .device_address = 0 },
        };

        return .{
            .geometry = vk.AccelerationStructureGeometryKHR{
                .geometry_type = .triangles_khr,
                .geometry = .{ .triangles = triangles },
                .flags = .{ .opaque_bit_khr = true },
            },
            .range = vk.AccelerationStructureBuildRangeInfoKHR{
                .primitive_count = tri_count,
                .primitive_offset = 0,
                .first_vertex = 0,
                .transform_offset = 0,
            },
            .index = index,
        };
    }
};

pub const vlk_compute_pipeline = struct {
    shader_module: vk.ShaderModule,
    pipeline: vlk_pipeline,

    pub fn init(
        device: *vlk_device,
        spirv: []const u8,
        bindings: []const vk.DescriptorSetLayoutBinding,
        binding_flags: []const vk.DescriptorBindingFlags,
        pcs: []const vlk_pc_layout,
    ) !vlk_compute_pipeline {
        const shader_module = try device.logical_device.createShaderModule(&.{
            .code_size = spirv.len,
            .p_code = @ptrCast(@alignCast(spirv.ptr)),
        }, null);
        errdefer device.logical_device.destroyShaderModule(shader_module, null);

        const shader_pipeline_info = vk.PipelineShaderStageCreateInfo{
            .stage = .{ .compute_bit = true },
            .module = shader_module,
            .p_name = "main",
        };

        const descriptor_set_layout = try vlk_descriptor_set_layout.init(device, bindings, binding_flags);
        errdefer descriptor_set_layout.deinit(device.logical_device);

        var ranges: [8]vk.PushConstantRange = undefined;
        for (pcs, 0..) |pc, i| {
            ranges[i] = pc.range;
        }

        const pipeline_layout = try device.logical_device.createPipelineLayout(&.{
            .set_layout_count = 1,
            .p_set_layouts = @ptrCast(&descriptor_set_layout.handle),
            .push_constant_range_count = @intCast(pcs.len),
            .p_push_constant_ranges = if (pcs.len > 0) &ranges else null,
        }, null);
        errdefer device.logical_device.destroyPipelineLayout(pipeline_layout, null);

        var pipeline: vk.Pipeline = undefined;
        _ = try device.logical_device.createComputePipelines(
            .null_handle,
            1,
            &[1]vk.ComputePipelineCreateInfo{.{
                .stage = shader_pipeline_info,
                .layout = pipeline_layout,
                .base_pipeline_handle = .null_handle,
                .base_pipeline_index = -1,
            }},
            null,
            @ptrCast(&pipeline),
        );

        return .{
            .shader_module = shader_module,
            .pipeline = .{
                .pipeline = pipeline,
                .layout = pipeline_layout,
                .descriptor_set_layout = descriptor_set_layout,
            },
        };
    }

    pub fn deinit(self: @This(), device: vk.DeviceProxy) void {
        self.pipeline.deinit(device);
        device.destroyShaderModule(self.shader_module, null);
    }
};

pub const vlk_fence = struct {
    handle: vk.Fence,

    pub fn init(device: *vlk_device, flags: vk.FenceCreateFlags) !vlk_fence {
        const handle = try device.logical_device.createFence(&.{ .flags = flags }, null);
        return .{ .handle = handle };
    }

    pub fn wait_and_reset(self: @This(), device: vk.DeviceProxy) !void {
        _ = try device.waitForFences(1, @ptrCast(&self.handle), vk.Bool32.true, std.math.maxInt(u64));
        try device.resetFences(1, @ptrCast(&self.handle));
    }

    pub fn deinit(self: @This(), device: vk.DeviceProxy) void {
        device.destroyFence(self.handle, null);
    }
};

fn create_vma_image(
    vma: *vlk_vma,
    format: vk.Format,
    extent: vk.Extent3D,
    mip_levels: u32,
    array_layer_count: u32,
    usage: vk.ImageUsageFlags,
) !struct { allocation: c_vma.VmaAllocation, image: vk.Image } {
    const vma_image_info = c_vma.VkImageCreateInfo{
        .sType = c_vma.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .imageType = c_vma.VK_IMAGE_TYPE_2D,
        .format = @intCast(@intFromEnum(format)),
        .extent = .{
            .width = extent.width,
            .height = extent.height,
            .depth = extent.depth,
        },
        .mipLevels = mip_levels,
        .arrayLayers = array_layer_count,
        .samples = c_vma.VK_SAMPLE_COUNT_1_BIT,
        .tiling = c_vma.VK_IMAGE_TILING_OPTIMAL,
        .usage = @bitCast(usage),
        .sharingMode = c_vma.VK_SHARING_MODE_EXCLUSIVE,
        .initialLayout = c_vma.VK_IMAGE_LAYOUT_UNDEFINED,
    };

    const alloc_info = c_vma.VmaAllocationCreateInfo{
        .usage = c_vma.VMA_MEMORY_USAGE_AUTO,
    };

    var vk_image: c_vma.VkImage = undefined;
    var allocation: c_vma.VmaAllocation = undefined;
    const result = c_vma.vmaCreateImage(
        vma.allocator,
        &vma_image_info,
        &alloc_info,
        &vk_image,
        &allocation,
        null,
    );

    if (result != c_vma.VK_SUCCESS) {
        return error.ImageCreationFailed;
    }

    // return the Vulkan image handle
    return .{ .allocation = allocation, .image = @as(vk.Image, @enumFromInt(@intFromPtr(vk_image))) };
}
fn create_image_view(
    device: *vlk_device,
    image: vk.Image,
    format: vk.Format,
    view_type: vk.ImageViewType,
    mip_levels: u32,
    array_layers: u32,
    aspect_flags: vk.ImageAspectFlags,
) !vk.ImageView {
    const view_info: vk.ImageViewCreateInfo = .{
        .components = vk.ComponentMapping{
            .r = .identity,
            .g = .identity,
            .b = .identity,
            .a = .identity,
        },
        .view_type = view_type,
        .image = image,
        .format = format,
        .subresource_range = .{
            .base_mip_level = 0,
            .level_count = mip_levels,
            .base_array_layer = 0,
            .layer_count = array_layers,
            .aspect_mask = aspect_flags,
        },
    };

    return try device.logical_device.createImageView(&view_info, null);
}
pub const vlk_image = struct {
    handle: vk.Image,
    view: vk.ImageView,
    allocation: c_vma.VmaAllocation,
    extent: vk.Extent3D,
    format: vk.Format,
    mip_levels: u32,

    pub fn init(
        vma: *vlk_vma,
        device: *vlk_device,
        format: vk.Format,
        usage_flags: vk.ImageUsageFlags,
        aspect_flags: vk.ImageAspectFlags,
        extent: vk.Extent3D,
        mipmapped: bool,
    ) !vlk_image {
        const mip_levels =
            if (mipmapped)
                std.math.log2_int(u32, @max(extent.width, extent.height)) + 1
            else
                1;

        const array_layer_count = 1;

        const handle = try create_vma_image(
            vma,
            format,
            extent,
            mip_levels,
            array_layer_count,
            usage_flags,
        );
        const view = try create_image_view(
            device,
            handle.image, // vk.Image from your VMA creation
            format, // vk.Format
            vk.ImageViewType.@"2d",
            mip_levels,
            array_layer_count,
            aspect_flags,
        );

        return .{
            .handle = handle.image,
            .view = view,
            .allocation = handle.allocation,
            .extent = extent,
            .format = format,
            .mip_levels = mip_levels,
        };
    }

    pub fn deinit(self: @This(), pvma: ?*vlk_vma, device: *vlk_device) void {
        device.logical_device.destroyImageView(self.view, null);
        if (pvma) |vma| {
            c_vma.vmaDestroyImage(
                vma.allocator,
                @ptrFromInt(@intFromEnum(self.handle)),
                self.allocation,
            );
        }
    }
    pub fn cmd_transition(
        self: @This(),
        cmd: vk.CommandBufferProxy,
        src_stage: vk.PipelineStageFlags2,
        dst_stage: vk.PipelineStageFlags2,
        src_access: vk.AccessFlags2,
        dst_access: vk.AccessFlags2,
        old_layout: vk.ImageLayout,
        new_layout: vk.ImageLayout,
        subresource_range: ?vk.ImageSubresourceRange,
    ) void {
        const barrier = vk.ImageMemoryBarrier2{
            .src_stage_mask = src_stage,
            .dst_stage_mask = dst_stage,
            .src_access_mask = src_access,
            .dst_access_mask = dst_access,
            .old_layout = old_layout,
            .new_layout = new_layout,
            .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .image = self.handle,
            .subresource_range = if (subresource_range) |v| v else self.full_subresource_range(),
        };
        const barriers = [_]vk.ImageMemoryBarrier2{barrier};
        const dep_info = vk.DependencyInfo{
            .image_memory_barrier_count = barriers.len,
            .p_image_memory_barriers = &barriers,
        };
        cmd.pipelineBarrier2(&dep_info);
    }

    pub fn aspect_mask(self: @This()) vk.ImageAspectFlags {
        return switch (self.format) {
            .d32_sfloat,
            .d16_unorm,
            => .{ .depth_bit = true },

            .d32_sfloat_s8_uint,
            .d24_unorm_s8_uint,
            .d16_unorm_s8_uint,
            => .{ .depth_bit = true, .stencil_bit = true },
            else => .{ .color_bit = true },
        };
    }

    pub fn full_subresource_range(self: @This()) vk.ImageSubresourceRange {
        return .{
            .aspect_mask = self.aspect_mask(),
            .base_mip_level = 0,
            .level_count = self.mip_levels,
            .base_array_layer = 0,
            .layer_count = 1,
        };
    }

    pub fn cmd_copy_from_buffer(
        self: @This(),
        cmd: vk.CommandBufferProxy,
        src: *const vlk_vma_buffer,
        mip_level: u32,
        base_array_layer: u32,
        layer_count: u32,
    ) void {
        const copy_region = vk.BufferImageCopy{
            .buffer_offset = 0,
            .buffer_row_length = 0,
            .buffer_image_height = 0,
            .image_subresource = .{
                .aspect_mask = .{ .color_bit = true },
                .mip_level = mip_level,
                .base_array_layer = base_array_layer,
                .layer_count = layer_count,
            },
            .image_offset = .{ .x = 0, .y = 0, .z = 0 },
            .image_extent = self.extent,
        };
        const copy_regions = [_]vk.BufferImageCopy{copy_region};
        cmd.copyBufferToImage(src.handle, self.handle, .transfer_dst_optimal, copy_regions.len, &copy_regions);
    }
};

pub fn write_exr_rgba(
    allocator: std.mem.Allocator,
    pixels: [*][4]f32,
    width: usize,
    height: usize,
    path: [*:0]const u8,
) !void {
    const count = width * height;
    const mem = try allocator.alloc(f32, count * 4);

    const r = mem[0..count];
    const g = mem[count .. count * 2];
    const b = mem[count * 2 .. count * 3];
    const a = mem[count * 3 .. count * 4];

    defer allocator.free(mem);

    for (0..count) |i| {
        r[i] = pixels[i][0];
        g[i] = pixels[i][1];
        b[i] = pixels[i][2];
        a[i] = pixels[i][3];
    }

    var header = tinyexr.EXRHeader{};
    tinyexr.InitEXRHeader(&header);

    var image = tinyexr.EXRImage{};
    tinyexr.InitEXRImage(&image);

    image.num_channels = 4;
    image.width = @intCast(width);
    image.height = @intCast(height);

    var image_ptr = [4][*]f32{ a.ptr, b.ptr, g.ptr, r.ptr };
    image.images = @ptrCast(&image_ptr);

    header.num_channels = 4;
    var channels = [4]tinyexr.EXRChannelInfo{
        std.mem.zeroes(tinyexr.EXRChannelInfo),
        std.mem.zeroes(tinyexr.EXRChannelInfo),
        std.mem.zeroes(tinyexr.EXRChannelInfo),
        std.mem.zeroes(tinyexr.EXRChannelInfo),
    };

    @memcpy(channels[0].name[0..2], "A\x00");
    @memcpy(channels[1].name[0..2], "B\x00");
    @memcpy(channels[2].name[0..2], "G\x00");
    @memcpy(channels[3].name[0..2], "R\x00");

    header.channels = &channels;

    var pixel_types = [4]c_int{
        tinyexr.TINYEXR_PIXELTYPE_FLOAT,
        tinyexr.TINYEXR_PIXELTYPE_FLOAT,
        tinyexr.TINYEXR_PIXELTYPE_FLOAT,
        tinyexr.TINYEXR_PIXELTYPE_FLOAT,
    };
    header.pixel_types = &pixel_types;
    header.requested_pixel_types = &pixel_types;

    var err: [*c]const u8 = null;
    const ret = tinyexr.SaveEXRImageToFile(&image, &header, path, &err);
    if (ret != tinyexr.TINYEXR_SUCCESS) {
        std.debug.print("tinyexr error: {s}\n", .{err});
        tinyexr.FreeEXRErrorMessage(err);
        return error.EXRWriteFailed;
    }
}

pub fn readfile_alloc(allocator: std.mem.Allocator, file: std.fs.File) ![]const u8 {
    var file_buffer: [1024]u8 = undefined;
    var reader = file.reader(&file_buffer);

    const stat = try file.stat();
    const size = stat.size;
    const contents = try reader.interface.readAlloc(allocator, size);

    return contents;
}

fn vlk_staging_buffer(vma: *vlk_vma, size: vk.DeviceSize, readback: bool) !vlk_vma_buffer {
    const usage = if (readback)
        c_vma.VK_BUFFER_USAGE_TRANSFER_DST_BIT
    else
        c_vma.VK_BUFFER_USAGE_TRANSFER_SRC_BIT;

    const host_flag = if (readback)
        c_vma.VMA_ALLOCATION_CREATE_HOST_ACCESS_RANDOM_BIT
    else
        c_vma.VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT;

    return vlk_vma_buffer.init(
        vma,
        size,
        @intCast(usage),
        c_vma.VMA_MEMORY_USAGE_AUTO,
        @intCast(host_flag | c_vma.VMA_ALLOCATION_CREATE_MAPPED_BIT),
    );
}

pub fn vlk_upload_buffer(vma: *vlk_vma, size: vk.DeviceSize) !vlk_vma_buffer {
    return vlk_staging_buffer(vma, size, false);
}

pub fn vlk_upload_buffer_with_data(vma: *vlk_vma, data: []const u8) !vlk_vma_buffer {
    const staging = try vlk_upload_buffer(vma, @intCast(data.len));
    try staging.map_memcpy(vma, data, 0);
    return staging;
}

pub fn vlk_readback_buffer(vma_alloc: *vlk_vma, size: vk.DeviceSize) !vlk_vma_buffer {
    return vlk_staging_buffer(vma_alloc, size, true);
}

pub fn vlk_cmd_begin_one(cmd: vk.CommandBufferProxy) !void {
    try cmd.beginCommandBuffer(&.{
        .flags = .{ .one_time_submit_bit = true },
    });
}

pub const general_purpose = struct {
    fence: vlk_fence,
    cmd: vk.CommandBufferProxy,

    pub fn init(device: *vlk_device, cmd: vk.CommandBufferProxy) !general_purpose {
        const fence = try vlk_fence.init(device, .{});
        return .{ .fence = fence, .cmd = cmd };
    }

    pub fn begin(self: @This()) !void {
        // try self.fence.wait_and_reset(device.logical_device);
        try vlk_cmd_begin_one(self.cmd);
    }

    pub fn submit(self: @This(), queue: vk.QueueProxy) !void {
        try self.cmd.endCommandBuffer();
        try queue.submit(1, &[1]vk.SubmitInfo{.{
            .command_buffer_count = 1,
            .p_command_buffers = @ptrCast(&self.cmd.handle),
        }}, self.fence.handle);
    }

    pub fn submit_and_wait(self: @This(), queue: vk.QueueProxy, device: vk.DeviceProxy) !void {
        try self.submit(queue);
        try self.fence.wait_and_reset(device);
    }

    pub fn deinit(self: @This(), device: *vlk_device) void {
        self.fence.deinit(device.logical_device);
    }
};

pub fn submit(
    queue: vk.QueueProxy,
    info: []const vk.SubmitInfo,
    fence: vk.Fence,
) !void {
    try queue.submit(@intCast(info.len), info.ptr, fence);
}

pub const vlk_fence_pool = struct {
    available: std.ArrayList(vk.Fence),
    in_use: std.ArrayList(vk.Fence),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, device: *vlk_device, initial_count: usize) !vlk_fence_pool {
        var pool = vlk_fence_pool{
            .available = try std.ArrayList(vk.Fence).initCapacity(allocator, initial_count),
            .in_use = try std.ArrayList(vk.Fence).initCapacity(allocator, initial_count),
            .allocator = allocator,
        };
        for (0..initial_count) |_| {
            const fence = try device.logical_device.createFence(&.{}, null);
            try pool.available.append(allocator, fence);
        }
        return pool;
    }

    pub fn acquire(self: *@This(), device: *vlk_device) !vk.Fence {
        const fence = if (self.available.items.len > 0)
            self.available.pop()
        else blk: {
            const f = try vlk_fence.init(device, .{ .signaled_bit = true });
            break :blk f.handle;
        };
        try self.in_use.append(self.allocator, fence.?);
        return fence.?;
    }

    // call each frame to reclaim signaled fences
    pub fn reclaim(self: *@This(), device: *vlk_device) !void {
        var i: usize = 0;
        while (i < self.in_use.items.len) {
            const fence = self.in_use.items[i];
            const status = device.logical_device.getFenceStatus(fence) catch {
                i += 1;
                continue;
            };
            if (status == .success) {
                // signaled — reset and return to pool
                try device.logical_device.resetFences(1, @ptrCast(&fence));
                _ = self.in_use.swapRemove(i);
                try self.available.append(self.allocator, fence);
            } else {
                i += 1;
            }
        }
    }

    pub fn deinit(self: *@This(), device: *vlk_device) void {
        for (self.available.items) |f| device.logical_device.destroyFence(f, null);
        for (self.in_use.items) |f| device.logical_device.destroyFence(f, null);
        self.available.deinit(self.allocator);
        self.in_use.deinit(self.allocator);
    }
};

pub const TileElm = struct {
    pos: u32,
    stride: u32,
    len: u32,
};

pub fn next_tile(t: u32, desired_stride: u32, max: u32) TileElm {
    const stride: u32 = blk: {
        const diff = @as(i32, @intCast(max)) - @as(i32, @intCast(t));
        if (diff > 0) {
            break :blk @min(@as(u32, @intCast(diff)), desired_stride);
        } else {
            return .{ .pos = 0, .stride = desired_stride, .len = desired_stride };
        }
    };
    const pos = t + stride;
    const len: u32 = blk: {
        const next_pos = pos + desired_stride;
        if (next_pos > max) {
            break :blk max - pos;
        }
        break :blk desired_stride;
    };
    return .{ .pos = pos, .stride = stride, .len = len };
}
