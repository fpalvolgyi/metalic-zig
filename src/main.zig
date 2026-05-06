const std = @import("std");
const appkit = @import("appkit.zig");
const metal = @import("metal.zig");

pub fn main() !void {
    const my_app = appkit.App.init();

    const win_rect = appkit.NSRect{ .x = 300, .y = 300, .w = 400, .h = 300 };
    const my_window = appkit.Window.init(win_rect);

    my_window.setTitle("Metal computer");

    const device = try metal.Device.init();

    const metal_layer = metal.setupMetalLayer(my_window, device);
    const drawable = metal_layer.nextDrawable();

    const render_pipeline_state = try metal.create_render_pipeline(device);
    const command_queue = device.newCommandQueue();
    const command_buffer = command_queue.commandBuffer();
    const render_pass_descriptor = metal.RenderPassDescriptor.renderPassDescriptor();
    const render_pass_color_attachment_descriptor = render_pass_descriptor.getColorAttachemnts().get(0);
    render_pass_color_attachment_descriptor.setTexture(drawable.texture());
    render_pass_color_attachment_descriptor.setLoadAction(metal.LoadAction.LoadActionClear);
    render_pass_color_attachment_descriptor.setClearColor(.{ .alpha = 1.0, .blue = 42.0 / 255.0, .green = 48.0 / 255.0, .red = 41.0 / 255.0 });
    render_pass_color_attachment_descriptor.setStoreAction(metal.StoreAction.StoreActionStore);

    const command_encoder = command_buffer.renderCommandEncoder(render_pass_descriptor);
    command_encoder.setRenderPipelineState(render_pipeline_state);

    const triangle = [3]metal.Vertex{
        .{
            .position = .{ 0.0, 0.5, 0.0 },
            .color = .{ 1.0, 0.0, 0.0, 1.0 },
        },
        .{
            .position = .{ -0.5, -0.5, 0.0 },
            .color = .{ 0.0, 1.0, 0.0, 1.0 },
        },
        .{
            .position = .{ 0.5, -0.5, 0.0 },
            .color = .{ 0.0, 0.0, 1.0, 1.0 },
        },
    };

    const buffer = device.newBufferWithBytesNoCopy(&triangle, metal.MTLStorageMode.MTLResourceStorageModeShared);
    command_encoder.setVertexBuffer(buffer);
    command_encoder.drawPrimitives(metal.PrimitiveType.Triangle, 0, 3);
    command_encoder.endEncoding();
    command_buffer.presentDrawable(drawable.ptr);
    command_buffer.commit();
    command_buffer.waitUntilCompleted();

    my_window.show();

    my_app.run();
}
