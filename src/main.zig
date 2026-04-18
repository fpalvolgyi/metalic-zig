const std = @import("std");

const bridge = @cImport({
    @cInclude("metal_bridge.h");
});

pub fn main() !void {
    const device = bridge.bridge_create_device() orelse return error.NoGpu;
    defer bridge.bridge_release_device(device);

    var name_buf: [256]u8 = undefined;
    bridge.bridge_get_device_name(device, &name_buf);

    const name_ptr: [*:0]u8 = @ptrCast(&name_buf);
    const name_slice = std.mem.span(name_ptr);

    std.debug.print("Successfully connected to: {s}\n", .{name_slice});

    // 1. Create Pipeline
    const pipeline = bridge.bridge_create_compute_pipeline(device, "add_vectors") orelse return error.PipelineFail;

    // 2. Prepare Data
    var a = [_]f32{ 1.1, 2.2, 3.3, 4.4, 5.5 };
    var b = [_]f32{ 10.0, 20.0, 30.0, 40.0, 50.0 };
    var c = [_]f32{ 0.0, 0.0, 0.0, 0.0, 0.0 };

    const bufA = bridge.bridge_create_buffer_nocopy(device, &a, a.len);
    const bufB = bridge.bridge_create_buffer_nocopy(device, &b, b.len);
    const bufC = bridge.bridge_create_buffer_nocopy(device, &c, c.len);

    // 3. Run Computation
    bridge.bridge_run_adder(device, pipeline, bufA, bufB, bufC, a.len);

    // 4. Print Results (directly from our array 'c' thanks to Unified Memory!)
    for (c, 0..) |val, i| {
        std.debug.print("Index {d}: {d:.2} + {d:.2} = {d:.2}\n", .{ i, a[i], b[i], val });
    }
}
