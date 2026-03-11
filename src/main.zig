const gl = @import("gl");
const shaders = @import("shaders.zig");
const std = @import("std");
// const Scene = @import("scene.zig");

const c = @cImport({
    @cDefine("GLFW_INCLUDE_NONE", "1");
    @cInclude("GLFW/glfw3.h");
    @cInclude("dcimgui.h");
    @cInclude("backends/dcimgui_impl_glfw.h");
    @cInclude("backends/dcimgui_impl_opengl3.h");
});

fn errorCallback(errn: c_int, str: [*c]const u8) callconv(std.builtin.CallingConvention.c) void {
    std.log.err("GLFW Error '{}'': {s}", .{ errn, str });
}

pub fn main() !void {
    var procs: gl.ProcTable = undefined;

    _ = c.glfwSetErrorCallback(errorCallback);

    if (c.glfwInit() != c.GLFW_TRUE) {
        return;
    }
    defer c.glfwTerminate();

    const GLSL_VERSION = "#version 410";
    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MAJOR, 3);
    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MINOR, 0);

    const window = c.glfwCreateWindow(1280, 720, "SDF - Demos", null, null);
    if (window == null) {
        return;
    }
    defer c.glfwDestroyWindow(window);

    c.glfwMakeContextCurrent(window);
    c.glfwSwapInterval(1);

    if (!procs.init(c.glfwGetProcAddress)) return error.InitFailed;

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
    const vert = try shaders.compileShader(allocator, vert_source, gl.VERTEX_SHADER);

    const frag_paths = [_][:0]const u8{ "shaders/sphere-scene.frag", "shaders/shader.frag" };
    var programs: [frag_paths.len]u32 = undefined;

    for (frag_paths, 0..) |path, i| {
        const frag_source = try shaders.readFileToString(allocator, path);
        const frag = try shaders.compileShader(allocator, frag_source, gl.FRAGMENT_SHADER);

        const shders = [_]u32{ vert, frag };
        programs[i] = try shaders.setupShaderProgram(allocator, shders[0..]);

        defer allocator.free(frag_source);
    }

    _ = c.CIMGUI_CHECKVERSION();
    _ = c.ImGui_CreateContext(null);
    defer c.ImGui_DestroyContext(null);

    const imio = c.ImGui_GetIO();
    imio.*.ConfigFlags = c.ImGuiConfigFlags_NavEnableKeyboard;

    c.ImGui_StyleColorsDark(null);

    _ = c.cImGui_ImplGlfw_InitForOpenGL(window, true);
    defer c.cImGui_ImplGlfw_Shutdown();

    _ = c.cImGui_ImplOpenGL3_InitEx(GLSL_VERSION);
    defer c.cImGui_ImplOpenGL3_Shutdown();

    var is_active = false;
    var current_item: c_int = 0;
    const imgui_window = c.ImVec2{ .x = 300, .y = 100 };
    const imgui_window_pos = c.ImVec2{ .x = 20, .y = 20 };
    gl.ClearColor(0.1, 0.1, 0.1, 1);
    while (c.glfwWindowShouldClose(window) == 0) {
        c.glfwPollEvents();

        // UI
        c.cImGui_ImplOpenGL3_NewFrame();
        c.cImGui_ImplGlfw_NewFrame();
        c.ImGui_NewFrame();

        c.ImGui_SetNextWindowSize(imgui_window, c.ImGuiCond_FirstUseEver);
        c.ImGui_SetNextWindowPos(imgui_window_pos, c.ImGuiCond_FirstUseEver);
        _ = c.ImGui_Begin("Demos", &is_active, c.ImGuiWindowFlags_NoSavedSettings);
        if (c.ImGui_BeginCombo(" ", frag_paths[@intCast(current_item)], 0)) {
            for (frag_paths, 0..) |scene, i| {
                if (c.ImGui_Selectable(scene)) {
                    current_item = @intCast(i);
                }
            }
            c.ImGui_EndCombo();
        }
        c.ImGui_End();

        c.ImGui_Render();

        var width: c_int = 0;
        var height: c_int = 0;
        c.glfwGetFramebufferSize(window, &width, &height);
        gl.Viewport(0, 0, width, height);
        gl.Clear(gl.COLOR_BUFFER_BIT);

        // our rendering
        gl.UseProgram(programs[@intCast(current_item)]);
        var mouse_x: f64 = undefined;
        var mouse_y: f64 = undefined;
        c.glfwGetCursorPos(window, @ptrCast(&mouse_x), @ptrCast(&mouse_y));

        const uniform_window_size = gl.GetUniformLocation(programs[@intCast(current_item)], "u_resolution");
        gl.Uniform2f(uniform_window_size, @floatFromInt(width), @floatFromInt(height));

        const uniform_mouse_pos = gl.GetUniformLocation(programs[@intCast(current_item)], "u_mouse");
        gl.Uniform2f(uniform_mouse_pos, @floatCast(mouse_x), @floatCast(mouse_y));

        gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, EBO);
        gl.DrawElements(gl.TRIANGLES, 6, gl.UNSIGNED_INT, 0);
        //--------

        c.cImGui_ImplOpenGL3_RenderDrawData(c.ImGui_GetDrawData());
        c.glfwSwapBuffers(window);
    }
}
