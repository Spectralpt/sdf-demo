const c = @cImport({
    @cInclude("GLFW/glfw3.h");
});

pub const Init = c.glfwInit;
pub const Terminate = c.glfwTerminate;
pub const CreateWindow = c.glfwCreateWindow;
pub const DestroyWindow = c.glfwDestroyWindow;
pub const MakeContextCurrent = c.glfwMakeContextCurrent;
pub const WindowShouldClose = c.glfwWindowShouldClose;
pub const PollEvents = c.glfwPollEvents;
pub const SwapBuffers = c.glfwSwapBuffers;
pub const GetProcAddress = c.glfwGetProcAddress;
pub const WindowHint = c.glfwWindowHint;

pub const RESIZABLE = c.GLFW_RESIZABLE;
pub const FLOATING = c.GLFW_FLOATING;
pub const VISIBLE = c.GLFW_VISIBLE;
pub const FALSE = c.GLFW_FALSE;

pub const window = c.GLFWwindow;
