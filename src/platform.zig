const std = @import("std");
const builtin = @import("builtin");

const PlatformNT = struct {
    pub fn pl_beginWindowDrag(_: *anyopaque, _: i32, _: i32) void {
        std.debug.print("Window dragging not implemented on this platform.\n", .{});
    }
};

const platform = switch (builtin.os.tag) {
    .linux => @import("platform_x11.zig"),
    .windows => @import("platform_win.zig"),
    else => PlatformNT{},
};

pub fn beginWindowDrag(
    glfw_window: *anyopaque,
    mouse_x: i32,
    mouse_y: i32,
) void {
    platform.pl_beginWindowDrag(glfw_window, mouse_x, mouse_y);
}
