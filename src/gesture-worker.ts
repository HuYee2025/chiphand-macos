/// <reference lib="webworker" />

import { FilesetResolver, HandLandmarker, type HandLandmarkerOptions } from "@mediapipe/tasks-vision";
import type { GestureWorkerRequest, GestureWorkerResponse } from "./gesture-worker-protocol";

const scope = self as unknown as DedicatedWorkerGlobalScope;
let landmarker: HandLandmarker | null = null;

function respond(message: GestureWorkerResponse): void {
  scope.postMessage(message);
}

async function createLandmarker(
  vision: Parameters<typeof HandLandmarker.createFromOptions>[0],
  modelUrl: string,
): Promise<"GPU" | "CPU"> {
  const baseOptions = { modelAssetPath: modelUrl };
  const shared: Omit<HandLandmarkerOptions, "baseOptions" | "canvas"> = {
    runningMode: "VIDEO",
    numHands: 2,
    minHandDetectionConfidence: 0.45,
    minHandPresenceConfidence: 0.45,
    minTrackingConfidence: 0.45,
  };

  if (typeof OffscreenCanvas !== "undefined") {
    try {
      landmarker = await HandLandmarker.createFromOptions(vision, {
        ...shared,
        baseOptions: { ...baseOptions, delegate: "GPU" },
        canvas: new OffscreenCanvas(1, 1),
      });
      return "GPU";
    } catch {
      // Some Safari and browser-worker combinations do not expose WebGL in an OffscreenCanvas.
    }
  }

  landmarker = await HandLandmarker.createFromOptions(vision, {
    ...shared,
    baseOptions: { ...baseOptions, delegate: "CPU" },
  });
  return "CPU";
}

scope.addEventListener("message", async (event: MessageEvent<GestureWorkerRequest>) => {
  const message = event.data;
  try {
    if (message.type === "init") {
      const vision = await FilesetResolver.forVisionTasks(message.wasmRoot, true);
      const delegate = await createLandmarker(vision, message.modelUrl);
      respond({ type: "ready", delegate });
      return;
    }

    if (message.type === "close") {
      landmarker?.close();
      landmarker = null;
      scope.close();
      return;
    }

    if (!landmarker) throw new Error("手势识别 Worker 尚未初始化。");
    const startedAt = performance.now();
    const result = landmarker.detectForVideo(message.bitmap, message.timestamp);
    message.bitmap.close();
    respond({ type: "result", result, durationMs: performance.now() - startedAt });
  } catch (error) {
    if (message.type === "frame") message.bitmap.close();
    respond({ type: "error", message: error instanceof Error ? error.message : String(error) });
  }
});
