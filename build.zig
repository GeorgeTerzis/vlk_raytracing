const std = @import("std");
const builtin = @import("builtin");

fn add_slang_shader(b: *std.Build, dir: []const u8) *std.Build.Step.Run {
    const src_path = b.pathJoin(&.{ dir, "main.slang" });
    const out_path = b.pathJoin(&.{ dir, "shader.spv" });
    const cmd = b.addSystemCommand(&.{
        "slangc",
        "-O3",
        "-fvk-use-scalar-layout",
        src_path,
        "-o",
        out_path,
    });
    cmd.setName("slangc");
    return cmd;
}

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

    const shader_dirs = [_][]const u8{
        "src/shaders/hw_raytracing",
        "src/shaders/aa",
        "src/shaders/ta",
    };

    const shader_step = b.step("shaders", "Compile shaders");
    for (shader_dirs) |dir| {
        const cmd = add_slang_shader(b, dir);
        shader_step.dependOn(&cmd.step);
        exe.step.dependOn(&cmd.step);
        b.getInstallStep().dependOn(&cmd.step);
    }

    const containers = b.addModule("containers", .{
        .root_source_file = b.path("libs/containers/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const mth = b.addModule("mth", .{
        .root_source_file = b.path("src/mthlib/mth.zig"),
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
    });
    const obj = b.dependency("obj", .{
        .target = target,
        .optimize = optimize,
    });

    const translate_c = b.addTranslateC(.{
        .root_source_file = b.path("src/c.h"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const c_module = translate_c.createModule();

    {
        exe.root_module.addImport("emma", emma);
        exe.root_module.addImport("mth", mth);
        exe.root_module.addImport("containers", containers);
    }

    {
        exe.root_module.linkSystemLibrary("vulkan", .{});
        exe.root_module.linkSystemLibrary("sdl3", .{});
        exe.root_module.linkSystemLibrary("z", .{});
    }
    exe.root_module.link_libcpp = true;

    {
        exe.root_module.addCSourceFile(.{ .file = b.path("vk_deps/tinyexr/tinyexr.cc") });
        exe.root_module.addCSourceFile(.{ .file = b.path("vk_deps/tinyexr/miniz.c") });
        exe.root_module.addCSourceFile(.{ .file = b.path("vk_deps/cxx_vma/vma.cpp") });
    }
    emma.addImport("c_libs", c_module);
    emma.addImport("mth", mth);
    emma.addImport("obj", obj.module("obj"));
    emma.addImport("vulkan", vulkan.module("vulkan-zig"));
    emma.addImport("sdl3", sdl3.module("sdl3"));

    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_exe.step);

    const exe_check = b.addExecutable(.{
        .name = "foo",
        .root_module = exe.root_module,
    });
    const check = b.step("check", "Check if project compiles");
    check.dependOn(&exe_check.step);
}
