const std = @import("std");
const builtin = @import("builtin");
const sdl = @import("zsdl3");
const errors = @import("errors.zig");

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,

    pub fn with_alpha(self: Color, a: u8) Color {
        return .{ .r = self.r, .g = self.g, .b = self.b, .a = a };
    }
};

pub const RendererError = errors.SdlError || error{InitError};

pub const Renderer = struct {
    gpa: std.mem.Allocator,
    window: *sdl.SDL_Window,
    renderer: *sdl.SDL_Renderer,
    clear_color: Color,

    window_w: f32 = 0.0,
    window_h: f32 = 0.0,

    pub fn init(gpa: std.mem.Allocator, window: *sdl.SDL_Window, clear_color: Color) RendererError!Renderer {
        const sdl_renderer = sdl.createRenderer(window, null) orelse {
            return errors.sdl_error("failed to create renderer");
        };

        if (!sdl.setRenderDrawBlendMode(sdl_renderer, sdl.SDL_BLENDMODE_BLEND)) {
            return errors.sdl_error("failed to set blend mode");
        }

        const renderer: Renderer = .{
            .gpa = gpa,
            .window = window,
            .renderer = sdl_renderer,
            .clear_color = clear_color,
        };

        return renderer;
    }

    pub fn deinit(self: *Renderer) void {
        sdl.destroyRenderer(self.renderer);
    }

    pub fn begin_frame(self: *Renderer) void {
        _ = sdl.setRenderDrawColor(self.renderer, self.clear_color.r, self.clear_color.g, self.clear_color.b, 255);
        _ = sdl.renderClear(self.renderer);
    }

    pub fn end_frame(self: *Renderer) RendererError!void {
        if (!sdl.renderPresent(self.renderer)) {
            return errors.sdl_error("failed to present");
        }
    }

    pub fn draw_rect(self: *Renderer, x: f32, y: f32, w: f32, h: f32, color: Color) void {
        if (w <= 0 or h <= 0 or color.a == 0) {
            return;
        }

        const rect: sdl.SDL_FRect = .{ .x = x, .y = y, .w = w, .h = h };
        _ = sdl.setRenderDrawColor(self.renderer, color.r, color.g, color.b, color.a);
        _ = sdl.renderFillRect(self.renderer, &rect);
    }

    pub fn draw_text(self: *Renderer, text: *sdl.ttf.TTF_Text, x: f32, y: f32, color: Color) void {
        _ = sdl.setRenderDrawColor(self.renderer, color.r, color.g, color.b, color.a);
        _ = sdl.ttf.drawRendererText(text, x, y);
    }
};
