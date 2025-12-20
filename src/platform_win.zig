const std = @import("std");

const c = @cImport({
    @cDefine("GLFW_EXPOSE_NATIVE_WIN32", "1");
    @cInclude("GLFW/glfw3.h");
    @cInclude("GLFW/glfw3native.h");
});

pub fn pl_beginWindowDrag(
    glfw_window: *anyopaque,
    mouse_x: i32,
    mouse_y: i32,
) void {
    const hwnd = c.glfwGetWin32Window(@ptrCast(glfw_window));
    if (hwnd == null) return;

    const lparam = (mouse_y << 16) | (mouse_x & 0xFFFF);
    _ = c.PostMessageW(
        hwnd,
        c.WM_NCLBUTTONDOWN,
        c.HTCAPTION,
        lparam,
    );
}