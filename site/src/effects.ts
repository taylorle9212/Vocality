// Two quieter VGPU effects for sections past the hero:
// - a domain-warped thermal glow behind the pinned story (fullscreen `effect`), and
// - a heat trail under the cursor in the closing section (`pingPong` targets: diffuse, rise, cool).

import { effect, pingPong, sampler, surface, type Frame, type Gpu } from "vgpu";

import glowShader from "./shaders/glow.wgsl";
import heatSimShader from "./shaders/heat-sim.wgsl";
import heatViewShader from "./shaders/heat-view.wgsl";

const TRANSPARENT = [0, 0, 0, 0] as const;

export interface StoryGlow {
  active: boolean;
  setDark(dark: boolean): void;
  /** warmth 0...1 follows the dictation in the story. */
  encode(f: Frame, time: number, warmth: number): void;
}

export async function createStoryGlow(gpu: Gpu, canvas: HTMLCanvasElement): Promise<StoryGlow> {
  const surf = surface(gpu, canvas, { dpr: [1, 1.5], alphaMode: "premultiplied", clearColor: TRANSPARENT, label: "story-glow" });
  let dark = 0;
  let warmth = 0;
  const glow = effect(gpu, glowShader, {
    label: "story-glow",
    blend: "premultiplied",
    set: { glow: { size: [surf.size[0], surf.size[1]], time: 0, warmth: 0, dark: 0, pad0: 0, pad1: 0, pad2: 0 } },
  });
  await glow.compile(surf);
  surf.onResize(() => glow.set({ glow: { size: [surf.size[0], surf.size[1]] } }));

  return {
    active: true,
    setDark(next) {
      dark = next ? 1 : 0;
    },
    encode(f, time, target) {
      // Ease toward the target warmth so the glow breathes instead of snapping.
      warmth += (target - warmth) * 0.06;
      glow.set({ glow: { time: time % 4000, warmth, dark } });
      f.pass({ target: surf, clear: TRANSPARENT }, (pass) => pass.draw(glow));
    },
  };
}

export interface HeatField {
  active: boolean;
  setDark(dark: boolean): void;
  /** Pointer in CSS px relative to the canvas, or null when outside. */
  setPointer(point: [number, number] | null): void;
  encode(f: Frame, time: number): void;
}

export async function createHeatField(gpu: Gpu, canvas: HTMLCanvasElement): Promise<HeatField> {
  const surf = surface(gpu, canvas, { dpr: [1, 1.5], alphaMode: "premultiplied", clearColor: TRANSPARENT, label: "heat-surface" });
  // The simulation runs at a quarter of the CSS size; the view samples it with linear filtering.
  const simW = Math.max(64, Math.round(canvas.clientWidth / 4));
  const simH = Math.max(32, Math.round(canvas.clientHeight / 4));
  const field = pingPong(gpu, simW, simH, { format: "rgba16float", clearColor: [0, 0, 0, 1], label: "heat" });
  const linear = sampler(gpu, { magFilter: "linear", minFilter: "linear" });

  let pointer: [number, number] = [0, 0];
  let strength = 0;
  let dark = 0;

  const sim = effect(gpu, heatSimShader, {
    label: "heat-sim",
    set: {
      heat: { pointer, size: [simW, simH], radius: 3.2, strength: 0, cooling: 0.985, time: 0 },
      prev: field.read,
    },
  });
  const view = effect(gpu, heatViewShader, {
    label: "heat-view",
    blend: "premultiplied",
    set: { view: { time: 0, dark: 0, pad0: 0, pad1: 0 }, heatTex: field.read, heatSampler: linear },
  });
  await Promise.all([sim.compile(field.write), view.compile(surf)]);

  return {
    active: true,
    setDark(next) {
      dark = next ? 1 : 0;
    },
    setPointer(point) {
      if (!point) {
        strength = 0;
        return;
      }
      const w = Math.max(1, canvas.clientWidth);
      const h = Math.max(1, canvas.clientHeight);
      pointer = [(point[0] / w) * simW, (point[1] / h) * simH];
      strength = 0.38;
    },
    encode(f, time) {
      sim.set({ heat: { pointer, strength, time: time % 4000 }, prev: field.read });
      f.pass({ target: field.write, clear: [0, 0, 0, 1] }, (pass) => pass.draw(sim));
      field.swap();
      view.set({ view: { time: time % 4000, dark }, heatTex: field.read });
      f.pass({ target: surf, clear: TRANSPARENT }, (pass) => pass.draw(view));
    },
  };
}
