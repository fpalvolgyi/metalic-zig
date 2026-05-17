// Minimal CoreGraphics + CoreText C bindings for font atlas baking.
// Linked via CoreGraphics.framework and CoreText.framework in build.zig.

pub const CGFloat        = f64;
pub const CGColorSpaceRef = ?*anyopaque;
pub const CGContextRef    = ?*anyopaque;
pub const CTFontRef       = ?*anyopaque;
pub const CFStringRef     = ?*anyopaque;
pub const CGGlyph         = u16;
pub const UniChar         = u16;

pub const CGPoint = extern struct { x: CGFloat, y: CGFloat };
pub const CGSize  = extern struct { width: CGFloat, height: CGFloat };
pub const CGRect  = extern struct { origin: CGPoint, size: CGSize };

pub const kCFStringEncodingUTF8: u32 = 0x08000100;
// CTFontOrientation: kCTFontOrientationDefault = 0
pub const kCTFontOrientationDefault: u32 = 0;

// CoreFoundation
pub extern "c" fn CFStringCreateWithCString(alloc: ?*anyopaque, cStr: [*c]const u8, encoding: u32) CFStringRef;
pub extern "c" fn CFRelease(obj: ?*anyopaque) void;

// CoreGraphics — bitmap context
pub extern "c" fn CGColorSpaceCreateDeviceGray() CGColorSpaceRef;
pub extern "c" fn CGColorSpaceRelease(space: CGColorSpaceRef) void;
pub extern "c" fn CGBitmapContextCreate(
    data: ?*anyopaque, width: usize, height: usize,
    bitsPerComponent: usize, bytesPerRow: usize,
    space: CGColorSpaceRef, bitmapInfo: u32,
) CGContextRef;
pub extern "c" fn CGContextRelease(c: CGContextRef) void;
pub extern "c" fn CGBitmapContextGetData(c: CGContextRef) ?*anyopaque;
pub extern "c" fn CGContextSetGrayFillColor(c: CGContextRef, gray: CGFloat, alpha: CGFloat) void;
pub extern "c" fn CGContextFillRect(c: CGContextRef, rect: CGRect) void;
pub extern "c" fn CGContextSetShouldAntialias(c: CGContextRef, should: bool) void;
pub extern "c" fn CGContextSetShouldSmoothFonts(c: CGContextRef, should: bool) void;

// CoreText — font + glyph rendering
pub extern "c" fn CTFontCreateWithName(name: CFStringRef, size: CGFloat, matrix: ?*anyopaque) CTFontRef;
pub extern "c" fn CTFontGetAscent(font: CTFontRef) CGFloat;
pub extern "c" fn CTFontGetDescent(font: CTFontRef) CGFloat;
pub extern "c" fn CTFontGetGlyphsForCharacters(
    font: CTFontRef, characters: [*]const UniChar, glyphs: [*]CGGlyph, count: isize,
) bool;
pub extern "c" fn CTFontGetBoundingRectsForGlyphs(
    font: CTFontRef, orientation: u32,
    glyphs: [*]const CGGlyph, boundingRects: ?[*]CGRect, count: isize,
) CGRect;
pub extern "c" fn CTFontGetAdvancesForGlyphs(
    font: CTFontRef, orientation: u32,
    glyphs: [*]const CGGlyph, advances: ?[*]CGSize, count: isize,
) f64;
pub extern "c" fn CTFontDrawGlyphs(
    font: CTFontRef,
    glyphs: [*]const CGGlyph, positions: [*]const CGPoint,
    count: usize, context: CGContextRef,
) void;
