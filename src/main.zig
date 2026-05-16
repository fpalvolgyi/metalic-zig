const std = @import("std");
const appkit = @import("appkit.zig");
const metal = @import("metal.zig");
const objc = @import("obj_runtime.zig");
const cv = @import("corevideo.zig");

// ---------------------------------------------------------------------------
// Global render state — populated in applicationDidFinishLaunching, read by
// the NSTimer callback on every display tick.
// ---------------------------------------------------------------------------
const RenderState = struct {
    metal_layer: metal.MetalLayer,
    command_queue: metal.CommandQueue,
    pipeline: metal.RenderPipelineState,
    vertex_buffer: metal.Buffer,
};

var g_render_state: ?RenderState = null;

const triangle = [3]metal.Vertex{
    .{ .position = .{ 0.0, 0.5, 0.0 }, .color = .{ 1.0, 0.0, 0.0, 1.0 } },
    .{ .position = .{ -0.5, -0.5, 0.0 }, .color = .{ 0.0, 1.0, 0.0, 1.0 } },
    .{ .position = .{ 0.5, -0.5, 0.0 }, .color = .{ 0.0, 0.0, 1.0, 1.0 } },
};

// ---------------------------------------------------------------------------
// NSApplicationDelegate callbacks
// ---------------------------------------------------------------------------

fn applicationDidFinishLaunching(_: objc.ID, _: ?*objc.Sel, _: objc.ID) callconv(.c) void {
    const win_rect = appkit.NSRect{ .x = 300, .y = 300, .w = 800, .h = 600 };
    const window = appkit.Window.init(win_rect);
    window.setTitle("Metal kernel");

    const device = metal.Device.init() catch {
        std.debug.print("ERROR: no GPU found\n", .{});
        return;
    };

    const layer = metal.setupMetalLayer(window, device);

    const pipeline = metal.create_render_pipeline(device) catch {
        std.debug.print("ERROR: pipeline creation failed\n", .{});
        return;
    };

    const command_queue = device.newCommandQueue();
    const vertex_buffer = device.newBufferWithBytes(&triangle, .MTLResourceStorageModeShared);

    window.show();

    // Activate after the window exists so it receives focus without a dock click.
    objc.send(void, objc.send(objc.ID, objc.getClass("NSApplication"), "sharedApplication", .{}),
        "activateIgnoringOtherApps:", .{@as(u8, 1)});

    g_render_state = .{
        .metal_layer = layer,
        .command_queue = command_queue,
        .pipeline = pipeline,
        .vertex_buffer = vertex_buffer,
    };

    startDisplayLink();
}

fn applicationShouldTerminateAfterLastWindowClosed(_: objc.ID, _: ?*objc.Sel, _: objc.ID) callconv(.c) bool {
    return true;
}

fn displayLinkCallback(
    _: cv.CVDisplayLinkRef,
    _: ?*const anyopaque,
    _: ?*const anyopaque,
    _: cv.CVOptionFlags,
    _: ?*cv.CVOptionFlags,
    _: ?*anyopaque,
) callconv(.c) cv.CVReturn {
    const state = g_render_state orelse return 0;
    drawFrame(state.metal_layer, state.command_queue, state.pipeline, state.vertex_buffer);
    return 0;
}

// ---------------------------------------------------------------------------
// Delegate class registration
// ---------------------------------------------------------------------------

fn registerDelegate() objc.ID {
    const cls = objc.objc_allocateClassPair(objc.getClass("NSObject"), "AppDelegate", 0).?;

    _ = objc.class_addMethod(cls, objc.sel_registerName("applicationDidFinishLaunching:"),
        @ptrCast(&applicationDidFinishLaunching), "v@:@");
    _ = objc.class_addMethod(cls, objc.sel_registerName("applicationShouldTerminateAfterLastWindowClosed:"),
        @ptrCast(&applicationShouldTerminateAfterLastWindowClosed), "B@:@");

    objc.objc_registerClassPair(cls);

    return objc.send(objc.ID, cls, "new", .{});
}

fn startDisplayLink() void {
    var link: cv.CVDisplayLinkRef = null;
    _ = cv.CVDisplayLinkCreateWithActiveCGDisplays(&link);
    _ = cv.CVDisplayLinkSetOutputCallback(link, &displayLinkCallback, null);
    _ = cv.CVDisplayLinkStart(link);
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

pub fn main() !void {
    const app = appkit.App.init();
    const delegate = registerDelegate();
    app.setDelegate(delegate);
    app.run();
}

// ---------------------------------------------------------------------------
// Render
// ---------------------------------------------------------------------------

fn drawFrame(
    metal_layer: metal.MetalLayer,
    command_queue: metal.CommandQueue,
    pipeline: metal.RenderPipelineState,
    vertex_buffer: metal.Buffer,
) void {
    const drawable = metal_layer.nextDrawable();
    const texture = drawable.texture();

    const pass = metal.RenderPassDescriptor.renderPassDescriptor();
    const color_attach = pass.getColorAttachemnts().get(0);
    color_attach.setTexture(texture);
    color_attach.setLoadAction(metal.LoadAction.LoadActionClear);
    color_attach.setClearColor(.{ .red = 0.1, .green = 0.1, .blue = 0.15, .alpha = 1.0 });
    color_attach.setStoreAction(metal.StoreAction.StoreActionStore);

    const cmd = command_queue.commandBuffer();
    const enc = cmd.renderCommandEncoder(pass);
    enc.setRenderPipelineState(pipeline);
    enc.setVertexBuffer(vertex_buffer);
    enc.drawPrimitives(metal.PrimitiveType.Triangle, 0, 3);
    enc.endEncoding();

    cmd.presentDrawable(drawable.ptr);
    cmd.commit();
}
