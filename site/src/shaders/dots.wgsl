// Expands each dot into a screen-aligned quad and shades it as an
// antialiased round dot in the thermal ("inferno") palette. Output is
// premultiplied so dots composite cleanly over the page background.

struct Dot {
  pos: vec2f,
  vel: vec2f,
  seed: vec4f,
  state: vec4f,
}

struct View {
  resolution: vec2f,
  aspect: f32,
  pixelSize: f32,
  // 0 = light page, 1 = dark page
  dark: f32,
  sizeBoost: f32,
  pad0: f32,
  pad1: f32,
}

@group(0) @binding(0) var<storage, read> dots: array<Dot>;
@group(0) @binding(1) var<uniform> view: View;

struct VertexOut {
  @builtin(position) position: vec4f,
  @location(0) local: vec2f,
  @location(1) color: vec3f,
  @location(2) alpha: f32,
  @location(3) radiusPx: f32,
}

// #320A5E → #781C6D → #BC3754 → #ED6925 → #FBB61A
fn thermal(t: f32) -> vec3f {
  let c0 = vec3f(0.196, 0.039, 0.369);
  let c1 = vec3f(0.471, 0.110, 0.427);
  let c2 = vec3f(0.737, 0.216, 0.329);
  let c3 = vec3f(0.929, 0.412, 0.145);
  let c4 = vec3f(0.984, 0.714, 0.102);
  let x = clamp(t, 0.0, 1.0) * 4.0;
  if (x < 1.0) { return mix(c0, c1, x); }
  if (x < 2.0) { return mix(c1, c2, x - 1.0); }
  if (x < 3.0) { return mix(c2, c3, x - 2.0); }
  return mix(c3, c4, x - 3.0);
}

@vertex fn vs_main(
  @builtin(vertex_index) vertex: u32,
  @builtin(instance_index) instance: u32,
) -> VertexOut {
  var quad = array<vec2f, 6>(
    vec2f(-1.0, -1.0), vec2f(1.0, -1.0), vec2f(-1.0, 1.0),
    vec2f(-1.0, 1.0), vec2f(1.0, -1.0), vec2f(1.0, 1.0),
  );
  let corner = quad[vertex];
  let d = dots[instance];
  var out: VertexOut;
  out.local = corner;
  out.alpha = d.state.x;
  if (d.state.x < 0.003) {
    out.position = vec4f(2.0, 2.0, 0.0, 1.0);
    return out;
  }

  let bright = d.state.y;
  // On a white page the pale yellow end washes out, so shift the palette darker.
  let range = mix(vec2f(0.05, 0.86), vec2f(0.18, 1.0), view.dark);
  let t = mix(range.x, range.y, clamp(d.seed.z + bright * 0.25, 0.0, 1.0));
  out.color = thermal(t);

  let radius = (d.seed.w * (1.0 + 0.45 * bright) * view.sizeBoost) * view.pixelSize;
  out.radiusPx = radius;
  let padded = radius + 1.0;
  let ndc = vec2f(d.pos.x / view.aspect, d.pos.y);
  out.position = vec4f(ndc + corner * padded * 2.0 / view.resolution, 0.0, 1.0);
  out.local = corner * padded;
  return out;
}

@fragment fn fs_main(in: VertexOut) -> @location(0) vec4f {
  let dist = length(in.local);
  let coverage = clamp(in.radiusPx + 0.5 - dist, 0.0, 1.0);
  // Sub-pixel dots fade instead of shimmering.
  let a = coverage * in.alpha * min(1.0, in.radiusPx * 1.4);
  if (a <= 0.002) {
    discard;
  }
  return vec4f(in.color * a, a);
}
