import {
  FilesetResolver,
  GestureRecognizer,
  type GestureRecognizerResult,
  type NormalizedLandmark,
} from "@mediapipe/tasks-vision";

type Handedness = "Left" | "Right";
type NativeMessage =
  | { type: "ready"; delegate: "GPU" | "CPU" }
  | { type: "progress"; message: string }
  | {
      type: "pose";
      handedness: Handedness | null;
      confidence: number;
      gesture: string;
      gestureConfidence: number;
      inferenceDuration: number;
      recognitionFPS: number;
      landmarks: NormalizedLandmark[];
    }
  | { type: "lost" }
  | { type: "error"; message: string };

declare global {
  interface Window {
    webkit?: {
      messageHandlers?: {
        handPose?: { postMessage: (message: NativeMessage) => void };
      };
    };
    stopRecognition?: () => void;
    setControlHand?: (hand: Handedness) => void;
    setPointerModeEnabled?: (enabled: boolean) => void;
  }
}

const videoElement = document.querySelector<HTMLVideoElement>("#camera");
if (!videoElement) throw new Error("缺少摄像头视频节点。");
const video: HTMLVideoElement = videoElement;
const canvasElement = document.querySelector<HTMLCanvasElement>("#skeleton");
if (!canvasElement) throw new Error("缺少骨架画布节点。");
const canvas: HTMLCanvasElement = canvasElement;
const contextValue = canvas.getContext("2d");
if (!contextValue) throw new Error("无法创建骨架画布。");
const context: CanvasRenderingContext2D = contextValue;

const DISPLAY_CONNECTIONS = [
  [0, 1], [1, 3], [3, 4],
  [0, 5], [5, 6], [6, 8],
  [0, 9], [9, 10], [10, 12],
  [0, 13], [13, 14], [14, 16],
  [0, 17], [17, 18], [18, 20],
  [5, 9], [9, 13], [13, 17],
] as const;
const DISPLAY_POINTS = [0, 1, 3, 4, 5, 6, 8, 9, 10, 12, 13, 14, 16, 17, 18, 20] as const;

let recognizer: GestureRecognizer | null = null;
let stream: MediaStream | null = null;
let active = false;
let timer: number | null = null;
let lastVideoTime = -1;
let lastInferenceAt = 0;
let selectedHand: Handedness | null = null;
let controlHand: Handedness = "Right";
let pointerModeEnabled = false;
let previousLandmarks: NormalizedLandmark[] | null = null;
let targetFPS = 30;
let fastWindows = 0;
let inferenceDurations: number[] = [];
let frameTimes: number[] = [];
let recognitionFPS = 0;

function post(message: NativeMessage): void {
  window.webkit?.messageHandlers?.handPose?.postMessage(message);
}

function normalizeHandedness(name: string | undefined): Handedness | null {
  return name === "Left" || name === "Right" ? name : null;
}

function selectHandIndex(result: GestureRecognizerResult): number {
  if (result.landmarks.length === 0) return -1;
  const preferred = result.handedness.findIndex(
    (categories) => normalizeHandedness(categories[0]?.categoryName) === selectedHand,
  );
  if (preferred >= 0) return preferred;
  return result.handedness.reduce((best, categories, index) => {
    const score = categories[0]?.score ?? 0;
    const bestScore = result.handedness[best]?.[0]?.score ?? -1;
    return score > bestScore ? index : best;
  }, 0);
}

function smoothLandmarks(next: readonly NormalizedLandmark[]): NormalizedLandmark[] {
  if (!previousLandmarks || previousLandmarks.length !== next.length) {
    return next.map((point) => ({ ...point }));
  }
  const alpha = 0.65;
  return next.map((point, index) => {
    const previous = previousLandmarks?.[index] ?? point;
    return {
      x: previous.x + (point.x - previous.x) * alpha,
      y: previous.y + (point.y - previous.y) * alpha,
      z: previous.z + (point.z - previous.z) * alpha,
      visibility: point.visibility,
    };
  });
}

function distance(a: NormalizedLandmark, b: NormalizedLandmark): number {
  return Math.hypot(a.x - b.x, a.y - b.y);
}

function isPinching(landmarks: readonly NormalizedLandmark[]): boolean {
  const wrist = landmarks[0];
  const thumb = landmarks[4];
  const index = landmarks[8];
  if (!wrist || !thumb || !index) return false;
  const palm = [5, 9, 13, 17].map((index) => landmarks[index]).filter(Boolean) as NormalizedLandmark[];
  if (palm.length === 0) return false;
  const scale = palm.reduce((sum, point) => sum + distance(wrist, point), 0) / palm.length;
  const fingersAreOpen = [
    [12, 10, 9],
    [16, 14, 13],
    [20, 18, 17],
  ].every(([tipIndex, pipIndex, mcpIndex]) => {
    const tip = landmarks[tipIndex];
    const pip = landmarks[pipIndex];
    const mcp = landmarks[mcpIndex];
    return tip && pip && mcp
      && distance(tip, wrist) > distance(pip, wrist) * 1.04
      && distance(tip, wrist) > distance(mcp, wrist) * 1.12;
  });
  return fingersAreOpen && distance(thumb, index) / Math.max(scale, 0.000_001) <= 0.18;
}

function fingerIsExtended(
  landmarks: readonly NormalizedLandmark[],
  tipIndex: number,
  pipIndex: number,
  mcpIndex: number,
): boolean {
  const wrist = landmarks[0];
  const tip = landmarks[tipIndex];
  const pip = landmarks[pipIndex];
  const mcp = landmarks[mcpIndex];
  return Boolean(wrist && tip && pip && mcp
    && distance(tip, wrist) > distance(pip, wrist) * 1.04
    && distance(tip, wrist) > distance(mcp, wrist) * 1.12);
}

function isPointingFingerConfiguration(landmarks: readonly NormalizedLandmark[]): boolean {
  return fingerIsExtended(landmarks, 8, 6, 5)
    && !fingerIsExtended(landmarks, 12, 10, 9)
    && !fingerIsExtended(landmarks, 16, 14, 13)
    && !fingerIsExtended(landmarks, 20, 18, 17);
}

function thumbPalmDistanceRatio(landmarks: readonly NormalizedLandmark[]): number | null {
  const wrist = landmarks[0];
  const thumb = landmarks[4];
  if (!wrist || !thumb) return null;
  const palm = [5, 9, 13, 17].map((index) => landmarks[index]).filter(Boolean) as NormalizedLandmark[];
  const thumbAnchors = [5, 9, 13, 6, 10]
    .map((index) => landmarks[index])
    .filter(Boolean) as NormalizedLandmark[];
  if (palm.length === 0 || thumbAnchors.length === 0) return null;
  const scale = palm.reduce((sum, point) => sum + distance(wrist, point), 0) / palm.length;
  return Math.min(...thumbAnchors.map((point) => distance(thumb, point))) / Math.max(scale, 0.000_001);
}

function isStrictPointing(landmarks: readonly NormalizedLandmark[]): boolean {
  const ratio = thumbPalmDistanceRatio(landmarks);
  return ratio !== null && ratio <= 0.90 && isPointingFingerConfiguration(landmarks);
}

function drawSkeleton(
  landmarks: readonly NormalizedLandmark[],
  handedness: Handedness | null,
  gesture: string,
  gestureConfidence: number,
): void {
  const width = video.videoWidth || 640;
  const height = video.videoHeight || 480;
  if (canvas.width !== width || canvas.height !== height) {
    canvas.width = width;
    canvas.height = height;
  }
  context.clearRect(0, 0, width, height);
  const color = handedness === "Left" ? "#ff4555" : handedness === "Right" ? "#3f8cff" : "#25c9e8";
  context.strokeStyle = color;
  context.fillStyle = "white";
  context.lineWidth = 3;
  context.lineCap = "round";
  for (const [from, to] of DISPLAY_CONNECTIONS) {
    const first = landmarks[from];
    const second = landmarks[to];
    if (!first || !second) continue;
    context.beginPath();
    context.moveTo(first.x * width, first.y * height);
    context.lineTo(second.x * width, second.y * height);
    context.stroke();
  }
  for (const index of DISPLAY_POINTS) {
    const point = landmarks[index];
    if (!point) continue;
    context.beginPath();
    context.arc(point.x * width, point.y * height, 5, 0, Math.PI * 2);
    context.fill();
    context.stroke();
  }
  if (isPinching(landmarks)) {
    const thumb = landmarks[4];
    const index = landmarks[8];
    if (!thumb || !index) return;
    const x = ((thumb.x + index.x) / 2) * width;
    const y = ((thumb.y + index.y) / 2) * height;
    context.beginPath();
    context.arc(x, y, 14, 0, Math.PI * 2);
    context.fillStyle = "#f8d84e";
    context.fill();
    context.lineWidth = 2;
    context.strokeStyle = "white";
    context.stroke();
  }
  if (pointerModeEnabled
      && ((gesture === "Pointing_Up"
        && gestureConfidence >= 0.70
        && isStrictPointing(landmarks))
        || isPointingFingerConfiguration(landmarks))) {
    const index = landmarks[8];
    if (index) {
      context.beginPath();
      context.arc(index.x * width, index.y * height, 11, 0, Math.PI * 2);
      context.fillStyle = "#f8d84e";
      context.fill();
      context.lineWidth = 2;
      context.strokeStyle = "white";
      context.stroke();
    }
  }
  if (gesture === "Thumb_Up" && gestureConfidence >= 0.70) {
    const palm = [0, 5, 9, 13, 17]
      .map((index) => landmarks[index])
      .filter(Boolean) as NormalizedLandmark[];
    if (palm.length > 0) {
      const x = palm.reduce((sum, point) => sum + point.x, 0) / palm.length * width;
      const y = palm.reduce((sum, point) => sum + point.y, 0) / palm.length * height;
      context.save();
      context.translate(x, y);
      context.scale(-1, 1);
      context.font = "42px -apple-system, BlinkMacSystemFont, sans-serif";
      context.textAlign = "center";
      context.textBaseline = "middle";
      context.fillText("👍", 0, 0);
      context.restore();
    }
  }
}

function clearSkeleton(): void {
  context.clearRect(0, 0, canvas.width, canvas.height);
}

async function createRecognizer(): Promise<"GPU" | "CPU"> {
  const wasmRoot = new URL("./mediapipe/wasm", window.location.href).href;
  const modelUrl = new URL("./mediapipe/gesture_recognizer.task", window.location.href).href;
  // WKWebView currently evaluates MediaPipe's ES6 WASM loader as a classic
  // script. The non-module loader uses the same model/runtime without the
  // unsupported `import.meta` path.
  const vision = await FilesetResolver.forVisionTasks(wasmRoot, false);
  const shared = {
    runningMode: "VIDEO" as const,
    numHands: 1,
    minHandDetectionConfidence: 0.45,
    minHandPresenceConfidence: 0.45,
    minTrackingConfidence: 0.45,
    cannedGesturesClassifierOptions: { scoreThreshold: 0.50 },
  };

  try {
    recognizer = await GestureRecognizer.createFromOptions(vision, {
      ...shared,
      baseOptions: { modelAssetPath: modelUrl, delegate: "GPU" },
      canvas: new OffscreenCanvas(1, 1),
    });
    return "GPU";
  } catch {
    recognizer = await GestureRecognizer.createFromOptions(vision, {
      ...shared,
      baseOptions: { modelAssetPath: modelUrl, delegate: "CPU" },
    });
    return "CPU";
  }
}

function updatePerformance(inferenceDuration: number, frameTime: number): void {
  inferenceDurations.push(inferenceDuration);
  if (inferenceDurations.length > 120) inferenceDurations.shift();
  frameTimes.push(frameTime);
  frameTimes = frameTimes.filter((time) => frameTime - time <= 1000);
  recognitionFPS = frameTimes.length;
  if (inferenceDurations.length < 120) return;

  const sorted = [...inferenceDurations].sort((a, b) => a - b);
  const p95 = sorted[Math.floor(sorted.length * 0.95)] ?? 0;
  inferenceDurations = [];
  if (targetFPS === 30 && p95 > 40) {
    targetFPS = 24;
    fastWindows = 0;
  } else if (targetFPS === 24) {
    fastWindows = p95 < 30 ? fastWindows + 1 : 0;
    if (fastWindows >= 5) {
      targetFPS = 30;
      fastWindows = 0;
    }
  }
}

function loop(): void {
  if (!active || !recognizer) return;
  timer = window.setTimeout(loop, 16);
  const now = performance.now();
  if (now - lastInferenceAt < 1000 / targetFPS || video.readyState < HTMLMediaElement.HAVE_CURRENT_DATA) return;
  if (video.currentTime === lastVideoTime) return;
  lastInferenceAt = now;
  lastVideoTime = video.currentTime;

  try {
    const inferenceStartedAt = performance.now();
    const result = recognizer.recognizeForVideo(video, now);
    const inferenceDuration = performance.now() - inferenceStartedAt;
    updatePerformance(inferenceDuration, now);
    const index = selectHandIndex(result);
    if (index < 0) {
      selectedHand = null;
      previousLandmarks = null;
      clearSkeleton();
      post({ type: "lost" });
      return;
    }
    const category = result.handedness[index]?.[0];
    selectedHand = normalizeHandedness(category?.categoryName);
    const gesture = result.gestures[index]?.[0];
    const landmarks = smoothLandmarks(result.landmarks[index] ?? []);
    previousLandmarks = landmarks;
    if (selectedHand === controlHand) {
      drawSkeleton(landmarks, selectedHand, gesture?.categoryName ?? "None", gesture?.score ?? 0);
    } else {
      clearSkeleton();
    }
    post({
      type: "pose",
      handedness: selectedHand,
      confidence: category?.score ?? 0,
      gesture: gesture?.categoryName ?? "None",
      gestureConfidence: gesture?.score ?? 0,
      inferenceDuration,
      recognitionFPS,
      landmarks,
    });
  } catch (error) {
    post({ type: "error", message: error instanceof Error ? error.message : String(error) });
  }
}

async function start(): Promise<void> {
  try {
    post({ type: "progress", message: "正在加载 MediaPipe 模型" });
    const delegate = await createRecognizer();
    post({ type: "progress", message: `模型已加载（${delegate}），正在打开摄像头` });
    stream = await navigator.mediaDevices.getUserMedia({
      audio: false,
      video: { width: { ideal: 640 }, height: { ideal: 480 }, frameRate: { ideal: 30, max: 30 } },
    });
    post({ type: "progress", message: "摄像头已打开，正在启动视频" });
    video.srcObject = stream;
    await video.play();
    post({ type: "progress", message: "视频已启动，正在开始识别" });
    active = true;
    post({ type: "ready", delegate });
    loop();
  } catch (error) {
    post({ type: "error", message: error instanceof Error ? error.message : String(error) });
  }
}

window.stopRecognition = () => {
  active = false;
  if (timer !== null) window.clearTimeout(timer);
  timer = null;
  stream?.getTracks().forEach((track) => track.stop());
  stream = null;
  video.srcObject = null;
  recognizer?.close();
  recognizer = null;
  selectedHand = null;
  previousLandmarks = null;
  targetFPS = 30;
  fastWindows = 0;
  inferenceDurations = [];
  frameTimes = [];
  recognitionFPS = 0;
  clearSkeleton();
};

window.setControlHand = (hand: Handedness) => {
  controlHand = hand;
  if (selectedHand !== controlHand) clearSkeleton();
};

window.setPointerModeEnabled = (enabled: boolean) => {
  pointerModeEnabled = enabled;
};

void start();
