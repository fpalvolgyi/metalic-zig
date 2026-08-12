# metal_kernel

A native macOS particle-physics playground written in [Zig](https://ziglang.org),
talking to AppKit and Metal directly — no Xcode project, no MetalKit, no
Objective-C source files. The goal is to prove out two things at once:

1. **A render engine with a basic compute shader driving a physics simulation** —
   a GPU compute kernel updates a particle system (gravity, boundary collision,
   mouse repulsion) every frame, and a render pipeline draws the result as
   point sprites, alongside an immediate-mode UI layer with signed-distance-field
   text.
2. **A Zig ⟷ Metal/Objective-C integration layer** — a small runtime binding
   (`obj_runtime.zig`) that calls `objc_msgSend` directly from Zig, with
   type-safe wrappers over AppKit, Metal, CoreVideo, CoreText and CoreGraphics
   built on top of it. Nothing here goes through a `.m`/`.mm` file or a
   generated bridging header.

## What it does

Launching the app opens a window with 100,000 particles simulated entirely on
the GPU. A compute kernel (`updateParticles` in `src/kernel.metal`) applies
gravity, bounces particles off the [-1, 1] NDC bounds, and repels them away
from the mouse cursor. A render pipeline (`particleVertex` / `particleFragment`)
draws each particle as an antialiased circular point sprite. A small
immediate-mode UI batcher overlays a HUD panel, stat bars, and a hover button
on top, rendered with SDF-based text for crisp scaling at any size.

Frame pacing is driven by `CVDisplayLink` rather than a busy-poll loop, and
window/app lifecycle is handled through a dynamically registered
`NSApplicationDelegate` — both wired up by hand through the Objective-C
runtime.

## Project structure

```
src/
  main.zig          Entry point, app delegate, per-frame compute + render pass
  obj_runtime.zig    Core Objective-C runtime bindings (objc_msgSend, class
                      registration, the type-safe `send()` helper)
  appkit.zig         NSApplication / NSWindow wrappers
  metal.zig          Device, pipeline, buffer, command queue/encoder wrappers
  corevideo.zig      CVDisplayLink bindings for vsync-aligned frame pacing
  coregraphics.zig   CoreGraphics helpers used by font baking
  font.zig           CoreText-based SDF font atlas baking
  ui.zig             Immediate-mode quad batcher (rects, buttons, text)
  kernel.metal       Compute (physics) + render (particles, UI) shaders

docs/
  ndc.md             Notes on the normalized device coordinate system used
                      throughout the project
  sdf_fonts.md        Notes on how the SDF font atlas is baked and sampled

FINDINGS.md          Debugging notes from getting the first frame on screen,
                      plus a comparison of this hand-rolled structure against
                      a typical Objective-C/AppKit project
```

## Requirements

- macOS with Xcode command line tools installed (for `xcrun`, `metal`, `metallib`)
- [Zig](https://ziglang.org) 0.16.0 or newer

## Building and running

```sh
zig build run
```

This compiles `src/kernel.metal` into `src/default.metallib` via `xcrun`
(see `build_kernel.sh` for the standalone equivalent), builds the Zig
executable, links it against AppKit, Foundation, Metal, QuartzCore,
CoreVideo, CoreText and CoreGraphics, and launches it.

Run the test suite with:

```sh
zig build test
```

## Why hand-roll the Objective-C bridge?

Doing this without MetalKit or a generated bridging header keeps every layer
of the stack — window creation, the run loop, shader compilation, buffer
uploads, frame pacing — visible and controllable from Zig. `FINDINGS.md`
documents the bugs hit along the way (missing buffer attributes, alignment
requirements on `newBufferWithBytesNoCopy`, run loop integration for
CoreAnimation) and contrasts the resulting structure with what an equivalent
Objective-C/AppKit project looks like.
