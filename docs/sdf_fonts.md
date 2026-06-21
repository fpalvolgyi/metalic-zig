# Signed Distance Field Font Rendering

## The problem with bitmap fonts

A bitmap atlas stores raw pixel coverage — each texel is either filled or empty.
When the GPU magnifies the texture, bilinear filtering blurs adjacent pixels
together, producing a fuzzy edge.

```
Bitmap at 1× (correct)      Bitmap at 3× (blurry)
┌───────────────┐            ┌───────────────┐
│   ██████      │            │   ░▒▓████▓▒░  │
│   ██  ██      │            │   ▒█░  ░█▒    │
│   ██████      │    3×      │   ▒█▒  ▒█▒    │
│   ██  ██      │  ──────►   │   ░▒▓████▓▒░  │
│   ██  ██      │            │   ░▒▓█▒░▒█▓░  │
└───────────────┘            └───────────────┘
```

The blurring is inevitable — the atlas does not encode WHERE the edge is,
only WHETHER a pixel happened to be covered at the baked size.

---

## What a Signed Distance Field stores

An SDF atlas stores, for every texel, the **distance to the nearest glyph edge**,
signed positive inside the glyph and negative outside.
The value is normalized to [0, 1] so it fits in an R8 texture:

```
  0.0  fully outside  (≥ spread pixels from any edge)
  0.5  exactly on the edge
  1.0  fully inside   (≥ spread pixels from any edge)
```

Visualized for the letter "I" with spread = 4 px:

```
atlas columns →
         outside  edge  inside  edge  outside
row 0:   0.0  0.1  0.3  0.5  0.7  1.0  1.0  0.7  0.5  0.3  0.1  0.0
row 1:   0.0  0.1  0.3  0.5  0.7  1.0  1.0  0.7  0.5  0.3  0.1  0.0
row 2:   0.0  0.1  0.3  0.5  0.7  1.0  1.0  0.7  0.5  0.3  0.1  0.0
```

When magnified 3×, each step in the ramp covers 3 screen pixels —
the GPU has plenty of room to interpolate a perfectly sharp edge.

---

## Baking the SDF (font.zig)

```
1. Render ASCII 32–126 into a 512×512 greyscale bitmap with CoreText.
   Anti-aliasing is disabled → binary: pixel is either 0 or 255.

2. Flip the bitmap vertically (CG origin = bottom-left, Metal = top-left).

3. For every pixel (x, y):
     inside = bitmap[y][x] > 127
     min_dist = nearest pixel with opposite state (brute force, radius = SPREAD)
     signed   = +min_dist if inside, −min_dist if outside
     sdf[y][x] = clamp((signed + SPREAD) / (2 × SPREAD), 0, 1) × 255

4. Force pixel (0,0) = 255 (sentinel for solid-rect quads, see below).

5. Upload via MTLBuffer.newTextureWithDescriptor:offset:bytesPerRow:
   (avoids replaceRegion's large-struct ABI issue on ARM64).
```

**Row wrapping** — with a gap of `2×SPREAD + 2` pixels between glyphs,
95 ASCII characters spread across ~4 rows of 28 px each, all fitting in 512 px.

**UV expansion** — each glyph's UV region is enlarged by SPREAD on every side
so the fragment shader can sample the full distance ramp around every edge:

```
  atlas glyph region    UV quad sent to GPU
  ┌──────────────┐      ┌────────────────────┐
  │  ░░▓▓▓▓░░   │  →   │░░░░░░░░░░░░░░░░░░░░│
  │  ░░▓▓▓▓░░   │      │░░  ░░▓▓▓▓░░  ░░░░░│
  │  ░░▓▓▓▓░░   │      │░░  ░░▓▓▓▓░░  ░░░░░│
  └──────────────┘      │░░░░░░░░░░░░░░░░░░░░│
   (glyph pixels)       └────────────────────┘
                         (glyph + SPREAD halo)
```

---

## Fragment shader (kernel.metal)

```metal
float dist = atlas.sample(smp, in.uv).r;  // SDF value [0, 1]

// fwidth() returns the screen-space rate of change of dist.
// Multiplying by 0.7 keeps the AA band about 1 screen pixel wide.
float aa = fwidth(dist) * 0.7;

// smoothstep creates a smooth 0→1 transition across the edge.
float coverage = smoothstep(0.5 - aa, 0.5 + aa, dist);
```

`fwidth` is key: it automatically adjusts the AA width to the current screen
mapping.  At 1× the band is ~1 px; at 3× it is still ~1 px (the ramp is wider
in atlas space, so its derivative in screen space is the same).

---

## Solid rectangles

`fillRect` maps all six vertices to UV `(0, 0)`.
Pixel `(0, 0)` in the atlas is forced to `255` — an isolated white pixel whose
nearest edge is 1 atlas pixel away.  With SPREAD = 4:

```
sdf = (1.0 + 4.0) / (2 × 4.0) = 0.625  →  smoothstep(0.5±ε, 0.625) = 1.0
```

Coverage is always 1.0 regardless of zoom, so solid fills work without a
separate code path.

---

## Advantages over a plain bitmap atlas

| Property          | Bitmap             | SDF                              |
|-------------------|--------------------|----------------------------------|
| Scaling           | Blurs above 1×     | Sharp at any scale               |
| Atlas size        | One atlas per size | One atlas for all sizes          |
| Render cost       | 1 texture lookup   | 1 lookup + smoothstep + fwidth   |
| Bake cost         | Fast               | O(W × H × spread²) at startup   |
| Thin strokes      | Accurate at 1×     | Can disappear below 1×           |

---

## Limitations of this implementation

- **Rasterized source** — glyphs are rendered with CoreText at 16 px, then the
  SDF is computed from the binary bitmap.  Edge positions are only accurate to
  ±0.5 px.  For production quality, render at 4× (64 px) and downsample.

- **Simple (not multi-channel) SDF** — sharp corners can round slightly at
  large zoom factors.  MSDF (multi-channel SDF) fixes this but requires an
  external tool such as `msdfgen`.

- **Fixed spread = 4 px** — glyphs scaled beyond ~4× the baked size will show
  rounded edges once pixels venture beyond the ramp region.
