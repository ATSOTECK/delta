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

    const debug_mode = true;
    const gpu_device = sdl.createGPUDevice(sdl.SDL_GPU_SHADERFORMAT_MSL, debug_mode, null);

    if (!sdl.claimWindowForGPUDevice(gpu_device, window)) {
        return;
    }
    defer sdl.releaseWindowFromGPUDevice(gpu_device, window);

    while (true) {
        var event: sdl.SDL_Event = undefined;
        while (sdl.pollEvent(&event)) {
            if (event.type == sdl.SDL_EVENT_QUIT) {
                return;
            }
        }

        const cmd_buffer = sdl.acquireGPUCommandBuffer(gpu_device);
        if (cmd_buffer == null) {
            continue;
        }

        var swapchain_texture: ?*sdl.SDL_GPUTexture = undefined;
        if (sdl.waitAndAcquireGPUSwapchainTexture(cmd_buffer, window, &swapchain_texture, null, null)) {
            if (swapchain_texture != null) {
                const clear_color: sdl.SDL_FColor = .{ .r = @as(f32, @floatFromInt(30)) / 255.0, .g = @as(f32, @floatFromInt(60)) / 255.0, .b = @as(f32, @floatFromInt(90)) / 255.0, .a = 1.0 };

                const color_target_info: sdl.SDL_GPUColorTargetInfo = .{
                    .texture = swapchain_texture,
                    .mip_level = 0,
                    .layer_or_depth_plane = 0,
                    .clear_color = clear_color,
                    .load_op = sdl.SDL_GPU_LOADOP_CLEAR,
                    .store_op = sdl.SDL_GPU_STOREOP_STORE,
                    .resolve_texture = null,
                    .resolve_mip_level = 0,
                    .resolve_layer = 0,
                    .cycle = false,
                    .cycle_resolve_texture = false,
                    .padding = .{ 0, 0 },
                };

                const render_pass = sdl.beginGPURenderPass(cmd_buffer, @ptrCast(&color_target_info), 1, null);
                sdl.endGPURenderPass(render_pass);
            }

            _ = sdl.submitGPUCommandBuffer(cmd_buffer);
        }
    }
}
