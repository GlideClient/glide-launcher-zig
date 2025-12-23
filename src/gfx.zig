const std = @import("std");
const builtin = @import("builtin");
pub const nvg = @import("nanovg");
const fonts = @import("fonts.zig");

pub const Renderer = struct {
    vg: nvg,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !Renderer {
        const vg = try nvg.gl.init(allocator, .{
            .stencil_strokes = true,
        });

        for (fonts.fonts) |fontData| {
            _ = vg.createFontMem(fontData.name, fontData.data);
        }

        return Renderer{
            .vg = vg,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Renderer) void {
        defer nvg.deinit(self.vg);
    }

    pub fn beginFrame(self: *Renderer, window_width: f32, window_height: f32, px_ratio: f32) void {
        self.vg.beginFrame(window_width, window_height, px_ratio);
    }

    pub fn endFrame(self: *Renderer) void {
        self.vg.endFrame();
    }

    pub fn rect(self: *Renderer, x: f32, y: f32, w: f32, h: f32, color: nvg.Color) void {
        self.vg.beginPath();
        self.vg.rect(x, y, w, h);
        self.vg.fillColor(color);
        self.vg.fill();
    }

    pub fn roundedRect(self: *Renderer, x: f32, y: f32, w: f32, h: f32, radius: f32, color: nvg.Color) void {
        self.vg.beginPath();
        self.vg.roundedRect(x, y, w, h, radius);
        self.vg.fillColor(color);
        self.vg.fill();
    }

    pub fn line(self: *Renderer, x1: f32, y1: f32, x2: f32, y2: f32, stroke_width: f32, color: nvg.Color) void {
        self.vg.beginPath();
        self.vg.moveTo(x1, y1);
        self.vg.lineTo(x2, y2);
        self.vg.strokeWidth(stroke_width);
        self.vg.strokeColor(color);
        self.vg.stroke();
    }

    pub fn circle(self: *Renderer, cx: f32, cy: f32, radius: f32, color: nvg.Color) void {
        self.vg.beginPath();
        self.vg.circle(cx, cy, radius);
        self.vg.fillColor(color);
        self.vg.fill();
    }

    pub fn text(self: *Renderer, x: f32, y: f32, font: [:0]const u8, string: []const u8, font_size: f32, color: nvg.Color, text_align: nvg.TextAlign) void {
        self.vg.fontFace(font);
        self.vg.fontSize(font_size);
        self.vg.fillColor(color);
        self.vg.textAlign(text_align);
        _ = self.vg.text(x, y, string);
    }

    pub fn textBox(self: *Renderer, x: f32, y: f32, break_width: f32, font: [:0]const u8, string: []const u8, font_size: f32, color: nvg.Color) void {
        self.vg.fontFace(font);
        self.vg.fontSize(font_size);
        self.vg.fillColor(color);
        self.vg.textAlign(.{
            .vertical = nvg.TextAlign.VerticalAlign.top,
            .horizontal = nvg.TextAlign.HorizontalAlign.left,
        });
        _ = self.vg.textBox(x, y, break_width, string);
    }

    pub fn createImage(self: *Renderer, data: []const u8, flags: nvg.ImageFlags) !nvg.Image {
        return self.vg.createImageMem(data, flags);
    }

    pub fn deleteImage(self: *Renderer, image: nvg.Image) void {
        self.vg.deleteImage(image);
    }

    pub fn drawImage(self: *Renderer, image: nvg.Image, x: f32, y: f32, w: f32, h: f32, angle: f32, alpha: f32) void {
        const paint = self.vg.imagePattern(x, y, w, h, angle, image, alpha);
        self.vg.beginPath();
        self.vg.rect(x, y, w, h);
        self.vg.fillPaint(paint);
        self.vg.fill();
    }

    pub fn drawImageBlurred(self: *Renderer, image: nvg.Image, x: f32, y: f32, w: f32, h: f32, blur_x: f32, blur_y: f32) void {
        var imageW: u32 = 0;
        var imageH: u32 = 0;
        self.vg.imageSize(image, &imageW, &imageH);
        const paint = self.vg.imageBlur(@floatFromInt(imageW), @floatFromInt(imageH), image, blur_x, blur_y);
        self.vg.beginPath();
        self.vg.rect(x, y, w, h);
        self.vg.fillPaint(paint);
        self.vg.fill();
    }

    pub fn save(self: *Renderer) void {
        self.vg.save();
    }

    pub fn restore(self: *Renderer) void {
        self.vg.restore();
    }

    pub fn clip(self: *Renderer) void {
        self.vg.clip();
    }

    pub fn scissor(self: *Renderer, x: f32, y: f32, w: f32, h: f32) void {
        self.vg.scissor(x, y, w, h);
    }

    pub fn resetScissor(self: *Renderer) void {
        self.vg.resetScissor();
    }

    pub fn translate(self: *Renderer, x: f32, y: f32) void {
        self.vg.translate(x, y);
    }

    pub fn rotate(self: *Renderer, angle: f32) void {
        self.vg.rotate(angle);
    }

    pub fn scale(self: *Renderer, sx: f32, sy: f32) void {
        self.vg.scale(sx, sy);
    }

    pub fn globalAlpha(self: *Renderer, alpha: f32) void {
        self.vg.globalAlpha(alpha);
    }

    pub fn textWidth(self: *Renderer, font: [:0]const u8, string: []const u8, font_size: f32) f32 {
        self.vg.fontFace(font);
        self.vg.fontSize(font_size);
        return self.vg.textBounds(0, 0, string, null);
    }
};

pub const ALIGN_TOP_LEFT: nvg.TextAlign = .{
    .vertical = nvg.TextAlign.VerticalAlign.top,
    .horizontal = nvg.TextAlign.HorizontalAlign.left,
};

pub const ALIGN_TOP_CENTER: nvg.TextAlign = .{
    .vertical = nvg.TextAlign.VerticalAlign.top,
    .horizontal = nvg.TextAlign.HorizontalAlign.center,
};

pub const ALIGN_TOP_RIGHT: nvg.TextAlign = .{
    .vertical = nvg.TextAlign.VerticalAlign.top,
    .horizontal = nvg.TextAlign.HorizontalAlign.right,
};

pub const ALIGN_MIDDLE_LEFT: nvg.TextAlign = .{
    .vertical = nvg.TextAlign.VerticalAlign.middle,
    .horizontal = nvg.TextAlign.HorizontalAlign.left,
};

pub const ALIGN_CENTER: nvg.TextAlign = .{
    .vertical = nvg.TextAlign.VerticalAlign.middle,
    .horizontal = nvg.TextAlign.HorizontalAlign.center,
};

pub const ALIGN_MIDDLE_RIGHT: nvg.TextAlign = .{
    .vertical = nvg.TextAlign.VerticalAlign.middle,
    .horizontal = nvg.TextAlign.HorizontalAlign.right,
};

pub const ALIGN_BOTTOM_LEFT: nvg.TextAlign = .{
    .vertical = nvg.TextAlign.VerticalAlign.bottom,
    .horizontal = nvg.TextAlign.HorizontalAlign.left,
};
pub const ALIGN_BOTTOM_CENTER: nvg.TextAlign = .{
    .vertical = nvg.TextAlign.VerticalAlign.bottom,
    .horizontal = nvg.TextAlign.HorizontalAlign.center,
};

pub const ALIGN_BOTTOM_RIGHT: nvg.TextAlign = .{
    .vertical = nvg.TextAlign.VerticalAlign.bottom,
    .horizontal = nvg.TextAlign.HorizontalAlign.right,
};

var renderer: ?Renderer = null;

pub fn init(allocator: std.mem.Allocator) !void {
    if (renderer != null) return error.RendererAlreadyInitialized;
    renderer = try Renderer.init(allocator);
}

pub fn deinit() void {
    if (renderer) |*r| {
        r.deinit();
        renderer = null;
    }
}

pub fn get() *Renderer {
    return &renderer.?;
}

pub fn rgba(r: u8, g: u8, b: u8, a: u8) nvg.Color {
    return nvg.rgba(r, g, b, a);
}

pub fn rgb(r: u8, g: u8, b: u8) nvg.Color {
    return nvg.rgb(r, g, b);
}

pub fn rgbaF(r: f32, g: f32, b: f32, a: f32) nvg.Color {
    return nvg.rgbaf(r, g, b, a);
}

pub fn rgbF(r: f32, g: f32, b: f32) nvg.Color {
    return nvg.rgbf(r, g, b);
}

pub fn gray(v: u8) nvg.Color {
    return rgb(v, v, v);
}

pub fn grayA(v: u8, a: u8) nvg.Color {
    return rgba(v,v,v,a);
}

pub fn grayF(v: f32) nvg.Color {
    return rgbF(v, v, v);
}

pub fn grayFA(v: f32, a: f32) nvg.Color {
    return rgbaF(v, v, v, a);
}