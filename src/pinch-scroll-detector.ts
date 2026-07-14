import { pinchCenter, pinchStrength } from "./hand-gesture-math";
import type { HandControlState, Point2D, SwipeDirection } from "./types";

export type PinchScrollUpdate = {
  active: boolean;
  deltaY: number;
  direction: Extract<SwipeDirection, "up" | "down"> | null;
};

export type PinchScrollDetectorOptions = {
  activationMilliseconds?: number;
  pinchThreshold?: number;
  releaseThreshold?: number;
  minimumConfidence?: number;
  minimumStep?: number;
  maximumStep?: number;
};

const DEFAULTS = {
  activationMilliseconds: 80,
  pinchThreshold: 0.34,
  releaseThreshold: 0.46,
  minimumConfidence: 0.65,
  minimumStep: 0.003,
  maximumStep: 0.12,
} as const;

const IDLE_UPDATE: PinchScrollUpdate = { active: false, deltaY: 0, direction: null };
const MAX_NORMALIZED_SCROLL_DELTA = 0.12;
const PINCH_SCROLL_GAIN = 1.8;

/** Maps a camera-space pinch drag to a document scroll delta.
 * Moving the hand upward drags page content upward and therefore reveals
 * the content below, matching trackpad and touchscreen scrolling. */
export function pinchDeltaToScrollPixels(deltaY: number, viewportHeight: number): number {
  const boundedDelta = Math.max(-MAX_NORMALIZED_SCROLL_DELTA, Math.min(MAX_NORMALIZED_SCROLL_DELTA, deltaY));
  return -boundedDelta * viewportHeight * PINCH_SCROLL_GAIN;
}

/**
 * Treats thumb-index contact as a clutch: while pinched, vertical movement
 * becomes a continuous page-scroll delta. Hysteresis avoids rapid on/off
 * toggling near the contact threshold.
 */
export class PinchScrollDetector {
  private readonly activationMilliseconds: number;
  private readonly pinchThreshold: number;
  private readonly releaseThreshold: number;
  private readonly minimumConfidence: number;
  private readonly minimumStep: number;
  private readonly maximumStep: number;
  private candidateSince: number | null = null;
  private active = false;
  private lastPoint: Point2D | null = null;

  constructor(options: PinchScrollDetectorOptions = {}) {
    this.activationMilliseconds = options.activationMilliseconds ?? DEFAULTS.activationMilliseconds;
    this.pinchThreshold = options.pinchThreshold ?? DEFAULTS.pinchThreshold;
    this.releaseThreshold = options.releaseThreshold ?? DEFAULTS.releaseThreshold;
    this.minimumConfidence = options.minimumConfidence ?? DEFAULTS.minimumConfidence;
    this.minimumStep = options.minimumStep ?? DEFAULTS.minimumStep;
    this.maximumStep = options.maximumStep ?? DEFAULTS.maximumStep;
  }

  update(state: HandControlState, now: number): PinchScrollUpdate {
    const point = pinchCenter(state.landmarks);
    if (!this.isUsable(state, point)) {
      this.reset();
      return IDLE_UPDATE;
    }

    const strength = pinchStrength(state.landmarks);
    if (!this.active) {
      if (strength > this.pinchThreshold) {
        this.candidateSince = null;
        return IDLE_UPDATE;
      }
      this.candidateSince ??= now;
      if (now - this.candidateSince < this.activationMilliseconds) return IDLE_UPDATE;
      this.active = true;
      this.lastPoint = point;
      return { active: true, deltaY: 0, direction: null };
    }

    if (strength >= this.releaseThreshold) {
      this.reset();
      return IDLE_UPDATE;
    }

    const previous = this.lastPoint ?? point;
    this.lastPoint = point;
    const deltaY = point.y - previous.y;
    const absoluteDelta = Math.abs(deltaY);
    if (absoluteDelta < this.minimumStep || absoluteDelta > this.maximumStep) {
      return { active: true, deltaY: 0, direction: null };
    }
    return { active: true, deltaY, direction: deltaY < 0 ? "up" : "down" };
  }

  isActive(): boolean {
    return this.active;
  }

  reset(): void {
    this.candidateSince = null;
    this.active = false;
    this.lastPoint = null;
  }

  private isUsable(state: HandControlState, point: Point2D | null): point is Point2D {
    return (
      state.detected &&
      !state.stale &&
      state.gesture === "Pinch" &&
      state.confidence >= this.minimumConfidence &&
      point !== null
    );
  }
}
