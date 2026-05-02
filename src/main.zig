const std = @import("std");
const appkit = @import("appkit.zig");
const metal = @import("metal.zig");

pub fn main() !void {
    const my_app = appkit.App.init();

    const win_rect = appkit.NSRect{ .x = 300, .y = 300, .w = 400, .h = 300 };
    const my_window = appkit.Window.init(win_rect);

    my_window.setTitle("Metal computer");

    const device = try metal.Device.init();

    _ = metal.setupMetalLayer(my_window, device);

    _ = try metal.create_render_pipeline(device);
    const command_queue = device.newCommandQueue();
    const command_buffer = command_queue.commandBuffer();
    const render_pass_descriptor = metal.RenderPassDescriptor.renderPassDescriptor();

    _ = command_buffer.renderCommandEncoder(render_pass_descriptor);

    my_window.show();

    my_app.run();
}
