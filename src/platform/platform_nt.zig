const std = @import("std");

pub fn pl_initWindowing(glfw_window: *anyopaque) void {
    _ = glfw_window;
    std.debug.print("Windowing initialization not required on this platform.\n", .{});
}

pub fn pl_beginWindowDrag(_: *anyopaque, _: i32, _: i32) void {
    std.debug.print("Window dragging not implemented on this platform.\n", .{});
}