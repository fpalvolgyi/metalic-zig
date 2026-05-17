// Bakes printable ASCII into a greyscale Metal texture using CoreText.
// Each pixel stores glyph coverage in the R channel (0=transparent, 255=opaque).
// Pixel (0,0) is always white so that fillRect quads (uv=0,0) sample coverage=1.

const std = @import("std");
const cg  = @import("coregraphics.zig");
const metal = @import("metal.zig");

pub const ATLAS_SIZE: usize = 512;
pub const FONT_SIZE:  cg.CGFloat = 16.0;
pub const FIRST_CHAR: u8 = 32;   // space
pub const LAST_CHAR:  u8 = 126;  // ~
pub const NUM_CHARS:  usize = LAST_CHAR - FIRST_CHAR + 1;

pub const GlyphInfo = struct {
    u0: f32, v0: f32,  // atlas UV top-left
    u1: f32, v1: f32,  // atlas UV bottom-right
    bearing_x: f32,    // pen-to-glyph-left, pixels
    bearing_y: f32,    // baseline-to-glyph-top, pixels (positive = above baseline)
    width:     f32,
    height:    f32,
    advance:   f32,    // horizontal pen advance, pixels
};

pub const FontAtlas = struct {
    glyphs:  [NUM_CHARS]GlyphInfo,
    texture: metal.Texture,
    ascent:  f32,
};

pub fn bake(device: metal.Device, font_name: [:0]const u8) !FontAtlas {
    const bitmap = try std.heap.page_allocator.alloc(u8, ATLAS_SIZE * ATLAS_SIZE);
    defer std.heap.page_allocator.free(bitmap);
    @memset(bitmap, 0);

    // Create CG context (greyscale, kCGBitmapByteOrderDefault|kCGImageAlphaNone = 0).
    const cs  = cg.CGColorSpaceCreateDeviceGray();
    defer cg.CGColorSpaceRelease(cs);
    const ctx = cg.CGBitmapContextCreate(bitmap.ptr, ATLAS_SIZE, ATLAS_SIZE, 8, ATLAS_SIZE, cs, 0);
    defer cg.CGContextRelease(ctx);

    cg.CGContextSetShouldSmoothFonts(ctx, false);

    // Create font.
    const cf_name = cg.CFStringCreateWithCString(null, font_name.ptr, cg.kCFStringEncodingUTF8);
    defer cg.CFRelease(cf_name);
    const font = cg.CTFontCreateWithName(cf_name, FONT_SIZE, null);
    defer cg.CFRelease(font);

    const ascent  = @as(f32, @floatCast(cg.CTFontGetAscent(font)));
    const descent = @as(f32, @floatCast(cg.CTFontGetDescent(font)));
    _ = descent;

    // Baseline position measured from the TOP of the atlas (y-down).
    // CG uses y-up: baseline_cg = ATLAS_SIZE - baseline_from_top.
    const baseline_from_top: f32 = ascent + 2.0; // 2px top padding
    const cg_baseline: cg.CGFloat = @as(f64, ATLAS_SIZE) - @as(f64, @floatCast(baseline_from_top));

    // White fill — glyphs render as white on the black background.
    cg.CGContextSetGrayFillColor(ctx, 1.0, 1.0);

    var glyphs: [NUM_CHARS]GlyphInfo = undefined;
    // Start at x=2 to leave column 0 for the white sentinel pixel.
    var pen_x: f32 = 2.0;

    for (FIRST_CHAR..LAST_CHAR + 1) |char_code| {
        const idx = char_code - FIRST_CHAR;
        const uc  = @as(cg.UniChar, @intCast(char_code));

        const uc_arr: [1]cg.UniChar  = .{uc};
        var   glyph_arr: [1]cg.CGGlyph = .{0};
        _ = cg.CTFontGetGlyphsForCharacters(font, &uc_arr, &glyph_arr, 1);

        var bbox_arr: [1]cg.CGRect = .{.{ .origin = .{ .x = 0, .y = 0 }, .size = .{ .width = 0, .height = 0 } }};
        _ = cg.CTFontGetBoundingRectsForGlyphs(font, cg.kCTFontOrientationDefault, &glyph_arr, &bbox_arr, 1);
        const bbox = bbox_arr[0];

        var adv_arr: [1]cg.CGSize = .{.{ .width = 0, .height = 0 }};
        _ = cg.CTFontGetAdvancesForGlyphs(font, cg.kCTFontOrientationDefault, &glyph_arr, &adv_arr, 1);
        const adv = adv_arr[0];

        const glyph_w = @as(f32, @floatCast(@ceil(bbox.size.width)));
        const glyph_h = @as(f32, @floatCast(@ceil(bbox.size.height)));
        const bear_x  = @as(f32, @floatCast(bbox.origin.x));
        // bearing_y = distance from baseline to top of glyph (y-up → positive above baseline)
        const bear_y  = @as(f32, @floatCast(bbox.origin.y + bbox.size.height));
        const advance = @as(f32, @floatCast(adv.width));

        if (glyph_w > 0 and glyph_h > 0) {
            const pos_arr: [1]cg.CGPoint = .{.{ .x = @floatCast(pen_x), .y = cg_baseline }};
            cg.CTFontDrawGlyphs(font, &glyph_arr, &pos_arr, 1, ctx);
        }

        // Convert CG y-up glyph bounds to UV in the final (flipped) texture.
        // In CG: glyph_top_cg = cg_baseline + bbox.origin.y + bbox.size.height
        // After vertical flip: flipped_top_row = ATLAS_SIZE - glyph_top_cg
        const cg_glyph_top = cg_baseline + bbox.origin.y + bbox.size.height;
        const flip_top = @as(f32, @floatCast(@as(f64, ATLAS_SIZE) - cg_glyph_top));
        const atlas_x  = pen_x + bear_x;

        glyphs[idx] = .{
            .u0 = atlas_x / @as(f32, ATLAS_SIZE),
            .v0 = flip_top / @as(f32, ATLAS_SIZE),
            .u1 = (atlas_x + glyph_w) / @as(f32, ATLAS_SIZE),
            .v1 = (flip_top + glyph_h) / @as(f32, ATLAS_SIZE),
            .bearing_x = bear_x,
            .bearing_y = bear_y,
            .width     = glyph_w,
            .height    = glyph_h,
            .advance   = advance,
        };

        pen_x += advance + 1.0;
    }

    // Flip the bitmap vertically: CG stores row 0 at the bottom, Metal expects row 0 at the top.
    var swap: [ATLAS_SIZE]u8 = undefined;
    for (0..ATLAS_SIZE / 2) |row| {
        const a = bitmap[row * ATLAS_SIZE .. (row + 1) * ATLAS_SIZE];
        const b = bitmap[(ATLAS_SIZE - 1 - row) * ATLAS_SIZE .. (ATLAS_SIZE - row) * ATLAS_SIZE];
        @memcpy(&swap, a);
        @memcpy(a, b);
        @memcpy(b, &swap);
    }

    // Sentinel: ensure pixel (0,0) is fully white for solid-rect UV=(0,0) sampling.
    bitmap[0] = 255;

    // Upload to a Metal R8 texture.
    const desc    = metal.TextureDescriptor.texture2D(.r8_unorm, ATLAS_SIZE, ATLAS_SIZE);
    const texture = device.newTextureWithDescriptor(desc);
    texture.replaceRegion(
        .{ .origin = .{ .x = 0, .y = 0, .z = 0 },
           .size   = .{ .width = ATLAS_SIZE, .height = ATLAS_SIZE, .depth = 1 } },
        0, bitmap.ptr, ATLAS_SIZE,
    );

    return .{ .glyphs = glyphs, .texture = texture, .ascent = ascent };
}
