const shaders = @import("shaders.zig");
const gl = @import("gl");
const std = @import("std");
const state = @import("state.zig");
const c = @cImport({
    @cInclude("GLFW/glfw3.h");
});

pub const SceneInitFn = *const fn (std.mem.Allocator) anyerror!Scene;
pub const CamInitFn = *const fn () state.scene_state;

pub const SceneMetadata = struct {
    name: [:0]const u8 = "",
};

pub const Scene = struct {
    textures: []u32,
    texture_names: []const [:0]const u8,
    shader_program: u32 = 0,

    pub fn deinit(self: *Scene, allocator: std.mem.Allocator) !void {
        gl.DeleteTextures(@intCast(self.textures.len), self.textures.ptr);
        allocator.free(self.textures);
        gl.DeleteProgram(self.shader_program);
    }
};

pub const SceneEntry = struct {
    metadata: SceneMetadata,
    init_fn: SceneInitFn,
    init_cam_fn: CamInitFn,
};
