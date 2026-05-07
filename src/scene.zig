const shaders = @import("shaders.zig");
const gl = @import("gl");
const std = @import("std");
const c = @cImport({
    @cInclude("GLFW/glfw3.h");
});

pub const Scene = struct {
    textures: []u32,
    texture_names: []const [:0]const u8,
    shader_program: u32 = 0,
    // vertex_shader: u32 = 0,
    // fragment_shader: u32 = 0,
};

pub const Scene_metadata = struct {
    id: u32 = 0,
    name: [:0]const u8 = "",
};

// TODO: Maybe i take a look at doing a struct that houses the init setup for Scene_setup
// not really sure if this would be THAT usefull
// NOTE: maybe i can even do some init function that could take this struct

// pub const Scene_setup = struct {
//
// };
