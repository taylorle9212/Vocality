// Story backdrop: slow, domain-warped thermal light behind the pinned window.
// `warmth` follows the dictation: it rises while speaking and cools after the send.

import { fbmSimplex3d } from "@vgpu/wgsl-std/noise/simplex";
import { thermal } from "./thermal.wgsl";

struct Glow {
  size: vec2f,
  time: f32,
  warmth: f32,
  dark: f32,
  pad0: f32,
  pad1: f32,
  pad2: f32,
}
@group(0) @binding(0) var<uniform> glow: Glow;

@fragment
fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let aspect = glow.size.x / max(glow.size.y, 1.0);
  let p = vec2f((uv.x - 0.5) * aspect, uv.y - 0.5);
  let t = glow.time * 0.05;
  // Domain warp: noise displaces the lookup of more noise, giving soft flowing shapes.
  let warp = vec2f(fbmSimplex3d(vec3f(p * 1.2, t), 3, 2.0, 0.5), fbmSimplex3d(vec3f(p * 1.2 + 7.3, t), 3, 2.0, 0.5));
  let n = fbmSimplex3d(vec3f(p * 1.6 + warp * 0.9, t * 1.4), 4, 2.0, 0.5) * 0.5 + 0.5;
  // Light concentrates around the window in the middle, fading to the edges.
  let center = 1.0 - smoothstep(0.15, 0.85, length(p * vec2f(0.75, 1.1)));
  let heat = n * (0.35 + 0.65 * glow.warmth);
  let rgb = thermal(0.12 + heat * 0.85);
  let alpha = center * smoothstep(0.25, 0.85, n) * mix(0.16, 0.32, glow.dark) * (0.45 + 0.55 * glow.warmth);
  return vec4f(rgb * alpha, alpha);
}
