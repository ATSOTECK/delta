const std = @import("std");
const sdl = @import("zsdl3");
const errors = @import("errors.zig");
const Workspace = @import("workspace.zig").Workspace;

pub const AppError = errors.SdlError || error{InitError};

pub const App = struct {
    gpa: std.mem.Allocator,
    workspace: Workspace, // TODO: Multiple workspaces.

    should_quit: bool = false,

    pub fn init(gpa: std.mem.Allocator) AppError!App {
        if (!sdl.init(sdl.SDL_INIT_VIDEO)) {
            return errors.sdl_error("failed to init SDL");
        }
        if (!sdl.ttf.init()) {
            return errors.sdl_error("failed to init SDL_ttf");
        }

        const workspace = try Workspace.init(gpa);
        const app: App = .{
            .gpa = gpa,
            .workspace = workspace,
        };
        return app;
    }

    fn deinit(self: *App) void {
        self.workspace.deinit();
        sdl.ttf.quit();
        sdl.quit();
    }

    pub fn run(self: *App) AppError!void {
        while (!self.should_quit) {
            try self.handle_events();
            try self.workspace.draw();

            if (self.workspace.should_close) {
                self.should_quit = true;
            }
        }

        self.deinit();
    }

    fn handle_events(self: *App) AppError!void {
        var event: sdl.SDL_Event = undefined;
        while (sdl.pollEvent(&event)) {
            switch (event.type) {
                sdl.SDL_EVENT_QUIT => self.should_quit = true,
                else => break,
            }

            _ = try self.workspace.handle_event(event);
        }
    }
};
