import type { ControlGesture, Point2D } from "./types";

const WRIST = 0;
const THUMB_TIP = 4;
const INDEX_TIP = 8;
const NON_THUMB_TIPS = [8, 12, 16, 20];
const MCPs = [5, 9, 13, 17];
// 只把“拇指和食指真正贴合”视为捏合；普通靠近不显示网页控制点。
const PINCH_DISTANCE_THRESHOLD = 0.18;

export function pointDistance(a: Point2D, b: Point2D): number {
  return Math.hypot(a.x - b.x, a.y - b.y);
}

export function handScale(landmarks: ReadonlyArray<Point2D>): number {
  const wrist = landmarks[WRIST];
  if (!wrist) return 1;
  const palmJoints = [5, 9, 13, 17]
    .map((index) => landmarks[index])
    .filter((point): point is Point2D => Boolean(point));
  if (palmJoints.length === 0) return 1;
  return Math.max(
    palmJoints.reduce((total, joint) => total + pointDistance(wrist, joint), 0) / palmJoints.length,
    0.000_001,
  );
}

export class HandDistanceCalibrator {
  private baseline: number | null = null;
  private startedAt: number | null = null;

  constructor(
    private readonly calibrationMilliseconds = 600,
    private readonly minimumSpeed = 0.45,
    private readonly maximumSpeed = 2.4,
  ) {}

  update(apparentScale: number, now: number): { speedScale: number; calibrating: boolean } {
    const sample = Math.max(apparentScale, 0.000_001);
    if (this.baseline === null || this.startedAt === null) {
      this.baseline = sample;
      this.startedAt = now;
      return { speedScale: 1, calibrating: true };
    }
    if (now - this.startedAt < this.calibrationMilliseconds) {
      this.baseline += (sample - this.baseline) * 0.2;
      return { speedScale: 1, calibrating: true };
    }
    // Apparent palm size grows approximately with proximity. A slightly
    // curved response keeps normal hand movement easy to control.
    const speedScale = Math.pow(sample / this.baseline, 1.35);
    return {
      speedScale: Math.max(this.minimumSpeed, Math.min(this.maximumSpeed, speedScale)),
      calibrating: false,
    };
  }

  reset(): void {
    this.baseline = null;
    this.startedAt = null;
  }
}

export function handOpenness(landmarks: ReadonlyArray<Point2D>): number {
  const wrist = landmarks[WRIST];
  if (!wrist) return 0;
  const tips = NON_THUMB_TIPS.map((index) => landmarks[index]).filter((point): point is Point2D => Boolean(point));
  if (tips.length === 0) return 0;
  const averageTipDistance = tips.reduce((sum, tip) => sum + pointDistance(wrist, tip), 0) / tips.length;
  return Math.max(0, Math.min(1, (averageTipDistance / handScale(landmarks) - 0.9) / 1.1));
}

export function isClosedFist(landmarks: ReadonlyArray<Point2D>): boolean {
  const wrist = landmarks[WRIST];
  if (!wrist) return false;
  return NON_THUMB_TIPS.every((tipIndex, index) => {
    const tip = landmarks[tipIndex];
    const mcp = landmarks[MCPs[index]];
    return Boolean(tip && mcp && pointDistance(tip, wrist) <= pointDistance(mcp, wrist));
  });
}

export function pinchStrength(landmarks: ReadonlyArray<Point2D>): number {
  const thumb = landmarks[THUMB_TIP];
  const index = landmarks[INDEX_TIP];
  if (!thumb || !index) return Number.POSITIVE_INFINITY;
  return pointDistance(thumb, index) / handScale(landmarks);
}

export function pinchCenter(landmarks: ReadonlyArray<Point2D>): Point2D | null {
  const thumb = landmarks[THUMB_TIP];
  const index = landmarks[INDEX_TIP];
  if (!thumb || !index) return null;
  return { x: (thumb.x + index.x) / 2, y: (thumb.y + index.y) / 2 };
}

export function isPinching(landmarks: ReadonlyArray<Point2D>, threshold = PINCH_DISTANCE_THRESHOLD): boolean {
  return pinchStrength(landmarks) <= threshold;
}

export function classifyHandGesture(landmarks: ReadonlyArray<Point2D>): ControlGesture {
  if (isClosedFist(landmarks)) return "Closed_Fist";
  if (isPinching(landmarks)) return "Pinch";
  if (handOpenness(landmarks) >= 0.38) return "Open_Palm";
  return "Other";
}
