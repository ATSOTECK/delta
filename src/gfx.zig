const std = @import("std");
const builtin = @import("builtin");
const sdl = @import("zsdl3");
const errors = @import("errors.zig");

const msl_source =
    \\#include <metal_stdlib>
    \\using namespace metal;
    \\struct VU { float2 screen; float2 translate; };
    \\struct QuadIn { float2 pos [[attribute(0)]]; float4 color [[attribute(1)]]; };
    \\struct QuadOut { float4 pos [[position]]; float4 color; };
    \\vertex QuadOut quad_vs(QuadIn in [[stage_in]], constant VU& u [[buffer(0)]]) {
    \\    QuadOut o;
    \\    float2 p = in.pos + u.translate;
    \\    o.pos = float4(p.x / u.screen.x * 2.0 - 1.0, 1.0 - p.y / u.screen.y * 2.0, 0.0, 1.0);
    \\    o.color = in.color;
    \\    return o;
    \\}
    \\fragment float4 quad_fs(QuadOut in [[stage_in]]) { return in.color; }
;

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,

    pub fn with_alpha(self: Color, a: u8) Color {
        return .{ .r = self.r, .g = self.g, .b = self.b, .a = a };
    }
};

const QuadVert = struct { x: f32, y: f32, color: Color };
const VertUniform = extern struct { window_w: f32, window_h: f32, tx: f32, ty: f32 };

const Cmd = union(enum) {
    quads: struct { first: u32, count: u32 },
    // scissor: sdl.SDL_Rect,
    // scissor_off,
};

const FrameBufs = struct {
    quad_buf: ?*sdl.SDL_GPUBuffer = null,
    quad_cap: u32 = 0,
    text_vbuf: ?*sdl.SDL_GPUBuffer = null,
    text_vcap: u32 = 0,
    text_ibuf: ?*sdl.SDL_GPUBuffer = null,
    text_icap: u32 = 0,
    transfer: ?*sdl.SDL_GPUTransferBuffer = null,
    transfer_cap: u32 = 0,
};

pub const RendererError = errors.SdlError || error{InitError};

pub const Renderer = struct {
    gpa: std.mem.Allocator,
    window: ?*sdl.SDL_Window,
    gpu_device: ?*sdl.SDL_GPUDevice,
    quad_pipeline: ?*sdl.SDL_GPUGraphicsPipeline = null,
    text_pipeline: ?*sdl.SDL_GPUGraphicsPipeline = null,
    pipeline_format: sdl.SDL_GPUTextureFormat = sdl.SDL_GPUTextureFormat.SDL_GPU_TEXTUREFORMAT_INVALID,
    sampler: *sdl.SDL_GPUSampler,
    clear_color: sdl.SDL_FColor,

    cmds: std.ArrayList(Cmd) = .empty,
    quad_verts: std.ArrayList(QuadVert) = .empty,

    window_w: f32 = 0.0,
    window_h: f32 = 0.0,
    frames: [3]FrameBufs = .{ .{}, .{}, .{} },
    frame_index: u32 = 0,

    pub fn init(gpa: std.mem.Allocator, window: ?*sdl.SDL_Window, color: Color) RendererError!Renderer {
        if (window == null) {
            return RendererError.InitError;
        }

        const debug_mode = builtin.mode == .Debug;
        const gpu_device = sdl.createGPUDevice(sdl.SDL_GPU_SHADERFORMAT_MSL, debug_mode, null) orelse {
            return errors.sdl_error("failed to create GPU device");
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
            return errors.sdl_error("failed to create GPU sampler");
        };

        const clear_color: sdl.SDL_FColor = .{
            .r = @as(f32, @floatFromInt(color.r)) / 255.0,
            .g = @as(f32, @floatFromInt(color.g)) / 255.0,
            .b = @as(f32, @floatFromInt(color.b)) / 255.0,
            .a = 1.0,
        };
        var renderer: Renderer = .{
            .gpa = gpa,
            .window = window,
            .gpu_device = gpu_device,
            .sampler = sampler,
            .clear_color = clear_color,
        };
        try renderer.claim_window();

        return renderer;
    }

    pub fn deinit(self: *Renderer) void {
        _ = sdl.waitForGPUIdle(self.gpu_device);
        sdl.releaseGPUSampler(self.gpu_device, self.sampler);
        sdl.destroyGPUDevice(self.gpu_device);
    }

    fn claim_window(self: *Renderer) RendererError!void {
        if (self.window == null) {
            return errors.sdl_error("tried to claim null window");
        }

        if (!sdl.claimWindowForGPUDevice(self.gpu_device, self.window)) {
            return errors.sdl_error("failed to claim window for GPU device");
        }

        var w: c_int = undefined;
        var h: c_int = undefined;
        if (!sdl.getWindowSize(self.window, &w, &h)) {
            return errors.sdl_error("failed to get window size");
        }
        self.window_w = @as(f32, @floatFromInt(w));
        self.window_h = @as(f32, @floatFromInt(h));

        if (self.quad_pipeline == null) {
            const fmt = sdl.getGPUSwapchainTextureFormat(self.gpu_device, self.window);
            try self.create_pipelines(fmt);
        }
    }

    fn make_shader(self: *Renderer, entry: [*:0]const u8, stage: sdl.SDL_GPUShaderStage, num_samplers: u32, num_uniforms: u32) RendererError!*sdl.SDL_GPUShader {
        return sdl.createGPUShader(self.gpu_device, &.{
            .code = msl_source,
            .code_size = msl_source.len,
            .entrypoint = entry,
            .format = sdl.SDL_GPU_SHADERFORMAT_MSL,
            .stage = stage,
            .num_samplers = num_samplers,
            .num_storage_textures = 0,
            .num_storage_buffers = 0,
            .num_uniform_buffers = num_uniforms,
            .props = 0,
        }) orelse errors.sdl_error("failed to create GPU pipeline");
    }

    fn create_pipelines(self: *Renderer, fmt: sdl.SDL_GPUTextureFormat) RendererError!void {
        self.pipeline_format = fmt;
        const quad_vs = try self.make_shader("quad_vs", sdl.SDL_GPU_SHADERSTAGE_VERTEX, 0, 1);
        defer sdl.releaseGPUShader(self.gpu_device, quad_vs);
        const quad_fs = try self.make_shader("quad_fs", sdl.SDL_GPU_SHADERSTAGE_FRAGMENT, 0, 0);
        defer sdl.releaseGPUShader(self.gpu_device, quad_fs);

        const blend: sdl.gpu.SDL_GPUColorTargetBlendState = .{
            .enable_blend = true,
            .src_color_blendfactor = sdl.SDL_GPU_BLENDFACTOR_SRC_ALPHA,
            .dst_color_blendfactor = sdl.SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
            .color_blend_op = sdl.SDL_GPU_BLENDOP_ADD,
            .src_alpha_blendfactor = sdl.SDL_GPU_BLENDFACTOR_SRC_ALPHA,
            .dst_alpha_blendfactor = sdl.SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
            .alpha_blend_op = sdl.SDL_GPU_BLENDOP_ADD,
            .color_write_mask = 0,
            .enable_color_write_mask = false,
            .padding = .{ 0, 0 },
        };
        var color_target = sdl.gpu.SDL_GPUColorTargetDescription{ .format = fmt, .blend_state = blend };

        var quad_attrs = [_]sdl.gpu.SDL_GPUVertexAttribute{
            .{
                .location = 0,
                .buffer_slot = 0,
                .format = sdl.gpu.SDL_GPUVertexElementFormat.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2,
                .offset = 0,
            },
            .{
                .location = 1,
                .buffer_slot = 0,
                .format = sdl.gpu.SDL_GPUVertexElementFormat.SDL_GPU_VERTEXELEMENTFORMAT_UBYTE4_NORM,
                .offset = 8,
            },
        };
        var quad_vb = [_]sdl.gpu.SDL_GPUVertexBufferDescription{.{
            .slot = 0,
            .pitch = @sizeOf(QuadVert),
            .input_rate = sdl.SDL_GPU_VERTEXINPUTRATE_VERTEX,
            .instance_step_rate = 0,
        }};
        self.quad_pipeline = sdl.createGPUGraphicsPipeline(self.gpu_device, &.{
            .vertex_shader = quad_vs,
            .fragment_shader = quad_fs,
            .primitive_type = sdl.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
            .rasterizer_state = .{
                .fill_mode = sdl.SDL_GPU_FILLMODE_FILL,
                .cull_mode = sdl.SDL_GPU_CULLMODE_NONE,
                .front_face = sdl.gpu.SDL_GPUFrontFace.SDL_GPU_FRONTFACE_COUNTER_CLOCKWISE,
                .depth_bias_constant_factor = 0.0,
                .depth_bias_clamp = 0.0,
                .depth_bias_slope_factor = 0.0,
                .enable_depth_bias = false,
                .enable_depth_clip = false,
                .padding = .{ 0, 0 },
            },
            .vertex_input_state = .{
                .vertex_buffer_descriptions = &quad_vb,
                .num_vertex_buffers = 1,
                .vertex_attributes = &quad_attrs,
                .num_vertex_attributes = 2,
            },
            .target_info = .{
                .color_target_descriptions = @ptrCast(&color_target),
                .num_color_targets = 1,
                .depth_stencil_format = sdl.SDL_GPUTextureFormat.SDL_GPU_TEXTUREFORMAT_INVALID,
                .has_depth_stencil_target = false,
                .padding = .{ 0, 0, 0 },
            },
            .multisample_state = .{
                .sample_count = sdl.gpu.SDL_GPUSampleCount.SDL_GPU_SAMPLECOUNT_1,
                .sample_mask = 0,
                .enable_mask = false,
                .enable_alpha_to_coverage = false,
                .padding = .{ 0, 0 },
            },
            .depth_stencil_state = .{
                .compare_op = sdl.gpu.SDL_GPUCompareOp.INVALID,
                .back_stencil_state = .{
                    .fail_op = sdl.gpu.SDL_GPUStencilOp.SDL_GPU_STENCILOP_INVALID,
                    .pass_op = sdl.gpu.SDL_GPUStencilOp.SDL_GPU_STENCILOP_INVALID,
                    .depth_fail_op = sdl.gpu.SDL_GPUStencilOp.SDL_GPU_STENCILOP_INVALID,
                    .compare_op = sdl.gpu.SDL_GPUCompareOp.INVALID,
                },
                .front_stencil_state = .{
                    .fail_op = sdl.gpu.SDL_GPUStencilOp.SDL_GPU_STENCILOP_INVALID,
                    .pass_op = sdl.gpu.SDL_GPUStencilOp.SDL_GPU_STENCILOP_INVALID,
                    .depth_fail_op = sdl.gpu.SDL_GPUStencilOp.SDL_GPU_STENCILOP_INVALID,
                    .compare_op = sdl.gpu.SDL_GPUCompareOp.INVALID,
                },
                .compare_mask = 0,
                .write_mask = 0,
                .enable_depth_test = false,
                .enable_depth_write = false,
                .enable_stencil_test = false,
                .padding = .{ 0, 0, 0 },
            },
            .props = 0,
        }) orelse return errors.sdl_error("failed to create quad pipeline");
    }

    pub fn begin_frame(self: *Renderer) void {
        self.cmds.clearRetainingCapacity();
        self.quad_verts.clearRetainingCapacity();
    }

    pub fn end_frame(self: *Renderer, window: ?*sdl.SDL_Window) RendererError!void {
        const cmd_buffer = sdl.acquireGPUCommandBuffer(self.gpu_device) orelse {
            return errors.sdl_error("failed to acquire command buffer");
        };
        var swapchain_texture: ?*sdl.SDL_GPUTexture = null;
        var sw: u32 = 0;
        var sh: u32 = 0;
        if (!sdl.waitAndAcquireGPUSwapchainTexture(cmd_buffer, window, @ptrCast(&swapchain_texture), &sw, &sh)) {
            _ = sdl.submitGPUCommandBuffer(cmd_buffer);
            return errors.sdl_error("failed to acquire swapchain texture");
        }
        if (swapchain_texture == null) {
            // minimized
            _ = sdl.submitGPUCommandBuffer(cmd_buffer);
            return;
        }

        const quad_bytes: u32 = @intCast(self.quad_verts.items.len * @sizeOf(QuadVert));
        const total: u32 = quad_bytes;

        const fb = &self.frames[self.frame_index % self.frames.len];
        self.frame_index +%= 1;

        if (total > 0) {
            try self.ensure_buffer(&fb.quad_buf, &fb.quad_cap, @max(quad_bytes, 1), sdl.SDL_GPU_BUFFERUSAGE_VERTEX);
            if (total > fb.transfer_cap) {
                var new_cap: u32 = @max(fb.transfer_cap, 16384);
                while (new_cap < total) new_cap *= 2;
                if (fb.transfer) |t| {
                    sdl.releaseGPUTransferBuffer(self.gpu_device, t);
                }

                fb.transfer = sdl.createGPUTransferBuffer(self.gpu_device, &.{
                    .usage = sdl.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
                    .size = new_cap,
                    .props = 0,
                }) orelse return errors.sdl_error("failed to create GPU transfer buffer");
                fb.transfer_cap = new_cap;
            }

            const mapped: [*]u8 = @ptrCast(sdl.mapGPUTransferBuffer(self.gpu_device, fb.transfer, true) orelse
                return errors.sdl_error("failed to map GPU transfer buffer"));

            if (quad_bytes > 0) {
                @memcpy(mapped[0..quad_bytes], @as([*]const u8, @ptrCast(self.quad_verts.items.ptr))[0..quad_bytes]);
            }
            sdl.unmapGPUTransferBuffer(self.gpu_device, fb.transfer);

            const copy = sdl.beginGPUCopyPass(cmd_buffer);
            if (quad_bytes > 0) {
                sdl.uploadToGPUBuffer(copy, &.{
                    .transfer_buffer = fb.transfer,
                    .offset = 0,
                }, &.{ .buffer = fb.quad_buf, .offset = 0, .size = quad_bytes }, true);
            }
            sdl.endGPUCopyPass(copy);
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

        const base_uniform = VertUniform{ .window_w = self.window_w, .window_h = self.window_h, .tx = 0, .ty = 0 };

        const Bound = enum { none, quad, text };
        var bound: Bound = .none;
        for (self.cmds.items) |cmd| {
            switch (cmd) {
                .quads => |q| {
                    if (bound != .quad) {
                        const binding: sdl.SDL_GPUBufferBinding = .{ .buffer = fb.quad_buf, .offset = 0 };
                        sdl.bindGPUGraphicsPipeline(render_pass, self.quad_pipeline);
                        sdl.bindGPUVertexBuffers(render_pass, 0, @ptrCast(&binding), 1);
                        sdl.pushGPUVertexUniformData(cmd_buffer, 0, &base_uniform, @sizeOf(VertUniform));
                        bound = .quad;
                    }
                    sdl.drawGPUPrimitives(render_pass, q.count, 1, q.first, 0);
                },
            }
        }

        sdl.endGPURenderPass(render_pass);

        if (!sdl.submitGPUCommandBuffer(cmd_buffer)) {
            return errors.sdl_error("failed to submit GPU command buffer");
        }
    }

    fn ensure_buffer(self: *Renderer, buf: *?*sdl.SDL_GPUBuffer, cap: *u32, needed: u32, usage: sdl.SDL_GPUBufferUsageFlags) RendererError!void {
        if (needed <= cap.*) {
            return;
        }

        var new_cap: u32 = @max(cap.*, 4096);
        while (new_cap < needed) {
            new_cap *= 2;
        }

        if (buf.*) |b| {
            sdl.releaseGPUBuffer(self.gpu_device, b);
        }

        buf.* = sdl.createGPUBuffer(self.gpu_device, &.{ .usage = usage, .size = new_cap, .props = 0 }) orelse {
            return errors.sdl_error("failed to create GPU buffer");
        };
        cap.* = new_cap;
    }

    pub fn rect(self: *Renderer, x: f32, y: f32, w: f32, h: f32, color: Color) void {
        if (w <= 0 or h <= 0 or color.a == 0) {
            return;
        }

        const first: u32 = @intCast(self.quad_verts.items.len);
        const vs = [_]QuadVert{
            .{ .x = x, .y = y, .color = color },
            .{ .x = x + w, .y = y, .color = color },
            .{ .x = x + w, .y = y + h, .color = color },
            .{ .x = x, .y = y, .color = color },
            .{ .x = x + w, .y = y + h, .color = color },
            .{ .x = x, .y = y + h, .color = color },
        };
        self.quad_verts.appendSlice(self.gpa, &vs) catch return;

        // Merge with previous quads command if contiguous.
        if (self.cmds.items.len > 0) {
            const last = &self.cmds.items[self.cmds.items.len - 1];
            if (last.* == .quads and last.quads.first + last.quads.count == first) {
                last.quads.count += 6;
                return;
            }
        }
        self.cmds.append(self.gpa, .{ .quads = .{ .first = first, .count = 6 } }) catch {};
    }
};
