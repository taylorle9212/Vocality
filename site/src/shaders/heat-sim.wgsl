// Heat trail simulation, one pass per frame between two ping-pong targets:
// spread to neighbours (diffusion), drift upward like rising air, cool down,
// and add heat under the pointer.

struct Heat {
  pointer: vec2f,   // in simulation pixels
  size: vec2f,      // simulation size in pixels
  radius: f32,
  strength: f32,    // 0 when the pointer is outside
  cooling: f32,
  time: f32,
}
@group(0) @binding(0) var<uniform> heat: Heat;
@group(0) @binding(1) var prev: texture_2d<f32>;

fn at(p: vec2i) -> f32 {
  let maxp = vec2i(heat.size) - vec2i(1);
  return textureLoad(prev, clamp(p, vec2i(0), maxp), 0).r;
}

@fragment
fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let p = vec2i(uv * heat.size);
  // Rising: read the cell just below, so heat moves up over time.
  let below = p + vec2i(0, 1);
  let center = at(below);
  let neighbours = (at(below + vec2i(1, 0)) + at(below - vec2i(1, 0)) + at(below + vec2i(0, 1)) + at(below - vec2i(0, 1))) * 0.25;
  var v = mix(center, neighbours, 0.55) * heat.cooling;
  let d = distance(uv * heat.size, heat.pointer);
  v += heat.strength * exp(-(d * d) / (heat.radius * heat.radius));
  return vec4f(min(v, 1.6), 0.0, 0.0, 1.0);
}
