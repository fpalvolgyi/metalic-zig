
#include <metal_stdlib>
using namespace metal;

// Layout must match Zig's Particle extern struct exactly.
struct Particle {
    float2 position;  // NDC -1..1
    float2 velocity;
    float4 color;
};

// Layout must match Zig's MouseUniforms extern struct exactly.
struct MouseUniforms {
    float2 pos;
    float  radius;
    float  strength;
};

struct VertexOut {
    float4 position   [[position]];
    float4 color;
    float  point_size [[point_size]];
};

// ---------------------------------------------------------------------------
// Compute — one thread per particle
// ---------------------------------------------------------------------------

kernel void updateParticles(
    device Particle* particles [[buffer(0)]],
    constant MouseUniforms& mouse [[buffer(1)]],
    uint id    [[thread_position_in_grid]],
    uint count [[threads_per_grid]])
{
    if (id >= count) return;

    Particle p = particles[id];

    const float dt      = 0.016;
    const float gravity = -0.4;
    const float damping = 0.82; // energy lost on floor bounce

    p.velocity.y += gravity * dt;
    p.position   += p.velocity * dt;

    if (p.position.x < -1.0) { p.position.x = -1.0; p.velocity.x =  abs(p.velocity.x); }
    if (p.position.x >  1.0) { p.position.x =  1.0; p.velocity.x = -abs(p.velocity.x); }
    if (p.position.y < -1.0) { p.position.y = -1.0; p.velocity.y =  abs(p.velocity.y) * damping; }
    if (p.position.y >  1.0) { p.position.y =  1.0; p.velocity.y = -abs(p.velocity.y); }

    // Mouse repulsion — push particles away from the cursor.
    float2 delta = p.position - mouse.pos;
    float  dist  = length(delta);
    if (dist < mouse.radius && dist > 0.0001) {
        float falloff = 1.0 - dist / mouse.radius;
        p.velocity += normalize(delta) * mouse.strength * falloff;
    }

    particles[id] = p;
}

// ---------------------------------------------------------------------------
// Render — one vertex per particle, drawn as points
// ---------------------------------------------------------------------------

vertex VertexOut particleVertex(
    uint id [[vertex_id]],
    constant Particle* particles [[buffer(0)]])
{
    VertexOut out;
    out.position   = float4(particles[id].position, 0.0, 1.0);
    out.color      = particles[id].color;
    out.point_size = 3.0;
    return out;
}

fragment float4 particleFragment(VertexOut in [[stage_in]],
                                  float2 coord [[point_coord]])
{
    // Discard corners so each point sprite is a circle.
    if (length(coord - 0.5) > 0.5) discard_fragment();
    return in.color;
}

// ---------------------------------------------------------------------------
// UI — immediate-mode quad batcher
// Layout must match Zig's UIVertex extern struct (32 bytes, no padding).
// ---------------------------------------------------------------------------

struct UIVertex {
    float2 pos;    // pixel coords, top-left origin, y increases downward
    float2 uv;
    float4 color;
};

struct UIOut {
    float4 position [[position]];
    float2 uv;
    float4 color;
};

struct ScreenSize {
    float w;
    float h;
};

vertex UIOut uiVertex(
    uint              vid    [[vertex_id]],
    constant UIVertex* verts [[buffer(0)]],
    constant ScreenSize& screen [[buffer(1)]])
{
    UIVertex v = verts[vid];
    // Pixel (top-left, y-down) → NDC (centre 0, y-up)
    float x_ndc =  (v.pos.x / screen.w) * 2.0 - 1.0;
    float y_ndc = -((v.pos.y / screen.h) * 2.0 - 1.0);
    UIOut out;
    out.position = float4(x_ndc, y_ndc, 0.0, 1.0);
    out.uv       = v.uv;
    out.color    = v.color;
    return out;
}

fragment float4 uiFragment(
    UIOut in [[stage_in]],
    texture2d<float> atlas [[texture(0)]],
    sampler smp [[sampler(0)]])
{
    // coverage=1 for solid rects (uv→white pixel), glyph alpha for text.
    float coverage = atlas.sample(smp, in.uv).r;
    return float4(in.color.rgb, in.color.a * coverage);
}
