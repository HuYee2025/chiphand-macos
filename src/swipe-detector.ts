import type { GestureAction, HandControlState, Point2D, SwipeDirection } from "./types";

type SwipeSample = Point2D & {
  time: number;
};

export type SwipeDetectorOptions = {
  historyMilliseconds?: number;
  minimumDurationMilliseconds?: number;
  maximumDurationMilliseconds?: number;
  minimumDisplacement?: number;
  dominantAxisRatio?: number;
  cooldownMilliseconds?: number;
  stableMilliseconds?: number;
  stableStepDistance?: number;
  minimumConfidence?: number;
  allowedDirections?: readonly SwipeDirection[];
};

const DEFAULTS = {
  historyMilliseconds: 360,
  minimumDurationMilliseconds: 100,
  maximumDurationMilliseconds: 450,
  minimumDisplacement: 0.16,
  dominantAxisRatio: 1.4,
  cooldownMilliseconds: 650,
  stableMilliseconds: 180,
  stableStepDistance: 0.018,
  minimumConfidence: 0.65,
} as const;

export function swipeDirectionToAction(direction: SwipeDirection): GestureAction {
  if (direction === "up") return "scroll-up";
  if (direction === "down") return "scroll-down";
  if (direction === "left") return "scroll-up";
  return "scroll-down";
}

export class SwipeDetector {
  private readonly historyMilliseconds: number;
  private readonly minimumDurationMilliseconds: number;
  private readonly maximumDurationMilliseconds: number;
  private readonly minimumDisplacement: number;
  private readonly dominantAxisRatio: number;
  private readonly cooldownMilliseconds: number;
  private readonly stableMilliseconds: number;
  private readonly stableStepDistance: number;
  private readonly minimumConfidence: number;
  private readonly allowedDirections: readonly SwipeDirection[];
  private samples: SwipeSample[] = [];
  private armed = true;
  private cooldownUntil = 0;
  private stableSince: number | null = null;
  private lastPalm: Point2D | null = null;
  private releaseObserved = false;

  constructor(options: SwipeDetectorOptions = {}) {
    this.historyMilliseconds = options.historyMilliseconds ?? DEFAULTS.historyMilliseconds;
    this.minimumDurationMilliseconds =
      options.minimumDurationMilliseconds ?? DEFAULTS.minimumDurationMilliseconds;
    this.maximumDurationMilliseconds =
      options.maximumDurationMilliseconds ?? DEFAULTS.maximumDurationMilliseconds;
    this.minimumDisplacement = options.minimumDisplacement ?? DEFAULTS.minimumDisplacement;
    this.dominantAxisRatio = options.dominantAxisRatio ?? DEFAULTS.dominantAxisRatio;
    this.cooldownMilliseconds = options.cooldownMilliseconds ?? DEFAULTS.cooldownMilliseconds;
    this.stableMilliseconds = options.stableMilliseconds ?? DEFAULTS.stableMilliseconds;
    this.stableStepDistance = options.stableStepDistance ?? DEFAULTS.stableStepDistance;
    this.minimumConfidence = options.minimumConfidence ?? DEFAULTS.minimumConfidence;
    this.allowedDirections = options.allowedDirections ?? ["up", "down", "left", "right"];
  }

  update(state: HandControlState, now: number): SwipeDirection | null {
    if (!this.isUsable(state)) {
      this.samples = [];
      this.stableSince = null;
      this.lastPalm = null;
      if (!this.armed) this.releaseObserved = true;
      if (this.releaseObserved && now >= this.cooldownUntil) this.rearm();
      return null;
    }

    const palm = { x: 1 - state.palm.x, y: state.palm.y };
    if (!this.armed) {
      this.updateRearming(palm, now);
      return null;
    }

    this.samples.push({ ...palm, time: now });
    const oldestAllowed = now - this.historyMilliseconds;
    this.samples = this.samples.filter((sample) => sample.time >= oldestAllowed);
    const first = this.samples[0];
    if (!first) return null;

    const duration = now - first.time;
    if (duration < this.minimumDurationMilliseconds || duration > this.maximumDurationMilliseconds) return null;

    const deltaX = palm.x - first.x;
    const deltaY = palm.y - first.y;
    const absoluteX = Math.abs(deltaX);
    const absoluteY = Math.abs(deltaY);
    let direction: SwipeDirection | null = null;

    if (absoluteX >= this.minimumDisplacement && absoluteX >= absoluteY * this.dominantAxisRatio) {
      direction = deltaX < 0 ? "left" : "right";
    } else if (absoluteY >= this.minimumDisplacement && absoluteY >= absoluteX * this.dominantAxisRatio) {
      direction = deltaY < 0 ? "up" : "down";
    }

    if (!direction || !this.allowedDirections.includes(direction)) return null;
    this.armed = false;
    this.cooldownUntil = now + this.cooldownMilliseconds;
    this.samples = [];
    this.stableSince = null;
    this.lastPalm = palm;
    this.releaseObserved = false;
    return direction;
  }

  reset(): void {
    this.samples = [];
    this.armed = true;
    this.cooldownUntil = 0;
    this.stableSince = null;
    this.lastPalm = null;
    this.releaseObserved = false;
  }

  private isUsable(state: HandControlState): boolean {
    return (
      state.detected &&
      !state.stale &&
      state.gesture === "Open_Palm" &&
      state.confidence >= this.minimumConfidence &&
      state.gestureConfidence >= this.minimumConfidence
    );
  }

  private updateRearming(palm: Point2D, now: number): void {
    if (this.releaseObserved && now >= this.cooldownUntil) {
      this.rearm(palm, now);
      return;
    }

    const movement = this.lastPalm ? Math.hypot(palm.x - this.lastPalm.x, palm.y - this.lastPalm.y) : 0;
    if (!this.lastPalm || movement > this.stableStepDistance) {
      this.stableSince = now;
    } else if (this.stableSince === null) {
      this.stableSince = now;
    }
    this.lastPalm = palm;

    if (
      this.stableSince !== null &&
      now - this.stableSince >= this.stableMilliseconds &&
      now >= this.cooldownUntil
    ) {
      this.rearm(palm, now);
    }
  }

  private rearm(palm?: Point2D, now?: number): void {
    this.armed = true;
    this.cooldownUntil = 0;
    this.stableSince = null;
    this.lastPalm = null;
    this.releaseObserved = false;
    this.samples = palm && now !== undefined ? [{ ...palm, time: now }] : [];
  }
}
