const shaders = @import("shaders.zig");
const gl = @import("gl");
const std = @import("std");
const c = @cImport({
    @cInclude("GLFW/glfw3.h");
});

pub const AppState = struct {
    width: c_int,
    height: c_int,
    mouse_x: f64,
    mouse_y: f64,
};

pub const Scene = struct {
    name: [*c]const u8,
    frag_path: []const u8,
    program: u32,
    setUniforms: ?*const fn (program: u32) void = null,
};

pub fn setupSphereScene(program: u32, state: *AppState) void {
    const uniform_window_size = gl.GetUniformLocation(program, "u_resolution");
    gl.Uniform2f(uniform_window_size, @floatFromInt(state.width), @floatFromInt(state.height));

    const uniform_mouse_pos = gl.GetUniformLocation(program, "u_mouse");
    gl.Uniform2f(uniform_mouse_pos, @floatCast(state.mouse_x), @floatCast(state.mouse_y));
}

pub fn initScenes(scenes: []Scene, allocator: std.mem.Allocator, vert: u32) !void {
    for (scenes) |*scene| {
        const frag_src = try shaders.readFileToString(allocator, scene.frag_path);
        defer allocator.free(frag_src);
        const frag = try shaders.compileShader(allocator, frag_src, gl.FRAGMENT_SHADER);
        scene.program = try shaders.setupShaderProgram(allocator, &[_]u32{ vert, frag });
    }
}
