# Metal Kernel — Findings & Architecture Analysis

## Why nothing renders

### Bug 1: Vertex shader missing `[[buffer(0)]]` (kernel.metal:7)

Without the attribute, Metal doesn't bind the vertex buffer to the shader parameter.

```metal
// Wrong — shader has no idea where to read from:
constant simd::float3* vertexPositions

// Fix:
constant simd::float3* vertexPositions [[buffer(0)]]
```

### Bug 2: Vertex stride mismatch (kernel.metal:6–8)

The `Vertex` struct is 28 bytes (`[3]f32` position + `[4]f32` color), but the shader reads it as tightly-packed `float3` (12 bytes each). Vertices 1 and 2 land in garbage memory. The shader needs to match the actual struct layout, or the struct needs to be split into two separate buffers.

### Bug 3: `newBufferWithBytesNoCopy` requires page-aligned memory (metal.zig:40)

The `triangle` array is stack-allocated and therefore not page-aligned. This function returns `nil` for non-page-aligned data. The nil buffer is silently passed to `setVertexBuffer`, so no vertex data reaches the GPU.

**Fix:** use `newBufferWithBytes:length:options:` instead, which copies data into a Metal-managed buffer with proper alignment.

### Structural issue: no proper run loop

Even after fixing the three bugs above, the window will stay blank without restructuring the main loop. CoreAnimation's compositing pipeline expects to participate in the `NSRunLoop`'s commit phase. The current manual poll with `nextEventMatchingMask:untilDate:inMode:dequeue:` using `distantPast` drains existing events but does not trigger CA transaction commits.

**Fix options:**
- Call `[NSApp run]` and trigger rendering via a `CADisplayLink` or `NSTimer` callback registered through the ObjC runtime.
- Process one run loop iteration per frame: replace the event drain loop with `CFRunLoopRunInMode(kCFRunLoopDefaultMode, 1.0/60.0, false)`.

---

## Zig vs. Objective-C project structure

| Concern | Objective-C | Current Zig |
|---|---|---|
| **Entry point** | `NSApplicationMain()` / `@NSApplicationMain` | Manual `main()` |
| **App lifecycle** | `NSApplicationDelegate` with `applicationDidFinishLaunching:` | No delegate — everything inline in `main()` |
| **Event loop** | `[NSApp run]` — a proper `NSRunLoop` handling timers, display updates, CA transactions | Manual poll with `nextEventMatchingMask:untilDate:inMode:dequeue:` using `distantPast` |
| **Rendering surface** | `MTKView` + `MTKViewDelegate` / `drawInMTKView:` callback | Manual `CAMetalLayer` + polling `nextDrawable` in a `while(true)` |
| **Shader library** | `[device newDefaultLibrary]` works from the app bundle resources | Same call, but a bare CLI binary has no bundle — must use `newLibraryWithFile:error:` or `newLibraryWithData:error:` |
| **Memory management** | ARC — automatic | Manual `NSAutoreleasePool` alloc/release per frame |
| **Type safety** | Native ObjC types with compiler checks | Every call is an `objc_msgSend` cast to a raw function pointer |
| **Threading** | `NSApplicationMain` guarantees the main thread for AppKit | Must be enforced manually |
| **Info.plist / bundle** | App bundle with `NSPrincipalClass`, `CFBundleIdentifier`, etc. | None — some AppKit features silently degrade without it |
| **Frame pacing** | `CADisplayLink` or `CVDisplayLink` for vsync-aligned rendering | Unbounded `while(true)` loop |

### Key takeaway

An ObjC project hands control to `[NSApp run]` immediately after setup. AppKit's run loop calls back at the right moments (display refresh, events, timers). The Zig project drives everything manually, which bypasses the run loop integration that CoreAnimation requires to composite frames onto the screen.
