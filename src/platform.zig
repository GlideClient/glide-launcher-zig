const std = @import("std");
const builtin = @import("builtin");

const platform = switch (builtin.os.tag) {
    .linux => @import("platform/platform_x11.zig"),
    .windows => @import("platform/platform_win.zig"),
    else => @import("platform/platform_nt.zig"),
};

pub fn beginWindowDrag(
    glfw_window: *anyopaque,
    mouse_x: i32,
    mouse_y: i32,
) void {
    platform.pl_beginWindowDrag(glfw_window, mouse_x, mouse_y);
}

pub fn initWindowing(glfw_window: *anyopaque) void {
    platform.pl_initWindowing(glfw_window);
}