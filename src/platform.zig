const std = @import("std");
const builtin = @import("builtin");

const platform = switch (builtin.os.tag) {
    .linux => @import("platform/platform_x11.zig"),
    .windows => @import("platform/platform_win.zig"),
    else => @import("platform/platform_nt.zig"),
};

/// Returns the platform string (e.g., "linux", "windows-x64", "macos-arm64")
pub fn getPlatformString() []const u8 {
    return switch (builtin.os.tag) {
        .linux => switch (builtin.cpu.arch) {
            .x86 => "linux-i386",
            else => "linux",
        },
        .windows => switch (builtin.cpu.arch) {
            .x86 => "windows-x86",
            else => "windows-x64",
        },
        .macos => switch (builtin.cpu.arch) {
            .aarch64 => "macos-arm64",
            else => "macos",
        },
        else => "linux",
    };
}

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