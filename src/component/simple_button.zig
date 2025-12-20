const std = @import("std");
const ui = @import("ui.zig");
const gfx = @import("../gfx.zig");
const scene = @import("../scene.zig");
const ctx = @import("../context.zig");

pub const ClickFn = *const fn (?*anyopaque) void;

pub const VData = struct {
    pressed: bool = false,
    hovered: bool = false,
    text: []const u8 = "",
    text_color: gfx.nvg.Color = gfx.gray(255),
    font: [:0]const u8 = "regular",
    font_size: f32 = 20,
    onClick: ?ClickFn = null,
    user: ?*anyopaque = null,
    hover_fade: f32 = 0.0,
};


fn onInit(c: *ui.Component) void {
    _ = c;
}

fn onUpdate(c: *ui.Component, delta_time: f32) void {
    const vd = c.getVData(VData);

    const target_fade: f32 = if (vd.hovered) 1.0 else 0.0;
    const fade_speed: f32 = 15.0;
    if (vd.hover_fade < target_fade) {
        vd.hover_fade += fade_speed * delta_time;
        if (vd.hover_fade > target_fade) {
            vd.hover_fade = target_fade;
        }
    } else if (vd.hover_fade > target_fade) {
        vd.hover_fade -= fade_speed * delta_time;
        if (vd.hover_fade < target_fade) {
            vd.hover_fade = target_fade;
        }
    }
}

fn onRender(c: *ui.Component, renderer: *gfx.Renderer) void {
    const vd = c.getVData(VData);

    const base_color = gfx.grayA(80, 120);
    const hover_color = gfx.grayA(95, 120);
    const pressed_color = gfx.grayA(110, 120);

    const pressed_mult: f32 = if (vd.pressed) 1.0 else 0.0;

    const color = gfx.rgbaF(
        base_color.r + (hover_color.r - base_color.r) * vd.hover_fade + (pressed_color.r - hover_color.r) * pressed_mult,
        base_color.g + (hover_color.g - base_color.g) * vd.hover_fade + (pressed_color.g - hover_color.g) * pressed_mult,
        base_color.b + (hover_color.b - base_color.b) * vd.hover_fade + (pressed_color.b - hover_color.b) * pressed_mult,
        base_color.a + (hover_color.a - base_color.a) * vd.hover_fade + (pressed_color.a - hover_color.a) * pressed_mult,
    );

    renderer.roundedRect(c.rect.x, c.rect.y, c.rect.width, c.rect.height, c.rect.height / 2, color);
    const text_x = c.rect.x + c.rect.width / 2;
    const text_y = c.rect.y + c.rect.height / 2 + 1;
    renderer.text(text_x, text_y, vd.font, vd.text, vd.font_size, vd.text_color, gfx.ALIGN_CENTER);
}

fn onMouseButton(c: *ui.Component, event: scene.MouseButtonEvent) void {
    const vd = c.getVData(VData);

    if (vd.hovered) {
        if (event.pressed) {
            vd.pressed = true;
        } else {
            if (vd.pressed) {
                if (vd.onClick) |handler| {
                    handler(vd.user);
                }
            }
            vd.pressed = false;
        }
    } else {
        vd.pressed = false;
    }
}

fn onMouseMove(c: *ui.Component, event: scene.MouseMoveEvent) void {
    const mx: f32 = @floatCast(event.x);
    const my: f32 = @floatCast(event.y);
    const vd = c.getVData(VData);

    if (ui.pointInRect(mx, my, c.rect)) {
        vd.hovered = true;
    } else {
        vd.hovered = false;
    }
}

fn onClose(c: *ui.Component) void {
    if (c.vdata) |vd| {
        const vd_ptr: *VData = @ptrCast(@alignCast(vd));
        c.allocator.destroy(vd_ptr);
    }
}

const VTABLE: ui.VTABLE = .{
    .onInit = &onInit,
    .onUpdate = &onUpdate,
    .onRender = &onRender,
    .onClose = &onClose,
    .onMouseButton = &onMouseButton,
    .onKey = null,
    .onMouseMove = &onMouseMove,
};

pub fn new(allocator: std.mem.Allocator, vdata: anytype, rect: ui.Rect) ?*ui.Component {
    const comp = allocator.create(ui.Component) catch return null;

    const vd_ptr = allocator.create(VData) catch {
        allocator.destroy(comp);
        return null;
    };
    vd_ptr.* = vdata;

    comp.* = .{
        .vtable = &VTABLE,
        .vdata = @ptrCast(vd_ptr),
        .rect = rect,
        .allocator = allocator
    };
    return comp;
}
