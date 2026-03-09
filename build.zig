const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const gl_bindings = @import("zigglgen").generateBindingsModule(b, .{
        .api = .gl,
        .version = .@"4.1",
        .profile = .core,
        .extensions = &.{ .ARB_clip_control, .NV_scissor_exclusive },
    });

    exe_mod.addImport("gl", gl_bindings);

    const exe = b.addExecutable(.{
        .name = "sdf-demos",
        .root_module = exe_mod,
    });

    exe.linkSystemLibrary("glfw3");
    exe.linkLibC();

    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);
    const run_step = b.step("run", "run the app");
    run_step.dependOn(&run_exe.step);

    const shader_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/shaders.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    shader_tests.linkSystemLibrary("glfw3");
    shader_tests.linkLibC();

    shader_tests.root_module.addImport("gl", gl_bindings);

    const run_shader_tests = b.addRunArtifact(shader_tests);
    const test_step = b.step("test", "run tests");
    test_step.dependOn(&run_shader_tests.step);
}
