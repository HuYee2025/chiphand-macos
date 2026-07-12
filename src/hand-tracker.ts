import type { HandLandmarkerResult, NormalizedLandmark } from "@mediapipe/tasks-vision";
import { classifyHandGesture, HandDistanceCalibrator, handScale } from "./hand-gesture-math";
import { mapPalmToSteering, palmCenter, PalmRotationCalibrator } from "./input-controller";
import type { GestureWorkerRequest, GestureWorkerResponse } from "./gesture-worker-protocol";
import { EMPTY_HAND_STATE, type HandControlState, type Handedness } from "./types";

const MIN_INFERENCE_INTERVAL_MS = 1000 / 30;
const MAX_INFERENCE_INTERVAL_MS = 1000 / 24;
const LOST_HAND_GRACE_MS = 220;
const LANDMARK_SMOOTHING = 0.5;

function normalizeHandedness(name: string | undefined): Handedness | null {
  if (name === "Left" || name === "Right") return name;
  return null;
}

function smoothLandmarks(
  previous: readonly NormalizedLandmark[] | null,
  next: readonly NormalizedLandmark[],
): NormalizedLandmark[] {
  if (!previous || previous.length !== next.length) return next.map((landmark) => ({ ...landmark }));
  return next.map((landmark, index) => {
    const prior = previous[index] ?? landmark;
    return {
      x: prior.x + (landmark.x - prior.x) * LANDMARK_SMOOTHING,
      y: prior.y + (landmark.y - prior.y) * LANDMARK_SMOOTHING,
      z: prior.z + (landmark.z - prior.z) * LANDMARK_SMOOTHING,
      visibility: landmark.visibility,
    };
  });
}

function selectHandIndex(result: HandLandmarkerResult, preferred: Handedness | null): number {
  if (result.landmarks.length === 0) return -1;
  const preferredIndex = result.handedness.findIndex((categories) => normalizeHandedness(categories[0]?.categoryName) === preferred);
  if (preferredIndex >= 0) return preferredIndex;
  return result.handedness.reduce((bestIndex, categories, index) => {
    const score = categories[0]?.score ?? 0;
    const bestScore = result.handedness[bestIndex]?.[0]?.score ?? -1;
    return score > bestScore ? index : bestIndex;
  }, 0);
}

export class HandTracker {
  private worker: Worker | null = null;
  private stream: MediaStream | null = null;
  private animationFrame = 0;
  private lastInferenceAt = 0;
  private lastVideoTime = -1;
  private workerBusy = false;
  private active = false;
  private inferenceLatencyMs = MIN_INFERENCE_INTERVAL_MS;
  private submittedAt = 0;
  private lastGoodState: HandControlState | null = null;
  private lastSeenAt = -Infinity;
  private selectedHand: Handedness | null = null;
  private readonly rotationCalibrator = new PalmRotationCalibrator();
  private readonly distanceCalibrator = new HandDistanceCalibrator();

  constructor(
    private readonly video: HTMLVideoElement,
    private readonly onState: (state: HandControlState) => void,
    private readonly onError: (message: string) => void,
  ) {}

  async start(): Promise<void> {
    if (this.active) return;
    if (!navigator.mediaDevices?.getUserMedia) {
      throw new Error("当前浏览器不支持摄像头访问，请使用最新版 Chrome、Edge 或 Safari。");
    }

    const mobile = window.matchMedia("(max-width: 720px)").matches;
    this.stream = await navigator.mediaDevices.getUserMedia({
      audio: false,
      video: {
        facingMode: "user",
        width: { ideal: mobile ? 480 : 640 },
        height: { ideal: mobile ? 360 : 480 },
        frameRate: { ideal: 30, max: 30 },
      },
    });
    this.video.srcObject = this.stream;
    await this.video.play();

    try {
      await this.startWorker();
    } catch (error) {
      this.stop();
      throw new Error(`手势模型加载失败：${error instanceof Error ? error.message : String(error)}`);
    }

    this.active = true;
    this.loop(performance.now());
  }

  stop(): void {
    this.active = false;
    cancelAnimationFrame(this.animationFrame);
    this.stream?.getTracks().forEach((track) => track.stop());
    this.stream = null;
    this.video.srcObject = null;
    if (this.worker) {
      this.worker.postMessage({ type: "close" } satisfies GestureWorkerRequest);
      this.worker.terminate();
      this.worker = null;
    }
    this.workerBusy = false;
    this.clearTracking();
    this.onState({ ...EMPTY_HAND_STATE, landmarks: [] });
  }

  private readonly loop = (now: number): void => {
    if (!this.active || !this.worker) return;
    this.animationFrame = requestAnimationFrame(this.loop);
    this.emitExpiredState(now);
    const adaptiveInterval = Math.max(
      MIN_INFERENCE_INTERVAL_MS,
      Math.min(MAX_INFERENCE_INTERVAL_MS, this.inferenceLatencyMs * 1.2),
    );
    if (this.workerBusy || now - this.lastInferenceAt < adaptiveInterval) return;
    if (this.video.readyState < HTMLMediaElement.HAVE_CURRENT_DATA || this.video.currentTime === this.lastVideoTime) return;

    this.lastInferenceAt = now;
    this.lastVideoTime = this.video.currentTime;
    this.submittedAt = now;
    this.workerBusy = true;
    void createImageBitmap(this.video)
      .then((bitmap) => {
        if (!this.active || !this.worker) {
          bitmap.close();
          this.workerBusy = false;
          return;
        }
        const message: GestureWorkerRequest = { type: "frame", bitmap, timestamp: now };
        this.worker.postMessage(message, [bitmap]);
      })
      .catch((error) => {
        this.workerBusy = false;
        this.onError(`无法读取摄像头画面：${error instanceof Error ? error.message : String(error)}`);
        this.stop();
      });
  };

  private handleResult(result: HandLandmarkerResult, workerDurationMs: number): void {
    this.workerBusy = false;
    const totalDuration = Math.max(workerDurationMs, performance.now() - this.submittedAt);
    this.inferenceLatencyMs = this.inferenceLatencyMs * 0.75 + totalDuration * 0.25;

    const index = selectHandIndex(result, this.selectedHand);
    const landmarks = index >= 0 ? result.landmarks[index] : undefined;
    if (!landmarks) {
      this.emitGraceState(performance.now());
      return;
    }

    const categories = result.handedness[index];
    const handedness = normalizeHandedness(categories?.[0]?.categoryName);
    this.selectedHand = handedness;
    const smoothed = smoothLandmarks(this.lastGoodState?.landmarks ?? null, landmarks);
    const palm = palmCenter(smoothed);
    const confidence = categories?.[0]?.score ?? 0;
    const distance = this.distanceCalibrator.update(handScale(smoothed), performance.now());
    const next: HandControlState = {
      detected: true,
      stale: false,
      handedness,
      confidence,
      palm,
      steering: mapPalmToSteering(palm),
      roll: this.rotationCalibrator.update(smoothed),
      speedScale: distance.speedScale,
      distanceCalibrating: distance.calibrating,
      gesture: classifyHandGesture(landmarks),
      gestureConfidence: 1,
      landmarks: smoothed,
    };
    this.lastGoodState = next;
    this.lastSeenAt = performance.now();
    this.onState(next);
  }

  private emitGraceState(now: number): void {
    if (!this.lastGoodState || now - this.lastSeenAt > LOST_HAND_GRACE_MS) {
      this.clearTracking();
      this.onState({ ...EMPTY_HAND_STATE, landmarks: [] });
      return;
    }
    this.onState({ ...this.lastGoodState, stale: true });
  }

  private emitExpiredState(now: number): void {
    if (this.lastGoodState && now - this.lastSeenAt > LOST_HAND_GRACE_MS) {
      this.clearTracking();
      this.onState({ ...EMPTY_HAND_STATE, landmarks: [] });
    }
  }

  private clearTracking(): void {
    this.lastGoodState = null;
    this.lastSeenAt = -Infinity;
    this.selectedHand = null;
    this.rotationCalibrator.reset();
    this.distanceCalibrator.reset();
  }

  private startWorker(): Promise<void> {
    this.worker = new Worker(new URL("./gesture-worker.ts", import.meta.url), { type: "module" });
    return new Promise((resolve, reject) => {
      let ready = false;
      const timeout = window.setTimeout(() => reject(new Error("手势模型加载超时。")), 30_000);
      const onMessage = (event: MessageEvent<GestureWorkerResponse>): void => {
        if (event.data.type === "ready") {
          ready = true;
          window.clearTimeout(timeout);
          resolve();
          return;
        }
        if (event.data.type === "result") {
          this.handleResult(event.data.result, event.data.durationMs);
          return;
        }
        this.workerBusy = false;
        window.clearTimeout(timeout);
        const error = new Error(event.data.message);
        if (ready) {
          this.onError(`手势识别发生错误：${error.message}`);
          this.stop();
        } else {
          reject(error);
        }
      };
      this.worker?.addEventListener("message", onMessage);
      this.worker?.addEventListener("error", (event) => {
        window.clearTimeout(timeout);
        const error = new Error(event.message || "手势识别 Worker 启动失败。");
        if (ready) {
          this.onError(error.message);
          this.stop();
        } else {
          reject(error);
        }
      });
      const initMessage: GestureWorkerRequest = {
        type: "init",
        wasmRoot: new URL("/mediapipe/wasm", window.location.href).href,
        modelUrl: new URL("/mediapipe/hand_landmarker.task", window.location.href).href,
      };
      this.worker?.postMessage(initMessage);
    });
  }
}
