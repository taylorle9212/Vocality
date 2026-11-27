// A looping, simulated dictation: a speech-like volume envelope while
// listening, then refine (dots condense into a line), send (dots stream into
// the send point) and a short rest before the next take.

export type Phase = "listening" | "refining" | "sending" | "sent";

export interface Envelope {
  /** Voice level, 0..1. */
  level: number;
  /** 0..1, how strongly dots are pulled onto the line. */
  refine: number;
  /** 0..1, progress of the stream into the send point. */
  send: number;
  phase: Phase;
  /** 0..1 progress through the current phase. */
  progress: number;
}

export interface TimelineOptions {
  listen: number;
  refine: number;
  send: number;
  rest: number;
  seed?: number;
}

const smooth = (a: number, b: number, x: number) => {
  const t = Math.min(1, Math.max(0, (x - a) / (b - a)));
  return t * t * (3 - 2 * t);
};

export function createTimeline(opts: TimelineOptions) {
  const seed = opts.seed ?? 0;
  const total = opts.listen + opts.refine + opts.send + opts.rest;

  /** Speech-like envelope: words separated by short pauses, syllables inside words. */
  const voice = (t: number) => {
    const s = t + seed * 7.3;
    const word = smooth(-0.15, 0.45, Math.sin(s * 1.35) + 0.45 * Math.sin(s * 3.1 + 1.2) + 0.2);
    const syllable = 0.5 + 0.5 * Math.sin(s * 11.0 + Math.sin(s * 4.3) * 1.6);
    const accent = 0.75 + 0.25 * Math.sin(s * 0.7 + 2.0);
    return Math.min(1, 0.06 + 0.94 * word * accent * (0.3 + 0.7 * Math.pow(syllable, 1.4)));
  };

  return {
    total,
    sample(time: number): Envelope {
      const t = ((time % total) + total) % total;
      if (t < opts.listen) {
        const fade = smooth(0, 0.5, t) * (1 - smooth(opts.listen - 0.5, opts.listen, t));
        return { level: voice(t) * fade, refine: 0, send: 0, phase: "listening", progress: t / opts.listen };
      }
      const r = t - opts.listen;
      if (r < opts.refine) {
        return {
          level: 0.18 * Math.exp(-r * 3),
          refine: smooth(0, Math.min(0.7, opts.refine * 0.6), r),
          send: 0,
          phase: "refining",
          progress: r / opts.refine,
        };
      }
      const s = r - opts.refine;
      if (s < opts.send) {
        const p = s / opts.send;
        return { level: 0, refine: 1, send: p, phase: "sending", progress: p };
      }
      const rest = s - opts.send;
      return { level: 0, refine: 1, send: 1, phase: "sent", progress: rest / opts.rest };
    },
  };
}

export type Timeline = ReturnType<typeof createTimeline>;
