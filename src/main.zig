const std = @import("std");
extern fn arc4random() u32;
const appkit = @import("appkit.zig");
const metal = @import("metal.zig");
const objc = @import("obj_runtime.zig");
const cv = @import("corevideo.zig");
const ui   = @import("ui.zig");
const font = @import("font.zig");

// ---------------------------------------------------------------------------
// Particle — layout must match the Metal shader struct exactly.
// ---------------------------------------------------------------------------

const Particle = extern struct {
    position: [2]f32,
    velocity: [2]f32,
    color: [4]f32,
};

const MouseUniforms = extern struct {
    pos: [2]f32,
    radius: f32,
    strength: f32,
};

const PARTICLE_COUNT: usize = 100_000;
const THREAD_GROUP_WIDTH: usize = 64;

// ---------------------------------------------------------------------------
// Global render state
// ---------------------------------------------------------------------------

const RenderState = struct {
    metal_layer:      metal.MetalLayer,
    command_queue:    metal.CommandQueue,
    render_pipeline:  metal.RenderPipelineState,
    compute_pipeline: metal.ComputePipelineState,
    particle_buffer:  metal.Buffer,
    window:           objc.ID,
    ui_pipeline:      metal.RenderPipelineState,
    ui_vertex_buffer: metal.Buffer,
    ui_sampler:       metal.SamplerState,
    batcher:          ui.QuadBatcher,
    font_atlas:       font.FontAtlas,
    screen_w:         f32,
    screen_h:         f32,
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

    const seed = @as(u64, arc4random()) << 32 | arc4random();
    var prng = std.Random.DefaultPrng.init(seed);
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

    const ui_pipeline      = try metal.create_ui_render_pipeline(device);
    const ui_vertex_buffer = device.newBufferWithLength(
        @sizeOf(ui.UIVertex) * ui.MAX_VERTICES, .MTLResourceStorageModeShared,
    );
    const ui_sampler  = device.newLinearSampler();
    const font_atlas  = try font.bake(device, "Menlo");

    g_render_state = .{
        .metal_layer      = layer,
        .command_queue    = command_queue,
        .render_pipeline  = render_pipeline,
        .compute_pipeline = compute_pipeline,
        .particle_buffer  = particle_buffer,
        .window           = window.ptr,
        .ui_pipeline      = ui_pipeline,
        .ui_vertex_buffer = ui_vertex_buffer,
        .ui_sampler       = ui_sampler,
        .batcher          = .{},
        .font_atlas       = font_atlas,
        .screen_w         = 800.0,
        .screen_h         = 600.0,
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
    if (g_render_state == null) return 0;
    drawFrame(&g_render_state.?);
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

const NSPoint = extern struct { x: f64, y: f64 };
const NSRect = extern struct {
    origin: extern struct { x: f64, y: f64 },
    size: extern struct { width: f64, height: f64 },
};

fn mousePosNDC(window: objc.ID) [2]f32 {
    const screen_pt = objc.send(NSPoint, objc.getClass("NSEvent"), "mouseLocation", .{});
    const win_pt = objc.send(NSPoint, window, "convertPointFromScreen:", .{screen_pt});
    const view = objc.send(objc.ID, window, "contentView", .{});
    const view_pt = objc.send(NSPoint, view, "convertPoint:fromView:", .{ win_pt, @as(objc.ID, null) });
    const bounds = objc.send(NSRect, view, "bounds", .{});
    const x = @as(f32, @floatCast(view_pt.x / bounds.size.width * 2.0 - 1.0));
    const y = @as(f32, @floatCast(view_pt.y / bounds.size.height * 2.0 - 1.0));
    return .{ x, y };
}

fn drawFrame(state: *RenderState) void {
    // Build UI for this frame.
    state.batcher.reset();
    const mouse_ndc = mousePosNDC(state.window);
    const mouse_px_x = (mouse_ndc[0] + 1.0) / 2.0 * state.screen_w;
    const mouse_px_y = (1.0 - mouse_ndc[1]) / 2.0 * state.screen_h;
    const atlas = &state.font_atlas;

    // HUD panel.
    state.batcher.fillRect(.{ .x = 10, .y = 10, .w = 210, .h = 82 },
        .{ .r = 0.05, .g = 0.05, .b = 0.12, .a = 0.85 });

    // Stat bars with labels.
    const label_x: f32 = 20;
    const bar_x:   f32 = 80;
    const white = ui.Color{ .r = 0.9, .g = 0.9, .b = 0.9, .a = 1 };

    state.batcher.drawText("Health", label_x, 34, white, atlas);
    state.batcher.fillRect(.{ .x = bar_x, .y = 24, .w = 90,  .h = 10 }, .{ .r = 0.85, .g = 0.25, .b = 0.25, .a = 1 });

    state.batcher.drawText("Speed",  label_x, 52, white, atlas);
    state.batcher.fillRect(.{ .x = bar_x, .y = 42, .w = 130, .h = 10 }, .{ .r = 0.25, .g = 0.75, .b = 0.35, .a = 1 });

    state.batcher.drawText("Energy", label_x, 70, white, atlas);
    state.batcher.fillRect(.{ .x = bar_x, .y = 60, .w = 55,  .h = 10 }, .{ .r = 0.25, .g = 0.50, .b = 0.95, .a = 1 });

    // Button (bottom-left) that highlights on hover.
    const btn = ui.Rect{ .x = 10, .y = state.screen_h - 50, .w = 120, .h = 36 };
    const hovered = btn.contains(mouse_px_x, mouse_px_y);
    const fill: ui.Color = if (hovered)
        .{ .r = 0.30, .g = 0.52, .b = 0.95, .a = 1 }
    else
        .{ .r = 0.18, .g = 0.38, .b = 0.80, .a = 1 };
    state.batcher.button(btn, fill, .{ .r = 0.60, .g = 0.78, .b = 1.0, .a = 1 });
    // Baseline is midpoint of button + ascent offset.
    state.batcher.drawText("Reset", btn.x + 22, btn.y + 23, white, atlas);

    // Upload UI vertices to shared GPU buffer.
    if (state.batcher.count > 0) {
        const dst = state.ui_vertex_buffer.contents() orelse unreachable;
        const byte_len = state.batcher.count * @sizeOf(ui.UIVertex);
        @memcpy(
            @as([*]u8, @ptrCast(dst))[0..byte_len],
            @as([*]const u8, @ptrCast(&state.batcher.vertices))[0..byte_len],
        );
    }

    const cmd = state.command_queue.commandBuffer();

    // Compute pass — GPU particle physics.
    const mouse = MouseUniforms{
        .pos      = mouse_ndc,
        .radius   = 0.15,
        .strength = 0.04,
    };
    const compute_enc = cmd.computeCommandEncoder();
    compute_enc.setComputePipelineState(state.compute_pipeline);
    compute_enc.setBuffer(state.particle_buffer, 0, 0);
    compute_enc.setBytes(MouseUniforms, &mouse, 1);
    compute_enc.dispatchThreads(
        .{ .width = PARTICLE_COUNT, .height = 1, .depth = 1 },
        .{ .width = THREAD_GROUP_WIDTH, .height = 1, .depth = 1 },
    );
    compute_enc.endEncoding();

    // Render pass — particles then UI, in one pass.
    const drawable = state.metal_layer.nextDrawable();
    const pass = metal.RenderPassDescriptor.renderPassDescriptor();
    const ca = pass.getColorAttachemnts().get(0);
    ca.setTexture(drawable.texture());
    ca.setLoadAction(.LoadActionClear);
    ca.setClearColor(.{ .red = 0.05, .green = 0.05, .blue = 0.1, .alpha = 1.0 });
    ca.setStoreAction(.StoreActionStore);

    const render_enc = cmd.renderCommandEncoder(pass);

    render_enc.setRenderPipelineState(state.render_pipeline);
    render_enc.setVertexBufferAt(state.particle_buffer, 0);
    render_enc.drawPrimitives(.Point, 0, PARTICLE_COUNT);

    if (state.batcher.count > 0) {
        const screen = ui.ScreenSize{ .w = state.screen_w, .h = state.screen_h };
        render_enc.setRenderPipelineState(state.ui_pipeline);
        render_enc.setVertexBufferAt(state.ui_vertex_buffer, 0);
        render_enc.setVertexBytes(ui.ScreenSize, &screen, 1);
        render_enc.setFragmentTexture(state.font_atlas.texture, 0);
        render_enc.setFragmentSamplerState(state.ui_sampler, 0);
        render_enc.drawPrimitives(.Triangle, 0, state.batcher.count);
    }

    render_enc.endEncoding();
    cmd.presentDrawable(drawable.ptr);
    cmd.commit();
}
