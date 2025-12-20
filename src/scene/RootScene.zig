const std = @import("std");
const scene = @import("../scene.zig");
const gfx = @import("../gfx.zig");
const Icons = @import("../icons.zig").Icons;
const fonts = @import("../fonts.zig");
const images = @import("../images.zig");
const ctx = @import("../context.zig");
const ui = @import("../component/ui.zig");

pub const State = struct {
    allocator: std.mem.Allocator,
    frame_count: u64 = 0,
    fps: u64 = 0,
    dt_count: f32 = 0,
    iconImage: ?gfx.nvg.Image = null,
    bgImage: ?gfx.nvg.Image = null,
    components: std.array_list.Managed(*ui.Component) = undefined,
};

fn pushComponent(state: *State, vdata: anytype, rect: ui.Rect, factory: fn (std.mem.Allocator, anytype, ui.Rect) ?*ui.Component) !void {
    const scn = factory(state.allocator, vdata, rect) orelse return error.ComponentCreationFailed;
    try state.components.append(scn);
    scn.init();
}

fn onLaunchButtonClick(user: ?*anyopaque) void {
    _ = user;
}

fn onCloseButtonClick(user: ?*anyopaque) void {
    _ = user;
    ctx.get().closeApp();
}

fn onSettingsButtonClick(user: ?*anyopaque) void {
    _ = user;
}

fn onAddButtonClick(user: ?*anyopaque) void {
    _ = user;
}

fn onInit(s: *scene.Scene) void {
    const st: *State = @ptrCast(@alignCast(s.vdata.?));

    st.iconImage = gfx.get().createImage(images.images[0], .{ .generate_mipmaps = true }) catch null;
    st.bgImage = gfx.get().createImage(images.images[1], .{ .generate_mipmaps = true }) catch null;

    st.components = std.array_list.Managed(*ui.Component).init(st.allocator);

    pushComponent(st, ui.SimpleButton.VData{
        .pressed = false,
        .text = "Launch Latest",
        .font = fonts.Regular,
        .onClick = &onLaunchButtonClick,
    }, .{
        .x = 20,
        .y = @as(f32, @floatFromInt(ctx.get().window_height)) - 70,
        .width = 240,
        .height = 50,
    }, ui.SimpleButton.new) catch {};

    pushComponent(st, ui.SimpleButton.VData{
        .pressed = false,
        .text = Icons.Fluent.DISMISS_24,
        .text_color = gfx.gray(200),
        .font = fonts.FluentRegular,
        .font_size = 17,
        .onClick = &onCloseButtonClick,
    }, .{
        .x = @as(f32, @floatFromInt(ctx.get().window_width)) - 44,
        .y = 14,
        .width = 30,
        .height = 30,
    }, ui.SimpleButton.new) catch {};

    pushComponent(st, ui.SimpleButton.VData{
        .pressed = false,
        .text = Icons.Fluent.SETTINGS_24,
        .text_color = gfx.gray(200),
        .font = fonts.FluentRegular,
        .font_size = 17,
        .onClick = &onSettingsButtonClick,
    }, .{
        .x = @as(f32, @floatFromInt(ctx.get().window_width)) - 79,
        .y = 14,
        .width = 30,
        .height = 30,
    }, ui.SimpleButton.new) catch {};

    pushComponent(st, ui.SimpleButton.VData{
        .pressed = false,
        .text = Icons.Fluent.ADD_24,
        .text_color = gfx.gray(200),
        .font = fonts.FluentRegular,
        .font_size = 17,
        .onClick = &onAddButtonClick,
    }, .{
        .x = @as(f32, @floatFromInt(ctx.get().window_width)) - 114,
        .y = 14,
        .width = 30,
        .height = 30,
    }, ui.SimpleButton.new) catch {};
}

fn onUpdate(s: *scene.Scene, delta_time: f32) void {
    const st: *State = @ptrCast(@alignCast(s.vdata.?));
    st.frame_count += 1;
    st.dt_count += delta_time;
    if (st.dt_count >= 1.0) {
        st.dt_count = 0;
        st.fps = st.frame_count;
        st.frame_count = 0;
    }

    for (st.components.items) |comp| {
        comp.update(delta_time);
    }
}

fn onRender(s: *scene.Scene, renderer: *gfx.Renderer) void {
    const st: *State = @ptrCast(@alignCast(s.vdata.?));

    const app_ctx = ctx.get();
    const w = app_ctx.window_width;
    const h = app_ctx.window_height;

    gfx.get().rect(0, 0, @floatFromInt(w), @floatFromInt(h), gfx.gray(10));

    if (st.bgImage) |img| {
        gfx.get().drawImage(img, 0, 0, @floatFromInt(w), @floatFromInt(h), 0, 0.6);
    }

    if (st.iconImage) |img| {
        gfx.get().drawImage(img, 10, 10, 30, 30, 0, 1);
    }

    gfx.get().text(50, 26, fonts.Regular, "Launcher", 20, gfx.grayF(1), gfx.ALIGN_MIDDLE_LEFT);
    gfx.get().text(20, 80, fonts.Regular, "Welcome back,", 24, gfx.grayF(1), gfx.ALIGN_TOP_LEFT);
    gfx.get().roundedRect(20, 114, 40, 40, 20, gfx.grayF(1));
    gfx.get().text(70, 134, fonts.SemiBold, "Shoroa_", 28, gfx.grayF(1), gfx.ALIGN_MIDDLE_LEFT);

    gfx.get().rect(0, 0, @as(f32, @floatFromInt(w)), 58, gfx.grayF(1));

    const mouse_x: f32 = @floatCast(app_ctx.mouse_x);
    const mouse_y: f32 = @floatCast(app_ctx.mouse_y);

    const mouse_text = std.fmt.allocPrint(st.allocator, "Mouse: {d:.0}, {d:.0}", .{ mouse_x, mouse_y }) catch "Mouse: ?, ?";
    const fps_text = std.fmt.allocPrint(st.allocator, "FPS: {d}", .{st.fps}) catch "FPS: ?";
    gfx.get().text(@as(f32, @floatFromInt(w)) - 10, @as(f32, @floatFromInt(h)) - 10, fonts.Regular, mouse_text, 14, gfx.grayF(0.7), gfx.ALIGN_BOTTOM_RIGHT);
    gfx.get().text(@as(f32, @floatFromInt(w)) - 10, @as(f32, @floatFromInt(h)) - 24, fonts.Regular, fps_text, 14, gfx.grayF(0.7), gfx.ALIGN_BOTTOM_RIGHT);
    st.allocator.free(mouse_text);
    st.allocator.free(fps_text);

    for (st.components.items) |comp| {
        comp.render(renderer);
    }
}

fn onClose(s: *scene.Scene) void {
    const st: *State = @ptrCast(@alignCast(s.vdata.?));

    for (st.components.items) |comp| {
        comp.close();
        st.allocator.destroy(comp);
    }
    st.components.deinit();

    st.allocator.destroy(st);
    s.vdata = null;
}

fn onMouseButton(s: *scene.Scene, event: scene.MouseButtonEvent) void {
    const st: *State = @ptrCast(@alignCast(s.vdata.?));

    for (st.components.items) |comp| {
        comp.mouseButton(event);
    }
}

fn onKey(s: *scene.Scene, event: scene.KeyEvent) void {
    const st: *State = @ptrCast(@alignCast(s.vdata.?));

    for (st.components.items) |comp| {
        comp.key(event);
    }
}

fn onMouseMove(s: *scene.Scene, event: scene.MouseMoveEvent) void {
    const st: *State = @ptrCast(@alignCast(s.vdata.?));

    for (st.components.items) |comp| {
        comp.mouseMove(event);
    }
}

const VTABLE: scene.VTABLE = .{
    .onInit = onInit,
    .onUpdate = onUpdate,
    .onRender = onRender,
    .onClose = onClose,
    .onMouseButton = onMouseButton,
    .onKey = onKey,
    .onMouseMove = onMouseMove,
};

pub fn new(allocator: std.mem.Allocator) !*scene.Scene {
    const st = try allocator.create(State);
    st.* = .{ .allocator = allocator };
    const scn = try allocator.create(scene.Scene);
    scn.* = .{ .vtable = &VTABLE, .vdata = st };
    return scn;
}
