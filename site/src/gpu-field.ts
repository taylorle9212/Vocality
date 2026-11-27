// WebGPU dot field built on vgpu: a compute pass integrates every dot in
// place, then an instanced draw expands each one into a round quad on the
// canvas surface. Both passes share one storage buffer, so nothing
// round-trips through the CPU after the initial upload.

import { compute, draw, frame, storage, surface, type Frame, type Gpu } from "vgpu";

import { makeDots, toWorld, type DotField, type FieldConfig, type Layout } from "./field";
import type { Envelope } from "./timeline";
import dotsShader from "./shaders/dots.wgsl";
import simulateShader from "./shaders/simulate.wgsl";

const WORKGROUP = 64;
const TRANSPARENT = [0, 0, 0, 0] as const;

export interface GpuField extends DotField {
  /** Encodes this field's compute + draw into a shared frame. */
  encode(f: Frame, env: Envelope, dt: number, time: number): void;
  readonly active: boolean;
}

export async function createGpuField(gpu: Gpu, canvas: HTMLCanvasElement, cfg: FieldConfig): Promise<GpuField> {
  const surf = surface(gpu, canvas, {
    dpr: [1, 2],
    alphaMode: "premultiplied",
    clearColor: TRANSPARENT,
    label: `${cfg.label}-surface`,
  });

  const cssSize = (): [number, number] => [Math.max(1, canvas.clientWidth), Math.max(1, canvas.clientHeight)];
  let [cssW, cssH] = cssSize();
  let layout: Layout = cfg.layout(cssW, cssH);

  const data = makeDots(cfg.count, layout.aspect, cfg.label.length * 7919);
  const dots = storage(gpu, data.byteLength, "read-write");
  dots.write(data);

  let pointer: [number, number] = [0, 0];
  let pointerActive = 0;
  let scroll = 0;
  let dark = 0;
  let active = true;
  let isStill = false;

  const layoutParams = () => ({
    aspect: layout.aspect,
    lineX: layout.lineX,
    lineY: layout.lineY,
    lineHalfWidth: layout.lineHalfWidth,
    sendTarget: layout.sendTarget,
    pointerRadius: layout.pointerRadius,
    flowScale: layout.flowScale,
    baseVisible: layout.baseVisible,
  });

  const viewParams = () => ({
    resolution: [surf.size[0], surf.size[1]],
    aspect: layout.aspect,
    pixelSize: surf.dpr,
    dark,
    sizeBoost: cfg.sizeBoost,
  });

  const sim = compute(gpu, simulateShader, {
    label: `${cfg.label}-simulate`,
    set: {
      dots,
      params: {
        ...layoutParams(),
        pointer,
        time: 0,
        dt: 0,
        level: 0,
        refine: 0,
        send: 0,
        pointerActive: 0,
        count: cfg.count,
        scroll: 0,
        pad2: 0,
      },
    },
  });

  const dotDraw = draw(gpu, {
    shader: dotsShader,
    vertices: 6,
    instances: cfg.count,
    blend: "premultiplied",
    label: `${cfg.label}-dots`,
    set: { dots, view: { ...viewParams(), pad0: 0, pad1: 0 } },
  });

  await Promise.all([sim.compile(), dotDraw.compile(surf)]);

  const relayout = () => {
    [cssW, cssH] = cssSize();
    layout = cfg.layout(cssW, cssH);
    sim.set({ params: layoutParams() });
    dotDraw.set({ view: viewParams() });
  };
  surf.onResize(relayout);
  relayout();

  const setEnvelope = (env: Envelope, dt: number, time: number) => {
    sim.set({
      params: {
        time: time % 2000,
        dt,
        level: env.level,
        refine: env.refine,
        send: env.send,
        pointer,
        pointerActive,
        scroll,
      },
    });
  };

  const groups = Math.ceil(cfg.count / WORKGROUP);
  const encodeDraw = (f: Frame) => f.pass({ target: surf, clear: TRANSPARENT }, (pass) => pass.draw(dotDraw));

  const field: GpuField = {
    get active() {
      return active;
    },
    setActive(next) {
      active = next;
    },
    setScroll(velocity) {
      scroll = velocity;
    },
    setPointer(point) {
      if (!point) {
        pointerActive = 0;
        return;
      }
      pointer = toWorld(point[0], point[1], cssW, cssH);
      pointerActive = 1;
    },
    setDark(next) {
      dark = next ? 1 : 0;
      dotDraw.set({ view: { dark } });
      if (isStill) frame(gpu, encodeDraw);
    },
    encode(f, env, dt, time) {
      setEnvelope(env, dt, time);
      f.computePass((pass) => pass.dispatch(sim, groups));
      encodeDraw(f);
    },
    tick(env, dt, time) {
      frame(gpu, (f) => field.encode(f, env, dt, time));
    },
    still(env) {
      isStill = true;
      // Integrate a couple of seconds up front, then present a single frame.
      setEnvelope(env, 1 / 30, 3);
      frame(gpu, (f) => {
        for (let k = 0; k < 90; k++) f.computePass((pass) => pass.dispatch(sim, groups));
        encodeDraw(f);
      });
      new ResizeObserver(() => frame(gpu, encodeDraw)).observe(canvas);
    },
  };
  return field;
}
