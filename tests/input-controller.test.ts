import assert from "node:assert/strict";
import test from "node:test";
import {
  GestureDebouncer,
  InputController,
  SteeringSmoother,
  advanceContinuousRoll,
  applyDeadzone,
  mapPalmToSteering,
  palmCenter,
  palmRoll,
} from "../src/input-controller";
import type { HandControlState } from "../src/types";

test("applyDeadzone removes center jitter and rescales the remaining range", () => {
  assert.equal(applyDeadzone(0.08, 0.1), 0);
  assert.equal(applyDeadzone(-0.1, 0.1), 0);
  assert.equal(applyDeadzone(1, 0.1), 1);
  assert.equal(applyDeadzone(-1, 0.1), -1);
  assert.ok(Math.abs(applyDeadzone(0.55, 0.1) - 0.5) < 1e-9);
});

test("mapPalmToSteering mirrors horizontal camera coordinates and keeps vertical direction natural", () => {
  assert.deepEqual(mapPalmToSteering({ x: 0.5, y: 0.5 }), { x: 0, y: 0 });
  assert.deepEqual(mapPalmToSteering({ x: 1, y: 0 }), { x: -1, y: 1 });
  assert.deepEqual(mapPalmToSteering({ x: 0, y: 1 }), { x: 1, y: -1 });
});

test("palmCenter averages wrist and MCP landmarks", () => {
  const landmarks = Array.from({ length: 21 }, () => ({ x: 0, y: 0 }));
  for (const index of [0, 5, 9, 13, 17]) landmarks[index] = { x: index / 20, y: index / 40 };
  const center = palmCenter(landmarks);
  assert.ok(Math.abs(center.x - 0.44) < 1e-9);
  assert.ok(Math.abs(center.y - 0.22) < 1e-9);
});

test("palmRoll maps mirrored wrist rotation to a normalized tunnel roll", () => {
  const neutral = Array.from({ length: 21 }, () => ({ x: 0.5, y: 0.5 }));
  neutral[0] = { x: 0.5, y: 0.8 };
  neutral[9] = { x: 0.5, y: 0.4 };
  assert.equal(palmRoll(neutral), 0);

  const tilted = neutral.map((point) => ({ ...point }));
  tilted[9] = { x: 0.2, y: 0.5 };
  assert.ok(palmRoll(tilted) > 0.8);
});

test("advanceContinuousRoll keeps rotating while palm tilt is held and stops at neutral", () => {
  const first = advanceContinuousRoll(0, 1, 0.5, 2);
  const second = advanceContinuousRoll(first, 1, 0.5, 2);
  const stopped = advanceContinuousRoll(second, 0, 1, 2);
  assert.ok(Math.abs(first - 1) < 1e-9);
  assert.ok(Math.abs(second - 2) < 1e-9);
  assert.ok(Math.abs(stopped - second) < 1e-9);
});

test("SteeringSmoother approaches target without jumping", () => {
  const smoother = new SteeringSmoother();
  const first = smoother.update({ x: 1, y: -1 }, 1 / 60);
  assert.ok(first.x > 0 && first.x < 1);
  assert.ok(first.y < 0 && first.y > -1);
  let current = first;
  for (let index = 0; index < 120; index += 1) current = smoother.update({ x: 1, y: -1 }, 1 / 60);
  assert.ok(current.x > 0.99);
  assert.ok(current.y < -0.99);
});

test("GestureDebouncer requires a stable confident gesture and emits once", () => {
  const debouncer = new GestureDebouncer(250, 0.65);
  assert.equal(debouncer.update("Closed_Fist", 0.9, 0), null);
  assert.equal(debouncer.update("Closed_Fist", 0.9, 249), null);
  assert.equal(debouncer.update("Closed_Fist", 0.9, 250), "Closed_Fist");
  assert.equal(debouncer.update("Closed_Fist", 0.9, 700), null);
  assert.equal(debouncer.update("Open_Palm", 0.5, 800), null);
  assert.equal(debouncer.update("Open_Palm", 0.9, 900), null);
  assert.equal(debouncer.update("Open_Palm", 0.9, 1150), "Open_Palm");
});

test("InputController gives detected hand priority over pointer fallback", () => {
  const controller = new InputController();
  controller.setPointer(100, 50, 100, 100);
  const pointer = controller.update(1);
  assert.ok(pointer.steering.x > 0.9);

  const handState: HandControlState = {
    detected: true,
    stale: false,
    handedness: "Right",
    confidence: 1,
    palm: { x: 1, y: 0.5 },
    steering: { x: -1, y: 0 },
    roll: 0.75,
    speedScale: 1.8,
    distanceCalibrating: false,
    gesture: "Open_Palm",
    gestureConfidence: 1,
    landmarks: [],
  };
  controller.setHandState(handState);
  const hand = controller.update(1);
  assert.ok(hand.steering.x < -0.9);
  assert.ok(hand.roll > 0.7);
  assert.ok(hand.speedScale > 1.7);
});
