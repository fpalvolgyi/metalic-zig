const std = @import("std");
const appkit = @import("appkit.zig");
const metal = @import("metal.zig");
const objc = @import("obj_runtime.zig");

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

// "v@:@"  →  void  id(self)  SEL(_cmd)  id(notification)
fn applicationDidFinishLaunching(self: objc.ID, _: ?*objc.Sel, _: objc.ID) callconv(.c) void {
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

    // Re-activate after the window exists so it receives focus without
    // requiring a dock click. The earlier activate in App.init fires before
    // the run loop and window are ready.
    const ns_app = objc.objc_getClass("NSApplication");
    const shared = objc.objc_msgSend(ns_app, objc.sel_registerName("sharedApplication"));
    const ActivateFn = *const fn (objc.ID, ?*objc.Sel, u8) callconv(.c) void;
    @as(ActivateFn, @ptrCast(&objc.objc_msgSend))(shared, objc.sel_registerName("activateIgnoringOtherApps:"), 1);

    g_render_state = .{
        .metal_layer = layer,
        .command_queue = command_queue,
        .pipeline = pipeline,
        .vertex_buffer = vertex_buffer,
    };

    scheduleRenderTimer(self);
}

// "B@:@"  →  BOOL  id(self)  SEL(_cmd)  id(sender)
fn applicationShouldTerminateAfterLastWindowClosed(_: objc.ID, _: ?*objc.Sel, _: objc.ID) callconv(.c) bool {
    return true;
}

// "v@:@"  →  void  id(self)  SEL(_cmd)  id(timer)
fn renderTick(_: objc.ID, _: ?*objc.Sel, _: objc.ID) callconv(.c) void {
    const state = g_render_state orelse return;
    drawFrame(state.metal_layer, state.command_queue, state.pipeline, state.vertex_buffer);
}

// ---------------------------------------------------------------------------
// Delegate class registration
// ---------------------------------------------------------------------------

fn registerDelegate() objc.ID {
    const NSObject = objc.objc_getClass("NSObject");
    const cls = objc.objc_allocateClassPair(NSObject, "AppDelegate", 0).?;

    _ = objc.class_addMethod(cls, objc.sel_registerName("applicationDidFinishLaunching:"),
        @ptrCast(&applicationDidFinishLaunching), "v@:@");
    _ = objc.class_addMethod(cls, objc.sel_registerName("applicationShouldTerminateAfterLastWindowClosed:"),
        @ptrCast(&applicationShouldTerminateAfterLastWindowClosed), "B@:@");
    _ = objc.class_addMethod(cls, objc.sel_registerName("renderTick:"),
        @ptrCast(&renderTick), "v@:@");

    objc.objc_registerClassPair(cls);

    return objc.objc_msgSend(cls, objc.sel_registerName("new"));
}

fn scheduleRenderTimer(delegate: objc.ID) void {
    const NSTimer = objc.objc_getClass("NSTimer");
    const sel = objc.sel_registerName("scheduledTimerWithTimeInterval:target:selector:userInfo:repeats:");
    const Fn = *const fn (objc.ID, ?*objc.Sel, f64, objc.ID, ?*objc.Sel, objc.ID, u8) callconv(.c) objc.ID;
    _ = @as(Fn, @ptrCast(&objc.objc_msgSend))(
        NSTimer, sel,
        1.0 / 60.0,
        delegate,
        objc.sel_registerName("renderTick:"),
        null,
        1,
    );
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
