const c = @import("c.zig").c;
const state = @import("state.zig");
const utils = @import("utils.zig");
const std = @import("std");
const scene = @import("scene.zig");

// TODO: maybe put frag path in appstate idk man ill figure it out
// light temperature is also fucked gg, will fix later:tm:
pub fn render(appState: *state.app_state, allocator: std.mem.Allocator, scenes: []const scene.Scene) !void {
    // const imgui_io = c.ImGui_GetIO();
    c.cImGui_ImplOpenGL3_NewFrame();
    c.cImGui_ImplGlfw_NewFrame();
    c.ImGui_NewFrame();

    c.ImGui_SetNextWindowSize(appState.imgui.window_size, c.ImGuiCond_FirstUseEver);
    c.ImGui_SetNextWindowPos(appState.imgui.window_pos, c.ImGuiCond_FirstUseEver);
    _ = c.ImGui_Begin("Demos", &appState.imgui.is_active, c.ImGuiWindowFlags_NoSavedSettings);
    if (c.ImGui_Button("Save Render")) {
        appState.renderer.want_to_save = true;
        var w: c_int = 0;
        var h: c_int = 0;
        c.glfwGetFramebufferSize(appState.window, &w, &h);

        // Note: In Zig, error handling in UI callbacks can be tricky.
        // We use 'catch' to prevent a crash if the disk is full.
        utils.saveScreenshot(allocator, w, h, appState.renderer.total_accumulated_frames) catch |err| {
            std.log.err("Failed to save screenshot: {}", .{err});
        };
    }
    const current_idx = @as(usize, @intCast(appState.renderer.current_scene));
    const preview_name = scenes[current_idx].name.ptr;
    if (c.ImGui_BeginCombo(" ", preview_name, 0)) {
        for (scenes, 0..) |s, i| {
            if (c.ImGui_Selectable(s.name.ptr)) {
                appState.renderer.current_scene = @intCast(i);
                appState.renderer.total_accumulated_frames = 0;
            }
        }
        c.ImGui_EndCombo();
    }
    c.ImGui_Spacing();

    c.ImGui_SeparatorText("Metrics");
    c.ImGui_Text("Frame: %d", appState.renderer.total_accumulated_frames);
    c.ImGui_Text("Frame time: %.2f ms", appState.metrics.ms_per_frame);

    c.ImGui_SeparatorText("Position");
    c.ImGui_Text("x: %.2f", appState.scene.state.cam_pos[0]);
    c.ImGui_Text("y: %.2f", appState.scene.state.cam_pos[1]);
    c.ImGui_Text("z: %.2f", appState.scene.state.cam_pos[2]);
    c.ImGui_Text("yaw: %.2f", appState.scene.state.yaw);
    c.ImGui_Text("pitch: %.2f", appState.scene.state.pitch);

    c.ImGui_Spacing();
    c.ImGui_Spacing();
    // if (c.ImGui_SliderInt("Color temperature", @ptrCast(&light_temperature), 1000, 7000)) {
    //     // std.debug.print("temp:{any}\n", .{light_temperature});
    // }
    c.ImGui_End();

    c.ImGui_Render();
}
