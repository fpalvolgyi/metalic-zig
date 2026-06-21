// Bakes printable ASCII into a greyscale Metal texture using CoreText + SDF.
// Each pixel stores a normalized signed distance field value:
//   > 0.5  = inside the glyph,  0.5 = edge,  < 0.5 = outside.
// Glyph UVs are expanded by SDF_SPREAD so the shader sees a smooth halo around
// every character.  Pixel (0,0) is forced to 255 so fillRect quads whose UVs
// all point to (0,0) sample coverage = 1.

const std = @import("std");
const cg  = @import("coregraphics.zig");
const metal = @import("metal.zig");

pub const ATLAS_SIZE: usize    = 512;
pub const FONT_SIZE:  cg.CGFloat = 16.0;
pub const SDF_SPREAD: f32      = 4.0;  // distance field spread in atlas pixels
pub const FIRST_CHAR: u8       = 32;   // space
pub const LAST_CHAR:  u8       = 126;  // ~
pub const NUM_CHARS:  usize    = LAST_CHAR - FIRST_CHAR + 1;

pub const GlyphInfo = struct {
    u0: f32, v0: f32,  // atlas UV top-left  (includes SDF_SPREAD padding)
    u1: f32, v1: f32,  // atlas UV bottom-right
    bearing_x: f32,    // pen-to-quad-left  = bear_x - SDF_SPREAD
    bearing_y: f32,    // baseline-to-quad-top = bear_y + SDF_SPREAD
    width:     f32,    // glyph_w + 2*SDF_SPREAD
    height:    f32,    // glyph_h + 2*SDF_SPREAD
    advance:   f32,
};

pub const FontAtlas = struct {
    glyphs:  [NUM_CHARS]GlyphInfo,
    texture: metal.Texture,
    ascent:  f32,
};

// Brute-force SDF: for each pixel find the nearest pixel with opposite fill
// state and compute the signed distance.  Uses squared distances to avoid
// sqrt in the inner loop (only one sqrt per output pixel).
// spread controls how many pixels of ramp exist on each side of the edge.
fn computeSDF(src: []const u8, dst: []u8, width: usize, height: usize, spread: f32) void {
    const sr: usize = @intFromFloat(@ceil(spread));
    const no_edge_sq: f32 = (spread + 1.0) * (spread + 1.0);

    for (0..height) |y| {
        for (0..width) |x| {
            const inside = src[y * width + x] > 127;
            var min_sq: f32 = no_edge_sq;

            const y0 = if (y >= sr) y - sr else 0;
            const y1 = @min(y + sr + 1, height);
            const x0 = if (x >= sr) x - sr else 0;
            const x1 = @min(x + sr + 1, width);

            for (y0..y1) |sy| {
                for (x0..x1) |sx| {
                    if ((src[sy * width + sx] > 127) != inside) {
                        const dx = @as(f32, @floatFromInt(sx)) - @as(f32, @floatFromInt(x));
                        const dy = @as(f32, @floatFromInt(sy)) - @as(f32, @floatFromInt(y));
                        const d = dx * dx + dy * dy;
                        if (d < min_sq) min_sq = d;
                    }
                }
            }

            const dist   = @sqrt(min_sq);
            const signed = if (inside) dist else -dist;
            // Map [-spread, +spread] → [0, 1]; pixels fully in/outside clamp to 255/0.
            const norm   = (signed + spread) / (2.0 * spread);
            dst[y * width + x] = @intFromFloat(@max(0.0, @min(255.0, norm * 255.0)));
        }
    }
}

pub fn bake(device: metal.Device, font_name: [:0]const u8) !FontAtlas {
    const bitmap = try std.heap.page_allocator.alloc(u8, ATLAS_SIZE * ATLAS_SIZE);
    defer std.heap.page_allocator.free(bitmap);
    @memset(bitmap, 0);

    const sdf_buf = try std.heap.page_allocator.alloc(u8, ATLAS_SIZE * ATLAS_SIZE);
    defer std.heap.page_allocator.free(sdf_buf);

    const cs  = cg.CGColorSpaceCreateDeviceGray();
    defer cg.CGColorSpaceRelease(cs);
    const ctx = cg.CGBitmapContextCreate(bitmap.ptr, ATLAS_SIZE, ATLAS_SIZE, 8, ATLAS_SIZE, cs, 0);
    defer cg.CGContextRelease(ctx);

    // Keep greyscale AA on — at 16 px CoreText renders no pixels when AA is disabled.
    // The SDF threshold at 127 (>50% coverage = inside) gives a clean binary edge.
    cg.CGContextSetShouldSmoothFonts(ctx, false);

    const cf_name = cg.CFStringCreateWithCString(null, font_name.ptr, cg.kCFStringEncodingUTF8);
    defer cg.CFRelease(cf_name);
    const font = cg.CTFontCreateWithName(cf_name, FONT_SIZE, null);
    defer cg.CFRelease(font);

    const ascent  = @as(f32, @floatCast(cg.CTFontGetAscent(font)));
    const descent = @as(f32, @floatCast(cg.CTFontGetDescent(font)));
    // Row height = glyph extent + SDF padding top and bottom + a little extra.
    const row_h: f32 = @ceil(ascent + descent) + 2.0 * SDF_SPREAD + 4.0;

    cg.CGContextSetGrayFillColor(ctx, 1.0, 1.0);

    var glyphs: [NUM_CHARS]GlyphInfo = undefined;
    // Gap between adjacent glyph atlas regions so SDFs don't bleed into each other.
    const gap: f32 = 2.0 * SDF_SPREAD + 2.0;
    var pen_x: f32 = SDF_SPREAD + 2.0;
    var row_y: f32 = 0.0;  // top of current row in atlas y-down coordinates

    for (FIRST_CHAR..LAST_CHAR + 1) |char_code| {
        const idx = char_code - FIRST_CHAR;
        const uc  = @as(cg.UniChar, @intCast(char_code));

        const uc_arr:    [1]cg.UniChar  = .{uc};
        var   glyph_arr: [1]cg.CGGlyph = .{0};
        _ = cg.CTFontGetGlyphsForCharacters(font, &uc_arr, &glyph_arr, 1);

        var bbox_arr: [1]cg.CGRect = .{.{
            .origin = .{ .x = 0, .y = 0 },
            .size   = .{ .width = 0, .height = 0 },
        }};
        _ = cg.CTFontGetBoundingRectsForGlyphs(font, cg.kCTFontOrientationDefault,
                                                &glyph_arr, &bbox_arr, 1);
        const bbox = bbox_arr[0];

        var adv_arr: [1]cg.CGSize = .{.{ .width = 0, .height = 0 }};
        _ = cg.CTFontGetAdvancesForGlyphs(font, cg.kCTFontOrientationDefault,
                                           &glyph_arr, &adv_arr, 1);
        const adv = adv_arr[0];

        const glyph_w = @as(f32, @floatCast(@ceil(bbox.size.width)));
        const glyph_h = @as(f32, @floatCast(@ceil(bbox.size.height)));
        const bear_x  = @as(f32, @floatCast(bbox.origin.x));
        const bear_y  = @as(f32, @floatCast(bbox.origin.y + bbox.size.height));
        const advance = @as(f32, @floatCast(adv.width));

        // Wrap to next row when the glyph's SDF right edge would overflow.
        if (pen_x + advance + SDF_SPREAD >= @as(f32, ATLAS_SIZE)) {
            pen_x  = SDF_SPREAD + 2.0;
            row_y += row_h;
        }

        // Baseline in atlas y-down: row top + SDF top padding + ascent.
        const baseline_from_top = row_y + SDF_SPREAD + ascent + 1.0;
        // CG uses y-up, so flip to get CG baseline.
        const cg_baseline: cg.CGFloat = @as(f64, ATLAS_SIZE) -
                                        @as(f64, @floatCast(baseline_from_top));

        if (glyph_w > 0 and glyph_h > 0) {
            const pos_arr: [1]cg.CGPoint = .{.{ .x = @floatCast(pen_x), .y = cg_baseline }};
            cg.CTFontDrawGlyphs(font, &glyph_arr, &pos_arr, 1, ctx);
        }

        // Glyph top row in atlas y-down coordinates.
        // CG stores row 0 at the top (CG y = ATLAS_SIZE-1 is memory row 0),
        // so atlas_row = (ATLAS_SIZE-1) - cg_y for any CG y-up coordinate.
        const cg_glyph_top = cg_baseline + bbox.origin.y + bbox.size.height;
        const atlas_top = @as(f32, @floatCast(@as(f64, ATLAS_SIZE - 1) - cg_glyph_top));
        const atlas_x   = pen_x + bear_x;

        // UV region expanded by SDF_SPREAD so the shader sees the full distance ramp.
        glyphs[idx] = .{
            .u0        = (atlas_x  - SDF_SPREAD)             / @as(f32, ATLAS_SIZE),
            .v0        = (atlas_top - SDF_SPREAD)             / @as(f32, ATLAS_SIZE),
            .u1        = (atlas_x  + glyph_w + SDF_SPREAD)   / @as(f32, ATLAS_SIZE),
            .v1        = (atlas_top + glyph_h + SDF_SPREAD)  / @as(f32, ATLAS_SIZE),
            .bearing_x = bear_x - SDF_SPREAD,
            .bearing_y = bear_y + SDF_SPREAD,
            .width     = glyph_w + 2.0 * SDF_SPREAD,
            .height    = glyph_h + 2.0 * SDF_SPREAD,
            .advance   = advance,
        };

        pen_x += advance + gap;
    }

    // Compute signed distance field from the binary coverage bitmap.
    // No vertical flip needed: CG stores row 0 at the top of the image
    // (highest CG y), which is already the Metal/screen top-left origin.
    computeSDF(bitmap, sdf_buf, ATLAS_SIZE, ATLAS_SIZE, SDF_SPREAD);

    // Sentinel pixel (0,0) = 255 so fillRect quads (uv=0,0) sample coverage=1.
    sdf_buf[0] = 255;

    // Buffer-backed texture: avoids replaceRegion's large-struct ARM64 ABI issue.
    const desc    = metal.TextureDescriptor.texture2D(.r8_unorm, ATLAS_SIZE, ATLAS_SIZE);
    desc.setUsage(1); // MTLTextureUsageShaderRead
    const buf     = device.newBufferWithBytes(sdf_buf, .MTLResourceStorageModeShared);
    const texture = buf.newTextureWithDescriptor(desc, 0, ATLAS_SIZE);

    return .{ .glyphs = glyphs, .texture = texture, .ascent = ascent };
}
