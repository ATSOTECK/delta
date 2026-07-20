const std = @import("std");
const sdl = @import("zsdl3");
const gfx = @import("gfx.zig");
const errors = @import("errors.zig");

pub fn main(init: std.process.Init) !void {
    if (!sdl.init(sdl.SDL_INIT_VIDEO)) {
        return errors.sdl_error("failed to init SDL");
    }
    defer sdl.quit();

    const window = sdl.createWindow("delta", 1920, 1080, sdl.SDL_WINDOW_RESIZABLE);
    if (window == null) {
        return errors.sdl_error("failed to create window");
    }
    defer sdl.destroyWindow(window);

    const clear_color: gfx.Color = .{ .r = 30, .g = 60, .b = 90 };
    var renderer = try gfx.Renderer.init(init.gpa, window, clear_color);
    defer renderer.deinit();

    while (true) {
        var event: sdl.SDL_Event = undefined;
        while (sdl.pollEvent(&event)) {
            if (event.type == sdl.SDL_EVENT_QUIT) {
                return;
            }
        }

        renderer.begin_frame();

        renderer.rect(10, 10, 100, 100, .{ .r = 90, .g = 30, .b = 60 });

        try renderer.end_frame(window);
    }
}
