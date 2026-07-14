import type { NormalizedLandmark } from "@mediapipe/tasks-vision";

export type Handedness = "Left" | "Right";
export type ControlGesture = "Open_Palm" | "Closed_Fist" | "Pinch" | "Other";
export type SwipeDirection = "up" | "down" | "left" | "right";
export type GestureAction = "scroll-up" | "scroll-down" | "page-prev" | "page-next";

export type PageActionAdapter = {
  id: string;
  canHandle: (action: GestureAction, url: URL) => boolean;
  execute: (action: GestureAction) => boolean;
};

export type Point2D = {
  x: number;
  y: number;
};

export type HandControlState = {
  detected: boolean;
  stale: boolean;
  handedness: Handedness | null;
  confidence: number;
  palm: Point2D;
  steering: Point2D;
  roll: number;
  speedScale: number;
  distanceCalibrating: boolean;
  gesture: ControlGesture;
  gestureConfidence: number;
  landmarks: NormalizedLandmark[];
};

export const EMPTY_HAND_STATE: HandControlState = {
  detected: false,
  stale: false,
  handedness: null,
  confidence: 0,
  palm: { x: 0.5, y: 0.5 },
  steering: { x: 0, y: 0 },
  roll: 0,
  speedScale: 1,
  distanceCalibrating: false,
  gesture: "Other",
  gestureConfidence: 0,
  landmarks: [],
};
