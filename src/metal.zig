const objc = @import("obj_runtime.zig");
const appkit = @import("appkit.zig");
const std = @import("std");

pub const Vertex = extern struct {
    position: [3]f32,
    color: [4]f32,
};

extern "c" fn MTLCreateSystemDefaultDevice() ?*anyopaque;

pub fn getBufferPointer(buffer: objc.ID) [*]Vertex {
    const contents = objc.send(objc.ID, buffer, "contents", .{});
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

    pub fn newBufferWithBytes(self: Device, data: []const Vertex, storage_mode: MTLStorageMode) Buffer {
        return .{ .ptr = objc.send(objc.ID, self.ptr, "newBufferWithBytes:length:options:", .{
            @as(?*const anyopaque, data.ptr),
            data.len * @sizeOf(Vertex),
            @intFromEnum(storage_mode),
        }) };
    }

    pub fn newBufferWithBytesNoCopy(self: Device, data: []const Vertex, storage_mode: MTLStorageMode) Buffer {
        return .{ .ptr = objc.send(objc.ID, self.ptr, "newBufferWithBytesNoCopy:length:options:deallocator:", .{
            @as(?*const anyopaque, data.ptr),
            data.len * @sizeOf(Vertex),
            @intFromEnum(storage_mode),
            @as(objc.ID, null),
        }) };
    }

    pub fn newCommandQueue(self: Device) CommandQueue {
        return .{ .ptr = objc.send(objc.ID, self.ptr, "newCommandQueue", .{}) };
    }

    pub fn newDefaultLibrary(self: Device) objc.ID {
        return objc.send(objc.ID, self.ptr, "newDefaultLibrary", .{});
    }

    pub fn newRenderPipelineState(self: Device, descriptor: RenderPipelineDescriptor) !RenderPipelineState {
        var err: objc.ID = null;
        const state = objc.send(objc.ID, self.ptr, "newRenderPipelineStateWithDescriptor:error:", .{
            descriptor.ptr,
            @as(?*objc.ID, &err),
        });

        if (state == null) {
            if (err) |e| {
                const metal_err = Error{ .ptr = e };
                std.debug.print("Metal Pipeline Error: {s}\n", .{metal_err.localizedDescription()});
            }
            return error.PipelineStateCreationFailed;
        }

        return .{ .ptr = state };
    }
};

pub const Error = struct {
    ptr: objc.ID,

    pub fn localizedDescription(self: Error) [:0]const u8 {
        const ns_str = objc.send(objc.ID, self.ptr, "localizedDescription", .{});
        const c_str = objc.send(objc.ID, ns_str, "UTF8String", .{});
        return std.mem.span(@as([*c]const u8, @ptrCast(c_str)));
    }
};

pub const Library = struct {
    ptr: objc.ID,

    pub fn init(device: Device) Library {
        return .{ .ptr = device.newDefaultLibrary() };
    }

    pub fn newFunction(self: Library, name: [:0]const u8) objc.ID {
        return objc.send(objc.ID, self.ptr, "newFunctionWithName:", .{objc.stringWithUTF8String(name)});
    }
};

pub const RenderPipelineDescriptor = struct {
    ptr: objc.ID,

    pub fn new() RenderPipelineDescriptor {
        return .{ .ptr = objc.send(objc.ID, objc.getClass("MTLRenderPipelineDescriptor"), "new", .{}) };
    }

    pub fn setVertexFunction(self: RenderPipelineDescriptor, function: objc.ID) void {
        objc.send(void, self.ptr, "setVertexFunction:", .{function});
    }

    pub fn setFragmentFunction(self: RenderPipelineDescriptor, function: objc.ID) void {
        objc.send(void, self.ptr, "setFragmentFunction:", .{function});
    }

    pub fn getColorAttachemnts(self: RenderPipelineDescriptor) RenderPipelineColorAttachmentDescriptorArray {
        return .{ .ptr = objc.send(objc.ID, self.ptr, "colorAttachments", .{}) };
    }
};

pub const RenderPipelineColorAttachmentDescriptorArray = struct {
    ptr: objc.ID,

    pub fn get(self: RenderPipelineColorAttachmentDescriptorArray, index: usize) RenderPipelineColorAttachmentDescriptor {
        return .{ .ptr = objc.send(objc.ID, self.ptr, "objectAtIndexedSubscript:", .{index}) };
    }
};

pub const PixelFormat = enum(usize) {
    invalid = 0,
    a8_unorm = 1,
    r8_unorm = 10,
    r8_sint = 14,
    rgba8_unorm = 70,
    rgba8_unorm_srgb = 71,
    bgra8_unorm = 80,
    bgra8_unorm_srgb = 81,
    rgba16_float = 115,
    depth32_float = 252,
    stencil8 = 253,
    depth32_float_stencil8 = 260,
};

pub const RenderPipelineColorAttachmentDescriptor = struct {
    ptr: objc.ID,

    pub fn setPixelFormat(self: RenderPipelineColorAttachmentDescriptor, format: PixelFormat) void {
        objc.send(void, self.ptr, "setPixelFormat:", .{@intFromEnum(format)});
    }
};

pub const Texture = struct { ptr: objc.ID };

pub const Drawable = struct {
    ptr: objc.ID,

    pub fn texture(self: Drawable) Texture {
        return .{ .ptr = objc.send(objc.ID, self.ptr, "texture", .{}) };
    }
};

pub const MetalLayer = struct {
    ptr: objc.ID,

    pub fn nextDrawable(self: MetalLayer) Drawable {
        return .{ .ptr = objc.send(objc.ID, self.ptr, "nextDrawable", .{}) };
    }
};

pub fn setupMetalLayer(window: appkit.Window, device: Device) MetalLayer {
    const win_ptr = window.ptr;
    const dev_ptr = device.ptr;

    // Allocate and initialize CAMetalLayer
    const layer_alloc = objc.send(objc.ID, objc.getClass("CAMetalLayer"), "alloc", .{});
    const layer = objc.send(objc.ID, layer_alloc, "init", .{});

    // Configure device and pixel format
    objc.send(void, layer, "setDevice:", .{dev_ptr});
    objc.send(void, layer, "setPixelFormat:", .{@intFromEnum(PixelFormat.bgra8_unorm)});
    objc.send(void, layer, "setOpaque:", .{true});

    // Match the window's backing scale for Retina displays
    const scale = objc.send(f64, win_ptr, "backingScaleFactor", .{});
    objc.send(void, layer, "setContentsScale:", .{scale});

    // Attach to the window's content view
    const view = objc.send(objc.ID, win_ptr, "contentView", .{});
    objc.send(void, view, "setLayer:", .{layer});
    objc.send(void, view, "setWantsLayer:", .{true});

    // Set the layer frame so nextDrawable returns a properly-sized texture.
    const NSRect = extern struct {
        origin: extern struct { x: f64, y: f64 },
        size: extern struct { width: f64, height: f64 },
    };
    const bounds = objc.send(NSRect, view, "bounds", .{});
    objc.send(void, layer, "setFrame:", .{bounds});

    return .{ .ptr = layer };
}

pub const RenderPipelineState = struct { ptr: objc.ID };

pub const CommandQueue = struct {
    ptr: objc.ID,

    pub fn commandBuffer(self: CommandQueue) CommandBuffer {
        return .{ .ptr = objc.send(objc.ID, self.ptr, "commandBuffer", .{}) };
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
    red: f64,
    green: f64,
    blue: f64,
    alpha: f64,
};

pub const RenderPassColorAttachmentDescriptor = struct {
    ptr: objc.ID,

    pub fn setTexture(self: RenderPassColorAttachmentDescriptor, texture: Texture) void {
        objc.send(void, self.ptr, "setTexture:", .{texture.ptr});
    }

    pub fn setLoadAction(self: RenderPassColorAttachmentDescriptor, action: LoadAction) void {
        objc.send(void, self.ptr, "setLoadAction:", .{@intFromEnum(action)});
    }

    pub fn setClearColor(self: RenderPassColorAttachmentDescriptor, color: ClearColor) void {
        objc.send(void, self.ptr, "setClearColor:", .{color});
    }

    pub fn setStoreAction(self: RenderPassColorAttachmentDescriptor, action: StoreAction) void {
        objc.send(void, self.ptr, "setStoreAction:", .{@intFromEnum(action)});
    }
};

pub const RenderPassColorAttachmentDescriptorArray = struct {
    ptr: objc.ID,

    pub fn get(self: RenderPassColorAttachmentDescriptorArray, index: usize) RenderPassColorAttachmentDescriptor {
        return .{ .ptr = objc.send(objc.ID, self.ptr, "objectAtIndexedSubscript:", .{index}) };
    }
};

pub const RenderPassDescriptor = struct {
    ptr: objc.ID,

    pub fn renderPassDescriptor() RenderPassDescriptor {
        return .{ .ptr = objc.send(objc.ID, objc.getClass("MTLRenderPassDescriptor"), "renderPassDescriptor", .{}) };
    }

    pub fn getColorAttachemnts(self: RenderPassDescriptor) RenderPassColorAttachmentDescriptorArray {
        return .{ .ptr = objc.send(objc.ID, self.ptr, "colorAttachments", .{}) };
    }
};

const CommandBuffer = struct {
    ptr: objc.ID,

    pub fn renderCommandEncoder(self: CommandBuffer, descriptor: RenderPassDescriptor) RenderCommandEncoder {
        return .{ .ptr = objc.send(objc.ID, self.ptr, "renderCommandEncoderWithDescriptor:", .{descriptor.ptr}) };
    }

    pub fn presentDrawable(self: CommandBuffer, drawable: objc.ID) void {
        objc.send(void, self.ptr, "presentDrawable:", .{drawable});
    }

    pub fn commit(self: CommandBuffer) void {
        objc.send(void, self.ptr, "commit", .{});
    }

    pub fn waitUntilCompleted(self: CommandBuffer) void {
        objc.send(void, self.ptr, "waitUntilCompleted", .{});
    }
};

const RenderCommandEncoder = struct {
    ptr: objc.ID,

    pub fn setRenderPipelineState(self: RenderCommandEncoder, state: RenderPipelineState) void {
        objc.send(void, self.ptr, "setRenderPipelineState:", .{state.ptr});
    }

    pub fn setVertexBuffer(self: RenderCommandEncoder, buffer: Buffer) void {
        objc.send(void, self.ptr, "setVertexBuffer:offset:atIndex:", .{
            buffer.ptr, @as(usize, 0), @as(usize, 0),
        });
    }

    pub fn drawPrimitives(self: RenderCommandEncoder, primitive_type: PrimitiveType, vertex_start: usize, vertex_count: usize) void {
        objc.send(void, self.ptr, "drawPrimitives:vertexStart:vertexCount:", .{
            @intFromEnum(primitive_type), vertex_start, vertex_count,
        });
    }

    pub fn endEncoding(self: RenderCommandEncoder) void {
        objc.send(void, self.ptr, "endEncoding", .{});
    }
};

pub fn create_render_pipeline(device: Device) !RenderPipelineState {
    const library = Library.init(device);
    const vertex_shader = library.newFunction("vertexShader");
    const fragment_shader = library.newFunction("fragmentShader");
    const descriptor = RenderPipelineDescriptor.new();
    descriptor.setVertexFunction(vertex_shader);
    descriptor.setFragmentFunction(fragment_shader);
    descriptor.getColorAttachemnts().get(0).setPixelFormat(PixelFormat.bgra8_unorm);
    return device.newRenderPipelineState(descriptor);
}

pub const CaptureDescriptor = struct {
    pub fn init(device: objc.ID) objc.ID {
        const obj = objc.send(objc.ID, objc.getClass("MTLCaptureDescriptor"), "new", .{});
        objc.send(void, obj, "setCaptureObject:", .{device});
        // MTLCaptureDestinationGPUTraceDocument = 1
        objc.send(void, obj, "setDestination:", .{@as(usize, 1)});
        return obj;
    }
};
