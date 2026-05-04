const objc = @import("obj_runtime.zig");
const appkit = @import("appkit.zig");
const std = @import("std");

pub const Vertex = extern struct {
    position: [2]f32,
    color: [4]f32,
};

extern "c" fn MTLCreateSystemDefaultDevice() ?*anyopaque;

// Signature: (self, _cmd, pointer, length, options)
const NewBufferFn = *const fn (objc.ID, ?*objc.Sel, ?*const anyopaque, usize, usize) callconv(.c) objc.ID;
const msgSendNewBuffer: NewBufferFn = @ptrCast(&objc.objc_msgSend);

pub fn createBuffer(device: objc.ID, data: []const Vertex) objc.ID {
    const sel = objc.sel_registerName("newBufferWithBytes:length:options:");

    // Options 0 = MTLResourceStorageModeShared (Visible to both CPU and GPU)
    return msgSendNewBuffer(device, sel, data.ptr, data.len * @sizeOf(Vertex), 0);
}

/// When using this function allocate memory aligned to 4096 bytes (standard macOS page size)
/// const vertex_count = 1000;
/// const raw_mem = try std.heap.page_allocator.alignedAlloc(
///     Vertex,
///     4096,
///     vertex_count
/// );
/// defer std.heap.page_allocator.free(raw_mem);
/// const buffer = createBufferNoCopy(device.ptr, raw_mem);
///
/// The function passes null as the deallocation handler, which requires to manually release the allocated memory
pub fn createBufferNoCopy(device: objc.ID, data: []const Vertex) objc.ID {
    const sel = objc.sel_registerName("newBufferWithBytesNoCopy:length:options:deallocator:");

    // Signature: (self, _cmd, pointer, length, options, block)
    const NoCopyFn = *const fn (objc.ID, ?*objc.Sel, ?*const anyopaque, usize, usize, ?*anyopaque) callconv(.c) objc.ID;

    const msgSendNoCopy: NoCopyFn = @ptrCast(&objc.objc_msgSend);

    // Options:
    // 0 = MTLResourceStorageModeShared
    // (Required for NoCopy on macOS/iOS)
    return msgSendNoCopy(device, sel, data.ptr, data.len * @sizeOf(Vertex), 0, null // We pass null to handle deallocation manually in Zig
    );
}

pub fn getBufferPointer(buffer: objc.ID) [*]Vertex {
    const sel = objc.sel_registerName("contents");
    const contents = objc.objc_msgSend(buffer, sel);
    return @ptrCast(@alignCast(contents));
}

pub const Device = struct {
    ptr: objc.ID,

    pub fn init() !Device {
        const dev = MTLCreateSystemDefaultDevice();
        if (dev == null) return error.NoGpuFound;

        return .{ .ptr = dev };
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

pub fn setupMetalLayer(window: appkit.Window, device: Device) void {
    const win_ptr = window.ptr;
    const dev_ptr = device.ptr;

    const CAMetalLayer = objc.objc_getClass("CAMetalLayer") orelse unreachable;
    const layer = objc.objc_msgSend(CAMetalLayer, objc.sel_registerName("layer"));

    // Function pointer types for the calls
    const SetPtrFn = *const fn (?*anyopaque, ?*objc.Sel, ?*anyopaque) callconv(.c) void;
    const SetBoolFn = *const fn (?*anyopaque, ?*objc.Sel, u8) callconv(.c) void;
    const msgSendSetPtr: SetPtrFn = @ptrCast(&objc.objc_msgSend);
    const msgSendSetBool: SetBoolFn = @ptrCast(&objc.objc_msgSend);

    // 1. Set the device on the layer
    msgSendSetPtr(layer, objc.sel_registerName("setDevice:"), dev_ptr);

    // 2. Get the content view from the window (THIS WAS THE MISSING LINE)
    const view = objc.objc_msgSend(win_ptr, objc.sel_registerName("contentView"));

    // 3. Set the layer on the view
    msgSendSetPtr(view, objc.sel_registerName("setLayer:"), layer);

    // 4. Tell the view it MUST use a layer
    msgSendSetBool(view, objc.sel_registerName("setWantsLayer:"), 1);
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

pub const RenderPassDescriptor = struct {
    ptr: objc.ID,

    pub fn renderPassDescriptor() RenderPassDescriptor {
        return .{ .ptr = objc.objc_msgSend(null, objc.sel_registerName("renderPassDescriptor")) };
    }
};

const CommandBuffer = struct {
    ptr: objc.ID,

    pub fn renderCommandEncoder(_: CommandBuffer, descriptor: RenderPassDescriptor) RenderCommandEncoder {
        return .{ .ptr = objc.objc_msgSend(descriptor.ptr, objc.sel_registerName("renderCommandEncoderWithDescriptor:"), descriptor.ptr) };
    }
};

const RenderCommandEncoder = struct {
    ptr: objc.ID,

    pub fn setRenderPipelineState(self: RenderCommandEncoder, pipelineState: RenderPipelineState) void {
        objc.objc_msgSend(self.ptr, objc.sel_registerName("setRenderPipelineState:"), pipelineState.ptr);
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
