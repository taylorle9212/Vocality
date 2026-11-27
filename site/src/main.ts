// Entry: starts VGPU, creates the hero and island dot fields (with a 2D
// canvas fallback when WebGPU is unavailable), and drives the demo from one
// looping, simulated dictation.

import "./styles.css";
import { clock, frameLoop, init } from "vgpu";

import { createCpuField } from "./cpu-field";
import { createHeatField, createStoryGlow, type HeatField, type StoryGlow } from "./effects";
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
      baseVisible: 0.6, // most dots stay on screen at all times
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
const glowCanvas = $<HTMLCanvasElement>("story-glow");
const heatCanvas = $<HTMLCanvasElement>("heat-field");

/** How warm the story glow should be for a dictation moment. */
function warmthFor(env: Envelope): number {
  switch (env.phase) {
    case "listening":
      return 0.15 + 0.45 * env.progress + 0.4 * env.level;
    case "refining":
      return 0.85;
    case "sending":
      return 0.7;
    case "sent":
      return 0.25;
  }
}

/** Pauses an effect while its canvas is off screen. */
function watchActive(canvas: HTMLCanvasElement, target: { active: boolean }) {
  new IntersectionObserver(([entry]) => (target.active = Boolean(entry?.isIntersecting)), { threshold: 0 }).observe(canvas);
}

const heroTimeline = createTimeline({ listen: 6.5, refine: 1.8, send: 1.2, rest: 1.5, seed: 2 });
/** The hero never condenses or sends: the simulated voice only modulates the dots' energy. */
function ambient(time: number): Envelope {
  const voice = heroTimeline.sample(time).level;
  return { level: 0.22 + 0.6 * voice, refine: 0, send: 0, phase: "listening", progress: 0 };
}

/** Smoothed page scroll velocity, roughly -3...3. */
let scrollVelocity = 0;
let lastScrollY = window.scrollY;
function updateScroll(dt: number): number {
  const y = window.scrollY;
  const instant = (y - lastScrollY) / Math.max(dt, 1 / 240) / 900;
  lastScrollY = y;
  scrollVelocity += (Math.max(-3, Math.min(3, instant)) - scrollVelocity) * Math.min(1, dt * 10);
  return scrollVelocity;
}

const track = document.querySelector<HTMLElement>(".scrolly-track");
const captions = Array.from(document.querySelectorAll<HTMLElement>(".captions li"));
const root = document.documentElement;
const smoothstep = (a: number, b: number, x: number) => {
  const k = Math.min(1, Math.max(0, (x - a) / (b - a)));
  return k * k * (3 - 2 * k);
};

/** 0...1 progress through the pinned story; also sets the CSS vars that dim the backdrop and scale the window in. */
function storyProgress(): number {
  if (!track) return 0;
  const r = track.getBoundingClientRect();
  const span = Math.max(1, r.height - window.innerHeight);
  const p = Math.min(1, Math.max(0, -r.top / span));
  root.style.setProperty("--enter", String(smoothstep(-0.6, 0, -r.top / window.innerHeight)));
  return p;
}

/** Maps scroll progress to the dictation: listening (louder as you scroll), refining, sending, sent. */
function storyEnvelope(time: number): Envelope {
  const p = storyProgress();
  let env: Envelope;
  if (p < 0.5) {
    const k = p / 0.5;
    const syllables = 0.55 + 0.45 * Math.abs(Math.sin(time * 6.3) * Math.sin(time * 2.1 + 1));
    env = { level: (0.1 + 0.9 * k) * syllables, refine: 0, send: 0, phase: "listening", progress: k };
  } else if (p < 0.72) {
    const k = (p - 0.5) / 0.22;
    env = { level: 0.15 * (1 - k), refine: smoothstep(0, 0.6, k), send: 0, phase: "refining", progress: k };
  } else if (p < 0.86) {
    const k = (p - 0.72) / 0.14;
    env = { level: 0, refine: 1, send: k, phase: "sending", progress: k };
  } else {
    env = { level: 0, refine: 1, send: 1, phase: "sent", progress: (p - 0.86) / 0.14 };
  }
  const step = env.phase === "sending" ? "refining" : env.phase;
  for (const li of captions) li.classList.toggle("on", li.dataset.step === step);
  return env;
}

/** Slides sections in as they enter the viewport. */
function watchReveals() {
  const items = Array.from(document.querySelectorAll<HTMLElement>(".reveal"));
  items.forEach((el) => {
    const siblings = el.parentElement ? Array.from(el.parentElement.children).filter((c) => c.classList.contains("reveal")) : [];
    el.style.setProperty("--i", String(Math.max(0, siblings.indexOf(el))));
  });
  const io = new IntersectionObserver(
    (entries) => {
      for (const e of entries) if (e.isIntersecting) {
        e.target.classList.add("in");
        io.unobserve(e.target);
      }
    },
    { threshold: 0.15, rootMargin: "0px 0px -8% 0px" },
  );
  items.forEach((el) => io.observe(el));
}

const PROMPT = "Add a dark mode toggle to the settings page, then run the tests.";
const RING = 106.8;

/** Updates the island's DOM parts (ring, status, typed prompt) for a story sample. */
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

function watchPointer(canvas: HTMLCanvasElement, field: { setPointer(point: [number, number] | null): void }) {
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

interface Scene {
  hero?: DotField;
  island?: DotField;
  glow?: StoryGlow;
  heat?: HeatField;
  gpu: boolean;
  start: (loop: (dt: number, t: number) => void) => void;
}

async function createFields(): Promise<Scene> {
  if ("gpu" in navigator) {
    try {
      const gpu = await init();
      const hero = heroCanvas ? await createGpuField(gpu, heroCanvas, heroConfig) : undefined;
      const isl = islandCanvas ? await createGpuField(gpu, islandCanvas, islandConfig) : undefined;
      const glow = glowCanvas ? await createStoryGlow(gpu, glowCanvas) : undefined;
      const heat = heatCanvas ? await createHeatField(gpu, heatCanvas) : undefined;
      const time = clock(gpu);
      return {
        hero,
        island: isl,
        glow,
        heat,
        gpu: true,
        start(loop) {
          frameLoop(gpu, (f) => {
            const t = time.time;
            const dt = Math.min(1 / 20, time.deltaTime || 1 / 60);
            const heroEnv = ambient(t);
            hero?.setScroll?.(updateScroll(dt));
            const env = storyEnvelope(t);
            updateDemo(env);
            const fields: [GpuField | undefined, Envelope][] = [
              [hero, heroEnv],
              [isl, env],
            ];
            for (const [field, e] of fields) if (field?.active) field.encode(f, e, dt, t);
            if (glow?.active) glow.encode(f, t, warmthFor(env));
            if (heat?.active) heat.encode(f, t);
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
        const env = storyEnvelope(t);
        updateDemo(env);
        hero?.setScroll?.(updateScroll(dt));
        hero?.tick(ambient(t), dt, t);
        isl?.tick(env, dt, t);
        loop(dt, t);
        requestAnimationFrame(step);
      };
      requestAnimationFrame(step);
    },
  };
}

async function main() {
  watchReveals();
  const { hero, island: islandField, glow, heat, gpu, start } = await createFields();
  if (rendererNote) {
    rendererNote.textContent = gpu
      ? "Animations render with WebGPU via vgpu."
      : "Your browser doesn't support WebGPU, so the animations use a 2D canvas.";
  }

  const applyDark = () => {
    hero?.setDark(darkQuery.matches);
    islandField?.setDark(darkQuery.matches);
    glow?.setDark(darkQuery.matches);
    heat?.setDark(darkQuery.matches);
  };
  applyDark();
  darkQuery.addEventListener("change", applyDark);

  if (heroCanvas && hero) {
    watchVisibility(heroCanvas, hero);
    watchPointer(heroCanvas, hero);
  }
  if (glowCanvas && glow) watchActive(glowCanvas, glow);
  if (heatCanvas && heat) {
    watchActive(heatCanvas, heat);
    watchPointer(heatCanvas, heat);
  }
  if (islandCanvas && islandField) watchVisibility(islandCanvas, islandField);

  if (reducedMotion.matches) {
    // One settled frame of each field, no animation loop.
    const listening = { level: 0.55, refine: 0, send: 0, phase: "listening" as const, progress: 0.4 };
    hero?.still(listening);
    islandField?.still(listening);
    updateDemo({ ...listening, phase: "sent", progress: 1 });
    for (const li of captions) li.classList.add("on");
    return;
  }
  start(() => {});
}

void main();
