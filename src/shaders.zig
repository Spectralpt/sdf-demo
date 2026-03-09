const std = @import("std");
const gl = @import("gl");
const glfw = @import("glfw.zig");

pub fn readFileToString(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const cwd = std.fs.cwd();

    const file = try cwd.openFile(path, .{});
    defer file.close();

    const max_size = 1024 * 1024;
    const content = try file.readToEndAlloc(allocator, max_size);
    return content;
}

pub fn compileShader(allocator: std.mem.Allocator, shader_source: []const u8, shader_type: u32) !u32 {
    const shader = gl.CreateShader(shader_type);
    // std.debug.print("shader source:\n{s}\n", .{shader_source});
    const source_ptr = shader_source.ptr;
    const source_len: i32 = @intCast(shader_source.len);
    gl.ShaderSource(shader, 1, @ptrCast(&source_ptr), @ptrCast(&source_len));
    gl.CompileShader(shader);

    var result: u32 = undefined;
    gl.GetShaderiv(shader, gl.COMPILE_STATUS, @ptrCast(&result));

    if (result == gl.TRUE) return shader;

    var log_size: i32 = undefined;
    gl.GetShaderiv(shader, gl.INFO_LOG_LENGTH, @ptrCast(&log_size));

    const log_buffer: []u8 = try allocator.alloc(u8, @intCast(log_size));
    defer allocator.free(log_buffer);
    gl.GetShaderInfoLog(shader, log_size, null, log_buffer.ptr);

    try std.fs.File.stderr().writeAll(log_buffer);
    return error.shader_compilation_fail;
}

pub fn setupShaderProgram(allocator: std.mem.Allocator, shaders: []const u32) !u32 {
    const shaderProgram = gl.CreateProgram();
    for (shaders) |shader| {
        gl.AttachShader(shaderProgram, shader);
    }
    gl.LinkProgram(shaderProgram);

    for (shaders) |shader| {
        gl.DeleteShader(shader);
    }

    var status: u32 = undefined;
    gl.GetProgramiv(shaderProgram, gl.LINK_STATUS, @ptrCast(&status));
    if (status == gl.TRUE) return shaderProgram;

    var log_size: i32 = undefined;
    gl.GetProgramiv(shaderProgram, gl.INFO_LOG_LENGTH, @ptrCast(&log_size));

    const log_buffer: []u8 = try allocator.alloc(u8, @intCast(log_size));
    defer allocator.free(log_buffer);
    gl.GetProgramInfoLog(shaderProgram, log_size, null, log_buffer.ptr);

    try std.fs.File.stderr().writeAll(log_buffer);
    return error.shader_program_link_fail;
}

test "compileBasicShaderPass" {
    const expect = std.testing.expect;

    if (glfw.Init() == 0) return error.GlfwInitFailed;
    defer glfw.Terminate();

    glfw.WindowHint(glfw.VISIBLE, glfw.FALSE);

    const window = glfw.CreateWindow(1, 1, "test", null, null) orelse return error.WindowCreateFailed;
    defer glfw.DestroyWindow(window);

    glfw.MakeContextCurrent(window);

    // Load the GL proc table
    var procs: gl.ProcTable = undefined;
    if (!procs.init(glfw.GetProcAddress)) return error.GlInitFailed;
    gl.makeProcTableCurrent(&procs);
    defer gl.makeProcTableCurrent(null);

    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const fs_source =
        \\#version 330 core
        \\out vec4 FragColor;
        \\void main()
        \\{
        \\    FragColor = vec4(0.584f, 0.698f, 0.722f, 1.0f);
        \\}
    ;

    const shader = try compileShader(allocator, fs_source, gl.FRAGMENT_SHADER);
    try expect(shader != 0);
}

test "compileBasicShaderFail" {
    if (glfw.Init() == 0) return error.GlfwInitFailed;
    defer glfw.Terminate();

    glfw.WindowHint(glfw.VISIBLE, glfw.FALSE);

    const window = glfw.CreateWindow(1, 1, "test", null, null) orelse return error.WindowCreateFailed;
    defer glfw.DestroyWindow(window);

    glfw.MakeContextCurrent(window);

    // Load the GL proc table
    var procs: gl.ProcTable = undefined;
    if (!procs.init(glfw.GetProcAddress)) return error.GlInitFailed;
    gl.makeProcTableCurrent(&procs);
    defer gl.makeProcTableCurrent(null);

    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const fs_source =
        \\#version 330 core
        \\out vec4 FragColor;
        \\void main()
        \\{
        \\    FragColor = vec4(0.584f, 0.698f, 0.722f, 1.0f)
        \\}
    ;

    try std.testing.expectError(error.shader_compilation_fail, compileShader(allocator, fs_source, gl.FRAGMENT_SHADER));
}

test "createShaderProgram" {
    const expect = std.testing.expect;
    if (glfw.Init() == 0) return error.GlfwInitFailed;
    defer glfw.Terminate();

    glfw.WindowHint(glfw.VISIBLE, glfw.FALSE);

    const window = glfw.CreateWindow(1, 1, "test", null, null) orelse return error.WindowCreateFailed;
    defer glfw.DestroyWindow(window);

    glfw.MakeContextCurrent(window);

    // Load the GL proc table
    var procs: gl.ProcTable = undefined;
    if (!procs.init(glfw.GetProcAddress)) return error.GlInitFailed;
    gl.makeProcTableCurrent(&procs);
    defer gl.makeProcTableCurrent(null);

    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const fs_source =
        \\#version 330 core
        \\out vec4 FragColor;
        \\void main()
        \\{
        \\    FragColor = vec4(0.584f, 0.698f, 0.722f, 1.0f);
        \\}
    ;

    const shader = try compileShader(allocator, fs_source, gl.FRAGMENT_SHADER);
    const shaders = [_]u32{shader};
    const program = try setupShaderProgram(allocator, shaders[0..]);
    try expect(program != 0);
}
