const std = @import("std");
const builtin = @import("builtin");
const sdl = @import("zsdl3");

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,

    pub fn with_alpha(self: Color, a: u8) Color {
        return .{ .r = self.r, .g = self.g, .b = self.b, .a = a };
    }
};

pub const RendererError = error{Sdl};

pub fn sdl_error(msg: []const u8) RendererError {
    std.log.err("{s}: {?s}", .{ msg, sdl.getError() });
    return error.Sdl;
}

pub const Renderer = struct {
    gpa: std.mem.Allocator,
    gpu_device: ?*sdl.SDL_GPUDevice,
    quad_pipeline: ?*sdl.SDL_GPUGraphicsPipeline = null,
    text_pipeline: ?*sdl.SDL_GPUGraphicsPipeline = null,
    pipeline_format: sdl.SDL_GPUTextureFormat = sdl.SDL_GPUTextureFormat.SDL_GPU_TEXTUREFORMAT_INVALID,
    sampler: *sdl.SDL_GPUSampler,
    clear_color: sdl.SDL_FColor,

    pub fn init(gpa: std.mem.Allocator, color: Color) RendererError!Renderer {
        const debug_mode = builtin.mode == .Debug;
        const gpu_device = sdl.createGPUDevice(sdl.SDL_GPU_SHADERFORMAT_MSL, debug_mode, null) orelse {
            return sdl_error("failed to create GPU device");
        };
        const sampler = sdl.createGPUSampler(gpu_device, &.{
            .min_filter = sdl.SDL_GPU_FILTER_LINEAR,
            .mag_filter = sdl.SDL_GPU_FILTER_LINEAR,
            .mipmap_mode = sdl.SDL_GPU_SAMPLERMIPMAPMODE_NEAREST,
            .address_mode_u = sdl.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
            .address_mode_v = sdl.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
            .address_mode_w = sdl.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
            .mip_lod_bias = 0.0,
            .max_anisotropy = 0.0,
            .compare_op = sdl.gpu.SDL_GPUCompareOp.INVALID,
            .min_lod = 0.0,
            .max_lod = 0.0,
            .enable_anisotropy = false,
            .enable_compare = false,
            .padding = .{ 0, 0 },
            .props = 0,
        }) orelse {
            return sdl_error("failed to create GPU sampler");
        };

        const clear_color: sdl.SDL_FColor = .{ .r = @as(f32, @floatFromInt(color.r)) / 255.0, .g = @as(f32, @floatFromInt(color.g)) / 255.0, .b = @as(f32, @floatFromInt(color.b)) / 255.0, .a = 1.0 };
        return .{ .gpa = gpa, .gpu_device = gpu_device, .sampler = sampler, .clear_color = clear_color };
    }

    pub fn deinit(self: *Renderer) void {
        _ = sdl.waitForGPUIdle(self.gpu_device);
        sdl.releaseGPUSampler(self.gpu_device, self.sampler);
        sdl.destroyGPUDevice(self.gpu_device);
    }

    pub fn claim_window(self: *Renderer, window: ?*sdl.SDL_Window) RendererError!void {
        if (window == null) {
            return sdl_error("tried to claim null window");
        }

        if (!sdl.claimWindowForGPUDevice(self.gpu_device, window)) {
            return sdl_error("failed to claim window for GPU device");
        }
    }

    pub fn begin_frame(self: *Renderer) void {
        _ = self;
    }

    pub fn end_frame(self: *Renderer, window: ?*sdl.SDL_Window) RendererError!void {
        const cmd_buffer = sdl.acquireGPUCommandBuffer(self.gpu_device) orelse {
            return sdl_error("failed to acquire command buffer");
        };
        var swapchain_texture: ?*sdl.SDL_GPUTexture = null;
        var sw: u32 = 0;
        var sh: u32 = 0;
        if (!sdl.waitAndAcquireGPUSwapchainTexture(cmd_buffer, window, @ptrCast(&swapchain_texture), &sw, &sh)) {
            _ = sdl.submitGPUCommandBuffer(cmd_buffer);
            return sdl_error("failed to acquire swapchain texture");
        }
        if (swapchain_texture == null) {
            // minimized
            _ = sdl.submitGPUCommandBuffer(cmd_buffer);
            return;
        }

        const color_target_info: sdl.SDL_GPUColorTargetInfo = .{
            .texture = swapchain_texture,
            .mip_level = 0,
            .layer_or_depth_plane = 0,
            .clear_color = self.clear_color,
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

        if (!sdl.submitGPUCommandBuffer(cmd_buffer)) {
            return sdl_error("failed to submit GPU command buffer");
        }
    }
};
