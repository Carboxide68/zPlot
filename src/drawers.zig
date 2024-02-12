const std = @import("std");
const core = @import("mach-core");
const gpu = core.gpu;

pub const LineCreator = struct {
    pub var comp_pipeline: *gpu.ComputePipeline = undefined;

    pub fn init() void {
        const comp_shader = core.device.createShaderModuleWGSL("Line Generator", @embedFile("shaders/line_generator.wgsl"));

        comp_pipeline = core.device.createComputePipeline(&.{
            .compute = .{
                .entry_point = "main",
                .module = comp_shader,
            },
        });
    }

    pub fn deinit() void {
        comp_pipeline.release();
    }

    /// Create a line out of points
    /// Returns a buffer with vertex data for a line
    pub fn make_line(points: *gpu.Buffer, thickness: f32) *gpu.Buffer {
        const device = core.device;
        const queue = device.getQueue();
        const point_buf_size = points.getSize();
        const point_count = @divExact(point_buf_size, 8); //f32s
        const uniform_buffer = device.createBuffer(&.{
            .usage = .{
                .copy_dst = true,
                .uniform = true,
            },
            .size = 100,
        });
        defer uniform_buffer.destroy();
        queue.writeBuffer(uniform_buffer, 0, std.mem.asBytes(&thickness));

        const line_buffer = device.createBuffer(&.{
            .label = "Line Buffer",
            .usage = .{
                .vertex = true,
                .storage = true,
                .copy_src = true,
                .copy_dst = true,
            },
            .size = point_buf_size * 6 - 24,
        });

        const bind_group = device.createBindGroup(&.{
            .layout = comp_pipeline.getBindGroupLayout(0),
            .entry_count = 3,
            .entries = &[_]gpu.BindGroup.Entry{
                .{ .binding = 0, .buffer = points, .offset = 0, .size = point_buf_size },
                .{ .binding = 1, .buffer = line_buffer, .offset = 0, .size = point_buf_size * 6 - 24 },
                .{ .binding = 2, .buffer = uniform_buffer, .offset = 0, .size = @sizeOf(f32) },
            },
        });
        const cmd_enc = device.createCommandEncoder(&.{});
        const pass = cmd_enc.beginComputePass(&.{});
        pass.setPipeline(comp_pipeline);
        pass.setBindGroup(0, bind_group, null);
        pass.dispatchWorkgroups(@intCast(point_count + 2), 1, 1);
        pass.end();
        pass.release();
        const cmd_buf = cmd_enc.finish(&.{});
        queue.submit(&[_]*gpu.CommandBuffer{cmd_buf});
        return line_buffer;
    }
};
