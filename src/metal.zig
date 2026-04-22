const objc = @import("obj_runtime.zig");
const appkit = @import("appkit.zig");

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

    pub fn newCommandQueue(self: Device) objc.ID {
        const sel = objc.sel_registerName("newCommandQueue");
        return objc.objc_msgSend(self.ptr, sel);
    }

    pub fn newDefaultLibrary(self: Device) objc.ID {
        const sel = objc.sel_registerName("newDefaultLibrary");
        return objc.objc_msgSend(self.ptr, sel);
    }

    pub fn newRenderPipelineState(self: Device) objc.ID{
        const sel = objc.sel_registerName("newRenderPipelineState");
        return objc.objc_msgSend(self.ptr, sel);
    }
};

pub const Library = struct {
    ptr: objc.ID,

    pub fn init(device: Device) Library {
        return .{ .ptr = device.newDefaultLibrary()};
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

    pub fn new() objc.ID{
        const renderPipelineDescriptorClass = objc.objc_getClass("MTLRenderPipelineDescriptor");
        return objc.objc_msgSend(renderPipelineDescriptorClass, objc.sel_registerName("new"));
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

pub fn create_render_pipeline(device: Device) void{
    const library = Library.init(device);
    _ = library.newFunction("add_vectors");
}
