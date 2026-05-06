const scene = @import("../scene.zig");
const state = @import("../state.zig");
const gl = @import("gl");
const utils = @import("../utils.zig");
const shaders = @import("../shaders.zig");
const std = @import("std");

pub fn init(allocator: std.mem.Allocator) !scene.Scene {
    const vert_path = "../../shaders/shader.vert";
    const vert_source = try shaders.readFileToString(allocator, vert_path);
    defer allocator.free(vert_source);
    const compiled_vert = try shaders.compileShader(allocator, vert_source, gl.VERTEX_SHADER);

    const frag_path = "../../shaders/cook-torrance.frag";
    const frag_source = try shaders.readFileToString(allocator, frag_path);
    defer allocator.free(frag_source);
    const compiled_frag = try shaders.compileShader(allocator, frag_source, gl.FRAGMENT_SHADER);

    const shader_program = try shaders.setupShaderProgram(allocator, &.{ compiled_vert, compiled_frag });

    const texture_paths = &[_][:0]const u8{
        "textures/WoodFloor/Color.png",
        "textures/WoodFloor/Roughness.png",
        "textures/WoodFloor/Displacement.png",
        "textures/Onyx/Color.png",
        "textures/Onyx/Roughness.png",
        "textures/Onyx/Displacement.png",
        "textures/Tiles/Color.png",
        "textures/Tiles/Roughness.png",
        "textures/Tiles/Displacement.png",
    };

    const texture_names = &[_][:0]u8{
        "u_ground",
        "u_ground_roughness",
        "u_ground_disp",
        "u_onyx",
        "u_onyx_roughness",
        "u_onyx_displacement",
        "u_tile",
        "u_tile_roughness",
        "u_tile_displacement",
    };

    const textures = try allocator.alloc(u32, texture_paths.len);
    errdefer allocator.free(textures);

    gl.GenTextures(texture_paths.len, textures.ptr);

    const self: scene.Scene = .{
        .name = "scene1",
        .shader_program = shader_program,
        .texture_names = texture_names,
        .textures = textures,
    };

    for (texture_paths, 1..) |path, i| {
        try utils.loadTexture(path, @intCast(i));
    }

    return self;
}
