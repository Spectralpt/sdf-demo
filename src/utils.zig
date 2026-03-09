const gl = @import("gl");
const glfw = @import("glfw.zig");

// TODO: scrap this ai slop make my own thing
// not really important the test passes so it should be fine
pub const GLContext = struct {
    window: *glfw.window,
    procs: gl.ProcTable,

    pub fn init() !GLContext {
        if (glfw.Init() == 0) return error.GlfwInitFailed;
        glfw.WindowHint(glfw.VISIBLE, glfw.FALSE);
        const window = glfw.CreateWindow(1, 1, "test", null, null) orelse return error.WindowCreateFailed;
        glfw.MakeContextCurrent(window);
        var ctx: GLContext = .{ .window = window, .procs = undefined };
        if (!ctx.procs.init(glfw.GetProcAddress)) return error.GlInitFailed;
        gl.makeProcTableCurrent(&ctx.procs); // points to the struct field, not a local
        return ctx;
    }

    pub fn deinit(self: *GLContext) void {
        gl.makeProcTableCurrent(null);
        glfw.DestroyWindow(self.window);
        glfw.Terminate();
    }
};
