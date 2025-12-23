const std = @import("std");
const scene = @import("../scene.zig");
const gfx = @import("../gfx.zig");
const Icons = @import("../icons.zig").Icons;
const fonts = @import("../fonts.zig");
const images = @import("../images.zig");
const ctx = @import("../context.zig");
const ui = @import("../component/ui.zig");
const tween = @import("tween");

pub const State = struct {
    allocator: std.mem.Allocator,
    frame_count: u64 = 0,
    fps: u64 = 0,
    dt_count: f32 = 0,
    bgImage: ?gfx.nvg.Image = null,
    components: std.array_list.Managed(*ui.Component) = undefined,

    launch_button: ?*ui.Component = null,
    expand_button: ?*ui.Component = null,
    expand_smooth: f32 = 0.0,
    version_select_expanded: bool = false,

    versions_initialized: bool = false,
    version_components: std.array_list.Managed(*ui.Component) = undefined,
    version_component_scales: std.array_list.Managed(f32) = undefined,
    version_scroll_offset: f32 = 0.0,
    version_scroll_target: f32 = 0.0,
};

fn pushComponent(state: *State, list: *std.array_list.Managed(*ui.Component), vdata: anytype, rect: ui.Rect, factory: fn (std.mem.Allocator, anytype, ui.Rect) ?*ui.Component) !*ui.Component {
    const comp = factory(state.allocator, vdata, rect) orelse return error.ComponentCreationFailed;
    try list.append(comp);
    comp.init();
    return comp;
}

fn onLaunchButtonClick(user: ?*anyopaque) void {
    _ = user;
}

fn onExpandButtonClick(user: ?*anyopaque) void {
    if (user) |ptr| {
        const st: *State = @ptrCast(@alignCast(ptr));
        st.version_select_expanded = !st.version_select_expanded;
        if (st.expand_button) |btn| {
            if (st.version_select_expanded) {
                btn.getVData(ui.SimpleButton.VData).text = Icons.Fluent.CHEVRON_DOWN_24;
            } else {
                btn.getVData(ui.SimpleButton.VData).text = Icons.Fluent.CHEVRON_UP_24;
            }
        }
    }
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

    st.bgImage = gfx.get().createImage(images.images[0], .{ .generate_mipmaps = true }) catch null;

    st.components = std.array_list.Managed(*ui.Component).init(st.allocator);
    st.version_components = std.array_list.Managed(*ui.Component).init(st.allocator);
    st.version_component_scales = std.array_list.Managed(f32).init(st.allocator);

    st.launch_button = pushComponent(st, &st.components, ui.SimpleButton.VData{
        .text = "Launch Latest",
        .text_align = .LEFT,
        .font = fonts.Regular,
        .icon = .{
            .font = fonts.FluentRegular,
            .glyph = Icons.Fluent.PLAY_24,
            .size = 24,
        },
        .onClick = &onLaunchButtonClick,
    }, .{
        .x = 20,
        .y = @as(f32, @floatFromInt(ctx.get().window_height)) - 70,
        .width = 200,
        .height = 50,
    }, ui.SimpleButton.new) catch null;

    st.expand_button = pushComponent(st, &st.components, ui.SimpleButton.VData{
        .text = Icons.Fluent.CHEVRON_UP_24,
        .font = fonts.FluentRegular,
        .onClick = &onExpandButtonClick,
        .user = @as(?*anyopaque, st)
    },.{
        .x = 230,
        .y = @as(f32, @floatFromInt(ctx.get().window_height)) - 70,
        .width = 50,
        .height = 50,
    }, ui.SimpleButton.new) catch null;

    _ = pushComponent(st, &st.components, ui.SimpleButton.VData{
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
    }, ui.SimpleButton.new) catch null;

    _ = pushComponent(st, &st.components, ui.SimpleButton.VData{
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
    }, ui.SimpleButton.new) catch null;

    _ = pushComponent(st, &st.components, ui.SimpleButton.VData{
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
    }, ui.SimpleButton.new) catch null;
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

    const app_ctx = ctx.get();
    const h = app_ctx.window_height;

    if (ctx.get().version_manifest) |manifest| {
        if (!st.versions_initialized) {
            for (manifest.versions) |ver| {
                _ = pushComponent(st, &st.version_components, ui.SimpleButton.VData{
                    .text = ver,
                    .text_align = .LEFT,
                    .font = fonts.Regular,
                    .icon = .{
                        .font = fonts.FluentRegular,
                        .glyph = Icons.Fluent.CHECKMARK_24,
                        .alignment = .RIGHT,
                        .size = 20,
                    },
                    .fill_style = .{
                        .base_color = gfx.grayA(60, 0),
                        .hover_color = gfx.grayA(80, 50),
                        .pressed_color = gfx.grayA(100, 50),
                    },
                    .onClick = null,
                }, .{
                    .x = 22,
                    .y = 0,
                    .width = 256,
                    .height = 38,
                }, ui.SimpleButton.new) catch null;
                st.version_component_scales.append(1.0) catch {};
            }
            st.versions_initialized = true;
        }
    }

    if (st.version_select_expanded) {
        st.expand_smooth = tween.interp.lerpClamped(st.expand_smooth, 1.0, delta_time * 10.0);
    } else {
        st.expand_smooth = tween.interp.lerpClamped(st.expand_smooth, 0.0, delta_time * 10.0);
    }

    if (st.launch_button) |btn| {
        const base_y = @as(f32, @floatFromInt(ctx.get().window_height)) - 70;
        btn.rect.y = base_y - (130.0 * st.expand_smooth);
    }

    if (st.expand_button) |btn| {
        const base_y = @as(f32, @floatFromInt(ctx.get().window_height)) - 70;
        btn.rect.y = base_y - (130.0 * st.expand_smooth);
    }

    for (st.components.items) |comp| {
        comp.update(delta_time);
    }

    const panel_height: f32 = 122.0;
    const panel_top_padding: f32 = 2.0;
    const panel_bottom_padding: f32 = 2.0;
    const visible_height = panel_height - panel_top_padding - panel_bottom_padding;
    const item_height: f32 = 38.0;
    const item_spacing: f32 = 2.0;
    const total_items = @as(f32, @floatFromInt(st.version_components.items.len));
    const content_height = total_items * item_height + @max(0, total_items - 1) * item_spacing;
    const max_scroll = @max(0.0, content_height - visible_height);

    st.version_scroll_target = @max(0.0, @min(st.version_scroll_target, max_scroll));

    st.version_scroll_offset = tween.interp.lerpClamped(st.version_scroll_offset, st.version_scroll_target, delta_time * 10.0);

    const panel_y = @as(f32, @floatFromInt(h)) - 140.0 * st.expand_smooth;
    const panel_top = panel_y + panel_top_padding;
    const panel_bottom = panel_y + panel_height - panel_bottom_padding;

    var comp_i: usize = 0;
    for (st.version_components.items) |comp| {
        const item_y = panel_top + (@as(f32, @floatFromInt(comp_i)) * (item_height + item_spacing)) - st.version_scroll_offset;
        comp.rect.y = item_y;

        const item_top = item_y;
        const item_bottom = item_y + item_height;

        var visibility: f32 = 1.0;

        if (item_top < panel_top) {
            const overlap = panel_top - item_top;
            visibility = @max(0.0, 1.0 - (overlap / item_height));
        }

        else if (item_bottom > panel_bottom) {
            const overlap = item_bottom - panel_bottom;
            visibility = @max(0.0, 1.0 - (overlap / item_height));
        }

        if (comp_i < st.version_component_scales.items.len) {
            const target_scale = 0.5 + (visibility * 0.5);
            st.version_component_scales.items[comp_i] = tween.interp.lerpClamped(
                st.version_component_scales.items[comp_i],
                target_scale,
                delta_time * 15.0
            );
        }

        comp.update(delta_time);
        comp_i += 1;
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

    gfx.get().text(25, 25, fonts.Glicons, Icons.Gliconic.GLIDE, 26, gfx.gray(255), gfx.ALIGN_CENTER);

    gfx.get().text(46, 25, fonts.Regular, "Launcher", 20, gfx.grayF(1), gfx.ALIGN_MIDDLE_LEFT);
    gfx.get().text(20, 80, fonts.Regular, "Welcome back,", 24, gfx.grayF(1), gfx.ALIGN_TOP_LEFT);
    gfx.get().roundedRect(20, 114, 40, 40, 20, gfx.grayF(1));
    gfx.get().text(70, 134, fonts.SemiBold, "Shoroa_", 28, gfx.grayF(1), gfx.ALIGN_MIDDLE_LEFT);

    if (app_ctx.version_manifest == null) {
        gfx.get().text(@as(f32, @floatFromInt(w)) - 10, @as(f32, @floatFromInt(h)) - 10, fonts.Regular, "Failed to get versions", 14, gfx.grayF(0.7), gfx.ALIGN_BOTTOM_RIGHT);
    }

    for (st.components.items) |comp| {
        comp.render(renderer);
    }

    gfx.get().save();
    gfx.get().globalAlpha(st.expand_smooth);

    const panel_y = @as(f32, @floatFromInt(h)) - 140 * st.expand_smooth;
    gfx.get().roundedRect(20, panel_y, 260, 122, 20, gfx.grayA(80, 120));

    gfx.get().scissor(20, panel_y + 2, 260, 118);

    var comp_i: usize = 0;
    for (st.version_components.items) |comp| {
        gfx.get().save();

        const scale = if (comp_i < st.version_component_scales.items.len)
            st.version_component_scales.items[comp_i]
        else
            1.0;

        const center_x = comp.rect.x + comp.rect.width / 2.0;
        const center_y = comp.rect.y + comp.rect.height / 2.0;

        gfx.get().translate(center_x, center_y);
        gfx.get().scale(scale, scale);
        gfx.get().translate(-center_x, -center_y);

        gfx.get().globalAlpha(st.expand_smooth * scale);

        comp.render(renderer);
        gfx.get().restore();
        comp_i += 1;
    }

    gfx.get().resetScissor();
    gfx.get().restore();
}

fn onClose(s: *scene.Scene) void {
    const st: *State = @ptrCast(@alignCast(s.vdata.?));

    for (st.components.items) |comp| {
        comp.close();
        st.allocator.destroy(comp);
    }
    st.components.deinit();

    for (st.version_components.items) |comp| {
        comp.close();
        st.allocator.destroy(comp);
    }
    st.version_components.deinit();
    st.version_component_scales.deinit();

    st.allocator.destroy(st);
    s.vdata = null;
}

fn onMouseButton(s: *scene.Scene, event: scene.MouseButtonEvent) void {
    const st: *State = @ptrCast(@alignCast(s.vdata.?));

    for (st.components.items) |comp| {
        comp.mouseButton(event);
    }

    for (st.version_components.items) |comp| {
        comp.mouseButton(event);
    }
}

fn onKey(s: *scene.Scene, event: scene.KeyEvent) void {
    const st: *State = @ptrCast(@alignCast(s.vdata.?));

    for (st.components.items) |comp| {
        comp.key(event);
    }

    for (st.version_components.items) |comp| {
        comp.key(event);
    }
}

fn onMouseMove(s: *scene.Scene, event: scene.MouseMoveEvent) void {
    const st: *State = @ptrCast(@alignCast(s.vdata.?));

    for (st.components.items) |comp| {
        comp.mouseMove(event);
    }

    for (st.version_components.items) |comp| {
        comp.mouseMove(event);
    }
}

fn onScroll(s: *scene.Scene, xoffset: f64, yoffset: f64) void {
    const st: *State = @ptrCast(@alignCast(s.vdata.?));
    _ = xoffset;
    st.version_scroll_target -= @as(f32, @floatCast(yoffset)) * 40.0;
}

const VTABLE: scene.VTABLE = .{
    .onInit = onInit,
    .onUpdate = onUpdate,
    .onRender = onRender,
    .onClose = onClose,
    .onMouseButton = onMouseButton,
    .onKey = onKey,
    .onMouseMove = onMouseMove,
    .onScroll = onScroll
};

pub fn new(allocator: std.mem.Allocator) !*scene.Scene {
    const st = try allocator.create(State);
    st.* = .{ .allocator = allocator };
    const scn = try allocator.create(scene.Scene);
    scn.* = .{ .vtable = &VTABLE, .vdata = st };
    return scn;
}
