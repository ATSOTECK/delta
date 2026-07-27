const std = @import("std");
const sdl = @import("zsdl3");
const gfx = @import("gfx.zig");
const errors = @import("errors.zig");

pub const WorkspaceError = errors.SdlError || error{InitError};

pub const Workspace = struct {
    gpa: std.mem.Allocator,
    window: *sdl.SDL_Window,
    renderer: gfx.Renderer,

    should_close: bool = false,
    focused: bool = true,

    pub fn init(gpa: std.mem.Allocator) WorkspaceError!Workspace {
        const window = sdl.createWindow("Fingerspitzengefühl", 1920, 1080, sdl.SDL_WINDOW_RESIZABLE) orelse {
            return errors.sdl_error("failed to create window");
        };

        const clear_color: gfx.Color = .{ .r = 30, .g = 60, .b = 90 };
        const renderer = try gfx.Renderer.init(gpa, window, clear_color);

        const workspace: Workspace = .{
            .gpa = gpa,
            .window = window,
            .renderer = renderer,
        };
        return workspace;
    }

    pub fn deinit(self: *Workspace) void {
        sdl.destroyWindow(self.window);
    }

    pub fn handle_event(self: *Workspace, event: sdl.SDL_Event) WorkspaceError!bool {
        switch (event.type) {
            sdl.SDL_EVENT_WINDOW_CLOSE_REQUESTED => {
                self.should_close = true;
                return false;
            },
            sdl.SDL_EVENT_WINDOW_RESIZED, sdl.SDL_EVENT_WINDOW_EXPOSED => {
                try self.draw();
                return false;
            },
            sdl.SDL_EVENT_WINDOW_FOCUS_GAINED => {
                self.focused = true;
                return false;
            },
            sdl.SDL_EVENT_WINDOW_FOCUS_LOST => {
                self.focused = false;
                return false;
            },
            else => return true,
        }
    }

    pub fn draw(self: *Workspace) WorkspaceError!void {
        const renderer = &self.renderer;
        renderer.begin_frame();

        renderer.draw_rect(10, 10, 100, 100, .{ .r = 90, .g = 30, .b = 60 });
        renderer.draw_rect(60, 60, 100, 100, .{ .r = 30, .g = 90, .b = 60, .a = 100 });
        renderer.draw_rect_outline(250, 250, 100, 100, gfx.White);
        // renderer.draw_text(text, 10, 150, gfx.White);

        // renderer.draw_rect_outline(500, 100, 375, 42, gfx.Black);
        // renderer.start_clip_rect(500, 100, 375, 42);
        // renderer.draw_text(text_2, 500, 100, gfx.White);
        // renderer.end_clip_rect();

        // renderer.draw_text(text, 10, 250, gfx.White);

        try renderer.end_frame();
    }

    // fn resize(self: *Workspace) void {}
};
