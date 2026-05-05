const c = @cImport({
    @cInclude("dcimgui.h");
});

const mouse_state = struct {
    first_mouse: bool,
    is_captured: bool,
    imgui_wants_mouse: bool,
    moved: bool,
    lmb_pressed: bool,
    last_x: f64,
    last_y: f64,
};

const imgui_state = struct {
    window_size: c.ImVec2,
    window_pos: c.ImVec2,
    is_active: bool = false,
};

const scene_state = struct {
    cam_pos: [3]f32,
    yaw: f32,
    pitch: f32,
};

const metrics_state = struct {
    ms_per_frame: f64,
    last_time: f64,
};

const renderer_state = struct {
    total_accumulated_frames: u32,
    should_reset_accumulation: bool,
    current_scene: c_int,
    want_to_save: bool,
};

const app_state = struct {
    mouse: mouse_state = .{},
    imgui: imgui_state = .{},
    scene: scene_state = .{},
    metrics: metrics_state = .{},
    renderer: renderer_state = .{},
};
