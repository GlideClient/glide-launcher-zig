const std = @import("std");
const gfx = @import("../gfx.zig");
const scene = @import("../scene.zig");
const fonts = @import("../fonts.zig");
const ctx = @import("../context.zig");

pub const Button = @import("button.zig");

pub const Rect = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
};

pub fn pointInRect(px: f32, py: f32, rect: Rect) bool {
    return px >= rect.x and px <= (rect.x + rect.width) and
           py >= rect.y and py <= (rect.y + rect.height);
}

pub const Component = struct {
    vtable: *const VTABLE,
    rect: Rect,
    vdata: ?*anyopaque,
    allocator: std.mem.Allocator,

    pub fn getVData(self: *Component, comptime T: type) *T {
        return @ptrCast(@alignCast(self.vdata.?));
    }

    pub fn init(self: *Component) void {
        self.vtable.onInit(self);
    }

    pub fn update(self: *Component, deltaTime: f32) void {
        self.vtable.onUpdate(self, deltaTime);
    }

    pub fn render(self: *Component, renderer: *gfx.Renderer) void {
        self.vtable.onRender(self, renderer);
    }

    pub fn close(self: *Component) void {
        self.vtable.onClose(self);
    }

    pub fn mouseButton(self: *Component, event: scene.MouseButtonEvent) void {
        if (self.vtable.onMouseButton) |handler| {
            handler(self, event);
        }
    }

    pub fn key(self: *Component, event: scene.KeyEvent) void {
        if (self.vtable.onKey) |handler| {
            handler(self, event);
        }
    }

    pub fn mouseMove(self: *Component, event: scene.MouseMoveEvent) void {
        if (self.vtable.onMouseMove) |handler| {
            handler(self, event);
        }
    }
};

pub const VTABLE = struct {
    onInit: *const fn (self: *Component) void,
    onUpdate: *const fn (self: *Component, deltaTime: f32) void,
    onRender: *const fn (self: *Component, renderer: *gfx.Renderer) void,
    onClose: *const fn (self: *Component) void,
    onMouseButton: ?*const fn (self: *Component, event: scene.MouseButtonEvent) void = null,
    onKey: ?*const fn (self: *Component, event: scene.KeyEvent) void = null,
    onMouseMove: ?*const fn (self: *Component, event: scene.MouseMoveEvent) void = null,
};