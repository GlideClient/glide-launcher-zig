const std = @import("std");
const scene = @import("../scene.zig");
const gfx = @import("../gfx.zig");
const Icons = @import("../icons.zig").Icons;
const fonts = @import("../fonts.zig");
const images = @import("../images.zig");
const ctx = @import("../context.zig");
const ui = @import("../component/ui.zig");
const tween = @import("tween");
const launching = @import("../launch/launching.zig");
const launcher = @import("../launch/launcher.zig");
const game_files = @import("../launch/game_files.zig");
const json_types = @import("../json/types.zig");

pub const State = struct {
    allocator: std.mem.Allocator,
    frame_count: u64 = 0,
    fps: u64 = 0,
    dt_count: f32 = 0,
    bgImage: ?gfx.nvg.Image = null,
    components: std.array_list.Managed(*ui.Component) = undefined,

    launch_ctx: ?*launching.LaunchContext = null,
    launch_button: ?*ui.Component = null,
    expand_button: ?*ui.Component = null,
    expand_smooth: f32 = 0.0,
    version_select_expanded: bool = false,

    is_downloading: bool = false,
    download_progress: f32 = 0.0,
    download_progress_smooth: f32 = 0.0,
    download_status: []const u8 = "",
    download_thread: ?std.Thread = null,

    versions_initialized: bool = false,
    version_components: std.array_list.Managed(*ui.Component) = undefined,
    version_component_scales: std.array_list.Managed(f32) = undefined,
    version_button_users: std.array_list.Managed(*VersionButtonUsr) = undefined,
    version_scroll_offset: f32 = 0.0,
    version_scroll_target: f32 = 0.0,
};

const VersionButtonUsr = struct {
    version: []const u8,
    st: *State,
};

fn pushComponent(state: *State, list: *std.array_list.Managed(*ui.Component), vdata: anytype, rect: ui.Rect, factory: fn (std.mem.Allocator, anytype, ui.Rect) ?*ui.Component) !*ui.Component {
    const comp = factory(state.allocator, vdata, rect) orelse return error.ComponentCreationFailed;
    try list.append(comp);
    comp.init();
    return comp;
}

fn onLaunchProgress(status: []const u8, progress: f32, user_data: ?*anyopaque) void {
    if (user_data) |ptr| {
        const st: *State = @ptrCast(@alignCast(ptr));
        st.download_status = status;
        st.download_progress = progress;
    }
}

fn launchThread(st: *State) void {
    const version = launching.get().selected_version orelse {
        st.download_status = "Error: No version selected";
        st.is_downloading = false;
        return;
    };

    std.debug.print("=== Launching version: {s} ===\n", .{version});

    const client = launcher.fetchClientInfo(
        st.allocator,
        version,
        &onLaunchProgress,
        @as(?*anyopaque, st),
    ) orelse {
        st.is_downloading = false;
        return;
    };

    st.launch_ctx.?.client = client;
    std.debug.print("Client parsed successfully: {s} (id: {s})\n", .{ client.name, client.id });

    if (!launcher.downloadJava(st.allocator, client.java.component, &onLaunchProgress, @as(?*anyopaque, st))) {
        st.download_status = "Error: Failed to download Java";
        st.is_downloading = false;
        return;
    }

    if (client.manifest_url) |manifest_url| {
        st.download_status = "Downloading game files...";
        game_files.downloadAllGameFiles(
            st.allocator,
            manifest_url,
            &onLaunchProgress,
            @as(?*anyopaque, st),
        ) catch |err| {
            std.debug.print("Failed to download game files: {}\n", .{err});
            st.download_status = "Error: Failed to download game files";
            st.is_downloading = false;
            return;
        };
    }

    if (!launcher.downloadCustomLibraries(st.allocator, client, &onLaunchProgress, @as(?*anyopaque, st))) {
        std.debug.print("Warning: Some custom libraries failed to download\n", .{});
    }

    if (!launcher.downloadCustomClient(st.allocator, client, &onLaunchProgress, @as(?*anyopaque, st))) {
        st.download_status = "Error: Failed to download client";
        st.is_downloading = false;
        return;
    }

    launcher.launchGame(st.allocator, client, &onLaunchProgress, @as(?*anyopaque, st)) catch |err| {
        std.debug.print("Failed to launch game: {}\n", .{err});
        st.download_status = "Error: Failed to launch game";
        st.is_downloading = false;
        return;
    };

    st.download_status = "Game launched!";
    st.is_downloading = false;
}

fn startLaunch(st: *State) void {
    if (st.is_downloading) return;
    if (launching.get().selected_version == null) return;

    st.is_downloading = true;
    st.download_progress = 0.0;
    st.download_progress_smooth = 0.0;
    st.download_status = "Starting...";

    st.download_thread = std.Thread.spawn(.{}, launchThread, .{st}) catch {
        st.download_status = "Error: Failed to start";
        st.is_downloading = false;
        return;
    };
}

fn onLaunchButtonClick(user: ?*anyopaque) void {
    if (user) |ptr| {
        const st: *State = @ptrCast(@alignCast(ptr));
        startLaunch(st);
    }
}

fn onExpandButtonClick(user: ?*anyopaque) void {
    if (user) |ptr| {
        const st: *State = @ptrCast(@alignCast(ptr));
        st.version_select_expanded = !st.version_select_expanded;
        if (st.expand_button) |btn| {
            if (st.version_select_expanded) {
                btn.getVData(ui.Button.VData).text = Icons.Fluent.CHEVRON_DOWN_24;
            } else {
                btn.getVData(ui.Button.VData).text = Icons.Fluent.CHEVRON_UP_24;
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

fn onVersionSelectButtonClick(user: ?*anyopaque) void {
    if (user) |ptr| {
        const usr: *VersionButtonUsr = @ptrCast(@alignCast(ptr));

        if (!usr.st.version_select_expanded) return;

        const vdata = usr.st.launch_button.?.getVData(ui.Button.VData);
        const str = std.fmt.allocPrint(usr.st.allocator, "Launch {s}", .{usr.version}) catch "Launch";
        vdata.text = str;
        launching.get().selected_version = usr.version;
        usr.st.version_select_expanded = false;
        if (usr.st.expand_button) |btn| {
            btn.getVData(ui.Button.VData).text = Icons.Fluent.CHEVRON_UP_24;
        }
    }
}

fn onInit(s: *scene.Scene) void {
    const st: *State = @ptrCast(@alignCast(s.vdata.?));

    st.launch_ctx = st.allocator.create(launching.LaunchContext) catch null;
    if (st.launch_ctx) |lctx| {
        lctx.* = launching.LaunchContext.init();
        launching.set(lctx);
    }

    st.bgImage = gfx.get().createImage(images.images[0], .{ .generate_mipmaps = true }) catch null;

    st.components = std.array_list.Managed(*ui.Component).init(st.allocator);
    st.version_components = std.array_list.Managed(*ui.Component).init(st.allocator);
    st.version_component_scales = std.array_list.Managed(f32).init(st.allocator);
    st.version_button_users = std.array_list.Managed(*VersionButtonUsr).init(st.allocator);

    st.launch_button = pushComponent(st, &st.components, ui.Button.VData{
        .text = "fetching",
        .text_align = .LEFT,
        .font = fonts.Regular,
        .icon = .{
            .font = fonts.FluentRegular,
            .glyph = Icons.Fluent.PLAY_24,
            .size = 24,
        },
        .onClick = &onLaunchButtonClick,
        .user = @as(?*anyopaque, st),
    }, .{
        .x = 20,
        .y = @as(f32, @floatFromInt(ctx.get().window_height)) - 70,
        .width = 200,
        .height = 50,
    }, ui.Button.new) catch null;

    st.expand_button = pushComponent(st, &st.components, ui.Button.VData{
        .text = Icons.Fluent.CHEVRON_UP_24,
        .font = fonts.FluentRegular,
        .onClick = &onExpandButtonClick,
        .user = @as(?*anyopaque, st),
    }, .{
        .x = 230,
        .y = @as(f32, @floatFromInt(ctx.get().window_height)) - 70,
        .width = 50,
        .height = 50,
    }, ui.Button.new) catch null;

    _ = pushComponent(st, &st.components, ui.Button.VData{
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
    }, ui.Button.new) catch null;

    _ = pushComponent(st, &st.components, ui.Button.VData{
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
    }, ui.Button.new) catch null;

    _ = pushComponent(st, &st.components, ui.Button.VData{
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
    }, ui.Button.new) catch null;
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

    st.download_progress_smooth = tween.interp.lerpClamped(st.download_progress_smooth, st.download_progress, delta_time * 10.0);

    if (st.download_thread) |thread| {
        if (!st.is_downloading) {
            thread.join();
            st.download_thread = null;
        }
    }

    const app_ctx = ctx.get();
    const h = app_ctx.window_height;

    if (ctx.get().version_manifest) |manifest| {
        if (launching.get().selected_version == null) {
            launching.get().selected_version = manifest.latest;
            std.debug.print("Selected version set to latest: {s}\n", .{manifest.latest});
            st.launch_button.?.getVData(ui.Button.VData).text = std.fmt.allocPrint(st.allocator, "Launch {s}", .{manifest.latest}) catch "Launch";
        }

        if (!st.versions_initialized) {
            for (manifest.versions) |ver| {
                const usr = st.allocator.create(VersionButtonUsr) catch continue;
                usr.* = .{ .version = ver, .st = st };
                st.version_button_users.append(usr) catch {
                    st.allocator.destroy(usr);
                    continue;
                };

                _ = pushComponent(st, &st.version_components, ui.Button.VData{
                    .text = ver,
                    .text_align = .LEFT,
                    .font = fonts.Regular,
                    .fill_style = .{
                        .base_color = gfx.grayA(60, 0),
                        .hover_color = gfx.grayA(80, 50),
                        .pressed_color = gfx.grayA(100, 50),
                    },
                    .onClick = &onVersionSelectButtonClick,
                    .user = @as(?*anyopaque, usr),
                }, .{
                    .x = 22,
                    .y = 0,
                    .width = 256,
                    .height = 38,
                }, ui.Button.new) catch null;
                st.version_component_scales.append(1.0) catch {};
            }
            st.versions_initialized = true;
        }
    }

    // Expand/collapse animation
    const target_expand = if (st.version_select_expanded) @as(f32, 1.0) else @as(f32, 0.0);
    st.expand_smooth = tween.interp.lerpClamped(st.expand_smooth, target_expand, delta_time * 10.0);

    // Update button positions
    if (st.launch_button) |btn| {
        btn.rect.y = @as(f32, @floatFromInt(h)) - 70 - (130.0 * st.expand_smooth);
    }
    if (st.expand_button) |btn| {
        btn.rect.y = @as(f32, @floatFromInt(h)) - 70 - (130.0 * st.expand_smooth);
    }

    for (st.components.items) |comp| {
        comp.update(delta_time);
    }

    updateVersionScroll(st, h, delta_time);
}

fn updateVersionScroll(st: *State, h: u32, delta_time: f32) void {
    const panel_height: f32 = 122.0;
    const panel_padding: f32 = 2.0;
    const visible_height = panel_height - panel_padding * 2;
    const item_height: f32 = 38.0;
    const item_spacing: f32 = 2.0;
    const total_items = @as(f32, @floatFromInt(st.version_components.items.len));
    const content_height = total_items * item_height + @max(0, total_items - 1) * item_spacing;
    const max_scroll = @max(0.0, content_height - visible_height);

    st.version_scroll_target = @max(0.0, @min(st.version_scroll_target, max_scroll));
    st.version_scroll_offset = tween.interp.lerpClamped(st.version_scroll_offset, st.version_scroll_target, delta_time * 20.0);

    const panel_y = @as(f32, @floatFromInt(h)) - 140.0 * st.expand_smooth;
    const panel_top = panel_y + panel_padding;
    const panel_bottom = panel_y + panel_height - panel_padding;

    var i: usize = 0;
    for (st.version_components.items) |comp| {
        const item_y = panel_top + (@as(f32, @floatFromInt(i)) * (item_height + item_spacing)) - st.version_scroll_offset;
        comp.rect.y = item_y;

        var visibility: f32 = 1.0;
        if (item_y < panel_top) {
            visibility = @max(0.0, 1.0 - (panel_top - item_y) / item_height);
        } else if (item_y + item_height > panel_bottom) {
            visibility = @max(0.0, 1.0 - (item_y + item_height - panel_bottom) / item_height);
        }

        if (i < st.version_component_scales.items.len) {
            const target_scale = 0.5 + (visibility * 0.5);
            st.version_component_scales.items[i] = tween.interp.lerpClamped(st.version_component_scales.items[i], target_scale, delta_time * 15.0);
        }

        comp.update(delta_time);
        i += 1;
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
    gfx.get().text(70, 134, fonts.SemiBold, "Glider!", 28, gfx.grayF(1), gfx.ALIGN_MIDDLE_LEFT);

    if (app_ctx.version_manifest == null) {
        gfx.get().text(@as(f32, @floatFromInt(w)) - 10, @as(f32, @floatFromInt(h)) - 10, fonts.Regular, "Failed to get versions", 14, gfx.grayF(0.7), gfx.ALIGN_BOTTOM_RIGHT);
    }

    for (st.components.items) |comp| {
        comp.render(renderer);
    }

    if (st.is_downloading or st.download_progress_smooth > 0.01) {
        renderProgressBar(st, w, h);
    }

    renderVersionPanel(st, renderer, h);
}

fn renderProgressBar(st: *State, w: u32, h: u32) void {
    const bar_y: f32 = @as(f32, @floatFromInt(h)) - 3;
    const bar_width: f32 = @floatFromInt(w);

    gfx.get().rect(0, bar_y, bar_width, 3, gfx.grayA(40, 150));
    if (st.download_progress_smooth > 0) {
        gfx.get().rect(0, bar_y, bar_width * st.download_progress_smooth, 3, gfx.gray(255));
    }
    gfx.get().text(@as(f32, @floatFromInt(w)) - 10, @as(f32, @floatFromInt(h)) - 10, fonts.Regular, st.download_status, 12, gfx.grayF(0.8), gfx.ALIGN_BOTTOM_RIGHT);
}

fn renderVersionPanel(st: *State, renderer: *gfx.Renderer, h: u32) void {
    gfx.get().save();
    gfx.get().globalAlpha(st.expand_smooth);

    const panel_y = @as(f32, @floatFromInt(h)) - 140 * st.expand_smooth;
    gfx.get().roundedRect(20, panel_y, 260, 122, 20, gfx.grayA(80, 120));
    gfx.get().scissor(20, panel_y + 2, 260, 118);

    var i: usize = 0;
    for (st.version_components.items) |comp| {
        gfx.get().save();

        const scale = if (i < st.version_component_scales.items.len) st.version_component_scales.items[i] else 1.0;
        const center_x = comp.rect.x + comp.rect.width / 2.0;
        const center_y = comp.rect.y + comp.rect.height / 2.0;

        gfx.get().translate(center_x, center_y);
        gfx.get().scale(scale, scale);
        gfx.get().translate(-center_x, -center_y);
        gfx.get().globalAlpha(st.expand_smooth * scale);

        comp.render(renderer);
        gfx.get().restore();
        i += 1;
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

    for (st.version_button_users.items) |usr| {
        st.allocator.destroy(usr);
    }
    st.version_button_users.deinit();

    if (st.launch_ctx) |lctx| {
        st.allocator.destroy(lctx);
    }

    st.allocator.destroy(st);
    s.vdata = null;
}

fn onMouseButton(s: *scene.Scene, event: scene.MouseButtonEvent) void {
    const st: *State = @ptrCast(@alignCast(s.vdata.?));
    for (st.components.items) |comp| comp.mouseButton(event);
    for (st.version_components.items) |comp| comp.mouseButton(event);
}

fn onKey(s: *scene.Scene, event: scene.KeyEvent) void {
    const st: *State = @ptrCast(@alignCast(s.vdata.?));
    for (st.components.items) |comp| comp.key(event);
    for (st.version_components.items) |comp| comp.key(event);
}

fn onMouseMove(s: *scene.Scene, event: scene.MouseMoveEvent) void {
    const st: *State = @ptrCast(@alignCast(s.vdata.?));
    for (st.components.items) |comp| comp.mouseMove(event);
    for (st.version_components.items) |comp| comp.mouseMove(event);
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
    .onScroll = onScroll,
};

pub fn new(allocator: std.mem.Allocator) !*scene.Scene {
    const st = try allocator.create(State);
    st.* = .{ .allocator = allocator };
    const scn = try allocator.create(scene.Scene);
    scn.* = .{ .vtable = &VTABLE, .vdata = st };
    return scn;
}
