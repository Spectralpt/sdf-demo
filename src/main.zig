const gl = @import("gl");
const shaders = @import("shaders.zig");
const std = @import("std");
const zstbi = @import("zstbi");
const utils = @import("utils.zig");
const state = @import("state.zig");
const cli = @import("cli.zig");
const c = @import("c.zig").c;
const ui = @import("ui.zig");
// const Scene = @import("scene.zig");

fn errorCallback(errn: c_int, str: [*c]const u8) callconv(std.builtin.CallingConvention.c) void {
    std.log.err("GLFW Error '{}'': {s}", .{ errn, str });
}

fn cursorPosCallback(window: ?*c.GLFWwindow, xpos: f64, ypos: f64) callconv(std.builtin.CallingConvention.c) void {
    const user_ptr = c.glfwGetWindowUserPointer(window);
    const app = @as(*state.app_state, @ptrCast(@alignCast(user_ptr)));

    if (!app.mouse.is_captured) return;

    if (app.mouse.first_mouse) {
        app.mouse.last_pos[0] = xpos;
        app.mouse.last_pos[1] = ypos;
        app.mouse.first_mouse = false;
        return;
    }

    const x_offset = xpos - app.mouse.last_pos[0];
    const y_offset = app.mouse.last_pos[1] - ypos; // Y is inverted in screen space

    app.mouse.last_pos[0] = xpos;
    app.mouse.last_pos[1] = ypos;

    const sensitivity: f32 = 0.005;
    app.scene.yaw -= @as(f32, @floatCast(x_offset)) * sensitivity;
    app.scene.pitch -= @as(f32, @floatCast(y_offset)) * sensitivity;

    // Constrain pitch (approx 85 degrees)
    if (app.scene.pitch > 1.5) app.scene.pitch = 1.5;
    if (app.scene.pitch < -1.5) app.scene.pitch = -1.5;

    // This flag tells your main loop to reset u_frame and clear the ping-pong buffers
    app.mouse.moved = true;
}

fn mouseButtonCallback(window: ?*c.GLFWwindow, button: c_int, action: c_int, mods: c_int) callconv(std.builtin.CallingConvention.c) void {
    _ = mods;
    if (button == c.GLFW_MOUSE_BUTTON_LEFT) {
        const user_ptr = c.glfwGetWindowUserPointer(window);
        const app = @as(*state.app_state, @ptrCast(@alignCast(user_ptr)));

        if (action == c.GLFW_PRESS) {
            app.mouse.is_captured = true;
            app.mouse.lmb_pressed = true;
            c.glfwSetInputMode(window, c.GLFW_CURSOR, c.GLFW_CURSOR_DISABLED);
            std.debug.print("pressed lmb\n", .{});

            app.mouse.first_mouse = true;
        } else if (action == c.GLFW_RELEASE) {
            app.mouse.is_captured = false;
            app.mouse.lmb_pressed = false; // Resetting the pressed state
            c.glfwSetInputMode(window, c.GLFW_CURSOR, c.GLFW_CURSOR_NORMAL);
        }
    }
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

    var appState = state.app_state{};
    appState.window_title = "SDF Path Tracing";

    // CLI ARGS
    try cli.processArgs(&appState, allocator);

    const GLSL_VERSION = "#version 460";

    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MAJOR, 4);
    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MINOR, 6);
    c.glfwWindowHint(c.GLFW_OPENGL_PROFILE, c.GLFW_OPENGL_CORE_PROFILE);
    appState.window = c.glfwCreateWindow(appState.window_w, appState.window_h, appState.window_title.ptr, null, null);
    if (appState.window == null) {
        return;
    }
    defer c.glfwDestroyWindow(appState.window);

    c.glfwSetWindowUserPointer(appState.window, &appState);

    // Callbacks
    _ = c.glfwSetCursorPosCallback(appState.window, cursorPosCallback);
    _ = c.glfwSetErrorCallback(errorCallback);
    _ = c.glfwSetMouseButtonCallback(appState.window, mouseButtonCallback);

    c.glfwMakeContextCurrent(appState.window);
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
        "shaders/sanity.frag",
        "shaders/cook-torrance.frag",
        "shaders/ct-newScene1.frag",
        "shaders/newScene1.frag",
        "shaders/roughness-scene.frag",
        "shaders/distortion-scene.frag",
        "shaders/simple-sphere.frag",
        "shaders/sphere-scene-pt.frag",
    };
    var programs: [frag_paths.len]u32 = undefined;

    for (frag_paths, 0..) |path, i| {
        const frag_source = try shaders.readFileToString(allocator, path);
        const frag = try shaders.compileShader(allocator, frag_source, gl.FRAGMENT_SHADER);

        const compiled_shaders = [_]u32{ vert, frag };
        programs[i] = try shaders.setupShaderProgram(allocator, compiled_shaders[0..]);

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
        gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA32F, appState.renderer.render_w, appState.renderer.render_h, 0, gl.RGBA, gl.FLOAT, null);
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

    _ = c.cImGui_ImplGlfw_InitForOpenGL(appState.window, true);
    defer c.cImGui_ImplGlfw_Shutdown();

    _ = c.cImGui_ImplOpenGL3_InitEx(GLSL_VERSION);
    defer c.cImGui_ImplOpenGL3_Shutdown();

    // TODO:
    // figure out what to do this these variables
    // probably want to remove rendered frame on the
    // screenshot and video rework
    // spf_frames can maybe go to state
    var spf_frames: u32 = 0;
    var rendered_frame: u32 = 1;

    appState.imgui.is_active = false;
    appState.renderer.current_scene = 0;
    appState.imgui.window_size = .{ .x = 0, .y = 0 };
    appState.renderer.total_accumulated_frames = 0;
    appState.metrics.ms_per_frame = 0;
    appState.renderer.want_to_save = false;
    appState.renderer.current_scene = 0;

    //scene state
    var light_temperature: i32 = 5000;

    appState.metrics.last_time = c.glfwGetTime();
    while (c.glfwWindowShouldClose(appState.window) == 0) {
        c.glfwPollEvents();

        // UI
        try ui.render(&appState, allocator, &frag_paths);

        var width: c_int = 0;
        var height: c_int = 0;
        c.glfwGetFramebufferSize(appState.window, &width, &height);
        gl.Viewport(0, 0, appState.renderer.render_w, appState.renderer.render_h);
        gl.Clear(gl.COLOR_BUFFER_BIT);

        // our rendering

        //uniforms setup
        gl.UseProgram(programs[@intCast(appState.renderer.current_scene)]);
        var mouse_x: f64 = undefined;
        var mouse_y: f64 = undefined;
        c.glfwGetCursorPos(appState.window, @ptrCast(&mouse_x), @ptrCast(&mouse_y));

        const uniform_window_size = gl.GetUniformLocation(programs[@intCast(appState.renderer.current_scene)], "u_resolution");
        // gl.Uniform2f(uniform_window_size, @floatFromInt(width), @floatFromInt(height));
        gl.Uniform2f(uniform_window_size, @floatFromInt(appState.renderer.render_w), @floatFromInt(appState.renderer.render_h));

        const uniform_mouse_pos = gl.GetUniformLocation(programs[@intCast(appState.renderer.current_scene)], "u_mouse");
        gl.Uniform2f(uniform_mouse_pos, @floatCast(mouse_x), @floatCast(mouse_y));

        const current_time: f64 = c.glfwGetTime();
        const uniform_time = gl.GetUniformLocation(programs[@intCast(appState.renderer.current_scene)], "u_time");
        gl.Uniform1f(uniform_time, @floatCast(current_time));

        const uniform_frame = gl.GetUniformLocation(programs[@intCast(appState.renderer.current_scene)], "u_frame");
        gl.Uniform1i(uniform_frame, @intCast(appState.renderer.total_accumulated_frames));

        gl.Uniform1i(gl.GetUniformLocation(programs[@intCast(appState.renderer.current_scene)], "u_spf"), 1);

        const temperatureRGB = utils.kelvinToColor(light_temperature);
        const uniform_temperatureRGB = gl.GetUniformLocation(programs[@intCast(appState.renderer.current_scene)], "u_tempColor");
        gl.Uniform3f(uniform_temperatureRGB, temperatureRGB[0], temperatureRGB[1], temperatureRGB[2]);

        // yaw and pitch
        const uniform_cam_rot = gl.GetUniformLocation(programs[@intCast(appState.renderer.current_scene)], "u_cameraRot");
        gl.Uniform2f(uniform_cam_rot, appState.scene.yaw, appState.scene.pitch);

        //camera position
        const uniform_cam_pos = gl.GetUniformLocation(programs[@intCast(appState.renderer.current_scene)], "u_cameraPos");
        gl.Uniform3fv(uniform_cam_pos, 1, @ptrCast(&appState.scene.cam_pos));

        // --- WASD MOVEMENT LOGIC ---
        const speed: f32 = 0.05; // Adjust this to change movement speed
        var moved_this_frame = false;

        // Forward (W) / Backward (S)
        if (c.glfwGetKey(appState.window, c.GLFW_KEY_W) == c.GLFW_PRESS) {
            appState.scene.cam_pos[0] -= @sin(appState.scene.yaw) * speed;
            appState.scene.cam_pos[2] -= @cos(appState.scene.yaw) * speed;
            moved_this_frame = true;
        }
        if (c.glfwGetKey(appState.window, c.GLFW_KEY_S) == c.GLFW_PRESS) {
            appState.scene.cam_pos[0] += @sin(appState.scene.yaw) * speed;
            appState.scene.cam_pos[2] += @cos(appState.scene.yaw) * speed;
            moved_this_frame = true;
        }
        // Left (A) / Right (D)
        if (c.glfwGetKey(appState.window, c.GLFW_KEY_A) == c.GLFW_PRESS) {
            appState.scene.cam_pos[0] -= @cos(appState.scene.yaw) * speed;
            appState.scene.cam_pos[2] += @sin(appState.scene.yaw) * speed;
            moved_this_frame = true;
        }
        if (c.glfwGetKey(appState.window, c.GLFW_KEY_D) == c.GLFW_PRESS) {
            appState.scene.cam_pos[0] += @cos(appState.scene.yaw) * speed;
            appState.scene.cam_pos[2] -= @sin(appState.scene.yaw) * speed;
            moved_this_frame = true;
        }
        // Up (Space) / Down (Left Shift)
        if (c.glfwGetKey(appState.window, c.GLFW_KEY_SPACE) == c.GLFW_PRESS) {
            appState.scene.cam_pos[1] += speed;
            moved_this_frame = true;
        }
        if (c.glfwGetKey(appState.window, c.GLFW_KEY_LEFT_SHIFT) == c.GLFW_PRESS) {
            appState.scene.cam_pos[1] -= speed;
            moved_this_frame = true;
        }

        // if (frame % 1000 == 0 and frame != 0) {
        //     want_to_save = true;
        // }

        //textures setup
        gl.ActiveTexture(gl.TEXTURE1);
        gl.BindTexture(gl.TEXTURE_2D, textures[0]);
        gl.Uniform1i(gl.GetUniformLocation(programs[@intCast(appState.renderer.current_scene)], "u_ground"), 1);

        gl.ActiveTexture(gl.TEXTURE2);
        gl.BindTexture(gl.TEXTURE_2D, textures[1]);
        gl.Uniform1i(gl.GetUniformLocation(programs[@intCast(appState.renderer.current_scene)], "u_ground_roughness"), 2);

        gl.ActiveTexture(gl.TEXTURE3);
        gl.BindTexture(gl.TEXTURE_2D, textures[2]);
        gl.Uniform1i(gl.GetUniformLocation(programs[@intCast(appState.renderer.current_scene)], "u_ground_disp"), 3);

        gl.ActiveTexture(gl.TEXTURE4);
        gl.BindTexture(gl.TEXTURE_2D, textures[3]);
        gl.Uniform1i(gl.GetUniformLocation(programs[@intCast(appState.renderer.current_scene)], "u_onyx"), 4);

        gl.ActiveTexture(gl.TEXTURE5);
        gl.BindTexture(gl.TEXTURE_2D, textures[4]);
        gl.Uniform1i(gl.GetUniformLocation(programs[@intCast(appState.renderer.current_scene)], "u_onyx_roughness"), 5);

        gl.ActiveTexture(gl.TEXTURE6);
        gl.BindTexture(gl.TEXTURE_2D, textures[5]);
        gl.Uniform1i(gl.GetUniformLocation(programs[@intCast(appState.renderer.current_scene)], "u_onyx_displacement"), 6);

        gl.ActiveTexture(gl.TEXTURE7);
        gl.BindTexture(gl.TEXTURE_2D, textures[6]);
        gl.Uniform1i(gl.GetUniformLocation(programs[@intCast(appState.renderer.current_scene)], "u_tile"), 7);

        gl.ActiveTexture(gl.TEXTURE8);
        gl.BindTexture(gl.TEXTURE_2D, textures[7]);
        gl.Uniform1i(gl.GetUniformLocation(programs[@intCast(appState.renderer.current_scene)], "u_tile_roughness"), 8);

        gl.ActiveTexture(gl.TEXTURE9);
        gl.BindTexture(gl.TEXTURE_2D, textures[8]);
        gl.Uniform1i(gl.GetUniformLocation(programs[@intCast(appState.renderer.current_scene)], "u_tile_displacement"), 9);

        //drawing fbo
        gl.ActiveTexture(gl.TEXTURE0);
        gl.BindTexture(gl.TEXTURE_2D, pass1_textures[current]);
        gl.Uniform1i(gl.GetUniformLocation(programs[@intCast(appState.renderer.current_scene)], "u_pass1"), 0);
        gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, EBO);
        gl.BindFramebuffer(gl.FRAMEBUFFER, fbos[1 - current]);
        const imgui_io = c.ImGui_GetIO();
        if ((appState.mouse.moved or moved_this_frame) and imgui_io.*.WantCaptureMouse == false) {
            const clear_color = [4]f32{ 0.0, 0.0, 0.0, 0.0 };
            gl.ClearBufferfv(gl.COLOR, 0, @ptrCast(&clear_color));

            // Temporarily bind and clear source
            gl.BindFramebuffer(gl.FRAMEBUFFER, fbos[current]);
            gl.ClearBufferfv(gl.COLOR, 0, @ptrCast(&clear_color));

            // Re-bind destination
            gl.BindFramebuffer(gl.FRAMEBUFFER, fbos[1 - current]);
            appState.renderer.total_accumulated_frames = 0;
            appState.mouse.moved = false;
        }
        gl.DrawElements(gl.TRIANGLES, 6, gl.UNSIGNED_INT, 0);
        //invert framebuffer
        current = 1 - current;

        // blit to screen
        gl.BindFramebuffer(gl.FRAMEBUFFER, 0);

        var win_w: c_int = 0;
        var win_h: c_int = 0;
        c.glfwGetFramebufferSize(appState.window, &win_w, &win_h);
        gl.Viewport(0, 0, win_w, win_h); // Shrink viewport for the screen

        gl.UseProgram(mainProg);
        gl.ActiveTexture(gl.TEXTURE0);
        gl.BindTexture(gl.TEXTURE_2D, pass1_textures[current]);
        gl.Uniform1i(gl.GetUniformLocation(mainProg, "u_pass1"), 0);
        gl.Uniform2f(gl.GetUniformLocation(mainProg, "u_resolution"), @floatFromInt(width), @floatFromInt(height));
        gl.DrawElements(gl.TRIANGLES, 6, gl.UNSIGNED_INT, 0);

        if (appState.renderer.want_to_save) {
            utils.saveScreenshot(allocator, win_w, win_h, rendered_frame) catch |err| {
                std.log.err("Failed to save screenshot: {}", .{err});
            };
            rendered_frame += 1;
            appState.renderer.want_to_save = false;

            //temp
            appState.mouse.moved = true;
            light_temperature -= 100;
        }

        //--------

        while (gl.GetError() != gl.NO_ERROR) {
            std.debug.print("OpenGL Error:{any}\n", .{gl.GetError()});
        }
        c.cImGui_ImplOpenGL3_RenderDrawData(c.ImGui_GetDrawData());

        appState.renderer.total_accumulated_frames += 1;
        spf_frames += 1;
        const spf_current_time = c.glfwGetTime();
        if (spf_current_time - appState.metrics.last_time >= 1.0) {
            appState.metrics.ms_per_frame = 1000 / @as(f32, @floatFromInt(spf_frames));
            spf_frames = 0;
            appState.metrics.last_time += 1.0;
        }
        c.glfwSwapBuffers(appState.window);
        // if (light_temperature <= 900) {
        //     std.process.exit(0);
        // }
    }
}
