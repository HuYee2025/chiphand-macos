import assert from "node:assert/strict";
import test from "node:test";
import {
  DEFAULT_GESTURE_SETTINGS,
  normalizeGestureSettings,
  pinchContactThreshold,
  pinchReleaseThreshold,
  swipeMinimumDisplacement,
} from "../src/gesture-settings";

test("gesture sensitivity defaults preserve the existing interaction thresholds", () => {
  assert.ok(Math.abs(swipeMinimumDisplacement(DEFAULT_GESTURE_SETTINGS) - 0.16) < 1e-9);
  assert.ok(Math.abs(pinchContactThreshold(DEFAULT_GESTURE_SETTINGS) - 0.18) < 1e-9);
  assert.ok(Math.abs(pinchReleaseThreshold(DEFAULT_GESTURE_SETTINGS) - 0.2) < 1e-9);
});

test("higher sensitivity accepts shorter swipes and a slightly wider pinch gap", () => {
  const low = normalizeGestureSettings({ swipeSensitivity: 0, pinchSensitivity: 0 });
  const high = normalizeGestureSettings({ swipeSensitivity: 100, pinchSensitivity: 100 });
  assert.ok(swipeMinimumDisplacement(high) < swipeMinimumDisplacement(low));
  assert.ok(pinchContactThreshold(high) > pinchContactThreshold(low));
  assert.ok(pinchReleaseThreshold(high) > pinchReleaseThreshold(low));
});

test("gesture sensitivity values are clamped before they reach detectors", () => {
  assert.deepEqual(normalizeGestureSettings({ swipeSensitivity: -10, pinchSensitivity: 140 }), {
    swipeSensitivity: 0,
    pinchSensitivity: 100,
  });
});
