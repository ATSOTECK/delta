const std = @import("std");
const App = @import("app.zig").App;

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

    var app = try App.init(init.gpa);
    try app.run();

    // const text_engine: ?*sdl.ttf.TTF_TextEngine = sdl.ttf.createRendererTextEngine(renderer.renderer) orelse {
    //     return errors.sdl_error("failed to create GPU text engine");
    // };
    // const font: *sdl.ttf.TTF_Font = sdl.ttf.openFont("assets/font/JetBrainsMono-Regular.ttf", 32) orelse {
    //     return errors.sdl_error("failed to load font");
    // };
    // const text: *sdl.ttf.TTF_Text = sdl.ttf.createText(text_engine, font, "Hello, world!", 0) orelse {
    //     return errors.sdl_error("failed to create text");
    // };

    // const text_2: *sdl.ttf.TTF_Text = sdl.ttf.createText(text_engine, font, "This is a really long line of text isn't it!", 0) orelse {
    //     return errors.sdl_error("failed to create text");
    // };
}
