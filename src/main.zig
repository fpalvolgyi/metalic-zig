const std = @import("std");
const appkit = @import("appkit.zig");
const metal = @import("metal.zig");
const objc = @import("obj_runtime.zig");
const cv = @import("corevideo.zig");

// ---------------------------------------------------------------------------
// Particle — layout must match the Metal shader struct exactly.
// ---------------------------------------------------------------------------

const Particle = extern struct {
    position: [2]f32,
    velocity: [2]f32,
    color: [4]f32,
};

const PARTICLE_COUNT: usize = 100_000;
const THREAD_GROUP_WIDTH: usize = 64;

// ---------------------------------------------------------------------------
// Global render state
// ---------------------------------------------------------------------------

const RenderState = struct {
    metal_layer: metal.MetalLayer,
    command_queue: metal.CommandQueue,
    render_pipeline: metal.RenderPipelineState,
    compute_pipeline: metal.ComputePipelineState,
    particle_buffer: metal.Buffer,
};

var g_render_state: ?RenderState = null;

// ---------------------------------------------------------------------------
// NSApplicationDelegate callbacks
// ---------------------------------------------------------------------------

fn applicationDidFinishLaunching(_: objc.ID, _: ?*objc.Sel, _: objc.ID) callconv(.c) void {
    setup() catch |err| std.debug.print("Setup error: {}\n", .{err});
}

fn applicationShouldTerminateAfterLastWindowClosed(_: objc.ID, _: ?*objc.Sel, _: objc.ID) callconv(.c) bool {
    return true;
}

// ---------------------------------------------------------------------------
// Setup (called from the delegate callback)
// ---------------------------------------------------------------------------

fn setup() !void {
    const win_rect = appkit.NSRect{ .x = 300, .y = 300, .w = 800, .h = 600 };
    const window = appkit.Window.init(win_rect);
    window.setTitle("Particle system");

    const device = try metal.Device.init();
    const layer = metal.setupMetalLayer(window, device);
    const render_pipeline = try metal.create_render_pipeline(device, "particleVertex", "particleFragment");
    const compute_pipeline = try metal.create_compute_pipeline(device, "updateParticles");
    const command_queue = device.newCommandQueue();

    // Initialise particles on the CPU, then upload to a shared Metal buffer.
    const particles = try std.heap.page_allocator.alloc(Particle, PARTICLE_COUNT);
    defer std.heap.page_allocator.free(particles);

    var prng = std.Random.DefaultPrng.init(@bitCast(std.time.milliTimestamp()));
    const rand = prng.random();
    for (particles) |*p| {
        p.position = .{ rand.float(f32) * 2.0 - 1.0, rand.float(f32) * 2.0 - 1.0 };
        p.velocity = .{ (rand.float(f32) * 2.0 - 1.0) * 0.4, rand.float(f32) * 0.4 };
        p.color    = .{ rand.float(f32), rand.float(f32), rand.float(f32), 1.0 };
    }

    const particle_buffer = device.newBufferWithBytes(particles, .MTLResourceStorageModeShared);

    window.show();
    objc.send(void,
        objc.send(objc.ID, objc.getClass("NSApplication"), "sharedApplication", .{}),
        "activateIgnoringOtherApps:", .{@as(u8, 1)});

    g_render_state = .{
        .metal_layer     = layer,
        .command_queue   = command_queue,
        .render_pipeline = render_pipeline,
        .compute_pipeline = compute_pipeline,
        .particle_buffer = particle_buffer,
    };

    startDisplayLink();
}

// ---------------------------------------------------------------------------
// CVDisplayLink
// ---------------------------------------------------------------------------

fn displayLinkCallback(
    _: cv.CVDisplayLinkRef,
    _: ?*const anyopaque,
    _: ?*const anyopaque,
    _: cv.CVOptionFlags,
    _: ?*cv.CVOptionFlags,
    _: ?*anyopaque,
) callconv(.c) cv.CVReturn {
    const state = g_render_state orelse return 0;
    drawFrame(state);
    return 0;
}

fn startDisplayLink() void {
    var link: cv.CVDisplayLinkRef = null;
    _ = cv.CVDisplayLinkCreateWithActiveCGDisplays(&link);
    _ = cv.CVDisplayLinkSetOutputCallback(link, &displayLinkCallback, null);
    _ = cv.CVDisplayLinkStart(link);
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
// Per-frame render: compute pass (physics) → render pass (draw)
// ---------------------------------------------------------------------------

fn drawFrame(state: RenderState) void {
    const cmd = state.command_queue.commandBuffer();

    // Compute pass — update particle positions on the GPU.
    const compute_enc = cmd.computeCommandEncoder();
    compute_enc.setComputePipelineState(state.compute_pipeline);
    compute_enc.setBuffer(state.particle_buffer, 0, 0);
    compute_enc.dispatchThreads(
        .{ .width = PARTICLE_COUNT, .height = 1, .depth = 1 },
        .{ .width = THREAD_GROUP_WIDTH, .height = 1, .depth = 1 },
    );
    compute_enc.endEncoding();

    // Render pass — draw each particle as a coloured circle.
    const drawable = state.metal_layer.nextDrawable();
    const pass = metal.RenderPassDescriptor.renderPassDescriptor();
    const ca = pass.getColorAttachemnts().get(0);
    ca.setTexture(drawable.texture());
    ca.setLoadAction(.LoadActionClear);
    ca.setClearColor(.{ .red = 0.05, .green = 0.05, .blue = 0.1, .alpha = 1.0 });
    ca.setStoreAction(.StoreActionStore);

    const render_enc = cmd.renderCommandEncoder(pass);
    render_enc.setRenderPipelineState(state.render_pipeline);
    render_enc.setVertexBuffer(state.particle_buffer);
    render_enc.drawPrimitives(.Point, 0, PARTICLE_COUNT);
    render_enc.endEncoding();

    cmd.presentDrawable(drawable.ptr);
    cmd.commit();
}
