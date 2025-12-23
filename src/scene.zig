const std = @import("std");
const gfx = @import("gfx.zig");

pub const SceneManager = struct {
    scenes: std.ArrayList(*Scene),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !SceneManager {
        return SceneManager{
            .scenes = try std.ArrayList(*Scene).initCapacity(allocator, 500),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SceneManager) void {
        for (self.scenes.items) |scene_ptr| {
            scene_ptr.close();
            self.allocator.destroy(scene_ptr);
        }
        self.scenes.deinit(self.allocator);
    }

    pub fn pushScene(self: *SceneManager, scene: *Scene) !void {
        try self.scenes.append(self.allocator, scene);
        scene.init();
    }

    pub fn pushNew(self: *SceneManager, factory: fn (std.mem.Allocator) anyerror!*Scene) !void {
        const scn = try factory(self.allocator);
        try self.scenes.append(self.allocator, scn);
        scn.init();
    }

    pub fn popScene(self: *SceneManager) void {
        if (self.scenes.items.len > 0) {
            const scene_ptr = self.scenes.items[self.scenes.items.len - 1];
            scene_ptr.close();
            _ = self.scenes.pop();
        }
    }

    pub fn popSceneFree(self: *SceneManager) void {
        if (self.scenes.items.len > 0) {
            const scene_ptr = self.scenes.items[self.scenes.items.len - 1];
            scene_ptr.close();
            _ = self.scenes.pop();
            self.allocator.destroy(scene_ptr);
        }
    }

    pub fn update(self: *SceneManager, deltaTime: f32) void {
        if (self.scenes.items.len > 0) {
            const scene_ptr = self.scenes.items[self.scenes.items.len - 1];
            scene_ptr.update(deltaTime);
        }
    }

    pub fn render(self: *SceneManager, renderer: *gfx.Renderer) void {
        if (self.scenes.items.len > 0) {
            const scene_ptr = self.scenes.items[self.scenes.items.len - 1];
            scene_ptr.render(renderer);
        }
    }

    pub fn mouseButton(self: *SceneManager, event: MouseButtonEvent) void {
        if (self.scenes.items.len > 0) {
            const scene_ptr = self.scenes.items[self.scenes.items.len - 1];
            scene_ptr.mouseButton(event);
        }
    }

    pub fn key(self: *SceneManager, event: KeyEvent) void {
        if (self.scenes.items.len > 0) {
            const scene_ptr = self.scenes.items[self.scenes.items.len - 1];
            scene_ptr.key(event);
        }
    }

    pub fn mouseMove(self: *SceneManager, event: MouseMoveEvent) void {
        if (self.scenes.items.len > 0) {
            const scene_ptr = self.scenes.items[self.scenes.items.len - 1];
            scene_ptr.mouseMove(event);
        }
    }

    pub fn scroll(self: *SceneManager, xoffset: f64, yoffset: f64) void {
        if (self.scenes.items.len > 0) {
            const scene_ptr = self.scenes.items[self.scenes.items.len - 1];
            scene_ptr.scroll(xoffset, yoffset);
        }
    }
};

pub var MGR: SceneManager = undefined;

pub const Scene = struct {
    vtable: *const VTABLE,
    vdata: ?*anyopaque = null,

    pub fn init(self: *Scene) void {
        self.vtable.onInit(self);
    }

    pub fn update(self: *Scene, deltaTime: f32) void {
        self.vtable.onUpdate(self, deltaTime);
    }

    pub fn render(self: *Scene, renderer: *gfx.Renderer) void {
        self.vtable.onRender(self, renderer);
    }

    pub fn close(self: *Scene) void {
        self.vtable.onClose(self);
    }

    pub fn mouseButton(self: *Scene, event: MouseButtonEvent) void {
        if (self.vtable.onMouseButton) |handler| {
            handler(self, event);
        }
    }

    pub fn key(self: *Scene, event: KeyEvent) void {
        if (self.vtable.onKey) |handler| {
            handler(self, event);
        }
    }

    pub fn mouseMove(self: *Scene, event: MouseMoveEvent) void {
        if (self.vtable.onMouseMove) |handler| {
            handler(self, event);
        }
    }

    pub fn scroll(self: *Scene, xoffset: f64, yoffset: f64) void {
        if (self.vtable.onScroll) |handler| {
            handler(self, xoffset, yoffset);
        }
    }
};

pub const MouseButton = enum(u8) {
    left = 0,
    right = 1,
    middle = 2,
};

pub const MouseButtonEvent = struct {
    button: MouseButton,
    pressed: bool,
    x: f64,
    y: f64,
};

pub const KeyEvent = struct {
    key: i32,
    scancode: i32,
    action: i32,
    mods: i32,
};

pub const MouseMoveEvent = struct {
    x: f64,
    y: f64,
};

pub const VTABLE = struct {
    onInit: *const fn (self: *Scene) void,
    onUpdate: *const fn (self: *Scene, deltaTime: f32) void,
    onRender: *const fn (self: *Scene, renderer: *gfx.Renderer) void,
    onClose: *const fn (self: *Scene) void,
    onMouseButton: ?*const fn (self: *Scene, event: MouseButtonEvent) void = null,
    onKey: ?*const fn (self: *Scene, event: KeyEvent) void = null,
    onMouseMove: ?*const fn (self: *Scene, event: MouseMoveEvent) void = null,
    onScroll: ?*const fn (self: *Scene, xoffset: f64, yoffset: f64) void = null,
};