const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{ .default_target = .{} });
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "emma",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const shader_step = b.step("shaders", "Compile shaders");
    const compile_shader = b.addSystemCommand(&.{
        "slangc",
        "-O3",
        "src/shaders/hw_raytracing/main.slang",
        "-o",
        "src/shaders/hw_raytracing/shader.spv",
    });

    compile_shader.setName("slangc");
    shader_step.dependOn(&compile_shader.step);
    exe.step.dependOn(&compile_shader.step);
    b.getInstallStep().dependOn(&compile_shader.step);

    const mth = b.addModule("mth", .{
        .root_source_file = b.path("src/mth.zig"),
        .target = target,
        .optimize = optimize,
    });

    const emma = b.addModule("emma", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const vkxml = b.path("vk_deps/vk.xml");
    const vulkan = b.dependency("vulkan", .{
        .target = target,
        .optimize = optimize,
        .registry = vkxml,
    });
    const sdl3 = b.dependency("sdl3", .{
        .target = target,
        .optimize = optimize,
        .callbacks = false,
    });
    // const zigimg = b.dependency("zigimg", .{
    //     .target = target,
    //     .optimize = optimize,
    // });
    const obj_mod = b.dependency("obj", .{ .target = target, .optimize = optimize }).module("obj");

    exe.addCSourceFile(.{
        .file = b.path("vk_deps/tinyexr/tinyexr.cc"),
    });
    exe.addCSourceFile(.{
        .file = b.path("vk_deps/tinyexr/miniz.c"),
    });
    exe.addCSourceFile(.{
        .file = b.path("vk_deps/cxx_vma/vma.cpp"),
    });

    // exe.root_module.addImport("zigimg", zigimg.module("zigimg"));
    exe.root_module.addImport("emma", emma);
    exe.linkLibCpp();
    // exe.linkSystemLibrary("vma");
    exe.linkSystemLibrary("vulkan");
    exe.linkSystemLibrary("sdl3");
    exe.linkSystemLibrary("z");
    // exe.addLibraryPath(b.path("vk_deps/cxx_vma"));

    emma.addImport("mth", mth);
    emma.addImport("obj", obj_mod);
    emma.addImport("vulkan", vulkan.module("vulkan-zig"));
    emma.addImport("sdl3", sdl3.module("sdl3"));
    emma.addIncludePath(b.path("vk_deps/tinyexr"));
    emma.addIncludePath(b.path("vk_deps/cxx_vma"));

    b.installArtifact(exe);
    const run_exe = b.addRunArtifact(exe);
    {
        const run_step = b.step("run", "Run the application");
        run_step.dependOn(&run_exe.step);
    }
}
