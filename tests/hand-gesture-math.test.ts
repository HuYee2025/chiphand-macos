import assert from "node:assert/strict";
import test from "node:test";
import {
  classifyHandGesture,
  HandDistanceCalibrator,
  handOpenness,
  isClosedFist,
  isPinching,
  pinchCenter,
  pinchStrength,
} from "../src/hand-gesture-math";
import { PalmRotationCalibrator } from "../src/input-controller";

function openHand(): Array<{ x: number; y: number }> {
  const landmarks = Array.from({ length: 21 }, () => ({ x: 0.5, y: 0.6 }));
  landmarks[0] = { x: 0.5, y: 0.82 };
  landmarks[5] = { x: 0.39, y: 0.62 };
  landmarks[9] = { x: 0.5, y: 0.59 };
  landmarks[13] = { x: 0.61, y: 0.62 };
  landmarks[17] = { x: 0.7, y: 0.67 };
  landmarks[8] = { x: 0.35, y: 0.2 };
  landmarks[12] = { x: 0.5, y: 0.14 };
  landmarks[16] = { x: 0.64, y: 0.2 };
  landmarks[20] = { x: 0.75, y: 0.31 };
  landmarks[4] = { x: 0.35, y: 0.74 };
  return landmarks;
}

test("open-hand classification does not depend on an extended thumb", () => {
  const landmarks = openHand();
  assert.ok(handOpenness(landmarks) > 0.38);
  assert.equal(classifyHandGesture(landmarks), "Open_Palm");
  landmarks[4] = { ...landmarks[0] };
  assert.equal(classifyHandGesture(landmarks), "Open_Palm");
});

test("fist and pinch use normalized joint distances", () => {
  const landmarks = openHand();
  assert.ok(pinchStrength(landmarks) > 0.35);
  for (const index of [8, 12, 16, 20]) landmarks[index] = { x: 0.5, y: 0.74 };
  assert.equal(isClosedFist(landmarks), true);
  assert.equal(classifyHandGesture(landmarks), "Closed_Fist");
});

test("thumb-index contact is classified as a pinch with a midpoint", () => {
  const landmarks = openHand();
  landmarks[4] = { x: 0.42, y: 0.28 };
  landmarks[8] = { x: 0.42, y: 0.28 };
  assert.equal(isPinching(landmarks), true);
  assert.equal(classifyHandGesture(landmarks), "Pinch");
  assert.deepEqual(pinchCenter(landmarks), { x: 0.42, y: 0.28 });
});

test("pinch requires near-contact and releases after a small separation", () => {
  const landmarks = openHand();
  landmarks[4] = { x: 0.42, y: 0.28 };
  landmarks[8] = { x: 0.45, y: 0.28 };
  assert.equal(isPinching(landmarks), true);
  landmarks[8] = { x: 0.48, y: 0.28 };
  assert.equal(isPinching(landmarks), false);
  assert.notEqual(classifyHandGesture(landmarks), "Pinch");
});

test("PalmRotationCalibrator treats the first seen orientation as neutral", () => {
  const calibrator = new PalmRotationCalibrator();
  const baseline = openHand();
  assert.equal(calibrator.update(baseline), 0);
  const tilted = baseline.map((point) => ({ ...point }));
  tilted[9] = { x: 0.25, y: 0.62 };
  assert.ok(calibrator.update(tilted) > 0.4);
  calibrator.reset();
  assert.equal(calibrator.update(tilted), 0);
});

test("HandDistanceCalibrator uses apparent palm size for a bounded speed multiplier", () => {
  const calibrator = new HandDistanceCalibrator(600);
  assert.deepEqual(calibrator.update(0.2, 0), { speedScale: 1, calibrating: true });
  assert.deepEqual(calibrator.update(0.2, 500), { speedScale: 1, calibrating: true });
  assert.deepEqual(calibrator.update(0.2, 650), { speedScale: 1, calibrating: false });
  assert.ok(calibrator.update(0.28, 700).speedScale > 1.5);
  assert.equal(calibrator.update(0.7, 750).speedScale, 2.4);
  assert.equal(calibrator.update(0.04, 800).speedScale, 0.45);
  calibrator.reset();
  assert.deepEqual(calibrator.update(0.4, 900), { speedScale: 1, calibrating: true });
});
