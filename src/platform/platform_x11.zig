const std = @import("std");

const c = @cImport({
    @cDefine("GLFW_EXPOSE_NATIVE_X11", "1");
    @cInclude("GLFW/glfw3.h");
    @cInclude("GLFW/glfw3native.h");
    @cInclude("X11/Xlib.h");
    @cInclude("X11/Xatom.h");
});

pub fn pl_initWindowing(glfw_window: *anyopaque) void {
    _ = glfw_window;
    std.debug.print("Windowing initialization not required on this platform.\n", .{});
}

pub fn pl_beginWindowDrag(
    glfw_window: *anyopaque,
    mouse_x: i32,
    mouse_y: i32,
) void {
    const display = c.glfwGetX11Display();
    if (display == null) return;

    const window = c.glfwGetX11Window(@ptrCast(glfw_window));
    if (window == 0) return;

    var ev: c.XEvent = undefined;
    ev.xclient.type = c.ClientMessage;
    ev.xclient.window = window;
    ev.xclient.message_type =
    c.XInternAtom(display, "_NET_WM_MOVERESIZE", c.False);
    ev.xclient.format = 32;

    ev.xclient.data.l[0] = mouse_x;
    ev.xclient.data.l[1] = mouse_y;
    ev.xclient.data.l[2] = 8; // _NET_WM_MOVERESIZE_MOVE
    ev.xclient.data.l[3] = 1; // Button1
    ev.xclient.data.l[4] = 0;

    _ = c.XSendEvent(
        display,
        c.DefaultRootWindow(display),
        c.False,
        c.SubstructureRedirectMask | c.SubstructureNotifyMask,
        &ev,
    );
}
