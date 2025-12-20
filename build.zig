const std = @import("std");

/// Compile bundled GLAD (OpenGL loader) and GLFW3
/// No system dependencies required - libraries are compiled from source
fn linkGl(b: *std.Build, exe: *std.Build.Module, dep: *std.Build.Dependency) void {
    // Add GLAD (OpenGL loader) - from the nanovg_zig dependency
    exe.addIncludePath(dep.path("lib/gl2/include"));
    exe.addCSourceFile(.{ .file = dep.path("lib/gl2/src/glad.c"), .flags = &.{} });

    // Add GLFW3 include path - from our project's lib directory
    exe.addIncludePath(b.path("lib/glfw3/include"));

    const target = exe.resolved_target.?;
    const target_os = target.result.os.tag;

    // Platform-specific GLFW compilation
    const glfw_flags = switch (target_os) {
        .linux => &[_][]const u8{"-D_GLFW_X11", "-D_GLFW_EGL"},
        .macos => &[_][]const u8{"-D_GLFW_COCOA"},
        .windows => &[_][]const u8{"-D_GLFW_WIN32"},
        else => &[_][]const u8{"-D_GLFW_X11", "-D_GLFW_EGL"},
    };

    // GLFW core source files (common to all platforms)
    exe.addCSourceFile(.{
        .file = b.path("lib/glfw3/src/init.c"),
        .flags = glfw_flags
    });
    exe.addCSourceFile(.{
        .file = b.path("lib/glfw3/src/context.c"),
        .flags = glfw_flags
    });
    exe.addCSourceFile(.{
        .file = b.path("lib/glfw3/src/input.c"),
        .flags = glfw_flags
    });
    exe.addCSourceFile(.{
        .file = b.path("lib/glfw3/src/monitor.c"),
        .flags = glfw_flags
    });
    exe.addCSourceFile(.{
        .file = b.path("lib/glfw3/src/platform.c"),
        .flags = glfw_flags
    });
    exe.addCSourceFile(.{
        .file = b.path("lib/glfw3/src/window.c"),
        .flags = glfw_flags
    });
    exe.addCSourceFile(.{
        .file = b.path("lib/glfw3/src/vulkan.c"),
        .flags = glfw_flags
    });

    // Platform-specific source files
    switch (target_os) {
        .linux => {
            exe.addCSourceFile(.{
                .file = b.path("lib/glfw3/src/x11_init.c"),
                .flags = glfw_flags
            });
            exe.addCSourceFile(.{
                .file = b.path("lib/glfw3/src/x11_monitor.c"),
                .flags = glfw_flags
            });
            exe.addCSourceFile(.{
                .file = b.path("lib/glfw3/src/x11_window.c"),
                .flags = glfw_flags
            });
            exe.addCSourceFile(.{
                .file = b.path("lib/glfw3/src/xkb_unicode.c"),
                .flags = glfw_flags
            });
            exe.addCSourceFile(.{
                .file = b.path("lib/glfw3/src/posix_module.c"),
                .flags = glfw_flags
            });
            exe.addCSourceFile(.{
                .file = b.path("lib/glfw3/src/posix_thread.c"),
                .flags = glfw_flags
            });
            exe.addCSourceFile(.{
                .file = b.path("lib/glfw3/src/posix_time.c"),
                .flags = glfw_flags
            });
            exe.addCSourceFile(.{
                .file = b.path("lib/glfw3/src/posix_poll.c"),
                .flags = glfw_flags
            });
            exe.addCSourceFile(.{
                .file = b.path("lib/glfw3/src/linux_joystick.c"),
                .flags = glfw_flags
            });
            exe.addCSourceFile(.{
                .file = b.path("lib/glfw3/src/glx_context.c"),
                .flags = glfw_flags
            });
            exe.addCSourceFile(.{
                .file = b.path("lib/glfw3/src/egl_context.c"),
                .flags = glfw_flags
            });
            exe.addCSourceFile(.{
                .file = b.path("lib/glfw3/src/osmesa_context.c"),
                .flags = glfw_flags
            });
            exe.addCSourceFile(.{
                .file = b.path("lib/glfw3/src/null_init.c"),
                .flags = glfw_flags
            });
            exe.addCSourceFile(.{
                .file = b.path("lib/glfw3/src/null_joystick.c"),
                .flags = glfw_flags
            });
            exe.addCSourceFile(.{
                .file = b.path("lib/glfw3/src/null_monitor.c"),
                .flags = glfw_flags
            });
            exe.addCSourceFile(.{
                .file = b.path("lib/glfw3/src/null_window.c"),
                .flags = glfw_flags
            });

            // Link required X11 libraries
            exe.linkSystemLibrary("x11", .{});
            exe.linkSystemLibrary("xrandr", .{});
        },
        .macos => {
            exe.addCSourceFile(.{
                .file = b.path("lib/glfw3/src/cocoa_init.m"),
                .flags = glfw_flags
            });
            exe.addCSourceFile(.{
                .file = b.path("lib/glfw3/src/cocoa_monitor.m"),
                .flags = glfw_flags
            });
            exe.addCSourceFile(.{
                .file = b.path("lib/glfw3/src/cocoa_window.m"),
                .flags = glfw_flags
            });
            exe.addCSourceFile(.{
                .file = b.path("lib/glfw3/src/cocoa_joystick.m"),
                .flags = glfw_flags
            });
            exe.addCSourceFile(.{
                .file = b.path("lib/glfw3/src/cocoa_time.c"),
                .flags = glfw_flags
            });
            exe.addCSourceFile(.{
                .file = b.path("lib/glfw3/src/nsgl_context.m"),
                .flags = glfw_flags
            });
            exe.addCSourceFile(.{
                .file = b.path("lib/glfw3/src/egl_context.c"),
                .flags = glfw_flags
            });
            exe.addCSourceFile(.{
                .file = b.path("lib/glfw3/src/osmesa_context.c"),
                .flags = glfw_flags
            });
            exe.addCSourceFile(.{
                .file = b.path("lib/glfw3/src/posix_thread.c"),
                .flags = glfw_flags
            });
            exe.addCSourceFile(.{
                .file = b.path("lib/glfw3/src/posix_module.c"),
                .flags = glfw_flags
            });

            // macOS frameworks and libraries
            exe.linkFramework("Cocoa", .{});
            exe.linkFramework("OpenGL", .{});
            exe.linkFramework("IOKit", .{});
            exe.linkFramework("CoreFoundation", .{});
        },
        .windows => {
            exe.addCSourceFile(.{
                .file = b.path("lib/glfw3/src/win32_init.c"),
                .flags = glfw_flags
            });
            exe.addCSourceFile(.{
                .file = b.path("lib/glfw3/src/win32_monitor.c"),
                .flags = glfw_flags
            });
            exe.addCSourceFile(.{
                .file = b.path("lib/glfw3/src/win32_window.c"),
                .flags = glfw_flags
            });
            exe.addCSourceFile(.{
                .file = b.path("lib/glfw3/src/win32_joystick.c"),
                .flags = glfw_flags
            });
            exe.addCSourceFile(.{
                .file = b.path("lib/glfw3/src/win32_thread.c"),
                .flags = glfw_flags
            });
            exe.addCSourceFile(.{
                .file = b.path("lib/glfw3/src/win32_time.c"),
                .flags = glfw_flags
            });
            exe.addCSourceFile(.{
                .file = b.path("lib/glfw3/src/win32_module.c"),
                .flags = glfw_flags
            });
            exe.addCSourceFile(.{
                .file = b.path("lib/glfw3/src/wgl_context.c"),
                .flags = glfw_flags
            });
            exe.addCSourceFile(.{
                .file = b.path("lib/glfw3/src/egl_context.c"),
                .flags = glfw_flags
            });
            exe.addCSourceFile(.{
                .file = b.path("lib/glfw3/src/osmesa_context.c"),
                .flags = glfw_flags
            });
            exe.addCSourceFile(.{
                .file = b.path("lib/glfw3/src/null_init.c"),
                .flags = glfw_flags
            });
            exe.addCSourceFile(.{
                .file = b.path("lib/glfw3/src/null_joystick.c"),
                .flags = glfw_flags
            });
            exe.addCSourceFile(.{
                .file = b.path("lib/glfw3/src/null_monitor.c"),
                .flags = glfw_flags
            });
            exe.addCSourceFile(.{
                .file = b.path("lib/glfw3/src/null_window.c"),
                .flags = glfw_flags
            });

            // Windows libraries
            exe.linkSystemLibrary("user32", .{});
            exe.linkSystemLibrary("gdi32", .{});
            exe.linkSystemLibrary("shell32", .{});
            exe.linkSystemLibrary("ole32", .{});
            exe.linkSystemLibrary("opengl32", .{});
        },
        else => {
            // Fallback to minimal X11 for unknown platforms
            exe.addCSourceFile(.{
                .file = b.path("lib/glfw3/src/posix_time.c"),
                .flags = &.{"-D_GLFW_X11"}
            });
        },
    }
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const nanovg_zig = b.dependency("nanovg_zig", .{
        .target = target,
        .optimize = optimize,
    });

    const app_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = false,
    });


    linkGl(b, app_mod, nanovg_zig);
    app_mod.addImport("nanovg", nanovg_zig.module("nanovg"));

    const run = b.step("run", "Run the app");

    const app_exe = b.addExecutable(.{
        .name = "glide_launcher_zig",
        .root_module = app_mod,
    });

    // Windows: Make it a GUI app (no console window)
    if (target.result.os.tag == .windows) {
        app_exe.subsystem = .Windows;
    }

    b.installArtifact(app_exe);

    const run_app = b.addRunArtifact(app_exe);
    if (b.args) |args| run_app.addArgs(args);
    run_app.step.dependOn(b.getInstallStep());

    run.dependOn(&run_app.step);
}
