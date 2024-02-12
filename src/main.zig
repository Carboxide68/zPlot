const std = @import("std");
const core = @import("mach-core");
const gpu = core.gpu;

const drawers = @import("drawers.zig");

pub const App = @This();

pub const GPUInterface = core.wgpu.dawn.Interface;
pub const SYSGPUInterface = core.sysgpu.Impl;

const POINT_COUNT = 1000;

title_timer: core.Timer,
pipeline: *gpu.RenderPipeline,

point_buf: *gpu.Buffer = undefined,
line_buf: *gpu.Buffer = undefined,

pub fn main() !void {
    // Run from the directory where the executable is located so relative assets can be found.
    var buffer: [1024]u8 = undefined;
    const path = std.fs.selfExeDirPath(buffer[0..]) catch ".";
    std.os.chdir(path) catch {};

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    core.allocator = gpa.allocator();

    // Initialize GPU implementation
    if (comptime core.options.use_wgpu) try core.wgpu.Impl.init(core.allocator, .{});
    if (comptime core.options.use_sysgpu) try core.sysgpu.Impl.init(core.allocator, .{});

    var app: App = undefined;
    try app.init();
    defer app.deinit();

    while (!try core.update(&app)) {}
}

pub fn init(app: *App) !void {
    try core.init(.{});
    const device = core.device;

    const shader_module = core.device.createShaderModuleWGSL("shader.wgsl", @embedFile("shader.wgsl"));
    defer shader_module.release();

    // Fragment state
    const blend = gpu.BlendState{};
    const color_target = gpu.ColorTargetState{
        .format = core.descriptor.format,
        .blend = &blend,
        .write_mask = gpu.ColorWriteMaskFlags.all,
    };
    const fragment = gpu.FragmentState.init(.{
        .module = shader_module,
        .entry_point = "frag_main",
        .targets = &.{color_target},
    });
    const pipeline_descriptor = gpu.RenderPipeline.Descriptor{
        .fragment = &fragment,
        .vertex = gpu.VertexState{
            .module = shader_module,
            .entry_point = "vertex_main",
        },
    };
    const pipeline = device.createRenderPipeline(&pipeline_descriptor);

    app.* = .{ .title_timer = try core.Timer.start(), .pipeline = pipeline };

    drawers.LineCreator.init();

    const points = try core.allocator.alloc([2]f32, POINT_COUNT);
    defer core.allocator.free(points);
    for (points, 0..) |*point, i| {
        const f: f32 = @floatFromInt(i);
        const angle = f * 2 * std.math.pi / (POINT_COUNT - 1);
        point[0] = @cos(angle) * 0.5;
        point[1] = @sin(angle) * 0.5;
    }
    app.point_buf = device.createBuffer(&.{
        .usage = .{
            .storage = true,
            .copy_dst = true,
        },
        .size = POINT_COUNT * 8,
    });

    const queue = core.device.getQueue();
    queue.writeBuffer(app.point_buf, 0, points);
    app.line_buf = drawers.LineCreator.make_line(app.point_buf, 0.01);
}

pub fn deinit(app: *App) void {
    defer core.deinit();
    defer drawers.LineCreator.deinit();
    _ = app;
}

pub fn update(app: *App) !bool {
    const device = core.device;
    var iter = core.pollEvents();
    while (iter.next()) |event| {
        switch (event) {
            .close => return true,
            else => {},
        }
    }

    const queue = core.queue;
    const back_buffer_view = core.swap_chain.getCurrentTextureView().?;
    const color_attachment = gpu.RenderPassColorAttachment{
        .view = back_buffer_view,
        .clear_value = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
        .load_op = .clear,
        .store_op = .store,
    };

    const encoder = device.createCommandEncoder(null);
    const render_pass_info = gpu.RenderPassDescriptor.init(.{
        .color_attachments = &.{color_attachment},
    });

    const bg = device.createBindGroup(&.{
        .layout = app.pipeline.getBindGroupLayout(0),
        .entry_count = 1,
        .entries = &[_]gpu.BindGroup.Entry{
            .{
                .binding = 0,
                .buffer = app.line_buf,
                .offset = 0,
                .size = app.line_buf.getSize(),
            },
        },
    });

    const pass = encoder.beginRenderPass(&render_pass_info);
    pass.setPipeline(app.pipeline);
    pass.setBindGroup(0, bg, null);
    pass.draw(POINT_COUNT * 6, 1, 0, 0);
    pass.end();
    pass.release();

    var command = encoder.finish(null);
    encoder.release();

    queue.submit(&[_]*gpu.CommandBuffer{command});
    command.release();
    core.swap_chain.present();
    back_buffer_view.release();

    // update the window title every second
    if (app.title_timer.read() >= 1.0) {
        app.title_timer.reset();
        try core.printTitle("Triangle [ {d}fps ] [ Input {d}hz ]", .{
            core.frameRate(),
            core.inputRate(),
        });
    }

    return false;
}
