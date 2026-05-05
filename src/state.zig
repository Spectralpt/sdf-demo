const c = @import("c.zig").c;

pub const mouse_state = struct {
    first_mouse: bool = false,
    is_captured: bool = false,
    imgui_wants_mouse: bool = false,
    moved: bool = false,
    lmb_pressed: bool = false,
    //0 -> x; 1 -> y
    last_pos: [2]f64 = .{ 0, 0 },
};

pub const imgui_state = struct {
    window_size: c.ImVec2 = .{ .x = 0, .y = 0 },
    window_pos: c.ImVec2 = .{ .x = 0, .y = 0 },
    is_active: bool = false,
};

pub const scene_state = struct {
    cam_pos: [3]f32 = .{ 0, 0, 0 },
    yaw: f32 = 0,
    pitch: f32 = 0,
};

pub const metrics_state = struct {
    ms_per_frame: f64 = 0,
    last_time: f64 = 0,
};

pub const renderer_state = struct {
    total_accumulated_frames: u32 = 0,
    should_reset_accumulation: bool = false,
    current_scene: c_int = 0,
    want_to_save: bool = false,
    render_w: c_int = 0,
    render_h: c_int = 0,
};

pub const app_state = struct {
    mouse: mouse_state = .{},
    imgui: imgui_state = .{},
    scene: scene_state = .{},
    metrics: metrics_state = .{},
    renderer: renderer_state = .{},
    window_w: c_int = 0,
    window_h: c_int = 0,
    window_title: []const u8 = "",
};
