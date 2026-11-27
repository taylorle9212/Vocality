// Shared description of a dot field: its layout in world units and the
// initial per-dot data. World space is x in [-aspect, aspect], y in [-1, 1]
// (y up), so it maps straight to clip space once x is divided by aspect.

import type { Envelope } from "./timeline";

export const FLOATS_PER_DOT = 12; // pos.xy, vel.xy, seed.xyzw, state.xyzw

export interface Layout {
  aspect: number;
  lineX: number;
  lineY: number;
  lineHalfWidth: number;
  sendTarget: [number, number];
  pointerRadius: number;
  flowScale: number;
  /** Fraction of dots visible when the voice is silent. */
  baseVisible: number;
}

export interface FieldConfig {
  label: string;
  count: number;
  /** Multiplies the per-dot radius (CSS px). */
  sizeBoost: number;
  /** Computes the layout from the canvas's CSS size. */
  layout: (width: number, height: number) => Layout;
}

export interface DotField {
  /** Pointer in CSS px relative to the canvas, or null when outside. */
  setPointer(point: [number, number] | null): void;
  setDark(dark: boolean): void;
  /** Advances and draws one frame. */
  tick(env: Envelope, dt: number, time: number): void;
  /** Settles the field into a still frame (reduced motion). */
  still(env: Envelope): void;
  setActive(active: boolean): void;
}

export function makeDots(count: number, aspect: number, seed = 1): Float32Array<ArrayBuffer> {
  let s = seed >>> 0 || 1;
  const rand = () => {
    s ^= s << 13;
    s ^= s >>> 17;
    s ^= s << 5;
    return (s >>> 0) / 4294967296;
  };
  const data = new Float32Array(count * FLOATS_PER_DOT);
  for (let i = 0; i < count; i++) {
    const o = i * FLOATS_PER_DOT;
    data[o + 0] = (rand() * 2 - 1) * aspect;
    data[o + 1] = rand() * 2 - 1;
    data[o + 4] = rand(); // line slot
    data[o + 5] = rand(); // appearance threshold
    data[o + 6] = Math.pow(rand(), 0.85); // palette position
    data[o + 7] = 0.55 + Math.pow(rand(), 2.2) * 1.0; // radius, CSS px
  }
  return data;
}

/** CSS px relative to an element → world units for a field of that size. */
export function toWorld(x: number, y: number, width: number, height: number): [number, number] {
  const aspect = width / Math.max(1, height);
  return [(x / Math.max(1, width)) * 2 * aspect - aspect, 1 - (y / Math.max(1, height)) * 2];
}
