// Entry: starts VGPU, creates the hero and island dot fields (with a 2D
// canvas fallback when WebGPU is unavailable), and drives the demo from one
// looping, simulated dictation.

import "./styles.css";
import { clock, frameLoop, init } from "vgpu";

import { createCpuField } from "./cpu-field";
import type { DotField, FieldConfig, Layout } from "./field";
import { createGpuField, type GpuField } from "./gpu-field";
import { createTimeline, type Envelope } from "./timeline";

const heroConfig: FieldConfig = {
  label: "hero",
  count: 6000,
  sizeBoost: 1,
  layout: (w, h): Layout => {
    const aspect = w / Math.max(1, h);
    return {
      aspect,
      lineX: 0,
      lineY: -0.25,
      lineHalfWidth: aspect * 0.72,
      sendTarget: [aspect * 0.82, -0.25],
      pointerRadius: 0.28,
      flowScale: 1.4,
      baseVisible: 0.08,
    };
  },
};

const islandConfig: FieldConfig = {
  label: "island",
  count: 900,
  sizeBoost: 0.85,
  layout: (w, h): Layout => {
    const aspect = w / Math.max(1, h);
    return {
      aspect,
      lineX: 0,
      lineY: 0,
      lineHalfWidth: aspect * 0.92,
      sendTarget: [-aspect - 0.35, 0], // the send button sits to the left
      pointerRadius: 0,
      flowScale: 2.6,
      baseVisible: 0.05,
    };
  },
};

const $ = <T extends HTMLElement>(id: string) => document.getElementById(id) as T | null;
const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
const darkQuery = window.matchMedia("(prefers-color-scheme: dark)");

const heroCanvas = $<HTMLCanvasElement>("hero-field");
const islandCanvas = $<HTMLCanvasElement>("island-field");
const island = $("island");
const status = $("island-status");
const typed = $("typed");
const returnKey = $("return-key");
const ringProgress = $<SVGCircleElement & HTMLElement>("ring-progress");
const rendererNote = $("renderer-note");

const timeline = createTimeline({ listen: 5.5, refine: 1.6, send: 1.0, rest: 1.8, seed: 1 });
const heroTimeline = createTimeline({ listen: 6.5, refine: 1.8, send: 1.2, rest: 1.5, seed: 2 });
const PROMPT = "Add a dark mode toggle to the settings page, then run the tests.";
const RING = 106.8;

/** Updates the island's DOM parts (ring, status, typed prompt) for a timeline sample. */
function updateDemo(env: Envelope) {
  if (island) island.dataset.phase = env.phase;
  if (ringProgress) {
    const p = env.phase === "listening" ? env.progress : 1;
    ringProgress.style.strokeDashoffset = String(RING * (1 - p));
  }
  if (status) {
    const text = { listening: "Listening", refining: "Transcribing", sending: "Sending", sent: "Sent to Claude Code" }[env.phase];
    if (status.textContent !== text) status.textContent = text;
  }
  if (typed) {
    const shown =
      env.phase === "listening" ? 0 : env.phase === "refining" ? Math.round(PROMPT.length * Math.min(1, env.progress * 1.3)) : PROMPT.length;
    const text = PROMPT.slice(0, shown);
    if (typed.textContent !== text) typed.textContent = text;
  }
  returnKey?.classList.toggle("on", env.phase === "sent");
}

/** Pauses fields that are scrolled out of view. */
function watchVisibility(canvas: HTMLCanvasElement, field: DotField) {
  new IntersectionObserver(([entry]) => field.setActive(Boolean(entry?.isIntersecting)), { threshold: 0 }).observe(canvas);
}

function watchPointer(canvas: HTMLCanvasElement, field: DotField) {
  window.addEventListener(
    "pointermove",
    (e) => {
      const r = canvas.getBoundingClientRect();
      const inside = e.clientX >= r.left && e.clientX <= r.right && e.clientY >= r.top && e.clientY <= r.bottom;
      field.setPointer(inside ? [e.clientX - r.left, e.clientY - r.top] : null);
    },
    { passive: true },
  );
  window.addEventListener("pointerleave", () => field.setPointer(null));
}

async function createFields(): Promise<{ hero?: DotField; island?: DotField; gpu: boolean; start: (loop: (dt: number, t: number) => void) => void }> {
  if ("gpu" in navigator) {
    try {
      const gpu = await init();
      const hero = heroCanvas ? await createGpuField(gpu, heroCanvas, heroConfig) : undefined;
      const isl = islandCanvas ? await createGpuField(gpu, islandCanvas, islandConfig) : undefined;
      const time = clock(gpu);
      return {
        hero,
        island: isl,
        gpu: true,
        start(loop) {
          frameLoop(gpu, (f) => {
            const t = time.time;
            const dt = Math.min(1 / 20, time.deltaTime || 1 / 60);
            const heroEnv = heroTimeline.sample(t);
            const env = timeline.sample(t);
            updateDemo(env);
            const fields: [GpuField | undefined, Envelope][] = [
              [hero, heroEnv],
              [isl, env],
            ];
            for (const [field, e] of fields) if (field?.active) field.encode(f, e, dt, t);
            loop(dt, t);
          });
        },
      };
    } catch (error) {
      console.warn("WebGPU unavailable, using the 2D canvas field.", error);
    }
  }
  const hero = heroCanvas ? createCpuField(heroCanvas, heroConfig) : undefined;
  const isl = islandCanvas ? createCpuField(islandCanvas, islandConfig) : undefined;
  return {
    hero,
    island: isl,
    gpu: false,
    start(loop) {
      let last = performance.now();
      const step = (now: number) => {
        const dt = Math.min(1 / 20, (now - last) / 1000);
        last = now;
        const t = now / 1000;
        const env = timeline.sample(t);
        updateDemo(env);
        hero?.tick(heroTimeline.sample(t), dt, t);
        isl?.tick(env, dt, t);
        loop(dt, t);
        requestAnimationFrame(step);
      };
      requestAnimationFrame(step);
    },
  };
}

async function main() {
  const { hero, island: islandField, gpu, start } = await createFields();
  if (rendererNote) {
    rendererNote.textContent = gpu
      ? "Animations render with WebGPU via vgpu."
      : "Your browser doesn't support WebGPU, so the animations use a 2D canvas.";
  }

  const applyDark = () => {
    hero?.setDark(darkQuery.matches);
    islandField?.setDark(darkQuery.matches);
  };
  applyDark();
  darkQuery.addEventListener("change", applyDark);

  if (heroCanvas && hero) {
    watchVisibility(heroCanvas, hero);
    watchPointer(heroCanvas, hero);
  }
  if (islandCanvas && islandField) watchVisibility(islandCanvas, islandField);

  if (reducedMotion.matches) {
    // One settled frame of each field, no animation loop.
    const listening = { level: 0.55, refine: 0, send: 0, phase: "listening" as const, progress: 0.4 };
    hero?.still(listening);
    islandField?.still(listening);
    updateDemo({ ...listening, phase: "sent", progress: 1 });
    return;
  }
  start(() => {});
}

void main();
