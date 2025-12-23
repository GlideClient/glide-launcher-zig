const std = @import("std");

const c = @import("c.zig").c;
const hash = @import("hash.zig");

const nvg = @import("nanovg");
const gfx = @import("gfx.zig");
const scene = @import("scene.zig");
const RootScene = @import("scene/RootScene.zig");
const ctx = @import("context.zig");
const platform = @import("platform.zig");
const api = @import("web/api.zig");
const json_types = @import("json/types.zig");
const files = @import("file/files.zig");

const initial_width: u32 = 840;
const initial_height: u32 = 480;

fn keyCallback(window: ?*c.GLFWwindow, key: c_int, scancode: c_int, action: c_int, mods: c_int) callconv(.c) void {
    if (key == c.GLFW_KEY_ESCAPE and action == c.GLFW_PRESS) {
        c.glfwSetWindowShouldClose(window, c.GLFW_TRUE);
        return;
    }

    scene.MGR.key(.{
        .key = key,
        .scancode = scancode,
        .action = action,
        .mods = mods,
    });
}

fn mouseButtonCallback(window: ?*c.GLFWwindow, button: c_int, action: c_int, mods: c_int) callconv(.c) void {
    _ = window;
    _ = mods;

    const app_ctx = ctx.get();
    const mouse_button: scene.MouseButton = switch (button) {
        c.GLFW_MOUSE_BUTTON_LEFT => .left,
        c.GLFW_MOUSE_BUTTON_RIGHT => .right,
        c.GLFW_MOUSE_BUTTON_MIDDLE => .middle,
        else => return,
    };

    const pressed = action == c.GLFW_PRESS;

    // Update context state
    switch (mouse_button) {
        .left => app_ctx.mouse_left_down = pressed,
        .right => app_ctx.mouse_right_down = pressed,
        .middle => app_ctx.mouse_middle_down = pressed,
    }

    const w = app_ctx.window_width;

    const mx = app_ctx.mouse_x;
    const my = app_ctx.mouse_y;

    if (mx > 0 and my > 0 and mx <= @as(f64, @floatFromInt(w)) - 114 and my <= 50 and mouse_button == .left and pressed) {
        app_ctx.dragging_titlebar = true;
    } else if (mouse_button == .left) {
        app_ctx.dragging_titlebar = false;
    }

    scene.MGR.mouseButton(.{
        .button = mouse_button,
        .pressed = pressed,
        .x = app_ctx.mouse_x,
        .y = app_ctx.mouse_y,
    });
}

fn cursorPosCallback(window: ?*c.GLFWwindow, xpos: f64, ypos: f64) callconv(.c) void {
    _ = window;

    const app_ctx = ctx.get();
    app_ctx.setMousePos(xpos, ypos);

    scene.MGR.mouseMove(.{
        .x = xpos,
        .y = ypos,
    });
}

fn resizeCallback(window: ?*c.GLFWwindow, width: c_int, height: c_int) callconv(.c) void {
    _ = width;
    _ = height;
    c.glfwSetWindowSize(window, initial_width, initial_height);
}

fn scrollCallback(window: ?*c.GLFWwindow, xoffset: f64, yoffset: f64) callconv(.c) void {
    _ = window;

    scene.MGR.scroll(xoffset,yoffset);
}

fn get_manifest(allocator: std.mem.Allocator) !void {
    var local_manifest_buffer: [4096]u8 = undefined;
    const version_manifest_data: ?[]const u8 = api.fetchFile(allocator, "api/v1/client/manifest.json", "application/json") catch |api_err| blk: {
        std.debug.print("Failed to fetch manifest from API: {}, trying local file...\n", .{api_err});
        break :blk files.readLocalVersionManifest(allocator, &local_manifest_buffer) catch |local_err| {
            std.debug.print("Failed to read local manifest: {}\n", .{local_err});
            break :blk null;
        };
    };

    if (version_manifest_data) |manifest_data| {
        files.writeVersionManifest(allocator, manifest_data) catch |err| {
            std.debug.print("Failed to write manifest: {}\n", .{err});
        };

        const parsed = std.json.parseFromSlice(json_types.VersionManifest, allocator, manifest_data, .{
            .ignore_unknown_fields = true,
        }) catch |err| {
            std.debug.print("Failed to parse manifest: {}\n", .{err});
            return err;
        };
        defer parsed.deinit();

        ctx.get().version_manifest = parsed.value;
        std.debug.print("Version manifest loaded successfully\n", .{});
    } else {
        std.debug.print("Warning: No version manifest available, running without it\n", .{});
    }
}

pub fn main() !void {
    var window: ?*c.GLFWwindow = null;
    var prevt: f64 = 0;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    try files.initFileSystem(allocator);

    // const info = try hash.hashFileSha256("/home/shoroa/Code/MISC/glide-files/libraries/asm/asm.jar");
    // std.debug.print(
    //     "size={d}, sha256={s}\n",
    //     .{ info.size, std.fmt.bytesToHex(info.hash, .lower) },
    // );

    if (c.glfwInit() == c.GLFW_FALSE) {
        return error.GLFWInitFailed;
    }
    defer c.glfwTerminate();
    c.glfwWindowHint(c.GLFW_SCALE_TO_MONITOR, c.GLFW_FALSE);
    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MAJOR, 2);
    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MINOR, 1);
    c.glfwWindowHint(c.GLFW_SAMPLES, 4);
    c.glfwWindowHint(c.GLFW_VISIBLE, c.GLFW_FALSE);
    c.glfwWindowHint(c.GLFW_RESIZABLE, c.GLFW_FALSE);
    c.glfwWindowHint(c.GLFW_DECORATED, c.GLFW_FALSE);

    window = c.glfwCreateWindow(@intCast(initial_width), @intCast(initial_height), "Glide Launcher", null, null);
    if (window == null) {
        return error.GLFWInitFailed;
    }
    defer c.glfwDestroyWindow(window);

    platform.initWindowing(@ptrCast(window));

    _ = c.glfwSetKeyCallback(window, keyCallback);
    _ = c.glfwSetMouseButtonCallback(window, mouseButtonCallback);
    _ = c.glfwSetCursorPosCallback(window, cursorPosCallback);
    _ = c.glfwSetWindowSizeCallback(window, resizeCallback);
    _ = c.glfwSetScrollCallback(window, scrollCallback);

    c.glfwSetWindowSizeLimits(window, initial_width, initial_height, initial_width, initial_height);

    c.glfwMakeContextCurrent(window);
    c.glfwSetWindowSize(window, @intCast(initial_width), @intCast(initial_height));

    if (c.gladLoadGL() == 0) {
        return error.GLADInitFailed;
    }

    var app_ctx = ctx.AppContext.init(allocator, initial_width, initial_height);
    ctx.set(&app_ctx);
    app_ctx.window_handle = window;

    _ = try std.Thread.spawn(.{}, get_manifest, .{allocator});

    try gfx.init(allocator);

    scene.MGR = try scene.SceneManager.init(allocator);
    defer scene.MGR.deinit();

    try scene.MGR.pushNew(RootScene.new);

    c.glfwSwapInterval(1);
    c.glfwShowWindow(window);

    c.glfwSetTime(0);
    prevt = c.glfwGetTime();

    while (c.glfwWindowShouldClose(window) == c.GLFW_FALSE) {
        const t = c.glfwGetTime();
        const dt = t - prevt;
        scene.MGR.update(@floatCast(dt));
        prevt = t;

        const w = app_ctx.window_width;
        const h = app_ctx.window_height;

        const mx = app_ctx.mouse_x;
        const my = app_ctx.mouse_y;

        var win_x: c_int = 0;
        var win_y: c_int = 0;
        c.glfwGetWindowPos(window, &win_x, &win_y);

        const root_x = win_x + @as(c_int, @intFromFloat(mx));
        const root_y = win_y + @as(c_int, @intFromFloat(my));

        var fetch_w: c_int = 0;
        var fetch_h: c_int = 0;
        c.glfwGetFramebufferSize(window, &fetch_w, &fetch_h);

        if (fetch_w != @as(c_int, @intCast(w)) or fetch_h != @as(c_int, @intCast(h))) {
            c.glfwSetWindowSize(window, initial_width, initial_height);
        }

        if (app_ctx.dragging_titlebar) {
            platform.beginWindowDrag(@ptrCast(window), @intCast(root_x), @intCast(root_y));
        }

        c.glViewport(0, 0, @intCast(w), @intCast(h));
        c.glClearColor(0, 0, 0, 0);
        c.glClear(c.GL_COLOR_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT | c.GL_STENCIL_BUFFER_BIT);

        gfx.get().beginFrame();
        scene.MGR.render(gfx.get());
        gfx.get().endFrame();

        c.glfwSwapBuffers(window);
        c.glfwPollEvents();
    }

    c.glfwDestroyWindow(window);
    c.glfwTerminate();
}
