export type NativeHandedness = "Left" | "Right";

export type NativeHandCandidate = {
  handedness: NativeHandedness | null;
  score: number;
};

export type HandStabilityState = {
  active: NativeHandedness | null;
  candidate: NativeHandedness | null;
  candidateSince: number;
};

export const NATIVE_HAND_STABILITY_MS = 120;

export const INITIAL_HAND_STABILITY: HandStabilityState = {
  active: null,
  candidate: null,
  candidateSince: 0,
};

export function selectNativeHandIndex(
  candidates: readonly NativeHandCandidate[],
  controlHand: NativeHandedness,
  activeHand: NativeHandedness | null,
): number {
  if (candidates.length === 0) return -1;
  const controlIndex = candidates.findIndex(({ handedness }) => handedness === controlHand);
  if (controlIndex >= 0) return controlIndex;
  const activeIndex = activeHand
    ? candidates.findIndex(({ handedness }) => handedness === activeHand)
    : -1;
  if (activeIndex >= 0) return activeIndex;
  return candidates.reduce(
    (bestIndex, candidate, index) => candidate.score > (candidates[bestIndex]?.score ?? -1)
      ? index
      : bestIndex,
    0,
  );
}

export function updateHandStability(
  state: HandStabilityState,
  observed: NativeHandedness | null,
  now: number,
  stableForMs = NATIVE_HAND_STABILITY_MS,
): { state: HandStabilityState; active: NativeHandedness | null; isStable: boolean } {
  if (observed === null) {
    return {
      state: INITIAL_HAND_STABILITY,
      active: null,
      isStable: false,
    };
  }
  if (state.active === observed) {
    return {
      state: { active: observed, candidate: null, candidateSince: 0 },
      active: observed,
      isStable: true,
    };
  }
  if (state.candidate !== observed) {
    return {
      state: { ...state, candidate: observed, candidateSince: now },
      active: state.active,
      isStable: false,
    };
  }
  if (now - state.candidateSince >= stableForMs) {
    return {
      state: { active: observed, candidate: null, candidateSince: 0 },
      active: observed,
      isStable: true,
    };
  }
  return { state, active: state.active, isStable: false };
}
