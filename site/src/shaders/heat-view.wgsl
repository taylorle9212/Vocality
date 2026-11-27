// Draws the heat simulation in thermal colors, with a faint shimmer at rest.

import { simplex3d } from "@vgpu/wgsl-std/noise/simplex";
import { thermal } from "./thermal.wgsl";

struct View {
  time: f32,
  dark: f32,
  pad0: f32,
  pad1: f32,
}
@group(0) @binding(0) var<uniform> view: View;
@group(0) @binding(1) var heatTex: texture_2d<f32>;
@group(0) @binding(2) var heatSampler: sampler;

@fragment
fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let v = textureSample(heatTex, heatSampler, uv).r;
  let shimmer = (simplex3d(vec3f(uv * vec2f(6.0, 3.0), view.time * 0.12)) * 0.5 + 0.5) * 0.05;
  let h = v + shimmer;
  let rgb = thermal(0.08 + h * 0.75);
  let alpha = smoothstep(0.02, 0.7, h) * mix(0.7, 0.9, view.dark);
  return vec4f(rgb * alpha, alpha);
}
