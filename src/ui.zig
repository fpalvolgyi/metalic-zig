const font = @import("font.zig");

pub const MAX_QUADS    = 2048;
pub const MAX_VERTICES = MAX_QUADS * 6;

pub const Color = struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32 = 1.0,
};

// Pixel coordinates, top-left origin, y increases downward.
pub const Rect = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,

    pub fn contains(self: Rect, px: f32, py: f32) bool {
        return px >= self.x and px < self.x + self.w and
               py >= self.y and py < self.y + self.h;
    }
};

// Layout must match Metal's UIVertex exactly — 32 bytes, no padding.
// pos: offset 0 (8 B), uv: offset 8 (8 B), color: offset 16 (16 B)
pub const UIVertex = extern struct {
    pos:   [2]f32,
    uv:    [2]f32,
    color: [4]f32,
};

// Passed to the vertex shader at buffer index 1.
pub const ScreenSize = extern struct {
    w: f32,
    h: f32,
};

pub const QuadBatcher = struct {
    vertices: [MAX_VERTICES]UIVertex = undefined,
    count:    usize                  = 0,

    pub fn reset(self: *QuadBatcher) void {
        self.count = 0;
    }

    pub fn fillRect(self: *QuadBatcher, rect: Rect, color: Color) void {
        if (self.count + 6 > MAX_VERTICES) return;
        const c  = [4]f32{ color.r, color.g, color.b, color.a };
        const x0 = rect.x;
        const y0 = rect.y;
        const x1 = rect.x + rect.w;
        const y1 = rect.y + rect.h;
        // All UVs point to the sentinel pixel (0,0) which has SDF=1.0 → coverage=1.
        self.vertices[self.count + 0] = .{ .pos = .{ x0, y0 }, .uv = .{ 0, 0 }, .color = c };
        self.vertices[self.count + 1] = .{ .pos = .{ x1, y0 }, .uv = .{ 0, 0 }, .color = c };
        self.vertices[self.count + 2] = .{ .pos = .{ x0, y1 }, .uv = .{ 0, 0 }, .color = c };
        self.vertices[self.count + 3] = .{ .pos = .{ x1, y0 }, .uv = .{ 0, 0 }, .color = c };
        self.vertices[self.count + 4] = .{ .pos = .{ x1, y1 }, .uv = .{ 0, 0 }, .color = c };
        self.vertices[self.count + 5] = .{ .pos = .{ x0, y1 }, .uv = .{ 0, 0 }, .color = c };
        self.count += 6;
    }

    // Draws text with the baseline at (x, y).  atlas must have been baked beforehand.
    pub fn drawText(self: *QuadBatcher, text: []const u8, x: f32, y: f32, color: Color, atlas: *const font.FontAtlas) void {
        var pen_x = x;
        const c = [4]f32{ color.r, color.g, color.b, color.a };
        for (text) |ch| {
            if (ch < font.FIRST_CHAR or ch > font.LAST_CHAR) { pen_x += 8; continue; }
            if (self.count + 6 > MAX_VERTICES) return;
            const g  = atlas.glyphs[ch - font.FIRST_CHAR];
            const x0 = pen_x + g.bearing_x;
            const y0 = y     - g.bearing_y;  // baseline - ascent above baseline = glyph top
            const x1 = x0 + g.width;
            const y1 = y0 + g.height;
            self.vertices[self.count + 0] = .{ .pos = .{ x0, y0 }, .uv = .{ g.u0, g.v0 }, .color = c };
            self.vertices[self.count + 1] = .{ .pos = .{ x1, y0 }, .uv = .{ g.u1, g.v0 }, .color = c };
            self.vertices[self.count + 2] = .{ .pos = .{ x0, y1 }, .uv = .{ g.u0, g.v1 }, .color = c };
            self.vertices[self.count + 3] = .{ .pos = .{ x1, y0 }, .uv = .{ g.u1, g.v0 }, .color = c };
            self.vertices[self.count + 4] = .{ .pos = .{ x1, y1 }, .uv = .{ g.u1, g.v1 }, .color = c };
            self.vertices[self.count + 5] = .{ .pos = .{ x0, y1 }, .uv = .{ g.u0, g.v1 }, .color = c };
            self.count += 6;
            pen_x += g.advance;
        }
    }

    // Draws a filled rect with a 1px solid border on all four sides.
    pub fn button(self: *QuadBatcher, rect: Rect, fill: Color, border: Color) void {
        self.fillRect(rect, fill);
        const t: f32 = 1.0;
        self.fillRect(.{ .x = rect.x,              .y = rect.y,              .w = rect.w,         .h = t              }, border);
        self.fillRect(.{ .x = rect.x,              .y = rect.y + rect.h - t, .w = rect.w,         .h = t              }, border);
        self.fillRect(.{ .x = rect.x,              .y = rect.y + t,          .w = t,              .h = rect.h - 2 * t }, border);
        self.fillRect(.{ .x = rect.x + rect.w - t, .y = rect.y + t,          .w = t,              .h = rect.h - 2 * t }, border);
    }
};
