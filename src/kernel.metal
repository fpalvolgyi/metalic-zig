
#include <metal_stdlib>
using namespace metal;

// Layout must match Zig's Particle extern struct exactly.
struct Particle {
    float2 position;  // NDC -1..1
    float2 velocity;
    float4 color;
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
