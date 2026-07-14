import assert from "node:assert/strict";
import test from "node:test";
import { PinchScrollDetector } from "../src/pinch-scroll-detector";
import type { HandControlState } from "../src/types";

function pinchState(y: number, gap = 0, overrides: Partial<HandControlState> = {}): HandControlState {
  const point = (x: number, pointY: number) => ({ x, y: pointY, z: 0, visibility: 1 });
  const landmarks = Array.from({ length: 21 }, () => point(0.5, 0.6));
  landmarks[0] = point(0.5, 0.84);
  landmarks[5] = point(0.39, 0.64);
  landmarks[9] = point(0.5, 0.6);
  landmarks[13] = point(0.61, 0.64);
  landmarks[17] = point(0.7, 0.68);
  landmarks[4] = point(0.45 - gap / 2, y);
  landmarks[8] = point(0.45 + gap / 2, y);
  return {
    detected: true,
    stale: false,
    handedness: "Right",
    confidence: 0.95,
    palm: { x: 0.5, y: 0.6 },
    steering: { x: 0, y: 0 },
    roll: 0,
    speedScale: 1,
    distanceCalibrating: false,
    gesture: "Pinch",
    gestureConfidence: 1,
    landmarks,
    ...overrides,
  };
}

test("pinch requires a short stable contact before it starts scrolling", () => {
  const detector = new PinchScrollDetector();
  assert.deepEqual(detector.update(pinchState(0.3), 0), { active: false, deltaY: 0, direction: null });
  assert.deepEqual(detector.update(pinchState(0.3), 90), { active: true, deltaY: 0, direction: null });
});

test("pinched vertical dragging emits continuous page direction", () => {
  const detector = new PinchScrollDetector();
  detector.update(pinchState(0.3), 0);
  detector.update(pinchState(0.3), 90);
  const down = detector.update(pinchState(0.35), 120);
  assert.equal(down.active, true);
  assert.equal(down.direction, "down");
  assert.ok(down.deltaY > 0.04 && down.deltaY < 0.06);
  const up = detector.update(pinchState(0.31), 150);
  assert.equal(up.direction, "up");
  assert.ok(up.deltaY < -0.03);
});

test("pinch scrolling stops on release, tracking loss, and implausible jumps", () => {
  const detector = new PinchScrollDetector();
  detector.update(pinchState(0.3), 0);
  detector.update(pinchState(0.3), 90);
  assert.deepEqual(detector.update(pinchState(0.3, 0.25), 120), { active: false, deltaY: 0, direction: null });

  detector.update(pinchState(0.3), 200);
  detector.update(pinchState(0.3), 290);
  assert.deepEqual(detector.update(pinchState(0.7), 320), { active: true, deltaY: 0, direction: null });
  assert.deepEqual(detector.update(pinchState(0.7, 0, { detected: false }), 350), { active: false, deltaY: 0, direction: null });
});

test("a fist does not accidentally become a pinch scroll clutch", () => {
  const detector = new PinchScrollDetector();
  assert.deepEqual(
    detector.update(pinchState(0.3, 0, { gesture: "Closed_Fist" }), 0),
    { active: false, deltaY: 0, direction: null },
  );
});
