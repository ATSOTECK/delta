const std = @import("std");
const sdl = @import("zsdl3");

pub fn main(init: std.process.Init) !void {
    var buf: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &buf);
    const stdout = &stdout_writer.interface;

    try stdout.print("Hello, world!\n", .{});
    try stdout.flush();

    if (!sdl.init(sdl.SDL_INIT_VIDEO)) {
        return;
    }
    defer sdl.quit();

    const window = sdl.createWindow("delta", 1920, 1080, sdl.SDL_WINDOW_RESIZABLE);
    defer sdl.destroyWindow(window);

    const renderer = sdl.createRenderer(window, null);
    defer sdl.destroyRenderer(renderer);

    while (true) {
        var event: sdl.SDL_Event = undefined;
        while (sdl.pollEvent(&event)) {
            if (event.type == sdl.SDL_EVENT_QUIT) {
                return;
            }
        }

        _ = sdl.setRenderDrawColor(renderer, 30, 60, 90, 255);
        _ = sdl.renderClear(renderer);
        _ = sdl.renderPresent(renderer);
    }
}
