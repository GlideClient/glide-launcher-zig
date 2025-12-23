const std = @import("std");
const builtin = @import("builtin");
const ctx = @import("../context.zig");

const c = @cImport({
    @cDefine("GLFW_EXPOSE_NATIVE_WIN32", "1");
    @cInclude("GLFW/glfw3.h");
    @cInclude("GLFW/glfw3native.h");
    @cInclude("windows.h");
});

var prev_wndproc: c.WNDPROC = null;

const TITLEBAR_HEIGHT: i32 = 50;

fn wndProc(
    hwnd: c.HWND,
    msg: u32,
    wparam: usize,
    lparam: isize,
) callconv(.winapi) isize {
    switch (msg) {
        c.WM_NCHITTEST => {
            const x = @as(i16, @intCast(lparam & 0xFFFF));
            const y = @as(i16, @intCast((lparam >> 16) & 0xFFFF));

            var pt = c.POINT{ .x = x, .y = y };
            _ = c.ScreenToClient(hwnd, &pt);

            if (pt.y >= 0 and pt.y < TITLEBAR_HEIGHT and pt.x >= 0 and pt.x < ctx.get().window_width - 144) {
                return c.HTCAPTION;
            }

            return c.HTCLIENT;
        },
        else => {},
    }

    return c.CallWindowProcW(prev_wndproc, hwnd, msg, wparam, lparam);
}

pub fn pl_initWindowing(glfw_window: *anyopaque) void {
    const hwnd = c.glfwGetWin32Window(@ptrCast(glfw_window));
    if (hwnd == null) return;

    const old_proc = c.SetWindowLongPtrW(
        hwnd,
        c.GWLP_WNDPROC,
        @as(c.LONG_PTR, @intCast(@intFromPtr(&wndProc))),
    );

    prev_wndproc = @ptrFromInt(@as(usize, @intCast(old_proc)));

    std.debug.print("Windows windowing initialized (custom hit-test).\n", .{});
}

pub fn pl_beginWindowDrag(
    glfw_window: *anyopaque,
    mouse_x: i32,
    mouse_y: i32,
) void {
    _ = glfw_window;
    _ = mouse_x;
    _ = mouse_y;
    // NO-OP on Windows — dragging is automatic via WM_NCHITTEST
}
