const std = @import("std");
const builtin = @import("builtin");
const mth = @import("mth");
pub const c_libs = @import("c_libs");
pub const obj = @import("obj");
pub const sdl = @import("sdl3");
pub const vk = @import("vulkan");

pub const handle_lib = @import("handle.zig");
pub const read = @import("readfile.zig");
pub const exrimg = @import("exrimg.zig");
pub const local_geometry = @import("mesh.zig");

pub const HandleType = handle_lib.HandleType;
pub const readfile_alloc = read.readfile_alloc;
pub const readfile_allocZ = read.readfile_allocZ;

pub fn to_enum(comptime T: type, in: anytype) T {
    const int_val = @intFromPtr(in);
    return @as(T, @enumFromInt(int_val));
}

pub fn to_ptr(comptime T: type, in: anytype) T {
    return @ptrFromInt(@intFromEnum(in));
}

const required_device_extensions: []const [*:0]const u8 = &.{
    vk.extensions.khr_swapchain.name,
    vk.extensions.khr_ray_tracing_pipeline.name,
    vk.extensions.khr_acceleration_structure.name,
    vk.extensions.khr_deferred_host_operations.name,
    // vk.extensions.ext_mesh_shader.name,
    vk.extensions.khr_compute_shader_derivatives.name,
};
const required_features = .{
    vk.PhysicalDeviceAccelerationStructureFeaturesKHR{
        .acceleration_structure = vk.Bool32.true,
        .descriptor_binding_acceleration_structure_update_after_bind = vk.Bool32.true,
    },
    vk.PhysicalDeviceRayTracingPipelineFeaturesKHR{
        .ray_tracing_pipeline = vk.Bool32.true,
    },
    // vk.PhysicalDeviceComputeShaderDerivativesFeaturesKHR{
    //     .compute_derivative_group_quads = vk.Bool32.true,
    //     .compute_derivative_group_linear = vk.Bool32.true,
    // },
    vk.PhysicalDeviceBufferDeviceAddressFeatures{
        .buffer_device_address = vk.Bool32.true,
    },
    // vk.PhysicalDeviceDynamicRenderingFeatures{
    //     .dynamic_rendering = vk.Bool32.true,
    // },
    vk.PhysicalDeviceSynchronization2Features{
        .synchronization_2 = vk.Bool32.true,
    },

    vk.PhysicalDeviceShaderFloat16Int8Features{
        .shader_float_16 = vk.Bool32.true,
        .shader_int_8 = vk.Bool32.true,
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
    vk.PhysicalDeviceScalarBlockLayoutFeatures{
        .scalar_block_layout = vk.Bool32.true,
    },
    vk.PhysicalDeviceComputeShaderDerivativesFeaturesKHR{
        .s_type = .physical_device_compute_shader_derivatives_features_khr,
        .compute_derivative_group_quads = vk.Bool32.true,
        .compute_derivative_group_linear = vk.Bool32.true,
    },
};

// pub const max_frames_in_flight = 5;

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
        const enable_validation = builtin.mode == .Debug;

        const validation_feature_enables = [_]vk.ValidationFeatureEnableEXT{
            .best_practices_ext,
            .synchronization_validation_ext,
            // .gpu_assisted_ext,
            // .gpu_assisted_reserve_binding_slot_ext,
        };
        const validation_features = vk.ValidationFeaturesEXT{
            .enabled_validation_feature_count = validation_feature_enables.len,
            .p_enabled_validation_features = &validation_feature_enables,
            .disabled_validation_feature_count = 0,
            .p_disabled_validation_features = null,
        };

        const layers = if (enable_validation)
            &[_][*:0]const u8{"VK_LAYER_KHRONOS_validation"}
        else
            &[_][*:0]const u8{};

        const create_info: vk.InstanceCreateInfo = .{
            .p_application_info = &app_info,

            .enabled_extension_count = @intCast(extensions.len),
            .pp_enabled_extension_names = extensions.ptr,

            .enabled_layer_count = @intCast(layers.len),
            .pp_enabled_layer_names = layers.ptr,

            .p_next = if (enable_validation) &validation_features else null,
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
        defer allocator.free(physical_devices);
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

        const queue = try vlk_queue.init2(logical_device, queue_index, 0);

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
    proxy: vk.QueueProxy,
    family_index: u32,
    queue_index: u32,

    pub fn init(device: vk.DeviceProxy, family_index: u32, queue_index: u32) !vlk_queue {
        const queue = device.getDeviceQueue(family_index, queue_index);
        const proxy = vk.QueueProxy.init(queue, device.wrapper);
        return .{
            .proxy = proxy,
            .family_index = family_index,
            .queue_index = queue_index,
        };
    }

    pub fn init2(device: vk.DeviceProxy, family_index: u32, index: u32) !vk.QueueProxy {
        const queue = device.getDeviceQueue(family_index, index);
        const proxy = vk.QueueProxy.init(queue, device.wrapper);
        return proxy;
    }

    // pub fn create_command_pool(self: vlk_queue, device: vk.DeviceProxy) !vk.CommandPool {
    //     return device.createCommandPool(&.{
    //         .queue_family_index = self.family_index,
    //         .flags = .{ .reset_command_buffer_bit = true },
    //     }, null);
    // }

    pub fn submit(self: vlk_queue, submits: []const vk.SubmitInfo2, fence: vk.Fence) !void {
        try self.queue.submit2(submits.len, submits.ptr, fence);
    }

    pub fn wait_idle(self: vlk_queue) !void {
        try self.queue.waitIdle();
    }
};

pub const vlk_command_pool = struct {
    handle: vk.CommandPool,

    pub fn init(device: *vlk_device) !vlk_command_pool {
        const info = vk.CommandPoolCreateInfo{
            .queue_family_index = device.queue_family_index,
            .flags = .{
                .reset_command_buffer_bit = true,
            },
        };

        const pool = try device.logical_device.createCommandPool(&info, null);

        return .{
            .handle = pool,
        };
    }

    pub fn alloc_buffers_buf(
        self: @This(),
        device: vk.DeviceProxy,
        count: u32,
        level: vk.CommandBufferLevel,
        buf: []vk.CommandBuffer,
    ) !void {
        const info = vk.CommandBufferAllocateInfo{
            .command_pool = self.handle,
            .level = level,
            .command_buffer_count = count,
        };
        try device.allocateCommandBuffers(&info, buf.ptr);
    }
    pub fn alloc_buffers(
        self: @This(),
        allocator: std.mem.Allocator,
        device: vk.DeviceProxy,
        count: u32,
        level: vk.CommandBufferLevel,
    ) ![]vk.CommandBuffer {
        const buf = try allocator.alloc(vk.CommandBuffer, count);
        try self.alloc_buffers_buf(device, count, level, buf);
        return buf;
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
        self.sdl_window = try sdl.video.Window.init("EMMA", screen_width, screen_height, .{ .vulkan = true, .resizable = true });

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
    const images = try device.logical_device.getSwapchainImagesAllocKHR(swapchain, allocator);
    defer allocator.free(images);

    const mip_levels = 1;
    const count = images.len;

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
            .aspect_flags = .{
                .color_bit = true,
            },
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

    pub fn resize(
        self: *@This(),
        u: *vlk_unit,
        width: u32,
        height: u32,
    ) void {
        self.rebuild(
            u,
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
            var chosen_present_mode = vk.PresentModeKHR.fifo_khr;
            for (present_modes) |pm| {
                if (pm == .immediate_khr) {
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
        u: *vlk_unit,
        width: u32,
        height: u32,
    ) !vlk_swapchain {
        return create(allocator, &u.vki, &u.device, &u.window, width, height, null);
    }

    pub fn rebuild(
        self: *@This(),
        u: *vlk_unit,
        width: u32,
        height: u32,
    ) !void {
        try u.device.logical_device.deviceWaitIdle();
        const new = try create(self.allocator, &u.vki, &u.device, &u.window, width, height, self);
        self.deinit(&u.device);
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
        handle: vk.CommandBuffer,
    ) !vlk_frame {
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
    cmds: []vk.CommandBuffer,
    index: usize,

    pub fn max_frames_in_flight(self: @This()) usize {
        return self.frames.len;
    }

    pub fn init(
        allocator: std.mem.Allocator,
        device: *vlk_device,
        pool: *vlk_command_pool,
        count: u32,
    ) !vlk_frames {
        const frames = try allocator.alloc(vlk_frame, count);
        errdefer allocator.free(frames);

        var initialized: usize = 0;
        errdefer for (frames[0..initialized]) |f| f.deinit(device.logical_device);

        const buf = try pool.alloc_buffers(allocator, device.logical_device, count, .primary);
        for (frames, 0..buf.len) |*f, i| {
            f.* = try vlk_frame.init(device, buf[i]);
            initialized += 1;
        }

        return .{
            .frames = frames,
            .cmds = buf,
            .index = 0,
            // .allocator = allocator,
        };
    }

    pub fn current(self: *vlk_frames) *vlk_frame {
        return &self.frames[self.index];
    }

    pub fn advance(self: *vlk_frames) void {
        self.index = (self.index + 1) % self.frames.len;
    }

    pub fn deinit(self: *vlk_frames, allocator: std.mem.Allocator, device: vk.DeviceProxy) void {
        for (self.frames) |f| f.deinit(device);
        allocator.free(self.frames);
        allocator.free(self.cmds);
    }
};

pub const vlk_samplers = struct {
    pub const SamplerIdx = enum(u32) {
        linear_repeat = 0,
        linear_clamp = 1,
        nearest_repeat = 2,
        nearest_clamp = 3,
        shadow = 4,
        equirect = 5,
    };

    linear_repeat: vk.Sampler, // most 3D textures
    linear_clamp: vk.Sampler, // render targets, UI, decals
    nearest_repeat: vk.Sampler, // pixel art, data textures
    nearest_clamp: vk.Sampler, // shadow maps, lookup tables
    shadow: vk.Sampler, // depth compare, clamp to white border
    equirect: vk.Sampler, // equirectangular env maps: wrap U, clamp V
    pub fn mem_count() usize {
        return @typeInfo(@This()).@"struct".fields.len;
    }
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
            .equirect = try create_uv(
                device,
                .linear,
                .linear,
                .repeat,
                .clamp_to_edge,
                0,
                0,
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
        _ = compare;
        return create_uv(device, mag, min, address, address, min_lod, max_lod);
    }

    fn create_uv(
        device: *vlk_device,
        mag: vk.Filter,
        min: vk.Filter,
        address_u: vk.SamplerAddressMode,
        address_v: vk.SamplerAddressMode,
        min_lod: f32,
        max_lod: f32,
    ) !vk.Sampler {
        return device.logical_device.createSampler(&.{
            .mag_filter = mag,
            .min_filter = min,
            .mipmap_mode = if (max_lod > 0) .linear else .nearest,
            .address_mode_u = address_u,
            .address_mode_v = address_v,
            .address_mode_w = address_u,
            .mip_lod_bias = 0,
            .anisotropy_enable = vk.Bool32.false,
            .max_anisotropy = 1,
            .compare_enable = vk.Bool32.false,
            .compare_op = .always,
            .min_lod = min_lod,
            .max_lod = max_lod,
            .border_color = .int_opaque_black,
            .unnormalized_coordinates = vk.Bool32.false,
        }, null);
    }

    pub fn deinit(self: @This(), device: vk.DeviceProxy) void {
        device.destroySampler(self.linear_repeat, null);
        device.destroySampler(self.linear_clamp, null);
        device.destroySampler(self.nearest_repeat, null);
        device.destroySampler(self.nearest_clamp, null);
        device.destroySampler(self.shadow, null);
        device.destroySampler(self.equirect, null);
    }
};

pub const vlk_unit = struct {
    vki: vlk_instance,
    window: vlk_window,
    device: vlk_device,
    vma: vlk_vma,
    samplers: vlk_samplers,
    cmd_pool: vlk_command_pool,

    props: vk.PhysicalDeviceProperties,
    rtprops: vk.PhysicalDeviceRayTracingPipelinePropertiesKHR,

    pub fn queue(self: *@This()) vk.QueueProxy {
        return self.device.queue;
    }

    pub fn init(allocator: std.mem.Allocator, screen_width: usize, screen_height: usize) !vlk_unit {
        var vki = try vlk_instance.init(allocator);
        var window = try vlk_window.init(&vki, screen_width, screen_height);
        var device = try vlk_device.init(allocator, &vki, &window);
        const vma = try vlk_vma.init(&device, &vki);
        const samplers = try vlk_samplers.init(&device);
        const cmd_pool = try vlk_command_pool.init(&device);

        const props = vki.instance.getPhysicalDeviceProperties(device.physical_device);
        const rtprops = vlk_get_raytracing_properties(&vki, &device);
        return .{
            .vki = vki,
            .window = window,
            .device = device,
            .vma = vma,
            .samplers = samplers,
            .cmd_pool = cmd_pool,
            .props = props,
            .rtprops = rtprops,
        };
    }

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        self.cmd_pool.deinit(self.device.logical_device);
        self.samplers.deinit(self.device.logical_device);
        self.window.deinit();
        self.vma.deinit();
        self.device.deinit();
        self.vki.deinit(allocator);
    }
};

pub const vlk_vma = struct {
    allocator: c_libs.VmaAllocator,

    pub fn init(device: *vlk_device, vki: *vlk_instance) !vlk_vma {
        const vma_info = c_libs.VmaAllocatorCreateInfo{
            .physicalDevice = @ptrFromInt(@intFromEnum(device.physical_device)),
            .device = @ptrFromInt(@intFromEnum(device.logical_device.handle)),
            .instance = @ptrFromInt(@intFromEnum(vki.instance.handle)),
            .flags = c_libs.VMA_ALLOCATOR_CREATE_BUFFER_DEVICE_ADDRESS_BIT,
        };

        var vma: c_libs.VmaAllocator = undefined;
        const result = c_libs.vmaCreateAllocator(&vma_info, &vma);
        if (result != c_libs.VK_SUCCESS) {
            return error.VmaInitFailed;
        }

        return .{ .allocator = vma };
    }

    pub fn deinit(self: @This()) void {
        c_libs.vmaDestroyAllocator(self.allocator);
    }

    pub fn alloc_buffer_aligned(
        self: @This(),
        size: vk.DeviceSize,
        usage: c_libs.VkBufferUsageFlags,
        mem_usage: c_libs.VmaMemoryUsage,
        alloc_flags: c_libs.VmaAllocationCreateFlags,
        alignment: u64,
    ) !struct { buffer: c_libs.VkBuffer, allocation: c_libs.VmaAllocation, allocation_info: c_libs.VmaAllocationInfo } {
        const buffer_info = c_libs.VkBufferCreateInfo{
            .sType = c_libs.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
            .size = size,
            .usage = usage,
            .sharingMode = c_libs.VK_SHARING_MODE_EXCLUSIVE,
        };
        const alloc_create_info = c_libs.VmaAllocationCreateInfo{
            .usage = mem_usage,
            .flags = alloc_flags,
        };

        var buffer: c_libs.VkBuffer = undefined;
        var allocation: c_libs.VmaAllocation = undefined;
        var allocation_info: c_libs.VmaAllocationInfo = undefined;

        const result = c_libs.vmaCreateBufferWithAlignment(
            self.allocator,
            &buffer_info,
            &alloc_create_info,
            alignment,
            &buffer,
            &allocation,
            &allocation_info,
        );
        if (result != c_libs.VK_SUCCESS) return error.AllocationFailed;
        return .{
            .buffer = buffer,
            .allocation = allocation,
            .allocation_info = allocation_info,
        };
    }
    pub fn alloc_buffer(
        self: @This(),
        size: vk.DeviceSize,
        usage: c_libs.VkBufferUsageFlags,
        mem_usage: c_libs.VmaMemoryUsage,
        alloc_flags: c_libs.VmaAllocationCreateFlags,
    ) !struct { buffer: c_libs.VkBuffer, allocation: c_libs.VmaAllocation, allocation_info: c_libs.VmaAllocationInfo } {
        const buffer_info = c_libs.VkBufferCreateInfo{
            .sType = c_libs.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
            .size = size,
            .usage = usage,
            .sharingMode = c_libs.VK_SHARING_MODE_EXCLUSIVE,
        };

        const alloc_create_info = c_libs.VmaAllocationCreateInfo{
            .usage = mem_usage,
            .flags = alloc_flags,
        };

        var buffer: c_libs.VkBuffer = undefined;
        var allocation: c_libs.VmaAllocation = undefined;
        var allocation_info: c_libs.VmaAllocationInfo = undefined;

        const result = c_libs.vmaCreateBuffer(
            self.allocator,
            &buffer_info,
            &alloc_create_info,
            &buffer,
            &allocation,
            &allocation_info,
        );
        if (result != c_libs.VK_SUCCESS) return error.AllocationFailed;
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

    // extra
    device_address: bool = false,
    acceleration_structure_input: bool = false,
    acceleration_structure_storage: bool = false,

    pub fn bits(self: @This()) c_libs.VkBufferUsageFlags {
        var flags: c_libs.VkBufferUsageFlags = 0;
        if (self.vertex) flags |= c_libs.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT;
        if (self.index) flags |= c_libs.VK_BUFFER_USAGE_INDEX_BUFFER_BIT;
        if (self.storage) flags |= c_libs.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT;
        if (self.indirect) flags |= c_libs.VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT;
        if (self.transfer_src) flags |= c_libs.VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
        if (self.transfer_dst) flags |= c_libs.VK_BUFFER_USAGE_TRANSFER_DST_BIT;
        if (self.device_address) flags |= c_libs.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT;
        if (self.acceleration_structure_input) flags |= c_libs.VK_BUFFER_USAGE_ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_BIT_KHR;
        if (self.acceleration_structure_storage) flags |= c_libs.VK_BUFFER_USAGE_ACCELERATION_STRUCTURE_STORAGE_BIT_KHR;
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
    allocation: c_libs.VmaAllocation,
    info: c_libs.VmaAllocationInfo,
    size: vk.DeviceSize,
    alignment: u64,

    addr: ?vk.DeviceAddress = null,

    pub fn init_aligned(
        vma_alloc: *vlk_vma,
        size: vk.DeviceSize,
        usage: c_libs.VkBufferUsageFlags,
        mem_usage: c_libs.VmaMemoryUsage,
        alloc_flags: c_libs.VmaAllocationCreateFlags,
        alignment: u64,
    ) !vlk_vma_buffer {
        const result = try vma_alloc.alloc_buffer_aligned(size, usage, mem_usage, alloc_flags, alignment);
        return .{
            .handle = @enumFromInt(@intFromPtr(result.buffer)),
            .allocation = result.allocation,
            .info = result.allocation_info,
            .size = size,
            .alignment = alignment,
        };
    }

    pub fn init(
        vma_alloc: *vlk_vma,
        size: vk.DeviceSize,
        usage: c_libs.VkBufferUsageFlags,
        mem_usage: c_libs.VmaMemoryUsage,
        alloc_flags: c_libs.VmaAllocationCreateFlags,
    ) !vlk_vma_buffer {
        const result = try vma_alloc.alloc_buffer(size, usage, mem_usage, alloc_flags);
        return .{
            .handle = @enumFromInt(@intFromPtr(result.buffer)),
            .allocation = result.allocation,
            .info = result.allocation_info,
            .size = size,
            .alignment = 0,
        };
    }

    pub fn address(self: *@This(), device: *vlk_device) vk.DeviceAddress {
        if (self.addr) |addr| return addr;

        const info = vk.BufferDeviceAddressInfo{
            .buffer = self.handle,
        };
        const addr = device.logical_device.getBufferDeviceAddress(&info);
        self.addr = addr;
        return addr;
    }

    pub fn deinit(self: @This(), vma: *vlk_vma) void {
        c_libs.vmaDestroyBuffer(vma.allocator, @ptrFromInt(@intFromEnum(self.handle)), self.allocation);
    }

    pub fn map(self: @This(), vma_alloc: *vlk_vma) !*anyopaque {
        if (self.info.pMappedData) |p| return p;
        var mapped: ?*anyopaque = undefined;
        const result = c_libs.vmaMapMemory(vma_alloc.allocator, self.allocation, &mapped);
        if (result != c_libs.VK_SUCCESS) return error.MapFailed;
        return mapped.?;
    }

    pub fn unmap(self: @This(), vma: *vlk_vma) void {
        if (self.info.pMappedData) {
            return;
        } else {
            c_libs.vmaUnmapMemory(vma.allocator, self.allocation);
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
        const regions = [_]vk.BufferCopy{
            region,
        };

        cmd.copyBuffer(self.handle, dst.handle, &regions);
    }
};

pub const vlk_vma_buffer_view = struct {
    buffer: *vlk_vma_buffer,
    offset: vk.DeviceSize,
    size: vk.DeviceSize,

    pub fn init(buffer: *vlk_vma_buffer, offset: vk.DeviceSize, size: vk.DeviceSize) vlk_vma_buffer_view {
        std.debug.assert(offset + size <= buffer.size);
        return .{ .buffer = buffer, .offset = offset, .size = size };
    }

    pub fn whole(buffer: *vlk_vma_buffer) vlk_vma_buffer_view {
        return .{ .buffer = buffer, .offset = 0, .size = buffer.size };
    }

    pub fn handle(self: @This()) vk.Buffer {
        return self.buffer.handle;
    }

    pub fn address(self: @This(), device: *vlk_device) vk.DeviceAddress {
        return self.buffer.address(device) + self.offset;
    }

    pub fn descriptor_buffer_info(self: @This()) vk.DescriptorBufferInfo {
        return .{
            .buffer = self.buffer.handle,
            .offset = self.offset,
            .range = self.size,
        };
    }

    pub fn map_memcpy(self: @This(), vma: *vlk_vma, data: []const u8, offset: usize) !void {
        std.debug.assert(offset + data.len <= self.size);
        return self.buffer.map_memcpy(vma, data, self.offset + offset);
    }

    pub fn mapped_slice(self: @This(), comptime T: type, vma: *vlk_vma) ![]T {
        const ptr = try self.buffer.map(vma);
        const bytes: [*]u8 = @ptrCast(ptr);
        const base: [*]T = @ptrCast(@alignCast(bytes + self.offset));
        return base[0 .. self.size / @sizeOf(T)];
    }

    pub fn cmd_copy_to(self: @This(), dst: vlk_vma_buffer_view, cmd: vk.CommandBufferProxy) void {
        std.debug.assert(self.size <= dst.size);
        const region = vk.BufferCopy{
            .src_offset = self.offset,
            .dst_offset = dst.offset,
            .size = self.size,
        };
        cmd.copyBuffer(self.buffer.handle, dst.buffer.handle, &[_]vk.BufferCopy{region});
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

pub const vlk_shader_stage = struct {
    pub fn init(
        stage: vk.ShaderStageFlags,
        entry: [*:0]const u8,
        module: vk.ShaderModule,
        spec_info: ?*vk.SpecializationInfo,
    ) vk.PipelineShaderStageCreateInfo {
        return .{
            .stage = stage,
            .module = module,
            .p_name = entry,
            .flags = .{},
            .p_specialization_info = spec_info, // actually useful
        };
    }
};

pub const vlk_pipeline = struct {
    handle: vk.Pipeline,
    layout: vk.PipelineLayout,

    pub fn create_layout_info(
        push_constants: []const vk.PushConstantRange,
        descriptor_sets: []const vk.DescriptorSetLayout,
    ) vk.PipelineLayoutCreateInfo {
        return vk.PipelineLayoutCreateInfo{
            .flags = .{},

            .push_constant_range_count = @intCast(push_constants.len),
            .p_push_constant_ranges = push_constants.ptr,

            .set_layout_count = @intCast(descriptor_sets.len),
            .p_set_layouts = descriptor_sets.ptr,
        };
    }

    pub fn create_layout(device: *vlk_device, info: *const vk.PipelineLayoutCreateInfo) !vk.PipelineLayout {
        return device.logical_device.createPipelineLayout(info, null);
    }

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

    pub fn deinit(self: @This(), device: *vlk_device) void {
        device.logical_device.destroyPipeline(self.handle, null);
        device.logical_device.destroyPipelineLayout(self.layout, null);

        // for (self.descriptor_set_layouts) |layout| {
        //     device.logical_device.destroyDescriptorSetLayout(layout, null);
        // }
        // allocator.free(self.descriptor_set_layouts);
    }
};

pub const vlk_pipeline_instance = struct {
    pipeline: *vlk_pipeline,
    descriptor_sets: [4]vk.DescriptorSet,
    descriptor_set_count: u32,

    pub fn cmd_bind_compute(self: @This(), cmd: vk.CommandBufferProxy) void {
        cmd.bindPipeline(.compute, self.pipeline.handle);
    }

    pub fn cmd_bind_graphics(self: @This(), cmd: vk.CommandBufferProxy) void {
        cmd.bindPipeline(.graphics, self.pipeline.handle);
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

pub fn vlk_make_rt_pipeline_info(
    stages: []const vk.PipelineShaderStageCreateInfo,
    groups: []const vk.RayTracingShaderGroupCreateInfoKHR,
    max_recursion_depth: u32,
    layout: vk.PipelineLayout,
) vk.RayTracingPipelineCreateInfoKHR {
    return .{
        .base_pipeline_handle = .null_handle,
        .base_pipeline_index = -1,
        .stage_count = @intCast(stages.len),
        .p_stages = stages.ptr,
        .group_count = @intCast(groups.len),
        .p_groups = groups.ptr,
        .max_pipeline_ray_recursion_depth = max_recursion_depth,
        .layout = layout,
    };
}

pub const rt_group_info = struct {
    pub fn general(index: u32) vk.RayTracingShaderGroupCreateInfoKHR {
        return .{
            .type = .general_khr,
            .general_shader = index,
            .closest_hit_shader = vk.SHADER_UNUSED_KHR,
            .any_hit_shader = vk.SHADER_UNUSED_KHR,
            .intersection_shader = vk.SHADER_UNUSED_KHR,
        };
    }

    pub fn procedural_hit(closest_index: u32, intersection_index: u32) vk.RayTracingShaderGroupCreateInfoKHR {
        return .{
            .type = .procedural_hit_group_khr,
            .general_shader = vk.SHADER_UNUSED_KHR,
            .closest_hit_shader = closest_index,
            .any_hit_shader = vk.SHADER_UNUSED_KHR,
            .intersection_shader = intersection_index,
        };
    }

    pub fn procedural_hit_any(closest_index: u32, any_index: u32, intersection_index: u32) vk.RayTracingShaderGroupCreateInfoKHR {
        return .{
            .type = .procedural_hit_group_khr,
            .general_shader = vk.SHADER_UNUSED_KHR,
            .closest_hit_shader = closest_index,
            .any_hit_shader = any_index,
            .intersection_shader = intersection_index,
        };
    }

    pub fn triangles_hit_any(closest_index: u32, any_index: u32) vk.RayTracingShaderGroupCreateInfoKHR {
        return .{
            .type = .triangles_hit_group_khr,
            .general_shader = vk.SHADER_UNUSED_KHR,
            .closest_hit_shader = closest_index,
            .any_hit_shader = any_index,
            .intersection_shader = vk.SHADER_UNUSED_KHR,
        };
    }

    pub fn triangles_hit(index: u32) vk.RayTracingShaderGroupCreateInfoKHR {
        return .{
            .type = .triangles_hit_group_khr,
            .general_shader = vk.SHADER_UNUSED_KHR,
            .closest_hit_shader = index,
            .any_hit_shader = vk.SHADER_UNUSED_KHR,
            .intersection_shader = vk.SHADER_UNUSED_KHR,
        };
    }
};

fn vlk_pipeline_layout_create_info(push_constants: []const vk.PushConstantRange, descriptor_sets: []const vk.DescriptorSetLayout) vk.PipelineLayoutCreateInfo {
    return vk.PipelineLayoutCreateInfo{
        .push_constant_range_count = @intCast(push_constants.len),
        .p_push_constant_ranges = push_constants.ptr,

        .set_layout_count = @intCast(descriptor_sets.len),
        .p_set_layouts = descriptor_sets.ptr,
    };
}

const Slider = struct {
    slice: []u8,
    index: usize,

    pub fn get(self: *@This(), count: usize) ![]u8 {
        if (self.index + count > self.slice.len)
            return error.OutOfPoolMemory;
        const result = self.slice[self.index..][0..count];

        self.index += count;
        return result;
    }

    pub fn get_aligned(self: *@This(), alignment: usize, count: usize) ![]u8 {
        const aligned_index = std.mem.alignForward(usize, self.index, alignment);

        if (aligned_index + count > self.slice.len)
            return error.OutOfPoolMemory;

        const result = self.slice[aligned_index .. aligned_index + count];

        self.index = aligned_index + count;
        return result;
    }
};

const SbtLayout = struct {
    offset: usize,
    size: usize,
    count: usize,

    pub fn init(handle_alignment: usize, handle_size: usize, count: usize) SbtLayout {
        const stride = std.mem.alignForward(usize, handle_size, handle_alignment);
        return .{
            .offset = 0,
            .size = count * stride,
            .count = count,
        };
    }

    pub fn next(self: @This(), handle_alignment: usize, handle_size: usize, count: usize, base_alignment: usize) SbtLayout {
        const stride = std.mem.alignForward(usize, handle_size, handle_alignment);
        return .{
            .offset = std.mem.alignForward(usize, self.offset + self.size, base_alignment),
            .size = count * stride,
            .count = count,
        };
    }
};

pub fn push_constant_range(comptime T: type, stage_flags: vk.ShaderStageFlags, offset: usize) vk.PushConstantRange {
    return .{
        .offset = @intCast(offset),
        .size = @sizeOf(T),
        .stage_flags = stage_flags,
    };
}

pub const vlk_graphics_pipeline = struct {
    pipeline: vlk_pipeline,

    pub fn init(
        device: *vlk_device,
        pc_ranges: []const vk.PushConstantRange,
        layouts: []const vk.DescriptorSetLayout,
        stages: []const vk.PipelineShaderStageCreateInfo,
        color_formats: []const vk.Format,
        depth_format: vk.Format,
    ) !@This() {
        const dynamic_states = [_]vk.DynamicState{ .viewport, .scissor };
        const dynamic_state = vk.PipelineDynamicStateCreateInfo{
            .dynamic_state_count = dynamic_states.len,
            .p_dynamic_states = &dynamic_states,
        };

        // then viewport state just declares the count, actual values set at draw time
        const viewport_state = vk.PipelineViewportStateCreateInfo{
            .viewport_count = 1,
            .scissor_count = 1,
        };

        const depth_stencil = vk.PipelineDepthStencilStateCreateInfo{
            .depth_test_enable = true,
            .depth_write_enable = true,
            .depth_compare_op = .less,
            .depth_bounds_test_enable = false,
            .stencil_test_enable = false,
        };

        const vert_input = vk.PipelineVertexInputStateCreateInfo{
            .vertex_attribute_description_count = 0,
            .p_vertex_binding_descriptions = null,

            .vertex_binding_description_count = 0,
            .p_vertex_attribute_descriptions = null,
        };

        const input_assembly = vk.PipelineInputAssemblyStateCreateInfo{
            .topology = .triangle_list,
            .primitive_restart_enable = false,
            .flags = .{},
        };

        const rasterizer = vk.PipelineRasterizationStateCreateInfo{
            .depth_clamp_enable = true,
            .rasterizer_discard_enable = false,

            .polygon_mode = .fill,
            .line_width = 1.0,

            .cull_mode = .{ .back_bit = true },
            .front_face = .clockwise,

            .depth_bias_enable = false,
            .depth_bias_constant_factor = 0.0,
            .depth_bias_clamp = 0.0,
            .depth_bias_slope_factor = 0.0,
        };

        const multisampling = vk.PipelineMultisampleStateCreateInfo{
            .sample_shading_enable = false,

            .rasterization_samples = .{ .@"1_bit" = true },
            .min_sample_shading = 1.0,

            .p_sample_mask = null,

            .alpha_to_coverage_enable = false,
            .alpha_to_one_enable = false,
        };

        const color_blend_attachment = vk.PipelineColorBlendAttachmentState{
            .color_write_mask = .{
                .r_bit = true,
                .g_bit = true,
                .b_bit = true,
                .a_bit = true,
            },
            .blend_enable = false,
            .src_color_blend_factor = .one,
            .dst_color_blend_factor = .one,
            .color_blend_op = .add,
            .src_alpha_blend_factor = .one,
            .dst_alpha_blend_factor = .one,
            .alpha_blend_op = .add,
        };

        const color_blending = vk.PipelineColorBlendStateCreateInfo{
            .logic_op_enable = false,
            .logic_op = .copy,
            .attachment_count = 1,
            .p_attachments = &color_blend_attachment,
            .blend_constants = .{ 0, 0, 0, 0 },
        };

        const rendering_info = vk.PipelineRenderingCreateInfo{
            .color_attachment_count = @intCast(color_formats.len),
            .p_color_attachment_formats = color_formats.ptr,
            .depth_attachment_format = depth_format,
        };

        const pipeline_layout_info = vlk_pipeline.create_layout_info(pc_ranges, layouts);
        const pl_layout = try vlk_pipeline.create_layout(device, &pipeline_layout_info);

        const pipeline_infos = [_]vk.GraphicsPipelineCreateInfo{
            .{
                .p_next = &rendering_info,
                .stage_count = @intCast(stages.len),
                .p_stages = stages.ptr,
                .p_vertex_input_state = &vert_input,
                .p_input_assembly_state = &input_assembly,
                .p_viewport_state = &viewport_state,
                .p_rasterization_state = &rasterizer,
                .p_multisample_state = &multisampling,
                .p_depth_stencil_state = &depth_stencil,
                .p_color_blend_state = &color_blending,
                .p_dynamic_state = &dynamic_state,
                .layout = pl_layout,
                .render_pass = .null_handle,
                .subpass = 0,
            },
        };
        var pipelines = [_]vk.Pipeline{.null_handle};

        const result = try device.logical_device.createGraphicsPipelines(.null_handle, pipeline_infos, null, &pipelines);
        _ = result;

        const pipeline = vlk_pipeline{
            .handle = pipelines[0],
            .layout = pl_layout,
        };

        return .{
            .pipeline = pipeline,
        };
    }
};

pub const vlk_compute_pipeline = struct {
    pipeline: vlk_pipeline,
    pub fn init(
        allocator: std.mem.Allocator,
        u: *vlk_unit,
        pc_ranges: []const vk.PushConstantRange,
        descriptor_set_layouts: []vk.DescriptorSetLayout,
        stage: vk.PipelineShaderStageCreateInfo,
    ) !@This() {
        errdefer allocator.free(descriptor_set_layouts);
        const pipeline_layout_info = vlk_pipeline.create_layout_info(
            pc_ranges,
            descriptor_set_layouts,
        );
        const layout = try vlk_pipeline.create_layout(
            &u.device,
            &pipeline_layout_info,
        );
        errdefer u.device.logical_device.destroyPipelineLayout(layout, null);

        var pipelines = [_]vk.Pipeline{.null_handle};
        const pipeline_info = vk.ComputePipelineCreateInfo{
            .stage = stage,
            .layout = layout,
            .base_pipeline_index = -1,
            .base_pipeline_handle = .null_handle,
            .flags = .{},
        };
        _ = try u.device.logical_device.createComputePipelines(
            .null_handle,
            &[_]vk.ComputePipelineCreateInfo{
                pipeline_info,
            },
            null,
            &pipelines,
        );

        return .{
            .pipeline = .{
                .handle = pipelines[0],
                // .descriptor_set_layouts = descriptor_set_layouts,
                .layout = layout,
            },
        };
    }
    pub fn deinit(
        self: @This(),
        device: *vlk_device,
    ) void {
        self.pipeline.deinit(device);
    }
};

pub const vlk_rt_pipeline = struct {
    pipeline: vlk_pipeline,
    sbt: shader_binding_table,

    pub const shader_binding_table = struct {
        buffer: vlk_vma_buffer,
        raygen_region: vk.StridedDeviceAddressRegionKHR,
        miss_region: vk.StridedDeviceAddressRegionKHR,
        closest_hit_region: vk.StridedDeviceAddressRegionKHR,
        callable_region: vk.StridedDeviceAddressRegionKHR,

        pub fn deinit(self: @This(), vma: *vlk_vma) void {
            self.buffer.deinit(vma);
        }

        pub fn init(
            allocator: std.mem.Allocator,
            vma: *vlk_vma,
            device: *vlk_device,
            pipeline: vk.Pipeline,
            rt_props: *const vk.PhysicalDeviceRayTracingPipelinePropertiesKHR,
            pipeline_info: vk.RayTracingPipelineCreateInfoKHR,
            raygen_count: usize,
            miss_count: usize,
            closest_hit_count: usize,
            callable_count: usize,
            gp: ImediateSubmit,
        ) !shader_binding_table {
            //get properties
            const handle_size = rt_props.shader_group_handle_size;
            const handle_alignment = rt_props.shader_group_handle_alignment;
            const base_alignment = rt_props.shader_group_base_alignment;

            //group count
            const group_count = pipeline_info.group_count;

            //handles
            const handle_list_size: usize = handle_size * group_count;
            const handles = try allocator.alloc(u8, handle_list_size);
            defer allocator.free(handles);

            try device.logical_device.getRayTracingShaderGroupHandlesKHR(
                pipeline,
                0,
                group_count,
                handle_list_size,
                @ptrCast(handles.ptr),
            );

            const raygen = SbtLayout.init(
                @intCast(handle_alignment),
                @intCast(handle_size),
                @intCast(raygen_count),
            );
            const miss = raygen.next(
                handle_alignment,
                handle_size,
                miss_count,
                base_alignment,
            );
            const closest_hit = miss.next(
                handle_alignment,
                handle_size,
                closest_hit_count,
                base_alignment,
            );
            const callable = closest_hit.next(
                handle_alignment,
                handle_size,
                callable_count,
                base_alignment,
            );
            //this causes some extra padding on our buffer if callable.size == 0
            // I should add an if check here
            // but I would prefer a more "proper" way maybe shove them into an array so I can loop and check which one is the last idk
            // for now this will have to do
            const buffer_size = callable.offset + callable.size;

            var region_buffer = try vlk_vma_buffer.init_aligned(
                vma,
                buffer_size,
                c_libs.VK_BUFFER_USAGE_2_SHADER_BINDING_TABLE_BIT_KHR |
                    c_libs.VK_BUFFER_USAGE_2_SHADER_DEVICE_ADDRESS_BIT |
                    c_libs.VK_BUFFER_USAGE_2_TRANSFER_DST_BIT,
                c_libs.VMA_MEMORY_USAGE_AUTO_PREFER_DEVICE,
                0,
                base_alignment,
            );
            errdefer region_buffer.deinit(vma);

            const staging = try vlk_upload_buffer(vma, buffer_size);
            defer staging.deinit(vma);
            const staging_mapping_ptr: [*]u8 = @ptrCast(try staging.map(vma));
            const staging_mapping: []u8 = staging_mapping_ptr[0..buffer_size];

            const sbt_layouts = [_]SbtLayout{
                raygen, miss, closest_hit, callable,
            };

            {
                {
                    var staging_mapping_slider = Slider{ .slice = staging_mapping, .index = 0 };
                    var handle_slider = Slider{ .slice = handles, .index = 0 };
                    for (sbt_layouts) |layout| {
                        for (0..layout.count) |i| {
                            _ = i;
                            @memcpy(
                                try staging_mapping_slider.get_aligned(handle_alignment, handle_size),
                                try handle_slider.get(handle_size),
                            );
                        }
                    }
                }

                //upload staging buffer
                {
                    try gp.begin();
                    staging.cmd_copy_to(&region_buffer, gp.cmd);
                    try gp.submit_and_wait(device.queue, device.logical_device);
                }
            }
            const address = region_buffer.address(device);

            const raygen_stride = std.mem.alignForward(u64, handle_size, base_alignment);
            const handle_stride = std.mem.alignForward(u64, handle_size, handle_alignment);

            const raygen_region = vk.StridedDeviceAddressRegionKHR{
                .device_address = address + raygen.offset,
                .stride = raygen_stride,
                .size = raygen.size,
            };

            const miss_region = vk.StridedDeviceAddressRegionKHR{
                .device_address = address + miss.offset,
                .stride = handle_stride,
                .size = miss.size,
            };

            const closest_hit_region = vk.StridedDeviceAddressRegionKHR{
                .device_address = address + closest_hit.offset,
                .stride = handle_stride,
                .size = closest_hit.size,
            };

            const callable_region = vk.StridedDeviceAddressRegionKHR{
                .device_address = address + callable.offset,
                .stride = handle_stride,
                .size = callable.size,
            };

            return .{
                .buffer = region_buffer,
                .raygen_region = raygen_region,
                .miss_region = miss_region,
                .closest_hit_region = closest_hit_region,
                .callable_region = callable_region,
            };
        }
    };

    pub fn init(
        allocator: std.mem.Allocator,
        u: *vlk_unit,
        rt_props: *const vk.PhysicalDeviceRayTracingPipelinePropertiesKHR,
        pc_ranges: []const vk.PushConstantRange,
        set_layouts: []vk.DescriptorSetLayout,
        stages: []const vk.PipelineShaderStageCreateInfo,
        groups: []const vk.RayTracingShaderGroupCreateInfoKHR,
        is: ImediateSubmit,
    ) !vlk_rt_pipeline {
        //pipeline

        const pipeline_layout_info = vlk_pipeline.create_layout_info(pc_ranges, set_layouts);
        const layout = try vlk_pipeline.create_layout(&u.device, &pipeline_layout_info);
        //pipeline

        //rt pipeline
        var raygen_count: usize = 0;
        var miss_count: usize = 0;
        var closest_hit_count: usize = 0;
        var callable_count: usize = 0;

        for (groups) |group| {
            switch (group.type) {
                .general_khr => {
                    const stage = stages[group.general_shader].stage;
                    if (stage.raygen_bit_khr) raygen_count += 1;
                    if (stage.miss_bit_khr) miss_count += 1;
                    if (stage.callable_bit_khr) callable_count += 1;
                },
                .triangles_hit_group_khr => closest_hit_count += 1,
                .procedural_hit_group_khr => closest_hit_count += 1,
                _ => {},
            }
        }
        const rt_pipeline_info = [_]vk.RayTracingPipelineCreateInfoKHR{
            vlk_make_rt_pipeline_info(
                stages,
                groups,
                @min(@as(u32, 2), rt_props.max_ray_recursion_depth),
                layout,
            ),
        };

        var pipelines = [_]vk.Pipeline{.null_handle};
        const result = try u.device.logical_device.createRayTracingPipelinesKHR(
            .null_handle,
            .null_handle,
            &rt_pipeline_info,
            null,
            &pipelines,
        );
        _ = result;

        //wait for the above to be done
        // in case we use defered operations
        const pipeline = vlk_pipeline{
            .handle = pipelines[0],
            .layout = layout,
        };

        //after pipeline creation
        const sbt = try shader_binding_table.init(
            allocator,
            &u.vma,
            &u.device,
            pipeline.handle,
            rt_props,
            rt_pipeline_info[0],

            raygen_count,
            miss_count,
            closest_hit_count,
            callable_count,

            is,
        );

        return .{
            .pipeline = pipeline,
            .sbt = sbt,
        };
    }

    pub fn deinit(self: @This(), vma: *vlk_vma, device: *vlk_device) void {
        self.sbt.deinit(vma);
        self.pipeline.deinit(device);
    }
};

pub const device_geometry = struct {
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
        m: *const local_geometry.geometry,
    ) !device_geometry {
        const vertex_bytes = std.mem.sliceAsBytes(m.verts);
        const index_bytes = std.mem.sliceAsBytes(m.indices);

        var vertex_buffer = try vlk_vma_buffer.init(
            vma,
            vertex_bytes.len,
            c_libs.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT |
                c_libs.VK_BUFFER_USAGE_2_SHADER_DEVICE_ADDRESS_BIT |
                c_libs.VK_BUFFER_USAGE_2_TRANSFER_DST_BIT |
                c_libs.VK_BUFFER_USAGE_ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_BIT_KHR,
            c_libs.VMA_MEMORY_USAGE_AUTO,
            0,
        );
        try staging_buffers.append(allocator, try vlk_upload_buffer_with_data(vma, vertex_bytes));
        staging_buffers.getLast().cmd_copy_to(&vertex_buffer, cmd);

        var index_buffer = try vlk_vma_buffer.init(
            vma,
            index_bytes.len,
            c_libs.VK_BUFFER_USAGE_INDEX_BUFFER_BIT |
                c_libs.VK_BUFFER_USAGE_TRANSFER_DST_BIT |
                c_libs.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT |
                c_libs.VK_BUFFER_USAGE_ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_BIT_KHR,
            c_libs.VMA_MEMORY_USAGE_AUTO,
            0,
        );
        try staging_buffers.append(allocator, try vlk_upload_buffer_with_data(vma, index_bytes));
        staging_buffers.getLast().cmd_copy_to(&index_buffer, cmd);

        const normal_bytes = std.mem.sliceAsBytes(m.normals);
        const normal_buffer = try vlk_vma_buffer.init(
            vma,
            normal_bytes.len,
            c_libs.VK_BUFFER_USAGE_TRANSFER_DST_BIT |
                c_libs.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT |
                c_libs.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
            c_libs.VMA_MEMORY_USAGE_AUTO,
            0,
        );
        try staging_buffers.append(allocator, try vlk_upload_buffer_with_data(vma, normal_bytes));
        staging_buffers.getLast().cmd_copy_to(&normal_buffer, cmd);

        const normal_index_bytes = std.mem.sliceAsBytes(m.normal_indices);
        const normal_index_buffer = try vlk_vma_buffer.init(
            vma,
            normal_index_bytes.len,
            c_libs.VK_BUFFER_USAGE_TRANSFER_DST_BIT |
                c_libs.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT |
                c_libs.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
            c_libs.VMA_MEMORY_USAGE_AUTO,
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
        self.normal_buffer.deinit(vma);
        self.normal_index_buffer.deinit(vma);
    }
};

pub const blas_geometry_range = struct {
    begin: u32,
    len: u32,
};

pub const rt_acceleration_structure = struct {
    handle: vk.AccelerationStructureKHR,
    buffer: vlk_vma_buffer,

    pub fn address(self: @This(), device: *vlk_device) vk.DeviceAddress {
        const info = vk.AccelerationStructureDeviceAddressInfoKHR{
            .acceleration_structure = self.handle,
        };
        return device.logical_device.getAccelerationStructureDeviceAddressKHR(&info);
    }

    pub fn get_build_info_and_sizes(
        device: *vlk_device,
        as_type: vk.AccelerationStructureTypeKHR,
        flags: vk.BuildAccelerationStructureFlagsKHR,
        geometry: []const vk.AccelerationStructureGeometryKHR,
        primitive_counts: []const u32,
    ) struct { build_info: vk.AccelerationStructureBuildGeometryInfoKHR, sizes: vk.AccelerationStructureBuildSizesInfoKHR } {
        var build_info = vk.AccelerationStructureBuildGeometryInfoKHR{
            .type = as_type,
            .flags = flags,
            .mode = .build_khr,
            .geometry_count = @intCast(geometry.len),
            .p_geometries = geometry.ptr,
            .scratch_data = .{ .device_address = 0 },
        };
        var sizes = vk.AccelerationStructureBuildSizesInfoKHR{
            .acceleration_structure_size = 0,
            .build_scratch_size = 0,
            .update_scratch_size = 0,
        };
        device.logical_device.getAccelerationStructureBuildSizesKHR(.device_khr, &build_info, primitive_counts.ptr, &sizes);
        return .{ .build_info = build_info, .sizes = sizes };
    }

    pub fn create(
        device: *vlk_device,
        as_buffer: vlk_vma_buffer,
        offset: u64,
        as_type: vk.AccelerationStructureTypeKHR,
        sizes: vk.AccelerationStructureBuildSizesInfoKHR,
    ) !rt_acceleration_structure {
        const as_create_info = vk.AccelerationStructureCreateInfoKHR{
            .type = as_type,
            .buffer = as_buffer.handle,
            .size = sizes.acceleration_structure_size,
            .offset = offset,
            .create_flags = .{},
            .device_address = 0,
        };
        const as = try device.logical_device.createAccelerationStructureKHR(&as_create_info, null);
        return .{
            .handle = as,
            .buffer = as_buffer,
        };
    }

    pub fn record_build(
        self: rt_acceleration_structure,
        device: *vlk_device,
        scratch: *vlk_vma_buffer,
        build_info: vk.AccelerationStructureBuildGeometryInfoKHR,
        geometry_range: []const vk.AccelerationStructureBuildRangeInfoKHR,
        cmd: vk.CommandBufferProxy,
    ) void {
        var info = build_info;
        info.dst_acceleration_structure = self.handle;
        info.scratch_data = .{ .device_address = scratch.address(device) };

        const range_ptr = [_][*]const vk.AccelerationStructureBuildRangeInfoKHR{geometry_range.ptr};
        cmd.buildAccelerationStructuresKHR(@ptrCast(&info), &range_ptr);
    }

    pub fn init(
        allocator: std.mem.Allocator,
        vma: *vlk_vma,
        device: *vlk_device,
        as_type: vk.AccelerationStructureTypeKHR,
        geometry: []const vk.AccelerationStructureGeometryKHR,
        geometry_range: []const vk.AccelerationStructureBuildRangeInfoKHR,
        flags: vk.BuildAccelerationStructureFlagsKHR,
        staging_pool: *std.ArrayList(vlk_vma_buffer),
        cmd: vk.CommandBufferProxy,
    ) !rt_acceleration_structure {
        var primitive_counts = try std.ArrayList(u32).initCapacity(allocator, geometry_range.len);
        defer primitive_counts.deinit(allocator);

        for (geometry_range) |range| {
            primitive_counts.appendAssumeCapacity(range.primitive_count);
        }

        const bis = get_build_info_and_sizes(device, as_type, flags, geometry, primitive_counts.items);

        const as_buffer = try vlk_vma_buffer.init(
            vma,
            bis.sizes.acceleration_structure_size,
            c_libs.VK_BUFFER_USAGE_ACCELERATION_STRUCTURE_STORAGE_BIT_KHR | c_libs.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
            c_libs.VMA_MEMORY_USAGE_AUTO,
            0,
        );
        const as = try create(device, as_buffer, 0, as_type, bis.sizes);

        try staging_pool.append(allocator, try vlk_vma_buffer.init_aligned(
            vma,
            bis.sizes.build_scratch_size,
            c_libs.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | c_libs.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
            c_libs.VMA_MEMORY_USAGE_AUTO_PREFER_DEVICE,
            0,
            256,
        ));
        var scratch = staging_pool.getLast();

        as.record_build(device, &scratch, bis.build_info, geometry_range, cmd);

        return as;
    }

    pub fn init_blas(
        allocator: std.mem.Allocator,
        vma: *vlk_vma,
        device: *vlk_device,
        geometry: []const vk.AccelerationStructureGeometryKHR,
        geometry_range: []const vk.AccelerationStructureBuildRangeInfoKHR,
        flags: vk.BuildAccelerationStructureFlagsKHR,
        staging_pool: *std.ArrayList(vlk_vma_buffer),
        cmd: vk.CommandBufferProxy,
    ) !rt_acceleration_structure {
        return init(allocator, vma, device, .bottom_level_khr, geometry, geometry_range, flags, staging_pool, cmd);
    }

    // I want to move to a more defer way of doing stuff
    // gp is kinda forced here
    pub fn init_tlas(
        allocator: std.mem.Allocator,
        vma: *vlk_vma,
        device: *vlk_device,
        children: []rt_acceleration_structure,
        transforms: []vk.TransformMatrixKHR,
        flags: vk.BuildAccelerationStructureFlagsKHR,
        staging_pool: *std.ArrayList(vlk_vma_buffer),
        gp: ImediateSubmit,
    ) !rt_acceleration_structure {
        // build instance array
        var instances = try std.ArrayList(vk.AccelerationStructureInstanceKHR)
            .initCapacity(allocator, children.len);

        defer instances.deinit(allocator);
        {
            for (children, 0..) |blas, i| {
                const sbt_record_flags = vk.GeometryInstanceFlagsKHR{
                    .triangle_facing_cull_disable_bit_khr = true,
                };
                instances.appendAssumeCapacity(.{
                    .transform = transforms[i],
                    .instance_custom_index_and_mask = .{
                        .instance_custom_index = @intCast(i),
                        .mask = 0xFF,
                    },
                    .instance_shader_binding_table_record_offset_and_flags = .{
                        .instance_shader_binding_table_record_offset = 0,
                        .flags = @intCast(sbt_record_flags.toInt()),
                    },
                    .acceleration_structure_reference = blas.address(device),
                });
            }
        }

        // upload instance buffer
        const instance_buf_size = instances.items.len * @sizeOf(vk.AccelerationStructureInstanceKHR);
        var instance_buf = try vlk_vma_buffer.init(
            vma,
            instance_buf_size,
            c_libs.VK_BUFFER_USAGE_ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_BIT_KHR |
                c_libs.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT |
                c_libs.VK_BUFFER_USAGE_TRANSFER_DST_BIT,
            c_libs.VMA_MEMORY_USAGE_AUTO_PREFER_DEVICE,
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

        //for now
        try gp.begin();
        const result = try init(
            allocator,
            vma,
            device,
            .top_level_khr,
            @ptrCast(&geometry),
            @ptrCast(&range),
            flags,
            staging_pool,
            gp.cmd,
        );
        try gp.submit_and_wait(device.queue, device.logical_device);
        return result;
    }
    pub fn deinit(self: @This(), vma: *vlk_vma, device: *vlk_device) void {
        device.logical_device.destroyAccelerationStructureKHR(self.handle, null);
        self.buffer.deinit(vma);
    }
};

pub const raytracing_geometry_data = struct {
    geometry: vk.AccelerationStructureGeometryKHR,
    range: vk.AccelerationStructureBuildRangeInfoKHR,
    index: u32,

    pub fn init(
        meshes: []device_geometry,
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
                .flags = .{
                    .opaque_bit_khr = true,
                },
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

// pub const vlk_compute_pipeline = struct {
//     shader_module: vk.ShaderModule,
//     pipeline: vlk_pipeline,

//     pub fn init(
//         device: *vlk_device,
//         spirv: []const u8,
//         bindings: []const vk.DescriptorSetLayoutBinding,
//         binding_flags: []const vk.DescriptorBindingFlags,
//         pcs: []const vlk_pc_layout,
//     ) !vlk_compute_pipeline {
//         const shader_module = try device.logical_device.createShaderModule(&.{
//             .code_size = spirv.len,
//             .p_code = @ptrCast(@alignCast(spirv.ptr)),
//         }, null);
//         errdefer device.logical_device.destroyShaderModule(shader_module, null);

//         const shader_pipeline_info = vk.PipelineShaderStageCreateInfo{
//             .stage = .{ .compute_bit = true },
//             .module = shader_module,
//             .p_name = "main",
//         };

//         const descriptor_set_layout = try vlk_descriptor_set_layout.init(device, bindings, binding_flags);
//         errdefer descriptor_set_layout.deinit(device.logical_device);

//         var ranges: [8]vk.PushConstantRange = undefined;
//         for (pcs, 0..) |pc, i| {
//             ranges[i] = pc.range;
//         }

//         const pipeline_layout = try device.logical_device.createPipelineLayout(&.{
//             .set_layout_count = 1,
//             .p_set_layouts = @ptrCast(&descriptor_set_layout.handle),
//             .push_constant_range_count = @intCast(pcs.len),
//             .p_push_constant_ranges = if (pcs.len > 0) &ranges else null,
//         }, null);
//         errdefer device.logical_device.destroyPipelineLayout(pipeline_layout, null);

//         var pipeline: vk.Pipeline = undefined;
//         _ = try device.logical_device.createComputePipelines(
//             .null_handle,
//             1,
//             &[1]vk.ComputePipelineCreateInfo{.{
//                 .stage = shader_pipeline_info,
//                 .layout = pipeline_layout,
//                 .base_pipeline_handle = .null_handle,
//                 .base_pipeline_index = -1,
//             }},
//             null,
//             @ptrCast(&pipeline),
//         );

//         return .{
//             .shader_module = shader_module,
//             .pipeline = .{
//                 .pipeline = pipeline,
//                 .layout = pipeline_layout,
//                 .descriptor_set_layout = descriptor_set_layout,
//             },
//         };
//     }

//     pub fn deinit(self: @This(), device: vk.DeviceProxy) void {
//         self.pipeline.deinit(device);
//         device.destroyShaderModule(self.shader_module, null);
//     }
// };

pub const vlk_fence = struct {
    handle: vk.Fence,

    pub fn init(device: *vlk_device, flags: vk.FenceCreateFlags) !vlk_fence {
        const handle = try device.logical_device.createFence(&.{ .flags = flags }, null);
        return .{ .handle = handle };
    }

    pub fn wait_and_reset(self: @This(), device: vk.DeviceProxy) !void {
        const f = [_]vk.Fence{self.handle};
        _ = try device.waitForFences(&f, vk.Bool32.true, std.math.maxInt(u64));
        try device.resetFences(&f);
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
) !struct { allocation: c_libs.VmaAllocation, image: vk.Image } {
    const vma_image_info = c_libs.VkImageCreateInfo{
        .sType = c_libs.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .imageType = c_libs.VK_IMAGE_TYPE_2D,
        .format = @intCast(@intFromEnum(format)),
        .extent = .{
            .width = extent.width,
            .height = extent.height,
            .depth = extent.depth,
        },
        .mipLevels = mip_levels,
        .arrayLayers = array_layer_count,
        .samples = c_libs.VK_SAMPLE_COUNT_1_BIT,
        .tiling = c_libs.VK_IMAGE_TILING_OPTIMAL,
        .usage = @bitCast(usage),
        .sharingMode = c_libs.VK_SHARING_MODE_EXCLUSIVE,
        .initialLayout = c_libs.VK_IMAGE_LAYOUT_UNDEFINED,
    };

    const alloc_info = c_libs.VmaAllocationCreateInfo{
        .usage = c_libs.VMA_MEMORY_USAGE_AUTO,
    };

    var vk_image: c_libs.VkImage = undefined;
    var allocation: c_libs.VmaAllocation = undefined;
    const result = c_libs.vmaCreateImage(
        vma.allocator,
        &vma_image_info,
        &alloc_info,
        &vk_image,
        &allocation,
        null,
    );

    if (result != c_libs.VK_SUCCESS) {
        return error.ImageCreationFailed;
    }

    return .{
        .allocation = allocation,
        .image = @as(vk.Image, @enumFromInt(@intFromPtr(vk_image))),
    };
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
    allocation: c_libs.VmaAllocation,
    extent: vk.Extent3D,
    format: vk.Format,
    mip_levels: u32,
    aspect_flags: vk.ImageAspectFlags,

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
            .aspect_flags = aspect_flags,
        };
    }

    pub fn deinit(self: @This(), pvma: ?*vlk_vma, device: *vlk_device) void {
        device.logical_device.destroyImageView(self.view, null);
        if (pvma) |vma| {
            c_libs.vmaDestroyImage(
                vma.allocator,
                @ptrFromInt(@intFromEnum(self.handle)),
                self.allocation,
            );
        }
    }

    pub fn full_subresource_range(self: @This()) vk.ImageSubresourceRange {
        return .{
            .aspect_mask = self.aspect_flags,
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
                .aspect_mask = self.aspect_flags,
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

pub fn cmd_pipeline_barrier2(
    cmd: vk.CommandBufferProxy,
    image_barriers: []const vk.ImageMemoryBarrier2,
    buffer_barriers: []const vk.BufferMemoryBarrier2,
    memory_barriers: []const vk.MemoryBarrier2,
) void {
    const dep_info = vk.DependencyInfo{
        .image_memory_barrier_count = @intCast(image_barriers.len),
        .p_image_memory_barriers = image_barriers.ptr,

        .buffer_memory_barrier_count = @intCast(buffer_barriers.len),
        .p_buffer_memory_barriers = buffer_barriers.ptr,

        .memory_barrier_count = @intCast(memory_barriers.len),
        .p_memory_barriers = memory_barriers.ptr,
    };
    cmd.pipelineBarrier2(&dep_info);
}

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

    var header = c_libs.EXRHeader{};
    c_libs.InitEXRHeader(&header);

    var image = c_libs.EXRImage{};
    c_libs.InitEXRImage(&image);

    image.num_channels = 4;
    image.width = @intCast(width);
    image.height = @intCast(height);

    var image_ptr = [4][*]f32{
        a.ptr,
        b.ptr,
        g.ptr,
        r.ptr,
    };
    image.images = @ptrCast(&image_ptr);

    header.num_channels = 4;
    var channels = [4]c_libs.EXRChannelInfo{
        std.mem.zeroes(c_libs.EXRChannelInfo),
        std.mem.zeroes(c_libs.EXRChannelInfo),
        std.mem.zeroes(c_libs.EXRChannelInfo),
        std.mem.zeroes(c_libs.EXRChannelInfo),
    };

    @memcpy(channels[0].name[0..2], "A\x00");
    @memcpy(channels[1].name[0..2], "B\x00");
    @memcpy(channels[2].name[0..2], "G\x00");
    @memcpy(channels[3].name[0..2], "R\x00");

    header.channels = &channels;

    var pixel_types = [4]c_int{
        c_libs.TINYEXR_PIXELTYPE_FLOAT,
        c_libs.TINYEXR_PIXELTYPE_FLOAT,
        c_libs.TINYEXR_PIXELTYPE_FLOAT,
        c_libs.TINYEXR_PIXELTYPE_FLOAT,
    };
    header.pixel_types = &pixel_types;
    header.requested_pixel_types = &pixel_types;

    var err: [*c]const u8 = null;
    const ret = c_libs.SaveEXRImageToFile(&image, &header, path, &err);
    if (ret != c_libs.TINYEXR_SUCCESS) {
        std.debug.print("tinyexr error: {s}\n", .{err});
        c_libs.FreeEXRErrorMessage(err);
        return error.EXRWriteFailed;
    }
}

fn vlk_staging_buffer(vma: *vlk_vma, size: vk.DeviceSize, readback: bool) !vlk_vma_buffer {
    const usage = if (readback)
        c_libs.VK_BUFFER_USAGE_TRANSFER_DST_BIT
    else
        c_libs.VK_BUFFER_USAGE_TRANSFER_SRC_BIT;

    const host_flag = if (readback)
        c_libs.VMA_ALLOCATION_CREATE_HOST_ACCESS_RANDOM_BIT
    else
        c_libs.VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT;

    return vlk_vma_buffer.init(
        vma,
        size,
        @intCast(usage),
        c_libs.VMA_MEMORY_USAGE_AUTO,
        @intCast(host_flag | c_libs.VMA_ALLOCATION_CREATE_MAPPED_BIT),
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

pub const ImediateSubmit = struct {
    fence: vlk_fence,
    cmd: vk.CommandBufferProxy,

    pub fn init(device: *vlk_device, cmd: vk.CommandBufferProxy) !ImediateSubmit {
        const fence = try vlk_fence.init(device, .{});
        return .{ .fence = fence, .cmd = cmd };
    }

    pub fn begin(self: @This()) !void {
        // try self.fence.wait_and_reset(device.logical_device);
        try vlk_cmd_begin_one(self.cmd);
    }

    pub fn submit(self: @This(), queue: vk.QueueProxy) !void {
        try self.cmd.endCommandBuffer();
        const info = [_]vk.SubmitInfo{.{
            .command_buffer_count = 1,
            .p_command_buffers = @ptrCast(&self.cmd.handle),
        }};
        try queue.submit(&info, self.fence.handle);
    }

    pub fn submit_and_wait(self: @This(), queue: vk.QueueProxy, device: vk.DeviceProxy) !void {
        try self.submit(queue);
        try self.fence.wait_and_reset(device);
    }

    pub fn deinit(self: @This(), device: *vlk_device) void {
        self.fence.deinit(device.logical_device);
    }
};

// pub fn submit(
//     queue: vk.QueueProxy,
//     info: []const vk.SubmitInfo,
//     fence: vk.Fence,
// ) !void {
//     try queue.submit(@intCast(info.len), info.ptr, fence);
// }

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
    len: u32,

    pub fn init(desired_stride: u32, max: u32) TileElm {
        return .{
            .pos = 0,
            .len = @min(desired_stride, max),
        };
    }

    pub fn next(self: @This(), desired_stride: u32, max: u32) TileElm {
        const pos = self.pos + self.len;
        if (pos >= max) return init(desired_stride, max);
        return .{
            .pos = pos,
            .len = @min(desired_stride, max - pos),
        };
    }

    pub fn wrapped(self: @This()) bool {
        return self.pos == 0;
    }
};

pub fn create_set_info(set: []const vk.DescriptorSetLayoutBinding) vk.DescriptorSetLayoutCreateInfo {
    return .{
        .binding_count = @intCast(set.len),
        .p_bindings = set.ptr,
    };
}

pub fn vlk_create_set_layout_ex(
    device: *vlk_device,
    layouts: []const vk.DescriptorSetLayoutBinding,
    flags: []const vk.DescriptorBindingFlags,
) !vk.DescriptorSetLayout {
    if (flags.len != layouts.len)
        return error.InvalidBindingFlags;

    var info_flags = vk.DescriptorSetLayoutCreateFlags{};

    for (flags) |flag_set| {
        if (flag_set.update_after_bind_bit) {
            info_flags.update_after_bind_pool_bit = true;
        }
    }

    const flags_info = vk.DescriptorSetLayoutBindingFlagsCreateInfo{
        .binding_count = @intCast(flags.len),
        .p_binding_flags = flags.ptr,
    };

    const info = vk.DescriptorSetLayoutCreateInfo{
        .binding_count = @intCast(layouts.len),
        .p_bindings = layouts.ptr,
        .flags = info_flags,
        .p_next = &flags_info,
    };

    return try device.logical_device.createDescriptorSetLayout(&info, null);
}

pub fn vlk_create_set_layout(device: *vlk_device, set: []const vk.DescriptorSetLayoutBinding) !vk.DescriptorSetLayout {
    const infos = create_set_info(set);
    return try device.logical_device.createDescriptorSetLayout(&infos, null);
}

pub fn mth_to_vk_transform_matrix(m: mth.mat4) vk.TransformMatrixKHR {
    return .{
        .matrix = .{
            .{ m[0][0], m[0][1], m[0][2], m[0][3] },
            .{ m[1][0], m[1][1], m[1][2], m[1][3] },
            .{ m[2][0], m[2][1], m[2][2], m[2][3] },
        },
    };
}

pub fn fps_to_ms(fps: u32) f64 {
    if (fps == 0) return 0.0;
    return 1000.0 / @as(f64, @floatFromInt(fps));
}

pub fn ms_to_fps(ms: i64) f64 {
    if (ms == 0) return 0.0;
    return 1000.0 / @as(f64, @floatFromInt(ms));
}

pub fn Register(comptime Type: type) type {
    return struct {
        pub const Self = @This();
        pub const Storage = std.ArrayList(Type);
        pub const Handle = HandleType(Type);
        storage: Storage,

        pub fn init() Self {
            return .{ .storage = .empty };
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            self.storage.deinit(allocator);
        }

        pub fn append(self: *Self, allocator: std.mem.Allocator, value: Type) !Handle {
            const index = @as(u32, @intCast(self.storage.items.len));
            try self.storage.append(allocator, value);
            return .{ .value = index };
        }

        pub fn set(self: *Self, handle: Handle, value: Type) void {
            self.storage.items[handle.value] = value;
        }

        pub fn get(self: *Self, handle: Handle) *Type {
            return &self.storage.items[handle.value];
        }
    };
}

pub fn vlk_make_semaphore_binary(u: *vlk_unit) !vk.Semaphore {
    const info = vk.SemaphoreCreateInfo{};
    return try u.device.logical_device.createSemaphore(&info, null);
}

pub fn vlk_make_semaphore_timeline(u: *vlk_unit, initial_value: u64) !vk.Semaphore {
    var type_info = vk.SemaphoreTypeCreateInfo{
        .semaphore_type = .timeline,
        .initial_value = initial_value,
    };
    const info = vk.SemaphoreCreateInfo{ .p_next = &type_info };
    return try u.device.logical_device.createSemaphore(&info, null);
}

pub const TextureRegistry = struct {
    const Self = @This();
    const RegisterType = Register(vlk_image);
    pub const Handle = RegisterType.Handle;

    u: *vlk_unit,
    allocator: std.mem.Allocator,
    storage: RegisterType,
    managed: std.ArrayListUnmanaged(bool) = .empty,
    // graph_handles: std.ArrayListUnmanaged(sync.Graph.ResourceHandle) = .empty,

    pub fn init(u: *vlk_unit, allocator: std.mem.Allocator) Self {
        return .{ .u = u, .allocator = allocator, .storage = .init() };
    }

    pub fn deinit(self: *Self) void {
        for (self.storage.storage.items, self.managed.items) |img, is_managed| {
            if (is_managed) img.deinit(&self.u.vma, &self.u.device);
        }
        self.storage.deinit(self.allocator);
        self.managed.deinit(self.allocator);
        // self.graph_handles.deinit(self.allocator);
    }

    fn add(self: *Self, img: vlk_image, is_managed: bool) !Handle {
        const handle = try self.storage.append(self.allocator, img);
        const index = handle.value;

        if (index >= self.managed.items.len) {
            try self.managed.resize(self.allocator, index + 1);
            // try self.graph_handles.resize(self.allocator, index + 1);
        }
        self.managed.items[index] = is_managed;

        // const gh = try graph.register_resource(.{ .image = handle }, .{});
        // self.graph_handles.items[index] = gh;

        return handle;
    }

    pub fn register(
        self: *Self,
        // graph: *sync.Graph,
        format: vk.Format,
        usage_flags: vk.ImageUsageFlags,
        aspect_flags: vk.ImageAspectFlags,
        extent: vk.Extent3D,
        mipmapped: bool,
    ) !Handle {
        const v = try vlk_image.init(&self.u.vma, &self.u.device, format, usage_flags, aspect_flags, extent, mipmapped);
        errdefer v.deinit(&self.u.vma, &self.u.device);
        return self.add(v, true);
    }

    pub fn register_external(self: *Self, img: vlk_image) !Handle {
        return self.add(img, false);
    }

    pub fn replace_external(self: *Self, handle: Handle, new_img: vlk_image) void {
        self.storage.set(handle, new_img);
    }

    pub fn get(self: *Self, handle: Handle) vlk_image {
        return self.storage.get(handle).*;
    }

    // pub fn graph_handle(self: *Self, handle: Handle) sync.Graph.ResourceHandle {
    //     return self.graph_handles.items[handle.value];
    // }
};

pub const sync = struct {
    pub const Resource = union(enum) {
        buffer: struct {
            handle: vk.Buffer,
            size: vk.DeviceSize,
            offset: vk.DeviceSize = 0,
        },

        image: struct {
            handle: vk.Image,
            subresource_range: vk.ImageSubresourceRange,
        },
    };

    pub const SemaphorePool = struct {
        const BATCH = 10;

        pub const AcquiredSemaphore = struct {
            handle: Register(vk.Semaphore).Handle,
            semaphore: vk.Semaphore,
        };

        allocator: std.mem.Allocator,
        unit: *vlk_unit,

        storage: Register(vk.Semaphore),
        free: std.ArrayListUnmanaged(Register(vk.Semaphore).Handle) = .empty,

        pub fn init(allocator: std.mem.Allocator, unit: *vlk_unit) SemaphorePool {
            return .{
                .allocator = allocator,
                .unit = unit,
                .storage = Register(vk.Semaphore).init(),
            };
        }

        pub fn deinit(self: *SemaphorePool) void {
            for (self.storage.storage.items) |sem| {
                self.unit.device.logical_device.destroySemaphore(sem, null);
            }
            self.free.deinit(self.allocator);
            self.storage.deinit(self.allocator);
        }

        fn refill_binary(self: *SemaphorePool) !void {
            var i: u32 = 0;
            while (i < BATCH) : (i += 1) {
                const sem = try vlk_make_semaphore_binary(self.unit);
                const handle = try self.storage.append(self.allocator, sem);
                try self.free.append(self.allocator, handle);
            }
        }

        pub fn acquire_binary(self: *SemaphorePool) !AcquiredSemaphore {
            if (self.free.items.len == 0) try self.refill_binary();
            const handle = self.free.pop().?;
            return .{
                .handle = handle,
                .semaphore = self.storage.get(handle).*,
            };
        }
        pub fn acquire_binary_many(self: *SemaphorePool, allocator: std.mem.Allocator, count: usize) ![]AcquiredSemaphore {
            const storage = try allocator.alloc(AcquiredSemaphore, count);
            for (0..count) |i| {
                storage[i] = try self.acquire_binary();
            }

            return storage;
        }

        pub fn release_binary(self: *SemaphorePool, handle: Register(vk.Semaphore).Handle) !void {
            try self.free.append(self.allocator, handle);
        }
    };

    pub const Access = packed struct {
        read: bool = false,
        write: bool = false,
        pub const none = @This(){};
        pub const r = @This(){ .read = true };
        pub const w = @This(){ .write = true };
        pub const rw = @This(){ .read = true, .write = true };
    };

    pub const UsageState = struct {
        layout: vk.ImageLayout,
        queue_family: u32 = vk.QUEUE_FAMILY_IGNORED,
    };

    pub const Usage = struct {
        access: Access,
        state: UsageState,

        stage_mask: vk.PipelineStageFlags2,
        access_mask: vk.AccessFlags2,
    };

    pub const State = struct {
        last_submission_id: u32 = 0,
        access: Access = .{ .read = false, .write = false },

        stage_mask: vk.PipelineStageFlags2 = .{ .top_of_pipe_bit = true },
        access_mask: vk.AccessFlags2 = .{},

        ustate: UsageState = .{ .layout = .undefined },
    };

    pub const Requirements = struct {
        const Memory = enum {
            none,
            read_after_write,
            write_after_read,
            write_after_write,
        };

        mem: Memory,
        layout_transition: bool,
        queue_transition: bool,

        pub fn from_usage(prev: State, next: Usage) Requirements {
            return .{
                .mem = if (prev.access.write and next.access.write)
                    .write_after_write
                else if (prev.access.read and next.access.write)
                    .write_after_read
                else if (prev.access.write and next.access.read)
                    .read_after_write
                else
                    .none,
                .layout_transition = prev.ustate.layout != next.state.layout,
                .queue_transition = prev.ustate.queue_family != next.state.queue_family,
            };
        }
    };

    pub const Barrier = struct {
        const Kind = union(enum) {
            buf: vk.BufferMemoryBarrier2,
            img: vk.ImageMemoryBarrier2,
            mem: vk.MemoryBarrier2,
        };
        val: Kind,

        fn init(res: sync.Resource, prev: State, next: Usage, req: Requirements) Barrier {
            return switch (res) {
                .buffer => |b| .{
                    .val = .{
                        .buf = .{
                            .s_type = .buffer_memory_barrier_2,
                            .p_next = null,
                            .src_stage_mask = prev.stage_mask,
                            .src_access_mask = prev.access_mask,
                            .dst_stage_mask = next.stage_mask,
                            .dst_access_mask = next.access_mask,
                            .src_queue_family_index = if (req.queue_transition) prev.ustate.queue_family else vk.QUEUE_FAMILY_IGNORED,
                            .dst_queue_family_index = if (req.queue_transition) next.state.queue_family else vk.QUEUE_FAMILY_IGNORED,
                            .buffer = b.handle,
                            .offset = b.offset,
                            .size = b.size,
                        },
                    },
                },
                .image => |handle| blk: {
                    const img = handle.handle;
                    break :blk .{
                        .val = .{
                            .img = .{
                                .s_type = .image_memory_barrier_2,
                                .p_next = null,
                                .src_stage_mask = prev.stage_mask,
                                .src_access_mask = prev.access_mask,
                                .dst_stage_mask = next.stage_mask,
                                .dst_access_mask = next.access_mask,
                                .old_layout = prev.ustate.layout,
                                .new_layout = next.state.layout,
                                .src_queue_family_index = if (req.queue_transition) prev.ustate.queue_family else vk.QUEUE_FAMILY_IGNORED,
                                .dst_queue_family_index = if (req.queue_transition) next.state.queue_family else vk.QUEUE_FAMILY_IGNORED,
                                .image = img,
                                .subresource_range = handle.subresource_range,
                            },
                        },
                    };
                },
            };
        }
    };

    pub const Dependency = struct {
        req: Requirements,
        barier: ?Barrier,
        // semaphore: ?SemaphorePool.AcquiredSemaphore,

        fn init(
            res: sync.Resource,
            res_state: State,
            current_submission: u32,
            next: Usage,
            // pool: *SemaphorePool,
        ) !Dependency {
            const req = Requirements.from_usage(res_state, next);

            const same_submission = res_state.last_submission_id == current_submission;
            const needs_semaphore = !same_submission and req.queue_transition;
            const needs_barrier = (req.mem != .none) or req.layout_transition or req.queue_transition;

            if (needs_semaphore)
                @panic("Resource needing a semaphore is not supported");
            return .{
                .req = req,
                .barier = if (needs_barrier) Barrier.init(res, res_state, next, req) else null,
                // .semaphore = if (needs_semaphore) try pool.acquire_binary() else null,
            };
        }
    };

    pub const Graph = struct {
        pub const ResourceRegister = Register(sync.Resource);
        pub const ResourceHandle = ResourceRegister.Handle;

        allocator: std.mem.Allocator,
        resources: ResourceRegister,
        resource_states: std.ArrayList(State),
        semaphore_pool: *SemaphorePool,
        current_submission: u32 = 0,

        pub fn init(allocator: std.mem.Allocator, semaphore_pool: *SemaphorePool) Graph {
            return .{
                .allocator = allocator,
                .resources = Register(sync.Resource).init(),
                .resource_states = .empty,
                .semaphore_pool = semaphore_pool,
            };
        }

        pub fn deinit(self: *Graph) void {
            self.resources.deinit(self.allocator);
            self.resource_states.deinit(self.allocator);
        }

        pub fn register_resource(self: *Graph, res: sync.Resource, initial: State) !Register(sync.Resource).Handle {
            const handle = try self.resources.append(self.allocator, res);
            const idx = handle.value;
            if (idx >= self.resource_states.items.len) {
                try self.resource_states.resize(self.allocator, idx + 1);
            }
            self.resource_states.items[idx] = initial;
            return handle;
        }

        pub fn register_image(self: *Graph, img: vk.Image, subresource_range: vk.ImageSubresourceRange, initial: State) !Register(sync.Resource).Handle {
            return self.register_resource(.{ .image = .{
                .handle = img,
                .subresource_range = subresource_range,
            } }, initial);
        }

        pub fn use_batch(
            self: *Graph,
            cmd: vk.CommandBufferProxy,
            uses: []const struct { handle: ResourceHandle, next: Usage },
        ) !void {
            var buf_barriers: [32]vk.BufferMemoryBarrier2 = undefined;
            var buf_count: usize = 0;
            var img_barriers: [32]vk.ImageMemoryBarrier2 = undefined;
            var img_count: usize = 0;
            var mem_barriers: [32]vk.MemoryBarrier2 = undefined;
            var mem_count: usize = 0;

            for (uses, 0..) |u, i| {
                const res = self.resources.get(u.handle).*;
                const res_state = &self.resource_states.items[u.handle.value];
                const dep = try Dependency.init(res, res_state.*, self.current_submission, u.next);

                if (dep.barier) |b| {
                    switch (b.val) {
                        .buf => |bb| {
                            if (buf_count >= buf_barriers.len) return error.TooManyBarriers;
                            buf_barriers[buf_count] = bb;
                            buf_count += 1;
                        },
                        .img => |ib| {
                            if (img_count >= img_barriers.len) return error.TooManyBarriers;
                            img_barriers[img_count] = ib;
                            img_count += 1;
                        },
                        .mem => |mb| {
                            if (mem_count >= mem_barriers.len) return error.TooManyBarriers;
                            mem_barriers[mem_count] = mb;
                            mem_count += 1;
                        },
                    }
                }

                res_state.* = .{
                    .last_submission_id = self.current_submission,
                    .access = u.next.access,
                    .stage_mask = u.next.stage_mask,
                    .access_mask = u.next.access_mask,
                    .ustate = u.next.state,
                };
                _ = i;
            }

            if (buf_count != 0 or img_count != 0 or mem_count != 0) {
                const dep_info = vk.DependencyInfo{
                    .s_type = .dependency_info,
                    .p_next = null,
                    .buffer_memory_barrier_count = @intCast(buf_count),
                    .p_buffer_memory_barriers = buf_barriers[0..buf_count].ptr,
                    .image_memory_barrier_count = @intCast(img_count),
                    .p_image_memory_barriers = img_barriers[0..img_count].ptr,
                    .memory_barrier_count = @intCast(mem_count),
                    .p_memory_barriers = mem_barriers[0..mem_count].ptr,
                };
                cmd.pipelineBarrier2(&dep_info);
            }
        }

        pub fn use(
            self: *Graph,
            cmd: vk.CommandBufferProxy,
            handle: ResourceHandle,
            next: Usage,
        ) !void {
            const res = self.resources.get(handle).*;
            const res_state = &self.resource_states.items[handle.value];
            const dep = try Dependency.init(res, res_state.*, self.current_submission, next);

            if (dep.barier) |b| {
                switch (b.val) {
                    .buf => |buf_barrier| {
                        const dep_info = vk.DependencyInfo{
                            .s_type = .dependency_info,
                            .p_next = null,
                            .buffer_memory_barrier_count = 1,
                            .p_buffer_memory_barriers = @ptrCast(&buf_barrier),
                        };
                        cmd.pipelineBarrier2(&dep_info);
                    },
                    .img => |img_barrier| {
                        const dep_info = vk.DependencyInfo{
                            .s_type = .dependency_info,
                            .p_next = null,
                            .image_memory_barrier_count = 1,
                            .p_image_memory_barriers = @ptrCast(&img_barrier),
                        };
                        cmd.pipelineBarrier2(&dep_info);
                    },
                    .mem => |mem_barrier| {
                        const dep_info = vk.DependencyInfo{
                            .s_type = .dependency_info,
                            .p_next = null,
                            .memory_barrier_count = 1,
                            .p_memory_barriers = @ptrCast(&mem_barrier),
                        };
                        cmd.pipelineBarrier2(&dep_info);
                    },
                }
            }
            res_state.* = .{
                .last_submission_id = self.current_submission,
                .access = next.access,
                .stage_mask = next.stage_mask,
                .access_mask = next.access_mask,
                .ustate = next.state,
            };
            // return dep.semaphore;
        }

        pub fn update_resource(self: *Graph, handle: ResourceHandle, res: Resource) void {
            self.resources.storage.items[handle.value] = res;
        }
        pub fn update_state(self: *Graph, handle: ResourceHandle, state: State) void {
            self.resource_states.items[handle.value] = state;
        }

        pub fn advance_submission(self: *Graph) void {
            self.current_submission += 1;
        }
    };
};

const KeyBinding = struct {
    key: sdl.Scancode,
    ctx: *anyopaque,
    action_fn: *const fn (ctx: *anyopaque) void,
    edge_only: bool = false, // fire once per press instead of every frame it's held

    fn fire(self: KeyBinding) void {
        self.action_fn(self.ctx);
    }
};

pub const KeyBindings = struct {
    bindings: std.ArrayList(KeyBinding),
    prev_state: [sdl.c.SDL_SCANCODE_COUNT]bool = @splat(false),

    pub fn init(allocator: std.mem.Allocator) !KeyBindings {
        return .{ .bindings = try std.ArrayList(KeyBinding).initCapacity(allocator, 8) };
    }

    pub fn deinit(self: *KeyBindings, allocator: std.mem.Allocator) void {
        self.bindings.deinit(allocator);
    }

    pub fn bind(
        self: *KeyBindings,
        allocator: std.mem.Allocator,
        key: sdl.Scancode,
        ptr: anytype, // *SomeStruct
        comptime func: fn (@TypeOf(ptr)) void,
        edge_only: bool,
    ) !void {
        const Ptr = @TypeOf(ptr);
        const Wrapper = struct {
            fn call(erased: *anyopaque) void {
                const typed: Ptr = @ptrCast(@alignCast(erased));
                func(typed);
            }
        };
        try self.bindings.append(allocator, .{
            .key = key,
            .ctx = @ptrCast(ptr),
            .action_fn = Wrapper.call,
            .edge_only = edge_only,
        });
    }

    pub fn tick(self: *KeyBindings, key_state: []const bool) void {
        for (self.bindings.items) |binding| {
            const idx = @intFromEnum(binding.key);
            const down = key_state[idx];
            const fire = if (binding.edge_only)
                down and !self.prev_state[idx]
            else
                down;
            if (fire) binding.fire();
        }
        @memcpy(&self.prev_state, key_state[0..self.prev_state.len]);
    }
};

pub fn mat4_to_vk_transform(m: mth.float4x4) vk.TransformMatrixKHR {
    return .{
        .matrix = .{
            .{ m.at(0, 0), m.at(0, 1), m.at(0, 2), m.at(0, 3) },
            .{ m.at(1, 0), m.at(1, 1), m.at(1, 2), m.at(1, 3) },
            .{ m.at(2, 0), m.at(2, 1), m.at(2, 2), m.at(2, 3) },
        },
    };
}

pub const desc = struct {
    pub fn Info(comptime self: vk.DescriptorType) type {
        return switch (self) {
            .sampler,
            .combined_image_sampler,
            .sampled_image,
            .storage_image,
            .input_attachment,
            => vk.DescriptorImageInfo,

            .uniform_texel_buffer,
            .storage_texel_buffer,
            => vk.BufferView,

            .uniform_buffer,
            .storage_buffer,
            .uniform_buffer_dynamic,
            .storage_buffer_dynamic,
            => vk.DescriptorBufferInfo,

            .acceleration_structure_khr => vk.WriteDescriptorSetAccelerationStructureKHR,

            else => unreachable,
        };
    }

    pub fn build_writes(
        comptime kind: vk.DescriptorType,
        dst_set: vk.DescriptorSet,
        binding: u32,
        array_element: u32,
        info: []const Info(kind),
    ) vk.WriteDescriptorSet {
        var w = vk.WriteDescriptorSet{
            .dst_set = dst_set,
            .dst_binding = binding,
            .dst_array_element = array_element,
            .descriptor_count = @intCast(info.len),
            .descriptor_type = kind,
            .p_image_info = undefined,
            .p_buffer_info = undefined,
            .p_texel_buffer_view = undefined,
            .p_next = null,
        };
        switch (Info(kind)) {
            vk.DescriptorImageInfo => w.p_image_info = @ptrCast(info),
            vk.DescriptorBufferInfo => w.p_buffer_info = @ptrCast(info),
            vk.BufferView => w.p_texel_buffer_view = @ptrCast(info),
            vk.WriteDescriptorSetAccelerationStructureKHR => w.p_next = info,
            else => unreachable,
        }
        return w;
    }

    pub fn build_write(
        comptime kind: vk.DescriptorType,
        dst_set: vk.DescriptorSet,
        binding: u32,
        array_element: u32,
        info: *const Info(kind),
    ) vk.WriteDescriptorSet {
        var w = vk.WriteDescriptorSet{
            .dst_set = dst_set,
            .dst_binding = binding,
            .dst_array_element = array_element,
            .descriptor_count = 1,
            .descriptor_type = kind,
            .p_image_info = undefined,
            .p_buffer_info = undefined,
            .p_texel_buffer_view = undefined,
            .p_next = null,
        };
        switch (Info(kind)) {
            vk.DescriptorImageInfo => w.p_image_info = @ptrCast(info),
            vk.DescriptorBufferInfo => w.p_buffer_info = @ptrCast(info),
            vk.BufferView => w.p_texel_buffer_view = @ptrCast(info),
            vk.WriteDescriptorSetAccelerationStructureKHR => w.p_next = info,
            else => unreachable,
        }
        return w;
    }

    pub fn binding_info(kind: vk.DescriptorType, binding: u32, count: u32, stages: vk.ShaderStageFlags) vk.DescriptorSetLayoutBinding {
        return vk.DescriptorSetLayoutBinding{
            .binding = binding,
            .descriptor_type = kind,
            .descriptor_count = count,
            .stage_flags = stages,
        };
    }

    pub fn pool_size(comptime kind: vk.DescriptorType, count: u32) vk.DescriptorPoolSize {
        return .{ .type = kind, .descriptor_count = count };
    }

    pub fn update(
        device: *vlk_device,
        writes: ?[]vk.WriteDescriptorSet,
        copies: ?[]vk.CopyDescriptorSet,
    ) void {
        return device.logical_device.updateDescriptorSets(writes, copies);
    }

    pub fn copy(
        device: *vlk_device,
        copies: []vk.CopyDescriptorSet,
    ) void {
        return update(device, null, copies);
    }

    pub fn write(
        device: *vlk_device,
        writes: []vk.WriteDescriptorSet,
    ) void {
        return update(device, writes, null);
    }

    pub const BindSpec = struct {
        kind: vk.DescriptorType,
        count: u32,
        stages: vk.ShaderStageFlags,
        flags: vk.DescriptorBindingFlags,
    };

    pub fn get_vlk_bindings(comptime bindings: []const BindSpec) [bindings.len]vk.DescriptorSetLayoutBinding {
        var res: [bindings.len]vk.DescriptorSetLayoutBinding = undefined;
        for (bindings, 0..) |b, i| {
            res[i] = binding_info(b.kind, @intCast(i), b.count, b.stages);
        }
        return res;
    }

    pub fn get_vlk_flags(comptime bindings: []const BindSpec) [bindings.len]vk.DescriptorBindingFlags {
        var res: [bindings.len]vk.DescriptorBindingFlags = undefined;
        for (bindings, 0..) |b, i| {
            res[i] = b.flags;
        }
        return res;
    }
    pub fn eql_bindings(a: []const vk.DescriptorSetLayoutBinding, b: []const vk.DescriptorSetLayoutBinding) bool {
        if (a.len != b.len) return false;
        for (a, b) |x, y| {
            if (!std.meta.eql(x, y)) return false;
        }
        return true;
    }
    pub fn eql_flags(lhs: []const vk.DescriptorBindingFlags, rhs: []const vk.DescriptorBindingFlags) bool {
        return std.mem.eql(vk.DescriptorBindingFlags, rhs, lhs);
    }

    pub fn TypedSet(comptime _bindings: []const BindSpec) type {
        return struct {
            pub const bindings = _bindings;
            pub const vlk_bindings = get_vlk_bindings(bindings);
            pub const vlk_flags = get_vlk_flags(bindings);

            pub fn eql(self: @This(), other: anytype) bool {
                return eql_bindings(self.vlk_bindings, other.vlk_bindings) and eql_flags(self.vlk_flags, other.vlk_flags);
            }

            pub const Layout = extern struct {
                handle: vk.DescriptorSetLayout,

                pub fn init(device: *vlk_device) !Layout {
                    // var uses_flags = false;
                    // var requires_update_after_bind = false;

                    // for (bindings) |b| {
                    //     if (@as(u32, @bitCast(b.flags)) != 0) uses_flags = true;
                    //     if (b.flags.update_after_bind_bit) requires_update_after_bind = true;
                    // }

                    // var flags_info = vk.DescriptorSetLayoutBindingFlagsCreateInfo{
                    //     .binding_count = bindings.len,
                    //     .p_binding_flags = &vlk_flags,
                    // };

                    // var create_info = vk.DescriptorSetLayoutCreateInfo{
                    //     .flags = .{},
                    //     .binding_count = bindings.len,
                    //     .p_bindings = &vlk_bindings,
                    //     .p_next = if (uses_flags) &flags_info else null,
                    // };

                    // if (requires_update_after_bind) {
                    //     create_info.flags.update_after_bind_pool_bit = true;
                    // }

                    return .{ .handle = try vlk_create_set_layout_ex(device, &vlk_bindings, &vlk_flags) };
                }
                pub fn deinit(self: Layout, device: *vlk_device) void {
                    device.logical_device.destroyDescriptorSetLayout(self.handle, null);
                }

                pub fn alloc(self: Layout, device: *vlk_device, pool: vk.DescriptorPool, variable_size_alloc_count: ?u32) !Instance {
                    const layouts = [_]vk.DescriptorSetLayout{self.handle};

                    const alloc_info = vk.DescriptorSetAllocateInfo{
                        .descriptor_pool = pool,
                        .descriptor_set_count = 1,
                        .p_set_layouts = &layouts,
                        .p_next = if (variable_size_alloc_count) |count| &vk.DescriptorSetVariableDescriptorCountAllocateInfo{
                            .descriptor_set_count = 1,
                            .p_descriptor_counts = &.{count},
                        } else null,
                    };

                    var handles: [1]vk.DescriptorSet = undefined;
                    try device.logical_device.allocateDescriptorSets(&alloc_info, &handles);

                    return Instance{ .handle = handles[0] };
                }
            };
            pub const Instance = extern struct {
                handle: vk.DescriptorSet,

                pub fn build_write_one(
                    self: Instance,
                    comptime binding_idx: u32,
                    array_element: u32,
                    info: *const Info(bindings[binding_idx].kind),
                ) vk.WriteDescriptorSet {
                    const kind = Info(bindings[binding_idx].kind);
                    return build_write(kind, self.handle, binding_idx, array_element, info);
                }

                pub fn build_write_many(
                    self: Instance,
                    comptime binding_idx: u32,
                    array_element: u32,
                    info: *const Info(bindings[binding_idx].kind),
                ) vk.WriteDescriptorSet {
                    const kind = Info(bindings[binding_idx].kind);
                    return build_write(kind, self.handle, binding_idx, array_element, info);
                }

                pub fn write_one(
                    self: Instance,
                    device: *vlk_device,
                    comptime binding_idx: u32,
                    array_element: u32,
                    info: *const Info(bindings[binding_idx].kind),
                ) void {
                    const kind = bindings[binding_idx].kind;
                    const w = build_write(kind, self.handle, binding_idx, array_element, info);
                    var writes = [_]vk.WriteDescriptorSet{w};
                    desc.write(device, &writes);
                }

                pub fn write_many(
                    self: Instance,
                    device: *vlk_device,
                    comptime binding_idx: u32,
                    array_element: u32,
                    info: []const Info(bindings[binding_idx].kind),
                ) void {
                    const kind = bindings[binding_idx].kind;
                    const w = build_writes(kind, self.handle, binding_idx, array_element, info);
                    var writes = [_]vk.WriteDescriptorSet{w};
                    desc.write(device, &writes);
                }
            };
        };
    }

    pub fn write_sampler(sampler: vk.Sampler) vk.DescriptorImageInfo {
        return .{
            .image_view = .null_handle,
            .image_layout = .undefined,
            .sampler = sampler,
        };
    }

    pub fn get_vlk_bindings_from_sets(comptime sets: []const type) [sets.len][]const vk.DescriptorSetLayoutBinding {
        var res: [sets.len][]const vk.DescriptorSetLayoutBinding = undefined;
        inline for (sets, 0..) |S, i| {
            res[i] = &S.vlk_bindings;
        }
        return res;
    }

    pub fn get_vlk_flags_from_sets(comptime sets: []const type) [sets.len][]const vk.DescriptorBindingFlags {
        var res: [sets.len][]const vk.DescriptorBindingFlags = undefined;
        inline for (sets, 0..) |S, i| {
            res[i] = &S.vlk_flags;
        }
        return res;
    }

    pub fn get_layouts(comptime sets: []const type) struct {
        bindings: [sets.len][]const vk.DescriptorSetLayoutBinding,
        flags: [sets.len][]const vk.DescriptorBindingFlags,
    } {
        return .{
            .bindings = get_vlk_bindings_from_sets(sets),
            .flags = get_vlk_flags_from_sets(sets),
        };
    }
};

pub const vlk_format = struct {
    pub const rgba8: vk.Format = .r8g8b8a8_unorm;
    pub const rgba8_srgb: vk.Format = .r8g8b8a8_srgb;
    pub const bgra8: vk.Format = .b8g8r8a8_unorm;
    pub const bgra8_srgb: vk.Format = .b8g8r8a8_srgb;
    pub const r8: vk.Format = .r8_unorm;
    pub const rg8: vk.Format = .r8g8_unorm;

    pub const rgba16f: vk.Format = .r16g16b16a16_sfloat;
    pub const rgb16f: vk.Format = .r16g16b16_sfloat;
    pub const rg16f: vk.Format = .r16g16_sfloat;
    pub const r16f: vk.Format = .r16_sfloat;

    pub const rgba16: vk.Format = .r16g16b16a16_unorm;
    pub const rg16: vk.Format = .r16g16_unorm;
    pub const r16: vk.Format = .r16_unorm;

    pub const rgba32f: vk.Format = .r32g32b32a32_sfloat;
    pub const rgb32f: vk.Format = .r32g32b32_sfloat;
    pub const rg32f: vk.Format = .r32g32_sfloat;
    pub const r32f: vk.Format = .r32_sfloat;

    pub const r32u: vk.Format = .r32_uint;
    pub const r32i: vk.Format = .r32_sint;
    pub const rg32u: vk.Format = .r32g32_uint;
    pub const rgba32u: vk.Format = .r32g32b32a32_uint;

    pub const r16u: vk.Format = .r16_uint;
    pub const rg16u: vk.Format = .r16g16_uint;
    pub const rgba16u: vk.Format = .r16g16b16a16_uint;
    pub const r8u: vk.Format = .r8_uint;
    pub const rg8u: vk.Format = .r8g8_uint;
    pub const rgba8u: vk.Format = .r8g8b8a8_uint;

    pub const depth32f: vk.Format = .d32_sfloat;
    pub const depth16: vk.Format = .d16_unorm;
    pub const depth24_stencil8: vk.Format = .d24_unorm_s8_uint;
    pub const depth32f_stencil8: vk.Format = .d32_sfloat_s8_uint;

    pub const rg11b10f: vk.Format = .b10g11r11_ufloat_pack32;
    pub const rgb10a2: vk.Format = .a2b10g10r10_unorm_pack32;
    pub const e5bgr9f: vk.Format = .e5b9g9r9_ufloat_pack32;

    pub const bc1_rgb: vk.Format = .bc1_rgb_unorm_block;
    pub const bc1_rgb_srgb: vk.Format = .bc1_rgb_srgb_block;
    pub const bc1_rgba: vk.Format = .bc1_rgba_unorm_block;
    pub const bc1_rgba_srgb: vk.Format = .bc1_rgba_srgb_block;
    pub const bc2: vk.Format = .bc2_unorm_block;
    pub const bc2_srgb: vk.Format = .bc2_srgb_block;
    pub const bc3: vk.Format = .bc3_unorm_block;
    pub const bc3_srgb: vk.Format = .bc3_srgb_block;
    pub const bc4: vk.Format = .bc4_unorm_block;
    pub const bc4_signed: vk.Format = .bc4_snorm_block;
    pub const bc5: vk.Format = .bc5_unorm_block;
    pub const bc5_signed: vk.Format = .bc5_snorm_block;
    pub const bc6h: vk.Format = .bc6h_ufloat_block;
    pub const bc6h_signed: vk.Format = .bc6h_sfloat_block;
    pub const bc7: vk.Format = .bc7_unorm_block;
    pub const bc7_srgb: vk.Format = .bc7_srgb_block;
};

pub const all_shader_stages = vk.ShaderStageFlags{
    .compute_bit = true,

    .raygen_bit_khr = true,
    .miss_bit_khr = true,
    .closest_hit_bit_khr = true,
    .any_hit_bit_khr = true,
    .callable_bit_khr = true,
    .intersection_bit_khr = true,

    .fragment_bit = true,
    .vertex_bit = true,
    .geometry_bit = true,
    .mesh_bit_ext = true,
    .tessellation_evaluation_bit = true,
    .tessellation_control_bit = true,

    .task_bit_ext = true,

    .cluster_culling_bit_huawei = true,
    .subpass_shading_bit_huawei = true,
};

pub const update_after_bind = vk.DescriptorBindingFlags{
    .update_after_bind_bit = true,
};
pub const partialy_bound = vk.DescriptorBindingFlags{
    .partially_bound_bit = true,
    .update_after_bind_bit = true,
};
pub const bindless_flags = vk.DescriptorBindingFlags{
    .partially_bound_bit = true,
    .update_after_bind_bit = true,
    .variable_descriptor_count_bit = true, // valid for only the last think C [] on the last member of a struct
};

pub const StageFlagBuilder = struct {
    state: vk.ShaderStageFlags = .{},

    pub fn vertex(self: @This()) @This() {
        var res = self;
        res.state.vertex_bit = true;
        return res;
    }
    pub fn tessellation_control(self: @This()) @This() {
        var res = self;
        res.state.tessellation_control_bit = true;
        return res;
    }
    pub fn tessellation_evaluation(self: @This()) @This() {
        var res = self;
        res.state.tessellation_evaluation_bit = true;
        return res;
    }
    pub fn geometry(self: @This()) @This() {
        var res = self;
        res.state.geometry_bit = true;
        return res;
    }
    pub fn fragment(self: @This()) @This() {
        var res = self;
        res.state.fragment_bit = true;
        return res;
    }
    pub fn compute(self: @This()) @This() {
        var res = self;
        res.state.compute_bit = true;
        return res;
    }
    pub fn task_ext(self: @This()) @This() {
        var res = self;
        res.state.task_bit_ext = true;
        return res;
    }
    pub fn mesh_ext(self: @This()) @This() {
        var res = self;
        res.state.mesh_bit_ext = true;
        return res;
    }
    pub fn raygen(self: @This()) @This() {
        var res = self;
        res.state.raygen_bit_khr = true;
        return res;
    }
    pub fn any_hit(self: @This()) @This() {
        var res = self;
        res.state.any_hit_bit_khr = true;
        return res;
    }
    pub fn closest_hit(self: @This()) @This() {
        var res = self;
        res.state.closest_hit_bit_khr = true;
        return res;
    }
    pub fn miss(self: @This()) @This() {
        var res = self;
        res.state.miss_bit_khr = true;
        return res;
    }
    pub fn intersection(self: @This()) @This() {
        var res = self;
        res.state.intersection_bit_khr = true;
        return res;
    }
    pub fn callable(self: @This()) @This() {
        var res = self;
        res.state.callable_bit_khr = true;
        return res;
    }
    pub fn cluster_culling_huawei(self: @This()) @This() {
        var res = self;
        res.state.cluster_culling_bit_huawei = true;
        return res;
    }
    pub fn subpass_shading_huawei(self: @This()) @This() {
        var res = self;
        res.state.subpass_shading_bit_huawei = true;
        return res;
    }
    pub fn val(self: @This()) vk.ShaderStageFlags {
        return self.state;
    }
    pub fn all(self: @This()) vk.ShaderStageFlags {
        _ = self;
        return all_shader_stages;
    }
};
pub const shader_stages = StageFlagBuilder{};

pub const ShaderModule = struct {
    mod: vk.ShaderModule,

    pub fn init(device: *vlk_device, spirv: []const u8) !@This() {
        const vk_mod = try device.logical_device.createShaderModule(&.{
            .code_size = spirv.len,
            .p_code = @ptrCast(@alignCast(spirv.ptr)),
        }, null);

        return .{
            .mod = vk_mod,
        };
    }

    pub fn get_stage(self: @This(), entry: [*:0]const u8, stage: vk.ShaderStageFlags) vk.PipelineShaderStageCreateInfo {
        return vlk_shader_stage.init(stage, entry, self.mod, null);
    }

    pub fn deinit(self: @This(), device: *vlk_device) void {
        device.logical_device.destroyShaderModule(self.mod, null);
    }
};
