const gl = @import("gl");
const shaders = @import("shaders.zig");
const std = @import("std");
const zstbi = @import("zstbi");
const utils = @import("utils.zig");
// const Scene = @import("scene.zig");

const c = @cImport({
    @cDefine("GLFW_INCLUDE_NONE", "1");
    @cInclude("GLFW/glfw3.h");
    @cInclude("dcimgui.h");
    @cInclude("backends/dcimgui_impl_glfw.h");
    @cInclude("backends/dcimgui_impl_opengl3.h");
});

const MouseState = struct {
    last_x: f64 = 0.0,
    last_y: f64 = 0.0,
    yaw: f32 = -1.01,
    pitch: f32 = 0.15,
    // cam_pos: [3]f32 = .{ -54.37, -0.10, 39.99 },
    cam_pos: [3]f32 = .{ 0.0, 0.0, 0.0 },
    first_mouse: bool = true,
    is_captured: bool = false,
    moved: bool = false,
    lmb_pressed: bool = false,
};

fn errorCallback(errn: c_int, str: [*c]const u8) callconv(std.builtin.CallingConvention.c) void {
    std.log.err("GLFW Error '{}'': {s}", .{ errn, str });
}

fn cursorPosCallback(window: ?*c.GLFWwindow, xpos: f64, ypos: f64) callconv(std.builtin.CallingConvention.c) void {
    // 1. Get the pointer we attached to the window earlier
    const user_ptr = c.glfwGetWindowUserPointer(window);
    // 2. Cast it back to our Zig struct
    const state = @as(*MouseState, @ptrCast(@alignCast(user_ptr)));

    if (state.is_captured == false) return;

    if (state.first_mouse) {
        state.last_x = xpos;
        state.last_y = ypos;
        state.first_mouse = false;
        return;
    }

    const x_offset = xpos - state.last_x;
    const y_offset = state.last_y - ypos; // Y is inverted in screen space

    state.last_x = xpos;
    state.last_y = ypos;

    const sensitivity: f32 = 0.005;
    state.yaw -= @as(f32, @floatCast(x_offset)) * sensitivity;
    state.pitch -= @as(f32, @floatCast(y_offset)) * sensitivity;

    // Constrain pitch (approx 85 degrees)
    if (state.pitch > 1.5) state.pitch = 1.5;
    if (state.pitch < -1.5) state.pitch = -1.5;

    // This flag tells your main loop to reset u_frame and clear the ping-pong buffers
    state.moved = true;
}

fn mouseButtonCallback(window: ?*c.GLFWwindow, button: c_int, action: c_int, mods: c_int) callconv(std.builtin.CallingConvention.c) void {
    _ = mods;
    if (button == c.GLFW_MOUSE_BUTTON_LEFT) {
        // 1. Get the pointer we attached to the window earlier
        const user_ptr = c.glfwGetWindowUserPointer(window);
        // 2. Cast it back to our Zig struct
        const state = @as(*MouseState, @ptrCast(@alignCast(user_ptr)));
        if (action == c.GLFW_PRESS) {
            state.is_captured = true;
            state.lmb_pressed = true;
            c.glfwSetInputMode(window, c.GLFW_CURSOR, c.GLFW_CURSOR_DISABLED);
            std.debug.print("pressed lmb\n", .{});

            state.first_mouse = true;
        } else if (action == c.GLFW_RELEASE) {
            state.is_captured = false;
            c.glfwSetInputMode(window, c.GLFW_CURSOR, c.GLFW_CURSOR_NORMAL);
        }
    }
}

//temp image saver, ill do my own probably
fn saveScreenshot(allocator: std.mem.Allocator, width: c_int, height: c_int, file_n: u32) !void {
    const w = @as(usize, @intCast(width));
    const h = @as(usize, @intCast(height));
    const stride = w * 3; // 3 bytes per pixel (RGB)
    const total_size = stride * h;

    // 1. Allocate a buffer to hold the pixel data
    const pixels = try allocator.alloc(u8, total_size);
    defer allocator.free(pixels);

    // 2. Read the pixels from the currently active OpenGL Framebuffer
    // We use gl.RGB and gl.UNSIGNED_BYTE to get standard 24-bit color
    gl.ReadPixels(0, 0, width, height, gl.RGB, gl.UNSIGNED_BYTE, pixels.ptr);

    // 3. Flip the image vertically
    // OpenGL's (0,0) is bottom-left, but image files expect (0,0) at top-left
    const half_h = h / 2;
    for (0..half_h) |y| {
        const top_idx = y * stride;
        const bot_idx = (h - 1 - y) * stride;

        for (0..stride) |x| {
            const temp = pixels[top_idx + x];
            pixels[top_idx + x] = pixels[bot_idx + x];
            pixels[bot_idx + x] = temp;
        }
    }

    // 4. Write to a PPM file
    const filename = try std.fmt.allocPrint(allocator, "render/frame-{d:0>3}.ppm", .{file_n});
    const file = try std.fs.cwd().createFile(filename, .{});
    defer file.close();

    // Format the header text into a temporary stack buffer
    var header_buf: [64]u8 = undefined;
    const header = try std.fmt.bufPrint(&header_buf, "P6\n{} {}\n255\n", .{ w, h });

    // Dump the header, then dump the raw pixels directly to the file!
    try file.writeAll(header);
    try file.writeAll(pixels);

    std.debug.print("Screenshot saved to render.ppm!\n", .{});
}

pub fn main() !void {
    var procs: gl.ProcTable = undefined;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    if (c.glfwInit() != c.GLFW_TRUE) {
        return;
    }
    defer c.glfwTerminate();

    // CLI ARGS
    var args = try std.process.argsWithAllocator(allocator);
    var argsArray: std.ArrayList([:0]const u8) = .empty;
    defer argsArray.deinit(allocator);
    defer args.deinit();
    while (args.next()) |arg| {
        try argsArray.append(allocator, arg);
    }

    // if (argsArray.items.len < 5) {
    //     std.debug.print("Usage: sdf-demos <render_w> <render_h> <window_w> <window_h>\n", .{});
    //     return;
    // }

    var render_w: c_int = 1920;
    var render_h: c_int = 1080;

    var window_w: c_int = 1920;
    var window_h: c_int = 1080;

    if (argsArray.items.len >= 5) {
        render_w = try std.fmt.parseInt(c_int, argsArray.items[1], 10);
        render_h = try std.fmt.parseInt(c_int, argsArray.items[2], 10);

        window_w = try std.fmt.parseInt(c_int, argsArray.items[3], 10);
        window_h = try std.fmt.parseInt(c_int, argsArray.items[4], 10);
    }

    const GLSL_VERSION = "#version 460";

    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MAJOR, 4);
    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MINOR, 6);
    c.glfwWindowHint(c.GLFW_OPENGL_PROFILE, c.GLFW_OPENGL_CORE_PROFILE);
    const window = c.glfwCreateWindow(window_w, window_h, "SDF - Demos", null, null);
    if (window == null) {
        return;
    }
    defer c.glfwDestroyWindow(window);

    var mouse_state = MouseState{ .last_x = 0, .last_y = 0 };
    c.glfwSetWindowUserPointer(window, &mouse_state); // Attach the state here

    // Callbacks
    _ = c.glfwSetCursorPosCallback(window, cursorPosCallback);
    _ = c.glfwSetErrorCallback(errorCallback);
    _ = c.glfwSetMouseButtonCallback(window, mouseButtonCallback);

    c.glfwMakeContextCurrent(window);
    c.glfwSwapInterval(1);

    if (!procs.init(c.glfwGetProcAddress)) return error.InitFailed;

    gl.makeProcTableCurrent(&procs);
    defer gl.makeProcTableCurrent(null);

    const version_ptr = gl.GetString(gl.VERSION);
    const version_string = std.mem.span(version_ptr);
    std.debug.print("OpenGL Version:{s}\n", .{version_string orelse "Unknown"});

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

    // Textures
    zstbi.init(allocator);
    defer zstbi.deinit();

    var textures: [9]u32 = undefined;
    gl.GenTextures(9, @ptrCast(&textures));

    const texture_paths = [_][:0]const u8{
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

    for (texture_paths, 1..) |path, i| {
        try utils.loadTexture(path, @intCast(i));
    }

    const vert_source = try shaders.readFileToString(allocator, "shaders/shader.vert");
    defer allocator.free(vert_source);
    const vert = try shaders.compileShader(allocator, vert_source, gl.VERTEX_SHADER);

    //all shaders for pass1
    const frag_paths = [_][:0]const u8{
        "shaders/sanity.frag", //
        "shaders/cook-torrance.frag", //
        "shaders/ct-newScene1.frag", //
        "shaders/newScene1.frag", //
        "shaders/roughness-scene.frag",
        "shaders/distortion-scene.frag",
        "shaders/simple-sphere.frag", //
        "shaders/sphere-scene-pt.frag", //
    };
    var programs: [frag_paths.len]u32 = undefined;

    for (frag_paths, 0..) |path, i| {
        const frag_source = try shaders.readFileToString(allocator, path);
        const frag = try shaders.compileShader(allocator, frag_source, gl.FRAGMENT_SHADER);

        const shders = [_]u32{ vert, frag };
        programs[i] = try shaders.setupShaderProgram(allocator, shders[0..]);

        defer allocator.free(frag_source);
    }

    // main (tone mapping pass)
    const main_source = try shaders.readFileToString(allocator, "shaders/main.frag");
    const mainFS = try shaders.compileShader(allocator, main_source, gl.FRAGMENT_SHADER);
    const mainProg = try shaders.setupShaderProgram(allocator, &[_]u32{ mainFS, vert });
    defer allocator.free(main_source);

    //FRAME BUFFERS
    var fbos: [2]u32 = undefined;
    var pass1_textures: [2]u32 = undefined;
    var current: u32 = 0;

    gl.GenFramebuffers(2, @ptrCast(&fbos));
    gl.GenTextures(2, @ptrCast(&pass1_textures));
    for (0..2) |i| {
        //texture we write to
        gl.BindTexture(gl.TEXTURE_2D, pass1_textures[i]);
        gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA32F, render_w, render_h, 0, gl.RGBA, gl.FLOAT, null);
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);

        //attach texture to framebuffer
        gl.BindFramebuffer(gl.FRAMEBUFFER, fbos[i]);
        gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, pass1_textures[i], 0);
    }
    //cleanup
    gl.BindFramebuffer(gl.FRAMEBUFFER, 0);
    gl.BindTexture(gl.TEXTURE_2D, 0);

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
    const imgui_window = c.ImVec2{ .x = 0, .y = 0 };
    const imgui_window_pos = c.ImVec2{ .x = 20, .y = 20 };
    gl.ClearColor(0.1, 0.1, 0.1, 1);
    var frame: u32 = 0;
    var spf_frames: u32 = 0;
    var seconds_per_frame: f32 = 0;
    var rendered_frame: u32 = 1;
    var want_to_save: bool = false;

    var last_time = c.glfwGetTime();

    //scene state
    var light_temperature: i32 = 5000;
    while (c.glfwWindowShouldClose(window) == 0) {
        c.glfwPollEvents();

        // UI
        c.cImGui_ImplOpenGL3_NewFrame();
        c.cImGui_ImplGlfw_NewFrame();
        c.ImGui_NewFrame();

        c.ImGui_SetNextWindowSize(imgui_window, c.ImGuiCond_FirstUseEver);
        c.ImGui_SetNextWindowPos(imgui_window_pos, c.ImGuiCond_FirstUseEver);
        _ = c.ImGui_Begin("Demos", &is_active, c.ImGuiWindowFlags_NoSavedSettings);
        if (c.ImGui_Button("Save Render")) {
            want_to_save = true;
            var w: c_int = 0;
            var h: c_int = 0;
            c.glfwGetFramebufferSize(window, &w, &h);

            // Note: In Zig, error handling in UI callbacks can be tricky.
            // We use 'catch' to prevent a crash if the disk is full.
            saveScreenshot(allocator, w, h, frame) catch |err| {
                std.log.err("Failed to save screenshot: {}", .{err});
            };
        }
        if (c.ImGui_BeginCombo(" ", frag_paths[@intCast(current_item)], 0)) {
            for (frag_paths, 0..) |scene, i| {
                if (c.ImGui_Selectable(scene)) {
                    current_item = @intCast(i);
                    frame = 0;
                }
            }
            c.ImGui_EndCombo();
        }
        c.ImGui_Spacing();
        c.ImGui_Text("Frame: %d", frame);
        c.ImGui_Text("Frame time: %.2f ms", seconds_per_frame);
        c.ImGui_SeparatorText("Position");
        c.ImGui_Text("x: %.2f", mouse_state.cam_pos[0]);
        c.ImGui_Text("y: %.2f", mouse_state.cam_pos[1]);
        c.ImGui_Text("z: %.2f", mouse_state.cam_pos[2]);
        c.ImGui_Text("yaw: %.2f", mouse_state.yaw);
        c.ImGui_Text("pitch: %.2f", mouse_state.pitch);

        c.ImGui_Spacing();
        c.ImGui_Spacing();
        if (c.ImGui_SliderInt("Color temperature", @ptrCast(&light_temperature), 1000, 7000)) {
            std.debug.print("temp:{any}\n", .{light_temperature});
        }
        c.ImGui_End();

        c.ImGui_Render();

        var width: c_int = 0;
        var height: c_int = 0;
        c.glfwGetFramebufferSize(window, &width, &height);
        gl.Viewport(0, 0, render_w, render_h);
        gl.Clear(gl.COLOR_BUFFER_BIT);

        // our rendering

        //uniforms setup
        gl.UseProgram(programs[@intCast(current_item)]);
        var mouse_x: f64 = undefined;
        var mouse_y: f64 = undefined;
        c.glfwGetCursorPos(window, @ptrCast(&mouse_x), @ptrCast(&mouse_y));

        const uniform_window_size = gl.GetUniformLocation(programs[@intCast(current_item)], "u_resolution");
        // gl.Uniform2f(uniform_window_size, @floatFromInt(width), @floatFromInt(height));
        gl.Uniform2f(uniform_window_size, @floatFromInt(render_w), @floatFromInt(render_h));

        const uniform_mouse_pos = gl.GetUniformLocation(programs[@intCast(current_item)], "u_mouse");
        gl.Uniform2f(uniform_mouse_pos, @floatCast(mouse_x), @floatCast(mouse_y));

        const current_time: f64 = c.glfwGetTime();
        const uniform_time = gl.GetUniformLocation(programs[@intCast(current_item)], "u_time");
        gl.Uniform1f(uniform_time, @floatCast(current_time));

        const uniform_frame = gl.GetUniformLocation(programs[@intCast(current_item)], "u_frame");
        gl.Uniform1i(uniform_frame, @intCast(frame));

        gl.Uniform1i(gl.GetUniformLocation(programs[@intCast(current_item)], "u_spf"), 1);

        const temperatureRGB = utils.kelvinToColor(light_temperature);
        const uniform_temperatureRGB = gl.GetUniformLocation(programs[@intCast(current_item)], "u_tempColor");
        gl.Uniform3f(uniform_temperatureRGB, temperatureRGB[0], temperatureRGB[1], temperatureRGB[2]);

        // yaw and pitch
        const uniform_cam_rot = gl.GetUniformLocation(programs[@intCast(current_item)], "u_cameraRot");
        gl.Uniform2f(uniform_cam_rot, mouse_state.yaw, mouse_state.pitch);

        //camera position
        const uniform_cam_pos = gl.GetUniformLocation(programs[@intCast(current_item)], "u_cameraPos");
        gl.Uniform3fv(uniform_cam_pos, 1, @ptrCast(&mouse_state.cam_pos));

        // --- WASD MOVEMENT LOGIC ---
        const speed: f32 = 0.05; // Adjust this to change movement speed
        var moved_this_frame = false;

        // Forward (W) / Backward (S)
        if (c.glfwGetKey(window, c.GLFW_KEY_W) == c.GLFW_PRESS) {
            mouse_state.cam_pos[0] -= @sin(mouse_state.yaw) * speed;
            mouse_state.cam_pos[2] -= @cos(mouse_state.yaw) * speed;
            moved_this_frame = true;
        }
        if (c.glfwGetKey(window, c.GLFW_KEY_S) == c.GLFW_PRESS) {
            mouse_state.cam_pos[0] += @sin(mouse_state.yaw) * speed;
            mouse_state.cam_pos[2] += @cos(mouse_state.yaw) * speed;
            moved_this_frame = true;
        }
        // Left (A) / Right (D)
        if (c.glfwGetKey(window, c.GLFW_KEY_A) == c.GLFW_PRESS) {
            mouse_state.cam_pos[0] -= @cos(mouse_state.yaw) * speed;
            mouse_state.cam_pos[2] += @sin(mouse_state.yaw) * speed;
            moved_this_frame = true;
        }
        if (c.glfwGetKey(window, c.GLFW_KEY_D) == c.GLFW_PRESS) {
            mouse_state.cam_pos[0] += @cos(mouse_state.yaw) * speed;
            mouse_state.cam_pos[2] -= @sin(mouse_state.yaw) * speed;
            moved_this_frame = true;
        }
        // Up (Space) / Down (Left Shift)
        if (c.glfwGetKey(window, c.GLFW_KEY_SPACE) == c.GLFW_PRESS) {
            mouse_state.cam_pos[1] += speed;
            moved_this_frame = true;
        }
        if (c.glfwGetKey(window, c.GLFW_KEY_LEFT_SHIFT) == c.GLFW_PRESS) {
            mouse_state.cam_pos[1] -= speed;
            moved_this_frame = true;
        }

        // if (frame % 1000 == 0 and frame != 0) {
        //     want_to_save = true;
        // }

        //textures setup
        gl.ActiveTexture(gl.TEXTURE1);
        gl.BindTexture(gl.TEXTURE_2D, textures[0]);
        gl.Uniform1i(gl.GetUniformLocation(programs[@intCast(current_item)], "u_ground"), 1);

        gl.ActiveTexture(gl.TEXTURE2);
        gl.BindTexture(gl.TEXTURE_2D, textures[1]);
        gl.Uniform1i(gl.GetUniformLocation(programs[@intCast(current_item)], "u_ground_roughness"), 2);

        gl.ActiveTexture(gl.TEXTURE3);
        gl.BindTexture(gl.TEXTURE_2D, textures[2]);
        gl.Uniform1i(gl.GetUniformLocation(programs[@intCast(current_item)], "u_ground_disp"), 3);

        gl.ActiveTexture(gl.TEXTURE4);
        gl.BindTexture(gl.TEXTURE_2D, textures[3]);
        gl.Uniform1i(gl.GetUniformLocation(programs[@intCast(current_item)], "u_onyx"), 4);

        gl.ActiveTexture(gl.TEXTURE5);
        gl.BindTexture(gl.TEXTURE_2D, textures[4]);
        gl.Uniform1i(gl.GetUniformLocation(programs[@intCast(current_item)], "u_onyx_roughness"), 5);

        gl.ActiveTexture(gl.TEXTURE6);
        gl.BindTexture(gl.TEXTURE_2D, textures[5]);
        gl.Uniform1i(gl.GetUniformLocation(programs[@intCast(current_item)], "u_onyx_displacement"), 6);

        gl.ActiveTexture(gl.TEXTURE7);
        gl.BindTexture(gl.TEXTURE_2D, textures[6]);
        gl.Uniform1i(gl.GetUniformLocation(programs[@intCast(current_item)], "u_tile"), 7);

        gl.ActiveTexture(gl.TEXTURE8);
        gl.BindTexture(gl.TEXTURE_2D, textures[7]);
        gl.Uniform1i(gl.GetUniformLocation(programs[@intCast(current_item)], "u_tile_roughness"), 8);

        gl.ActiveTexture(gl.TEXTURE9);
        gl.BindTexture(gl.TEXTURE_2D, textures[8]);
        gl.Uniform1i(gl.GetUniformLocation(programs[@intCast(current_item)], "u_tile_displacement"), 9);

        //drawing fbo
        gl.ActiveTexture(gl.TEXTURE0);
        gl.BindTexture(gl.TEXTURE_2D, pass1_textures[current]);
        gl.Uniform1i(gl.GetUniformLocation(programs[@intCast(current_item)], "u_pass1"), 0);
        gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, EBO);
        gl.BindFramebuffer(gl.FRAMEBUFFER, fbos[1 - current]);
        if (mouse_state.moved or moved_this_frame) {
            const clear_color = [4]f32{ 0.0, 0.0, 0.0, 0.0 };
            gl.ClearBufferfv(gl.COLOR, 0, @ptrCast(&clear_color));

            // Temporarily bind and clear source
            gl.BindFramebuffer(gl.FRAMEBUFFER, fbos[current]);
            gl.ClearBufferfv(gl.COLOR, 0, @ptrCast(&clear_color));

            // Re-bind destination
            gl.BindFramebuffer(gl.FRAMEBUFFER, fbos[1 - current]);
            frame = 0;
            mouse_state.moved = false;
        }
        gl.DrawElements(gl.TRIANGLES, 6, gl.UNSIGNED_INT, 0);
        //invert framebuffer
        current = 1 - current;

        // blit to screen
        gl.BindFramebuffer(gl.FRAMEBUFFER, 0);

        var win_w: c_int = 0;
        var win_h: c_int = 0;
        c.glfwGetFramebufferSize(window, &win_w, &win_h);
        gl.Viewport(0, 0, win_w, win_h); // Shrink viewport for the screen

        gl.UseProgram(mainProg);
        gl.ActiveTexture(gl.TEXTURE0);
        gl.BindTexture(gl.TEXTURE_2D, pass1_textures[current]);
        gl.Uniform1i(gl.GetUniformLocation(mainProg, "u_pass1"), 0);
        gl.Uniform2f(gl.GetUniformLocation(mainProg, "u_resolution"), @floatFromInt(width), @floatFromInt(height));
        gl.DrawElements(gl.TRIANGLES, 6, gl.UNSIGNED_INT, 0);

        if (want_to_save) {
            saveScreenshot(allocator, win_w, win_h, rendered_frame) catch |err| {
                std.log.err("Failed to save screenshot: {}", .{err});
            };
            rendered_frame += 1;
            want_to_save = false;

            //temp
            mouse_state.moved = true;
            light_temperature -= 100;
        }

        //--------

        while (gl.GetError() != gl.NO_ERROR) {
            std.debug.print("OpenGL Error:{any}\n", .{gl.GetError()});
        }
        c.cImGui_ImplOpenGL3_RenderDrawData(c.ImGui_GetDrawData());

        frame += 1;
        spf_frames += 1;
        const spf_current_time = c.glfwGetTime();
        if (spf_current_time - last_time >= 1.0) {
            seconds_per_frame = 1000 / @as(f32, @floatFromInt(spf_frames));
            spf_frames = 0;
            last_time += 1.0;
        }
        c.glfwSwapBuffers(window);
        // if (light_temperature <= 900) {
        //     std.process.exit(0);
        // }
    }
}
