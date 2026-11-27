// One thread per dot. Dots drift through a curl-noise flow field whose speed
// follows the voice level, condense onto a horizontal line while "refining",
// and stream into the send point while "sending". Dots absorbed by the send
// point respawn at a random spot once the cycle returns to listening.

import { simplex3d } from "@vgpu/wgsl-std/noise/simplex";
import { hash2 } from "@vgpu/wgsl-std/hash";

struct Dot {
  pos: vec2f,
  vel: vec2f,
  // x: line slot (0..1), y: appearance threshold, z: palette position, w: base size
  seed: vec4f,
  // x: alpha, y: brightness, z: absorbed flag, w: respawn counter
  state: vec4f,
}

struct Params {
  pointer: vec2f,
  sendTarget: vec2f,
  aspect: f32,
  time: f32,
  dt: f32,
  level: f32,
  refine: f32,
  send: f32,
  pointerActive: f32,
  pointerRadius: f32,
  lineY: f32,
  lineHalfWidth: f32,
  flowScale: f32,
  baseVisible: f32,
  count: u32,
  lineX: f32,
  pad1: f32,
  pad2: f32,
}

@group(0) @binding(0) var<uniform> params: Params;
@group(0) @binding(1) var<storage, read_write> dots: array<Dot>;

fn potential(p: vec2f) -> f32 {
  return simplex3d(vec3f(p * params.flowScale, params.time * 0.07));
}

// Divergence-free flow: the curl of a scalar noise potential.
fn curl(p: vec2f) -> vec2f {
  let e = 0.01;
  let dx = potential(p + vec2f(e, 0.0)) - potential(p - vec2f(e, 0.0));
  let dy = potential(p + vec2f(0.0, e)) - potential(p - vec2f(0.0, e));
  return vec2f(dy, -dx) / (2.0 * e);
}

@compute @workgroup_size(64)
fn cs_main(@builtin(global_invocation_id) id: vec3u) {
  let i = id.x;
  if (i >= params.count) {
    return;
  }
  var d = dots[i];
  let dt = min(params.dt, 0.05);
  let level = params.level;
  let bounds = vec2f(params.aspect, 1.0);

  // Respawn absorbed dots once the send has finished.
  if (d.state.z > 0.5) {
    if (params.send < 0.02) {
      let r = hash2(vec2f(f32(i) * 0.37 + d.state.w * 13.1, params.time));
      d.pos = (r * 2.0 - 1.0) * bounds;
      d.vel = vec2f(0.0);
      d.state = vec4f(0.0, 0.0, 0.0, d.state.w + 1.0);
    }
    dots[i] = d;
    return;
  }

  // Flow field, faster and stronger with volume.
  let flow = curl(d.pos) * (0.025 + 0.22 * level);
  var accel = (flow - d.vel) * 2.2;

  // Send: stream toward the target; dots nearest the target leave the line first.
  let toTarget = params.sendTarget - d.pos;
  let dist = length(toTarget);
  let lag = d.seed.x * 0.55;
  let pull = smoothstep(lag, lag + 0.35, params.send);

  // Refine: spring toward this dot's slot on the line.
  let slot = vec2f(
    params.lineX + (d.seed.x * 2.0 - 1.0) * params.lineHalfWidth,
    params.lineY + (d.seed.y - 0.5) * 0.012
  );
  accel += ((slot - d.pos) * 14.0 - d.vel * 5.0) * params.refine * (1.0 - pull);

  accel += (normalize(toTarget + vec2f(1e-5)) * (2.5 + 6.0 * pull) - d.vel * 3.0) * pull * 4.0;

  // Pointer: dots part around the cursor.
  if (params.pointerActive > 0.5) {
    let away = d.pos - params.pointer;
    let pd = length(away);
    let falloff = 1.0 - smoothstep(0.0, params.pointerRadius, pd);
    accel += normalize(away + vec2f(1e-5)) * falloff * falloff * 3.5;
  }

  d.vel += accel * dt;
  d.pos += d.vel * dt;

  // Wrap around the edges while free-floating.
  if (params.refine < 0.05 && params.send < 0.05) {
    let span = bounds * 2.0 + 0.1;
    d.pos = d.pos - span * floor((d.pos + bounds + 0.05) / span);
  }

  if (params.send > 0.05 && dist < 0.035 * (0.6 + params.send)) {
    d.state.z = 1.0;
    d.state.x = 0.0;
    dots[i] = d;
    return;
  }

  // Louder voice reveals more dots and brightens them.
  let reveal = params.baseVisible + (1.0 - params.baseVisible) * max(level, params.refine * 0.9);
  let visible = 1.0 - smoothstep(reveal - 0.08, reveal, d.seed.y);
  let fadeRate = select(1.4, 5.0, visible > d.state.x);
  d.state.x = mix(d.state.x, visible, 1.0 - exp(-dt * fadeRate));
  let speed = length(d.vel);
  d.state.y = clamp(level * 0.8 + speed * 0.9 + params.refine * 0.3, 0.0, 1.5);

  dots[i] = d;
}
