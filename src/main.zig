const gl = @import("gl");
const glfw = @import("glfw.zig");
const shaders = @import("shaders.zig");
const std = @import("std");

var procs: gl.ProcTable = undefined;

pub fn main() !void {
    const width: u32 = 1280;
    const height: u32 = 720;

    if (glfw.Init() == 0) return error.GlfwInitFailed;
    defer glfw.Terminate();

    const window = glfw.CreateWindow(width, height, "SDF - Demos", null, null) orelse return error.WindowCreationFailed;
    defer glfw.DestroyWindow(window);

    glfw.MakeContextCurrent(window);
    defer glfw.MakeContextCurrent(null);

    if (!procs.init(glfw.GetProcAddress)) {
        return error.InitFailed;
    }

    gl.makeProcTableCurrent(&procs);
    defer gl.makeProcTableCurrent(null);

    const vertices = [_]f32{
        -1.0, 1.0, 0.0, //top left
        -1.0, -1.0, 0.0, //bottom left
        1.0, -1.0, 0.0, //bottom right
        1.0, 1.0, 0.0, //top right
    };

    const indices = [_]u32{
        0, 1, 2, // 1
        0, 2, 3, // 2
    };

    var VAO: u32 = undefined;
    gl.GenVertexArrays(1, @ptrCast(&VAO));
    gl.BindVertexArray(VAO);

    var VBO: u32 = undefined;
    //create the vbo
    gl.GenBuffers(1, @ptrCast(&VBO));
    //make this the current active vbo
    gl.BindBuffer(gl.ARRAY_BUFFER, VBO);
    //push the data into it
    // NOTE: does static draw imply the shader wont manipulate the vertex data or just that the cpu code wont
    gl.BufferData(gl.ARRAY_BUFFER, @sizeOf(f32) * vertices.len, &vertices, gl.STATIC_DRAW);
    //specify how the data inside the vbo is read
    gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, 3 * @sizeOf(f32), 0);
    //dont really know
    gl.EnableVertexAttribArray(0);

    var EBO: u32 = undefined;
    gl.GenBuffers(1, @ptrCast(&EBO));
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, EBO);
    gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, @sizeOf(u32) * indices.len, &indices, gl.STATIC_DRAW);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const vert_source = try shaders.readFileToString(allocator, "shaders/shader.vert");
    defer allocator.free(vert_source);
    const frag_source = try shaders.readFileToString(allocator, "shaders/sphere-scene.frag");
    defer allocator.free(frag_source);

    const vert = try shaders.compileShader(allocator, vert_source, gl.VERTEX_SHADER);
    const frag = try shaders.compileShader(allocator, frag_source, gl.FRAGMENT_SHADER);

    const shders = [_]u32{ vert, frag };
    const program = try shaders.setupShaderProgram(allocator, shders[0..]);
    // gl.PolygonMode(gl.FRONT_AND_BACK, gl.LINE);

    gl.ClearColor(0.1, 0.1, 0.1, 1);
    while (glfw.WindowShouldClose(window) == 0) {
        glfw.PollEvents();

        gl.Clear(gl.COLOR_BUFFER_BIT);
        gl.Viewport(0, 0, width, height);

        gl.UseProgram(program);
        const uniform_window_size = gl.GetUniformLocation(program, "u_resolution");
        gl.Uniform2f(uniform_window_size, width, height);

        var mouse_x: f64 = undefined;
        var mouse_y: f64 = undefined;
        glfw.GetCursorPos(window, @ptrCast(&mouse_x), @ptrCast(&mouse_y));
        // std.debug.print("x:{any};y:{any}", .{ mouse_x, mouse_y });
        const uniform_mouse_pos = gl.GetUniformLocation(program, "u_mouse");
        gl.Uniform2f(uniform_mouse_pos, @floatCast(mouse_x), @floatCast(mouse_y));

        gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, EBO);
        gl.DrawElements(gl.TRIANGLES, 6, gl.UNSIGNED_INT, 0);

        glfw.SwapBuffers(window);
    }
}
