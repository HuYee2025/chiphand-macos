import type { HandLandmarkerResult } from "@mediapipe/tasks-vision";

export type GestureWorkerRequest =
  | { type: "init"; wasmRoot: string; modelUrl: string }
  | { type: "frame"; bitmap: ImageBitmap; timestamp: number }
  | { type: "close" };

export type GestureWorkerResponse =
  | { type: "ready"; delegate: "GPU" | "CPU" }
  | { type: "result"; result: HandLandmarkerResult; durationMs: number }
  | { type: "error"; message: string };
