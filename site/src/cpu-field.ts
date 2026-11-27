// Canvas 2D fallback for browsers without WebGPU. It mirrors simulate.wgsl
// and dots.wgsl on the CPU with fewer dots, so the page keeps its look.

import { FLOATS_PER_DOT, makeDots, toWorld, type DotField, type FieldConfig, type Layout } from "./field";
import type { Envelope } from "./timeline";

const PALETTE: [number, number, number][] = [
  [0x32, 0x0a, 0x5e],
  [0x78, 0x1c, 0x6d],
  [0xbc, 0x37, 0x54],
  [0xed, 0x69, 0x25],
  [0xfb, 0xb6, 0x1a],
];

function thermal(t: number): string {
  const x = Math.min(1, Math.max(0, t)) * 4;
  const i = Math.min(3, Math.floor(x));
  const f = x - i;
  const a = PALETTE[i]!;
  const b = PALETTE[i + 1]!;
  return `rgb(${a[0] + (b[0] - a[0]) * f | 0},${a[1] + (b[1] - a[1]) * f | 0},${a[2] + (b[2] - a[2]) * f | 0})`;
}

const smooth = (a: number, b: number, x: number) => {
  const t = Math.min(1, Math.max(0, (x - a) / (b - a)));
  return t * t * (3 - 2 * t);
};

export function createCpuField(canvas: HTMLCanvasElement, cfg: FieldConfig): DotField {
  const ctx = canvas.getContext("2d")!;
  const count = Math.max(80, Math.round(cfg.count * 0.12));
  let cssW = 1;
  let cssH = 1;
  let dpr = 1;
  let layout: Layout = cfg.layout(Math.max(1, canvas.clientWidth), Math.max(1, canvas.clientHeight));
  const d = makeDots(count, layout.aspect, cfg.label.length * 7919);
  let pointer: [number, number] = [0, 0];
  let pointerActive = false;
  let dark = false;
  let time = 0;

  const resize = () => {
    cssW = Math.max(1, canvas.clientWidth);
    cssH = Math.max(1, canvas.clientHeight);
    dpr = Math.min(2, window.devicePixelRatio || 1);
    canvas.width = Math.round(cssW * dpr);
    canvas.height = Math.round(cssH * dpr);
    layout = cfg.layout(cssW, cssH);
  };
  resize();
  new ResizeObserver(resize).observe(canvas);

  const potential = (x: number, y: number) => {
    const p = layout.flowScale;
    return (
      Math.sin(x * p * 1.7 + time * 0.21) * Math.cos(y * p * 1.9 - time * 0.17) +
      0.5 * Math.sin((x + y) * p * 2.3 + time * 0.13)
    );
  };

  const step = (env: Envelope, dt: number) => {
    dt = Math.min(dt, 0.05);
    const ax = layout.aspect;
    for (let i = 0; i < count; i++) {
      const o = i * FLOATS_PER_DOT;
      let px = d[o]!, py = d[o + 1]!, vx = d[o + 2]!, vy = d[o + 3]!;
      const slotT = d[o + 4]!, thresh = d[o + 5]!;
      if (d[o + 10]! > 0.5) {
        if (env.send < 0.02) {
          d[o] = (Math.random() * 2 - 1) * ax;
          d[o + 1] = Math.random() * 2 - 1;
          d[o + 2] = d[o + 3] = d[o + 8] = d[o + 10] = 0;
        }
        continue;
      }
      const e = 0.01;
      const dx = potential(px + e, py) - potential(px - e, py);
      const dy = potential(px, py + e) - potential(px, py - e);
      const speed = (0.025 + 0.22 * env.level) / (2 * e);
      let accX = (dy * speed - vx) * 2.2;
      let accY = (-dx * speed - vy) * 2.2;

      const tx = layout.sendTarget[0] - px;
      const ty = layout.sendTarget[1] - py;
      const dist = Math.hypot(tx, ty) + 1e-5;
      const lag = slotT * 0.55;
      const pull = smooth(lag, lag + 0.35, env.send);
      const sx = layout.lineX + (slotT * 2 - 1) * layout.lineHalfWidth;
      const sy = layout.lineY + (thresh - 0.5) * 0.012;
      const r = env.refine * (1 - pull);
      accX += ((sx - px) * 14 - vx * 5) * r;
      accY += ((sy - py) * 14 - vy * 5) * r;
      const mag = 2.5 + 6 * pull;
      accX += ((tx / dist) * mag - vx * 3) * pull * 4;
      accY += ((ty / dist) * mag - vy * 3) * pull * 4;

      if (pointerActive) {
        const awx = px - pointer[0], awy = py - pointer[1];
        const pd = Math.hypot(awx, awy) + 1e-5;
        const f = 1 - smooth(0, layout.pointerRadius, pd);
        accX += (awx / pd) * f * f * 3.5;
        accY += (awy / pd) * f * f * 3.5;
      }

      vx += accX * dt;
      vy += accY * dt;
      px += vx * dt;
      py += vy * dt;
      if (env.refine < 0.05 && env.send < 0.05) {
        const spanX = ax * 2 + 0.1, spanY = 2.1;
        px -= spanX * Math.floor((px + ax + 0.05) / spanX);
        py -= spanY * Math.floor((py + 1.05) / spanY);
      }
      if (env.send > 0.05 && dist < 0.035 * (0.6 + env.send)) {
        d[o + 10] = 1;
        d[o + 8] = 0;
        continue;
      }
      const reveal = layout.baseVisible + (1 - layout.baseVisible) * Math.max(env.level, env.refine * 0.9);
      const visible = 1 - smooth(reveal - 0.08, reveal, thresh);
      const rate = visible > d[o + 8]! ? 5 : 1.4;
      d[o + 8] = d[o + 8]! + (visible - d[o + 8]!) * (1 - Math.exp(-dt * rate));
      d[o + 9] = Math.min(1.5, env.level * 0.8 + Math.hypot(vx, vy) * 0.9 + env.refine * 0.3);
      d[o] = px;
      d[o + 1] = py;
      d[o + 2] = vx;
      d[o + 3] = vy;
    }
  };

  const render = () => {
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    const ax = layout.aspect;
    const lo = dark ? 0.18 : 0.05;
    const hi = dark ? 1 : 0.86;
    for (let i = 0; i < count; i++) {
      const o = i * FLOATS_PER_DOT;
      const alpha = d[o + 8]!;
      if (alpha < 0.01 || d[o + 10]! > 0.5) continue;
      const bright = d[o + 9]!;
      const x = ((d[o]! / ax + 1) / 2) * canvas.width;
      const y = ((1 - d[o + 1]!) / 2) * canvas.height;
      const radius = Math.max(0.6, d[o + 7]! * (1 + 0.45 * bright) * cfg.sizeBoost * dpr);
      ctx.globalAlpha = alpha;
      ctx.fillStyle = thermal(lo + (hi - lo) * Math.min(1, d[o + 6]! + bright * 0.25));
      ctx.beginPath();
      ctx.arc(x, y, radius, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.globalAlpha = 1;
  };

  let isStill = false;
  return {
    setPointer(point) {
      if (!point) {
        pointerActive = false;
        return;
      }
      pointer = toWorld(point[0], point[1], cssW, cssH);
      pointerActive = true;
    },
    setDark(next) {
      dark = next;
      if (isStill) render();
    },
    setActive() {},
    tick(env, dt, t) {
      time = t;
      step(env, dt);
      render();
    },
    still(env) {
      isStill = true;
      time = 3;
      for (let k = 0; k < 90; k++) step(env, 1 / 30);
      render();
      new ResizeObserver(() => requestAnimationFrame(render)).observe(canvas);
    },
  };
}
