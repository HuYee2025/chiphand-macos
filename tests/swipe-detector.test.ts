import assert from "node:assert/strict";
import test from "node:test";
import { SwipeDetector, swipeDirectionToAction } from "../src/swipe-detector";
import type { HandControlState, Point2D, SwipeDirection } from "../src/types";

function handState(displayPalm: Point2D, overrides: Partial<HandControlState> = {}): HandControlState {
  return {
    detected: true,
    stale: false,
    handedness: "Right",
    confidence: 0.95,
    palm: { x: 1 - displayPalm.x, y: displayPalm.y },
    steering: { x: 0, y: 0 },
    roll: 0,
    speedScale: 1,
    distanceCalibrating: false,
    gesture: "Open_Palm",
    gestureConfidence: 1,
    landmarks: [],
    ...overrides,
  };
}

function feed(
  detector: SwipeDetector,
  points: readonly Point2D[],
  startTime = 0,
  interval = 60,
): SwipeDirection[] {
  return points
    .map((point, index) => detector.update(handState(point), startTime + index * interval))
    .filter((direction): direction is SwipeDirection => direction !== null);
}

const trajectories: Record<SwipeDirection, Point2D[]> = {
  up: [
    { x: 0.5, y: 0.7 },
    { x: 0.5, y: 0.61 },
    { x: 0.5, y: 0.52 },
  ],
  down: [
    { x: 0.5, y: 0.3 },
    { x: 0.5, y: 0.39 },
    { x: 0.5, y: 0.48 },
  ],
  left: [
    { x: 0.7, y: 0.5 },
    { x: 0.61, y: 0.5 },
    { x: 0.52, y: 0.5 },
  ],
  right: [
    { x: 0.3, y: 0.5 },
    { x: 0.39, y: 0.5 },
    { x: 0.48, y: 0.5 },
  ],
};

test("SwipeDetector recognizes all four mirrored camera directions", () => {
  for (const direction of ["up", "down", "left", "right"] as const) {
    const detector = new SwipeDetector();
    assert.deepEqual(feed(detector, trajectories[direction]), [direction]);
  }
});

test("SwipeDetector emits only once during cooldown", () => {
  const detector = new SwipeDetector();
  const first = feed(detector, trajectories.right);
  const repeated = feed(detector, trajectories.right, 180);
  assert.deepEqual(first, ["right"]);
  assert.deepEqual(repeated, []);
});

test("SwipeDetector rearms after release and cooldown", () => {
  const detector = new SwipeDetector();
  assert.deepEqual(feed(detector, trajectories.left), ["left"]);
  detector.update(handState({ x: 0.5, y: 0.5 }, { detected: false }), 300);
  detector.update(handState({ x: 0.5, y: 0.5 }, { detected: false }), 800);
  assert.deepEqual(feed(detector, trajectories.left, 900), ["left"]);
});

test("SwipeDetector rearms after the palm becomes stable", () => {
  const detector = new SwipeDetector();
  assert.deepEqual(feed(detector, trajectories.right), ["right"]);
  detector.update(handState({ x: 0.5, y: 0.7 }), 200);
  detector.update(handState({ x: 0.5, y: 0.7 }), 400);
  detector.update(handState({ x: 0.5, y: 0.7 }), 800);
  assert.deepEqual(
    feed(
      detector,
      [
        { x: 0.5, y: 0.61 },
        { x: 0.5, y: 0.52 },
      ],
      860,
    ),
    ["up"],
  );
});

test("SwipeDetector recognizes ten intentional swipes per direction without duplicates", () => {
  for (const direction of ["up", "down", "left", "right"] as const) {
    const detector = new SwipeDetector();
    const recognized: SwipeDirection[] = [];
    for (let attempt = 0; attempt < 10; attempt += 1) {
      const start = attempt * 1000;
      recognized.push(...feed(detector, trajectories[direction], start));
      detector.update(handState({ x: 0.5, y: 0.5 }, { detected: false }), start + 300);
      detector.update(handState({ x: 0.5, y: 0.5 }, { detected: false }), start + 800);
    }
    assert.equal(recognized.length, 10);
    assert.ok(recognized.every((result) => result === direction));
  }
});

test("SwipeDetector can reserve vertical movement for another control mode", () => {
  const detector = new SwipeDetector({ allowedDirections: ["left", "right"] });
  assert.deepEqual(feed(detector, trajectories.up), []);
  assert.deepEqual(feed(detector, trajectories.left, 1_000), ["left"]);
});

test("SwipeDetector ignores two minutes of stationary jitter and diagonal movement", () => {
  const detector = new SwipeDetector();
  const jitter = Array.from({ length: Math.ceil(120_000 / 33) }, (_, index) => ({
    x: 0.5 + Math.sin(index) * 0.012,
    y: 0.5 + Math.cos(index) * 0.012,
  }));
  assert.deepEqual(feed(detector, jitter, 0, 33), []);
  detector.reset();
  assert.deepEqual(
    feed(detector, [
      { x: 0.3, y: 0.3 },
      { x: 0.4, y: 0.4 },
      { x: 0.5, y: 0.5 },
    ]),
    [],
  );
});

test("SwipeDetector ignores fist, stale frames, and low confidence", () => {
  const invalidStates: Partial<HandControlState>[] = [
    { gesture: "Closed_Fist" },
    { stale: true },
    { confidence: 0.5 },
    { gestureConfidence: 0.5 },
  ];
  for (const overrides of invalidStates) {
    const detector = new SwipeDetector();
    const results = trajectories.up
      .map((point, index) => detector.update(handState(point, overrides), index * 60))
      .filter(Boolean);
    assert.deepEqual(results, []);
  }
});

test("swipe directions map to the expected browser actions", () => {
  assert.equal(swipeDirectionToAction("up"), "scroll-up");
  assert.equal(swipeDirectionToAction("down"), "scroll-down");
  assert.equal(swipeDirectionToAction("left"), "scroll-up");
  assert.equal(swipeDirectionToAction("right"), "scroll-down");
});
