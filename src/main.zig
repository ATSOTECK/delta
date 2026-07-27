const std = @import("std");
const sdl = @import("zsdl3");
const gfx = @import("gfx.zig");
const errors = @import("errors.zig");

pub fn main(init: std.process.Init) !void {
    const cwd = std.Io.Dir.cwd();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    if (cwd.realPathFile(init.io, ".", &path_buf)) |path_len| {
        const current_dir = path_buf[0..path_len];
        std.debug.print("cwd: {s}\n", .{current_dir});
    } else |err| {
        std.debug.print("Failed to get current directory: {any}\n", .{err});
        return err;
    }

    if (!sdl.init(sdl.SDL_INIT_VIDEO)) {
        return errors.sdl_error("failed to init SDL");
    }
    defer sdl.quit();
    if (!sdl.ttf.init()) {
        return errors.sdl_error("failed to init SDL_ttf");
    }
    defer sdl.ttf.quit();

    const window = sdl.createWindow("delta - Fingerspitzengefühl", 1920, 1080, sdl.SDL_WINDOW_RESIZABLE) orelse {
        return errors.sdl_error("failed to create window");
    };
    defer sdl.destroyWindow(window);

    const clear_color: gfx.Color = .{ .r = 30, .g = 60, .b = 90 };
    var renderer = try gfx.Renderer.init(init.gpa, window, clear_color);
    defer renderer.deinit();

    const text_engine: ?*sdl.ttf.TTF_TextEngine = sdl.ttf.createRendererTextEngine(renderer.renderer) orelse {
        return errors.sdl_error("failed to create GPU text engine");
    };
    const font: *sdl.ttf.TTF_Font = sdl.ttf.openFont("assets/font/JetBrainsMono-Regular.ttf", 32) orelse {
        return errors.sdl_error("failed to load font");
    };
    const text: *sdl.ttf.TTF_Text = sdl.ttf.createText(text_engine, font, "Hello, world!", 0) orelse {
        return errors.sdl_error("failed to create text");
    };

    const text_2: *sdl.ttf.TTF_Text = sdl.ttf.createText(text_engine, font, "This is a really long line of text isn't it!", 0) orelse {
        return errors.sdl_error("failed to create text");
    };

    while (true) {
        var event: sdl.SDL_Event = undefined;
        while (sdl.pollEvent(&event)) {
            if (event.type == sdl.SDL_EVENT_QUIT) {
                return;
            }
        }

        renderer.begin_frame();

        renderer.draw_rect(10, 10, 100, 100, .{ .r = 90, .g = 30, .b = 60 });
        renderer.draw_rect(60, 60, 100, 100, .{ .r = 30, .g = 90, .b = 60, .a = 100 });
        renderer.draw_rect_outline(250, 250, 100, 100, gfx.White);
        renderer.draw_text(text, 10, 150, gfx.White);

        renderer.draw_rect_outline(500, 100, 375, 42, gfx.Black);
        renderer.start_clip_rect(500, 100, 375, 42);
        renderer.draw_text(text_2, 500, 100, gfx.White);
        renderer.end_clip_rect();

        renderer.draw_text(text, 10, 250, gfx.White);

        try renderer.end_frame();
    }
}
