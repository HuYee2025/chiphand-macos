import test from "node:test";
import assert from "node:assert/strict";
import {
  INITIAL_HAND_STABILITY,
  selectNativeHandIndex,
  updateHandStability,
} from "../src/native-hand-selection";

test("native recognizer prefers the selected control hand when both hands are visible", () => {
  assert.equal(
    selectNativeHandIndex(
      [
        { handedness: "Left", score: 0.99 },
        { handedness: "Right", score: 0.60 },
      ],
      "Right",
      null,
    ),
    1,
  );
});

test("native hand labels need a short stable window before switching", () => {
  let state = INITIAL_HAND_STABILITY;
  let update = updateHandStability(state, "Right", 0);
  state = update.state;
  assert.equal(update.isStable, false);

  update = updateHandStability(state, "Right", 119);
  state = update.state;
  assert.equal(update.isStable, false);

  update = updateHandStability(state, "Right", 120);
  state = update.state;
  assert.equal(update.isStable, true);
  assert.equal(update.active, "Right");

  update = updateHandStability(state, "Left", 180);
  state = update.state;
  assert.equal(update.isStable, false);
  assert.equal(update.active, "Right");

  update = updateHandStability(state, "Right", 200);
  state = update.state;
  assert.equal(update.isStable, true);
  assert.equal(update.active, "Right");

  update = updateHandStability(state, "Left", 300);
  state = update.state;
  assert.equal(update.isStable, false);
  update = updateHandStability(state, "Left", 420);
  assert.equal(update.isStable, true);
  assert.equal(update.active, "Left");
});

test("native hand stability resets when no hand is observed", () => {
  const update = updateHandStability(
    { active: "Right", candidate: "Left", candidateSince: 100 },
    null,
    150,
  );
  assert.deepEqual(update.state, INITIAL_HAND_STABILITY);
  assert.equal(update.active, null);
  assert.equal(update.isStable, false);
});
