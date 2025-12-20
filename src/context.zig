const std = @import("std");

const c = @import("c.zig").c;

pub const AppContext = struct {
    window_width: u32,
    window_height: u32,
    window_handle: ?*c.GLFWwindow = null,
    pixel_ratio: f32,
    allocator: std.mem.Allocator,

    mouse_x: f64 = 0,
    mouse_y: f64 = 0,
    mouse_left_down: bool = false,
    mouse_right_down: bool = false,
    mouse_middle_down: bool = false,
    dragging_titlebar: bool = false,

    pub fn init(allocator: std.mem.Allocator, width: u32, height: u32) AppContext {
        return .{
            .window_width = width,
            .window_height = height,
            .pixel_ratio = 1.0,
            .allocator = allocator,
        };
    }

    pub fn setWindowSize(self: *AppContext, width: u32, height: u32) void {
        self.window_width = width;
        self.window_height = height;
    }

    pub fn setMousePos(self: *AppContext, x: f64, y: f64) void {
        self.mouse_x = x;
        self.mouse_y = y;
    }

    pub fn closeApp(self: *AppContext) void {
        c.glfwSetWindowShouldClose(self.window_handle, c.GLFW_TRUE);
    }
};

var ctx: ?*AppContext = null;

pub fn set(context: *AppContext) void {
    ctx = context;
}

pub fn get() *AppContext {
    return ctx.?;
}

