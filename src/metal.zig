const objc = @import("obj_runtime.zig");
const appkit = @import("appkit.zig");
const std = @import("std");

pub const Vertex = extern struct {
    position: [3]f32,
    color: [4]f32,
};

extern "c" fn MTLCreateSystemDefaultDevice() ?*anyopaque;

pub fn getBufferPointer(buffer: objc.ID) [*]Vertex {
    const sel = objc.sel_registerName("contents");
    const contents = objc.objc_msgSend(buffer, sel);
    return @ptrCast(@alignCast(contents));
}

pub const MTLStorageMode = enum(usize) { MTLResourceStorageModeShared = 0 };
pub const PrimitiveType = enum(usize) { Point = 0, Line = 1, LineStrip = 2, Triangle = 3, TriangleStrip = 4 };

pub const Buffer = struct { ptr: objc.ID };

pub const Device = struct {
    ptr: objc.ID,

    pub fn init() !Device {
        const dev = MTLCreateSystemDefaultDevice();
        if (dev == null) return error.NoGpuFound;

        return .{ .ptr = dev };
    }

    pub fn newBufferWithBytesNoCopy(self: Device, data: []const Vertex, storage_mode: MTLStorageMode) Buffer {
        const sel = objc.sel_registerName("newBufferWithBytesNoCopy:length:options:deallocator:");
        const NoCopyFn = *const fn (objc.ID, ?*objc.Sel, ?*const anyopaque, usize, usize, ?*anyopaque) callconv(.c) objc.ID;
        const msgSendNoCopy: NoCopyFn = @ptrCast(&objc.objc_msgSend);
        // Options:
        // 0 =
        // (Required for NoCopy on macOS/iOS)
        return .{ .ptr = msgSendNoCopy(self.ptr, sel, data.ptr, data.len * @sizeOf(Vertex), @intFromEnum(storage_mode), null) }; // We pass null to handle deallocation manually in Zig
    }

    pub fn newCommandQueue(self: Device) CommandQueue {
        const sel = objc.sel_registerName("newCommandQueue");
        return .{ .ptr = objc.objc_msgSend(self.ptr, sel) };
    }

    pub fn newDefaultLibrary(self: Device) objc.ID {
        const sel = objc.sel_registerName("newDefaultLibrary");
        return objc.objc_msgSend(self.ptr, sel);
    }

    pub fn newRenderPipelineState(self: Device, descriptor: RenderPipelineDescriptor) !RenderPipelineState {
        const sel = objc.sel_registerName("newRenderPipelineStateWithDescriptor:error:");

        const NewFn = *const fn (objc.ID, ?*objc.Sel, objc.ID, ?*objc.ID) callconv(.c) objc.ID;
        const msgSend: NewFn = @ptrCast(&objc.objc_msgSend);

        var err_ptr: objc.ID = null;
        const state_ptr = msgSend(self.ptr, sel, descriptor.ptr, &err_ptr);

        if (state_ptr == null) {
            if (err_ptr) |err_id| {
                const err = Error{ .ptr = err_id };
                std.debug.print("Metal Pipeline Error: {s}\n", .{err.localizedDescription()});
            }
            return error.PipelineStateCreationFailed;
        }

        return .{ .ptr = state_ptr };
    }
};

pub const Error = struct {
    ptr: objc.ID,

    pub fn localizedDescription(self: Error) [:0]const u8 {
        const sel = objc.sel_registerName("localizedDescription");
        const ns_str = objc.objc_msgSend(self.ptr, sel);
        const sel_utf8 = objc.sel_registerName("UTF8String");
        const c_str = objc.objc_msgSend(ns_str, sel_utf8);
        return std.mem.span(@as([*c]const u8, @ptrCast(c_str)));
    }
};

pub const Library = struct {
    ptr: objc.ID,

    pub fn init(device: Device) Library {
        return .{ .ptr = device.newDefaultLibrary() };
    }

    pub fn newFunction(self: Library, name: [:0]const u8) objc.ID {
        const name_ns = objc.stringWithUTF8String(name);

        const sel = objc.sel_registerName("newFunctionWithName:");
        const NewFunctionFn = *const fn (?*anyopaque, ?*objc.Sel, ?*anyopaque) callconv(.c) objc.ID;
        const msgNewFunction: NewFunctionFn = @ptrCast(&objc.objc_msgSend);
        return msgNewFunction(self.ptr, sel, name_ns);
    }
};

pub const RenderPipelineDescriptor = struct {
    ptr: objc.ID,

    pub fn new() RenderPipelineDescriptor {
        const renderPipelineDescriptorClass = objc.objc_getClass("MTLRenderPipelineDescriptor");
        return .{ .ptr = objc.objc_msgSend(renderPipelineDescriptorClass, objc.sel_registerName("new")) };
    }

    pub fn setVertexFunction(self: RenderPipelineDescriptor, function: objc.ID) void {
        _ = objc.objc_msgSend(self.ptr, objc.sel_registerName("setVertexFunction:"), function);
    }

    pub fn setFragmentFunction(self: RenderPipelineDescriptor, function: objc.ID) void {
        _ = objc.objc_msgSend(self.ptr, objc.sel_registerName("setFragmentFunction:"), function);
    }

    pub fn getColorAttachemnts(self: RenderPipelineDescriptor) RenderPipelineColorAttachmentDescriptorArray {
        const array_ptr = objc.objc_msgSend(self.ptr, objc.sel_registerName("colorAttachments"));
        return .{ .ptr = array_ptr };
    }
};

pub const RenderPipelineColorAttachmentDescriptorArray = struct {
    ptr: objc.ID,

    /// Equivalent to desc->colorAttachments()->object(index)
    pub fn get(self: RenderPipelineColorAttachmentDescriptorArray, index: usize) RenderPipelineColorAttachmentDescriptor {
        const sel = objc.sel_registerName("objectAtIndexedSubscript:");

        // Explicit cast for the return and the index parameter
        const GetObjFn = *const fn (objc.ID, ?*objc.Sel, usize) callconv(.c) objc.ID;
        const msgSendGet: GetObjFn = @ptrCast(&objc.objc_msgSend);

        return .{ .ptr = msgSendGet(self.ptr, sel, index) };
    }
};

pub const PixelFormat = enum(usize) {
    invalid = 0,

    // Common 8-bit formats
    a8_unorm = 1,
    r8_unorm = 10,
    r8_sint = 14,

    // The most common formats for CAMetalLayer
    rgba8_unorm = 70,
    rgba8_unorm_srgb = 71,
    bgra8_unorm = 80,
    bgra8_unorm_srgb = 81,

    // 16-bit / HDR formats
    rgba16_float = 115,

    // Depth and Stencil
    depth32_float = 252,
    stencil8 = 253,
    depth32_float_stencil8 = 260,
};

pub const RenderPipelineColorAttachmentDescriptor = struct {
    ptr: objc.ID,

    pub fn setPixelFormat(self: RenderPipelineColorAttachmentDescriptor, format: PixelFormat) void {
        const sel = objc.sel_registerName("setPixelFormat:");

        // Cast for the setter
        const SetFormatFn = *const fn (objc.ID, ?*objc.Sel, usize) callconv(.c) void;
        const msgSend: SetFormatFn = @ptrCast(&objc.objc_msgSend);

        msgSend(self.ptr, sel, @intFromEnum(format));
    }
};

pub const Texture = struct { ptr: objc.ID };

pub const Drawable = struct {
    ptr: objc.ID,

    pub fn texture(self: Drawable) Texture {
        const sel = objc.sel_registerName("texture");
        // Texture is a property, so we just send the 'texture' message
        const tex_ptr = objc.objc_msgSend(self.ptr, sel);
        return .{ .ptr = tex_ptr };
    }
};

pub const MetalLayer = struct {
    ptr: objc.ID,

    pub fn nextDrawable(self: MetalLayer) Drawable {
        return .{ .ptr = objc.objc_msgSend(self.ptr, objc.sel_registerName("nextDrawable")) };
    }
};

// pub fn setupMetalLayer(window: appkit.Window, device: Device) MetalLayer {
//     const win_ptr = window.ptr;
//     const dev_ptr = device.ptr;

//     const CAMetalLayer = objc.objc_getClass("CAMetalLayer") orelse unreachable;
//     const layer = objc.objc_msgSend(CAMetalLayer, objc.sel_registerName("layer"));

//     // Function pointer types for the calls
//     const SetPtrFn = *const fn (?*anyopaque, ?*objc.Sel, ?*anyopaque) callconv(.c) void;
//     const SetBoolFn = *const fn (?*anyopaque, ?*objc.Sel, u8) callconv(.c) void;
//     const msgSendSetPtr: SetPtrFn = @ptrCast(&objc.objc_msgSend);
//     const msgSendSetBool: SetBoolFn = @ptrCast(&objc.objc_msgSend);

//     // 1. Set the device on the layer
//     msgSendSetPtr(layer, objc.sel_registerName("setDevice:"), dev_ptr);

//     const sel = objc.sel_registerName("setPixelFormat:");

//     // Ensure the third argument is 'usize', not '*PixelFormat' or similar
//     const SetFormatFn = *const fn (objc.ID, ?*objc.Sel, usize) callconv(.c) void;
//     const msgSendSetFormat: SetFormatFn = @ptrCast(&objc.objc_msgSend);

//     // Use @intFromEnum to get the raw 80, 81, etc.
//     msgSendSetFormat(layer, sel, @intFromEnum(PixelFormat.bgra8_unorm));

//     // 2. Get the content view from the window (THIS WAS THE MISSING LINE)
//     const view = objc.objc_msgSend(win_ptr, objc.sel_registerName("contentView"));

//     // 3. Set the layer on the view
//     msgSendSetPtr(view, objc.sel_registerName("setLayer:"), layer);

//     // 4. Tell the view it MUST use a layer
//     msgSendSetBool(view, objc.sel_registerName("setWantsLayer:"), 1);

//     return .{ .ptr = layer };
// }
//
pub fn setupMetalLayer(window: appkit.Window, device: Device) MetalLayer {
    const win_ptr = window.ptr;
    const dev_ptr = device.ptr;

    // 1. Properly allocate and initialize the CAMetalLayer
    const CAMetalLayer = objc.objc_getClass("CAMetalLayer") orelse unreachable;
    const layer_alloc = objc.objc_msgSend(CAMetalLayer, objc.sel_registerName("alloc"));
    const layer = objc.objc_msgSend(layer_alloc, objc.sel_registerName("init"));

    // Function pointer types for common signatures
    const SetPtrFn = *const fn (objc.ID, ?*objc.Sel, ?*anyopaque) callconv(.c) void;
    const SetFloatFn = *const fn (objc.ID, ?*objc.Sel, f64) callconv(.c) void;
    const SetBoolFn = *const fn (objc.ID, ?*objc.Sel, bool) callconv(.c) void;
    const SetFormatFn = *const fn (objc.ID, ?*objc.Sel, usize) callconv(.c) void;

    const msgSendSetPtr: SetPtrFn = @ptrCast(&objc.objc_msgSend);
    const msgSendSetFloat: SetFloatFn = @ptrCast(&objc.objc_msgSend);
    const msgSendSetBool: SetBoolFn = @ptrCast(&objc.objc_msgSend);
    const msgSendSetFormat: SetFormatFn = @ptrCast(&objc.objc_msgSend);

    // 2. Set the device and basic properties
    msgSendSetPtr(layer, objc.sel_registerName("setDevice:"), dev_ptr);
    msgSendSetFormat(layer, objc.sel_registerName("setPixelFormat:"), @intFromEnum(PixelFormat.bgra8_unorm));

    // Set opaque to true for better performance if you don't need transparency
    msgSendSetBool(layer, objc.sel_registerName("setOpaque:"), true);

    // 3. Setup Retina Scaling (ContentsScale)
    const scale_sel = objc.sel_registerName("backingScaleFactor");
    const GetFloatFn = *const fn (objc.ID, ?*objc.Sel) callconv(.c) f64;
    const scale = @as(GetFloatFn, @ptrCast(&objc.objc_msgSend))(win_ptr, scale_sel);
    msgSendSetFloat(layer, objc.sel_registerName("setContentsScale:"), scale);

    // 4. Link to the View Hierarchy
    const view = objc.objc_msgSend(win_ptr, objc.sel_registerName("contentView"));
    msgSendSetPtr(view, objc.sel_registerName("setLayer:"), layer);
    msgSendSetBool(view, objc.sel_registerName("setWantsLayer:"), true);

    // 5. CRITICAL: Set the Frame
    // If the frame is (0,0), nextDrawable().texture() will be null.
    const NSRect = extern struct {
        origin: extern struct { x: f64, y: f64 },
        size: extern struct { width: f64, height: f64 },
    };

    const bounds_sel = objc.sel_registerName("bounds");
    const GetRectFn = *const fn (objc.ID, ?*objc.Sel) callconv(.c) NSRect;
    const view_bounds = @as(GetRectFn, @ptrCast(&objc.objc_msgSend))(view, bounds_sel);

    const SetRectFn = *const fn (objc.ID, ?*objc.Sel, NSRect) callconv(.c) void;
    @as(SetRectFn, @ptrCast(&objc.objc_msgSend))(layer, objc.sel_registerName("setFrame:"), view_bounds);

    return .{ .ptr = layer };
}

const RenderPipelineState = struct {
    ptr: objc.ID,
};

pub const CommandQueue = struct {
    ptr: objc.ID,

    pub fn commandBuffer(self: CommandQueue) CommandBuffer {
        return .{ .ptr = objc.objc_msgSend(self.ptr, objc.sel_registerName("commandBuffer")) };
    }
};

pub const LoadAction = enum(usize) {
    LoadActionDontCare = 0,
    LoadActionLoad = 1,
    LoadActionClear = 2,
};

pub const StoreAction = enum(usize) {
    StoreActionDontCare = 0,
    StoreActionStore = 1,
    StoreActionMultisampleResolve = 2,
    StoreActionStoreAndMultisampleResolve = 3,
    StoreActionUnknown = 4,
    StoreActionCustomSampleDepthStore = 5,
};

pub const ClearColor = extern struct {
    alpha: f64,
    blue: f64,
    green: f64,
    red: f64,
};

pub const RenderPassColorAttachmentDescriptor = struct {
    ptr: objc.ID,

    pub fn setTexture(self: RenderPassColorAttachmentDescriptor, texture: Texture) void {
        const sel = objc.sel_registerName("setTexture:");

        // Explicitly define the signature: (ID, Sel, ID)
        const SetTexFn = *const fn (objc.ID, ?*objc.Sel, objc.ID) callconv(.c) void;
        const msgSend: SetTexFn = @ptrCast(&objc.objc_msgSend);

        msgSend(self.ptr, sel, texture.ptr);
    }

    pub fn setLoadAction(self: RenderPassColorAttachmentDescriptor, load_action: LoadAction) void {
        _ = objc.objc_msgSend(self.ptr, objc.sel_registerName("setLoadAction:"), @intFromEnum(load_action));
    }

    pub fn setClearColor(self: RenderPassColorAttachmentDescriptor, clear_color: ClearColor) void {
        const sel = objc.sel_registerName("setClearColor:");
        const SetClearFn = *const fn (objc.ID, ?*objc.Sel, ClearColor) callconv(.c) void;
        const msgSend: SetClearFn = @ptrCast(&objc.objc_msgSend);
        msgSend(self.ptr, sel, clear_color);
    }

    pub fn setStoreAction(self: RenderPassColorAttachmentDescriptor, store_action: StoreAction) void {
        _ = objc.objc_msgSend(self.ptr, objc.sel_registerName("setStoreAction:"), @intFromEnum(store_action));
    }
};

pub const RenderPassColorAttachmentDescriptorArray = struct {
    ptr: objc.ID,

    /// Equivalent to desc->colorAttachments()->object(index)
    pub fn get(self: RenderPassColorAttachmentDescriptorArray, index: usize) RenderPassColorAttachmentDescriptor {
        const sel = objc.sel_registerName("objectAtIndexedSubscript:");

        // Explicit cast for the return and the index parameter
        const GetObjFn = *const fn (objc.ID, ?*objc.Sel, usize) callconv(.c) objc.ID;
        const msgSendGet: GetObjFn = @ptrCast(&objc.objc_msgSend);

        return .{ .ptr = msgSendGet(self.ptr, sel, index) };
    }
};

pub const RenderPassDescriptor = struct {
    ptr: objc.ID,

    pub fn renderPassDescriptor() RenderPassDescriptor {
        const class = objc.objc_getClass("MTLRenderPassDescriptor");
        return .{ .ptr = objc.objc_msgSend(class, objc.sel_registerName("renderPassDescriptor")) };
    }

    pub fn getColorAttachemnts(self: RenderPassDescriptor) RenderPassColorAttachmentDescriptorArray {
        const array_ptr = objc.objc_msgSend(self.ptr, objc.sel_registerName("colorAttachments"));
        return .{ .ptr = array_ptr };
    }
};

const CommandBuffer = struct {
    ptr: objc.ID,

    pub fn renderCommandEncoder(self: CommandBuffer, descriptor: RenderPassDescriptor) RenderCommandEncoder {
        const sel = objc.sel_registerName("renderCommandEncoderWithDescriptor:");

        // The signature: (CommandBufferPtr, Selector, DescriptorPtr) -> EncoderPtr
        const CreateEncoderFn = *const fn (objc.ID, ?*objc.Sel, objc.ID) callconv(.c) objc.ID;
        const msgSend: CreateEncoderFn = @ptrCast(&objc.objc_msgSend);

        const encoder_ptr = msgSend(self.ptr, sel, descriptor.ptr);

        return .{ .ptr = encoder_ptr };
    }

    pub fn presentDrawable(self: CommandBuffer, drawable: objc.ID) void {
        _ = objc.objc_msgSend(self.ptr, objc.sel_registerName("presentDrawable:"), drawable);
    }

    pub fn commit(self: CommandBuffer) void {
        _ = objc.objc_msgSend(self.ptr, objc.sel_registerName("commit"));
    }

    pub fn waitUntilCompleted(self: CommandBuffer) void {
        _ = objc.objc_msgSend(self.ptr, objc.sel_registerName("waitUntilCompleted"));
    }
};

const RenderCommandEncoder = struct {
    ptr: objc.ID,

    pub fn setRenderPipelineState(self: RenderCommandEncoder, pipelineState: RenderPipelineState) void {
        const sel = objc.sel_registerName("setRenderPipelineState:");

        // Signature: (EncoderPtr, Selector, PipelineStatePtr) -> void
        const SetPsoFn = *const fn (objc.ID, ?*objc.Sel, objc.ID) callconv(.c) void;
        const msgSend: SetPsoFn = @ptrCast(&objc.objc_msgSend);

        msgSend(self.ptr, sel, pipelineState.ptr);
    }

    pub fn setVertexBuffer(self: RenderCommandEncoder, buffer: Buffer) void {
        const sel = objc.sel_registerName("setVertexBuffer:offset:atIndex:");
        const SetVertexBufferFn = *const fn (?*anyopaque, ?*objc.Sel, ?*anyopaque, usize, usize) callconv(.c) void;
        const msgSetVertexBuffer: SetVertexBufferFn = @ptrCast(&objc.objc_msgSend);
        msgSetVertexBuffer(self.ptr, sel, buffer.ptr, 0, 0);
    }

    pub fn drawPrimitives(self: RenderCommandEncoder, primitive_type: PrimitiveType, vertex_start: usize, vertex_count: usize) void {
        // The correct selector name:
        const sel = objc.sel_registerName("drawPrimitives:vertexStart:vertexCount:");

        // Signature: (self, _sel, type, start, count)
        const DrawPrimitivesFn = *const fn (objc.ID, ?*objc.Sel, usize, usize, usize) callconv(.c) void;
        const msgSend: DrawPrimitivesFn = @ptrCast(&objc.objc_msgSend);

        msgSend(self.ptr, sel, @intFromEnum(primitive_type), vertex_start, vertex_count);
    }

    pub fn endEncoding(self: RenderCommandEncoder) void {
        const sel = objc.sel_registerName("endEncoding");
        _ = objc.objc_msgSend(self.ptr, sel);
    }
};

pub fn create_render_pipeline(device: Device) !RenderPipelineState {
    const library = Library.init(device);
    const vertex_shader = library.newFunction("vertexShader");
    const fragment_shader = library.newFunction("fragmentShader");
    const pipeline_descriptor = RenderPipelineDescriptor.new();
    pipeline_descriptor.setVertexFunction(vertex_shader);
    pipeline_descriptor.setFragmentFunction(fragment_shader);
    const color_attachments = pipeline_descriptor.getColorAttachemnts();
    color_attachments.get(0).setPixelFormat(PixelFormat.bgra8_unorm);
    return device.newRenderPipelineState(pipeline_descriptor);
}

pub const CaptureDescriptor = struct {
    pub fn init(device: objc.ID) objc.ID {
        const class = objc.objc_getClass("MTLCaptureDescriptor");
        const obj = objc.objc_msgSend(class, objc.sel_registerName("new"));

        // setCaptureObject: (this is the device)
        const setObjSel = objc.sel_registerName("setCaptureObject:");
        const SetObjFn = *const fn (objc.ID, ?*objc.Sel, objc.ID) callconv(.c) void;
        @as(SetObjFn, @ptrCast(&objc.objc_msgSend))(obj, setObjSel, device);

        // setDestination: (1 = MTLCaptureDestinationGPUTraceDocument)
        const setDestSel = objc.sel_registerName("setDestination:");
        const SetDestFn = *const fn (objc.ID, ?*objc.Sel, usize) callconv(.c) void;
        @as(SetDestFn, @ptrCast(&objc.objc_msgSend))(obj, setDestSel, 1);

        return obj;
    }
};
