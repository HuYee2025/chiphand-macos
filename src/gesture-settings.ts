export type GestureSettings = {
  /** 0 = deliberate long motion, 100 = shortest intentional motion. */
  swipeSensitivity: number;
  /** 0 = fingertips must touch very tightly, 100 = allows a small gap. */
  pinchSensitivity: number;
};

export const DEFAULT_GESTURE_SETTINGS: GestureSettings = {
  swipeSensitivity: 50,
  pinchSensitivity: 50,
};

function clamp(value: number, minimum: number, maximum: number): number {
  return Math.max(minimum, Math.min(maximum, value));
}

function asSensitivity(value: unknown, fallback: number): number {
  return typeof value === "number" && Number.isFinite(value) ? Math.round(clamp(value, 0, 100)) : fallback;
}

export function normalizeGestureSettings(value: Partial<GestureSettings> | undefined | null): GestureSettings {
  return {
    swipeSensitivity: asSensitivity(value?.swipeSensitivity, DEFAULT_GESTURE_SETTINGS.swipeSensitivity),
    pinchSensitivity: asSensitivity(value?.pinchSensitivity, DEFAULT_GESTURE_SETTINGS.pinchSensitivity),
  };
}

/** Higher sensitivity lowers the distance a palm must travel to count as a swipe. */
export function swipeMinimumDisplacement(settings: GestureSettings): number {
  return 0.22 - normalizeGestureSettings(settings).swipeSensitivity * 0.0012;
}

/** Higher sensitivity permits a slightly wider thumb-index gap. */
export function pinchContactThreshold(settings: GestureSettings): number {
  return 0.12 + normalizeGestureSettings(settings).pinchSensitivity * 0.0012;
}

export function pinchReleaseThreshold(settings: GestureSettings): number {
  return Math.min(0.28, pinchContactThreshold(settings) + 0.02);
}

export function sensitivityLabel(value: number): string {
  if (value <= 30) return "偏稳";
  if (value >= 70) return "偏灵敏";
  return "标准";
}
