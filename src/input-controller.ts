import type { ControlGesture, HandControlState, Point2D } from "./types";

const DEFAULT_DEADZONE = 0.1;

export function applyDeadzone(value: number, deadzone = DEFAULT_DEADZONE): number {
  const magnitude = Math.abs(value);
  if (magnitude <= deadzone) return 0;
  const normalized = (magnitude - deadzone) / (1 - deadzone);
  return Math.sign(value) * Math.min(1, normalized);
}

export function mapPalmToSteering(palm: Point2D, deadzone = DEFAULT_DEADZONE): Point2D {
  const mirroredX = 1 - palm.x;
  const horizontal = (mirroredX - 0.5) * 2;
  const vertical = (0.5 - palm.y) * 2;
  return {
    x: applyDeadzone(horizontal, deadzone),
    y: applyDeadzone(vertical, deadzone),
  };
}

export function palmCenter(landmarks: ReadonlyArray<Point2D>): Point2D {
  const palmIndices = [0, 5, 9, 13, 17];
  const available = palmIndices.map((index) => landmarks[index]).filter((point): point is Point2D => Boolean(point));
  if (available.length === 0) return { x: 0.5, y: 0.5 };
  const total = available.reduce(
    (sum, point) => ({ x: sum.x + point.x, y: sum.y + point.y }),
    { x: 0, y: 0 },
  );
  return { x: total.x / available.length, y: total.y / available.length };
}

export function palmRoll(landmarks: ReadonlyArray<Point2D>, deadzoneDegrees = 6): number {
  const wrist = landmarks[0];
  const middleMcp = landmarks[9];
  if (!wrist || !middleMcp) return 0;
  // Mirror X exactly like the camera preview. The wrist-to-middle-finger axis
  // works for either hand and measures rotation in the screen plane.
  const mirroredDeltaX = wrist.x - middleMcp.x;
  const upwardDeltaY = wrist.y - middleMcp.y;
  const angle = Math.atan2(mirroredDeltaX, upwardDeltaY);
  const normalized = Math.max(-1, Math.min(1, angle / (Math.PI / 4)));
  return applyDeadzone(normalized, deadzoneDegrees / 45);
}

export function wrapAngle(angle: number): number {
  return Math.atan2(Math.sin(angle), Math.cos(angle));
}

export function palmRotationAngle(landmarks: ReadonlyArray<Point2D>): number {
  const wrist = landmarks[0];
  const middleMcp = landmarks[9];
  if (!wrist || !middleMcp) return 0;
  return Math.atan2(wrist.x - middleMcp.x, wrist.y - middleMcp.y);
}

export class PalmRotationCalibrator {
  private baseline: number | null = null;

  update(landmarks: ReadonlyArray<Point2D>, deadzoneDegrees = 6): number {
    const angle = palmRotationAngle(landmarks);
    if (this.baseline === null) this.baseline = angle;
    const normalized = Math.max(-1, Math.min(1, wrapAngle(angle - this.baseline) / (Math.PI / 4)));
    return applyDeadzone(normalized, deadzoneDegrees / 45);
  }

  reset(): void {
    this.baseline = null;
  }
}

export function advanceContinuousRoll(
  currentAngle: number,
  rollInput: number,
  deltaSeconds: number,
  radiansPerSecond = 1.65,
): number {
  const next = currentAngle + Math.max(-1, Math.min(1, rollInput)) * radiansPerSecond * Math.max(0, deltaSeconds);
  return Math.atan2(Math.sin(next), Math.cos(next));
}

export class SteeringSmoother {
  private current: Point2D = { x: 0, y: 0 };

  update(target: Point2D, deltaSeconds: number, response = 9): Point2D {
    const alpha = 1 - Math.exp(-response * Math.max(0, deltaSeconds));
    this.current.x += (target.x - this.current.x) * alpha;
    this.current.y += (target.y - this.current.y) * alpha;
    return { ...this.current };
  }

  reset(): void {
    this.current = { x: 0, y: 0 };
  }
}

export class GestureDebouncer {
  private candidate: ControlGesture = "Other";
  private candidateSince = 0;
  private committed: ControlGesture = "Other";

  constructor(
    private readonly holdMilliseconds = 250,
    private readonly minimumConfidence = 0.65,
  ) {}

  update(gesture: ControlGesture, confidence: number, now: number): ControlGesture | null {
    const accepted = confidence >= this.minimumConfidence ? gesture : "Other";
    if (accepted !== this.candidate) {
      this.candidate = accepted;
      this.candidateSince = now;
      if (accepted === "Other") this.committed = "Other";
      return null;
    }
    if (accepted === "Other" || accepted === this.committed) return null;
    if (now - this.candidateSince < this.holdMilliseconds) return null;
    this.committed = accepted;
    return accepted;
  }

  reset(): void {
    this.candidate = "Other";
    this.committed = "Other";
    this.candidateSince = 0;
  }
}

export class InputController {
  private handState: HandControlState | null = null;
  private pointerTarget: Point2D = { x: 0, y: 0 };
  private readonly smoother = new SteeringSmoother();
  private currentRoll = 0;
  private currentSpeedScale = 1;

  setHandState(state: HandControlState): void {
    this.handState = state.detected ? state : null;
  }

  setPointer(clientX: number, clientY: number, width: number, height: number): void {
    this.pointerTarget = {
      x: applyDeadzone((clientX / Math.max(1, width) - 0.5) * 2, 0.08),
      y: applyDeadzone((0.5 - clientY / Math.max(1, height)) * 2, 0.08),
    };
  }

  releasePointer(): void {
    this.pointerTarget = { x: 0, y: 0 };
  }

  update(deltaSeconds: number): { steering: Point2D; roll: number; speedScale: number } {
    const steeringTarget = this.handState?.steering ?? this.pointerTarget;
    const rollTarget = this.handState?.roll ?? 0;
    const alpha = 1 - Math.exp(-8 * Math.max(0, deltaSeconds));
    this.currentRoll += (rollTarget - this.currentRoll) * alpha;
    const speedTarget = this.handState?.speedScale ?? 1;
    this.currentSpeedScale += (speedTarget - this.currentSpeedScale) * alpha;
    return {
      steering: this.smoother.update(steeringTarget, deltaSeconds),
      roll: this.currentRoll,
      speedScale: this.currentSpeedScale,
    };
  }
}
