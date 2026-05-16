const std = @import("std");
const appkit = @import("appkit.zig");
const metal = @import("metal.zig");
const objc = @import("obj_runtime.zig");

pub fn main() !void {
    const my_app = appkit.App.init();

    const win_rect = appkit.NSRect{ .x = 300, .y = 300, .w = 400, .h = 300 };
    const my_window = appkit.Window.init(win_rect);

    my_window.setTitle("Metal computer");

    const device = try metal.Device.init();

    const capture_manager = objc.objc_getClass("MTLCaptureManager");
    const shared_manager = objc.objc_msgSend(capture_manager, objc.sel_registerName("sharedCaptureManager"));

    const descriptor = metal.CaptureDescriptor.init(device.ptr);
    var err: objc.ID = null;
    const startSel = objc.sel_registerName("startCaptureWithDescriptor:error:");
    const StartFn = *const fn (objc.ID, ?*objc.Sel, objc.ID, ?*objc.ID) callconv(.c) bool;
    _ = @as(StartFn, @ptrCast(&objc.objc_msgSend))(shared_manager, startSel, descriptor, &err);

    const metal_layer = metal.setupMetalLayer(my_window, device);

    const render_pipeline_state = try metal.create_render_pipeline(device);
    const command_queue = device.newCommandQueue();

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

    my_window.show();

    //my_app.run();

    const buffer = device.newBufferWithBytesNoCopy(&triangle, metal.MTLStorageMode.MTLResourceStorageModeShared);

    while (true) {
        const pool = objc.objc_msgSend(objc.objc_getClass("NSAutoreleasePool"), objc.sel_registerName("alloc"));
        _ = objc.objc_msgSend(pool, objc.sel_registerName("init"));

        var count: usize = 0;
        while (count < 20) : (count += 1) {
            // nextEvent returns ?*anyopaque
            const event = my_app.nextEvent();

            // Use an 'if' capture to unwrap the optional
            if (event) |e| {
                const event_type = @as(*const fn (objc.ID, ?*objc.Sel) callconv(.c) u64, @ptrCast(&objc.objc_msgSend))(e, objc.sel_registerName("type"));

                if (event_type == 15) {
                    // Handle quit
                }

                // Pass 'e' (the unwrapped pointer) instead of 'event'
                my_app.sendEvent(e);
            } else {
                // Queue is empty, exit the inner loop
                break;
            }
        }
        std.debug.print("Drawing frame: ", .{});
        drawFrame(metal_layer, command_queue, render_pipeline_state, buffer);

        _ = objc.objc_msgSend(pool, objc.sel_registerName("release"));
    }
}

fn drawFrame(metal_layer: metal.MetalLayer, command_queue: metal.CommandQueue, render_pipeline_state: metal.RenderPipelineState, vertex_buffer: metal.Buffer) void {
    // 1. Get a fresh drawable for this specific frame
    const drawable = metal_layer.nextDrawable();
    const texture = drawable.texture();

    // 2. Setup your pass using the texture we just got
    const render_pass_descriptor = metal.RenderPassDescriptor.renderPassDescriptor();
    const render_pass_color_attachment_descriptor = render_pass_descriptor.getColorAttachemnts().get(0);

    render_pass_color_attachment_descriptor.setTexture(texture);
    render_pass_color_attachment_descriptor.setLoadAction(metal.LoadAction.LoadActionClear);
    render_pass_color_attachment_descriptor.setClearColor(.{ .alpha = 1.0, .blue = 0, .green = 1.0, .red = 0 });
    render_pass_color_attachment_descriptor.setStoreAction(metal.StoreAction.StoreActionStore);

    // 3. Encode commands
    const command_buffer = command_queue.commandBuffer();
    const command_encoder = command_buffer.renderCommandEncoder(render_pass_descriptor);
    command_encoder.setRenderPipelineState(render_pipeline_state);

    command_encoder.setVertexBuffer(vertex_buffer);
    command_encoder.drawPrimitives(metal.PrimitiveType.Triangle, 0, 3);
    command_encoder.endEncoding();
    command_buffer.presentDrawable(drawable.ptr);
    command_buffer.commit();
    //command_buffer.waitUntilCompleted();
}
