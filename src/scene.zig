const shaders = @import("shaders.zig");
const gl = @import("gl");
const std = @import("std");
const c = @cImport({
    @cInclude("GLFW/glfw3.h");
});

pub const Scene = struct {
    frag_shader: [100]u8,
    uniforms: [20]*const fn () !void,
};
