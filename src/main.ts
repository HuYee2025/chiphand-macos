import "./styles.css";
import { CameraOverlay } from "./camera-overlay";
import { GestureDebouncer, InputController } from "./input-controller";
import { TunnelController } from "./tunnel-controller";
import type { ControlGesture, HandControlState } from "./types";

function required<T extends Element>(selector: string): T {
  const element = document.querySelector<T>(selector);
  if (!element) throw new Error(`缺少页面元素：${selector}`);
  return element;
}

const app = required<HTMLElement>("#app");
const sceneRoot = required<HTMLElement>("#scene-root");
const video = required<HTMLVideoElement>("#camera-video");
const landmarkCanvas = required<HTMLCanvasElement>("#landmark-canvas");
const cameraPanel = required<HTMLElement>("#camera-panel");
const cameraPlaceholder = required<HTMLElement>("#camera-placeholder");
const introPanel = required<HTMLElement>("#intro-panel");
const cameraStart = required<HTMLButtonElement>("#camera-start");
const cameraHide = required<HTMLButtonElement>("#camera-hide");
const cameraShow = required<HTMLButtonElement>("#camera-show");
const pauseToggle = required<HTMLButtonElement>("#pause-toggle");
const trackingStatus = required<HTMLElement>("#tracking-status");
const fpsStatus = required<HTMLElement>("#fps-status");
const handLabel = required<HTMLElement>("#hand-label");
const gestureLabel = required<HTMLElement>("#gesture-label");
const introError = required<HTMLElement>("#intro-error");

const tunnel = new TunnelController(sceneRoot);
const input = new InputController();
const gestureDebouncer = new GestureDebouncer(250, 0.65);
const overlay = new CameraOverlay(video, landmarkCanvas);

let tracker: import("./hand-tracker").HandTracker | null = null;
let cameraRunning = false;
let handDetected = false;
let lastFrameAt = performance.now();
let fpsWindowStarted = lastFrameAt;
let fpsFrames = 0;

function gestureText(gesture: ControlGesture): string {
  if (gesture === "Open_Palm") return "张开手掌 · 前进";
  if (gesture === "Closed_Fist") return "握拳 · 暂停";
  if (gesture === "Pinch") return "拇指食指捏合";
  return "移动手掌控制方向";
}

function updatePauseButton(): void {
  const paused = tunnel.isPaused();
  pauseToggle.textContent = paused ? "继续" : "暂停";
  pauseToggle.setAttribute("aria-pressed", String(paused));
}

function setPaused(paused: boolean): void {
  tunnel.setPaused(paused);
  updatePauseButton();
}

function setTrackingStatus(text: string, state: "idle" | "active" | "error" = "idle"): void {
  trackingStatus.textContent = text;
  trackingStatus.classList.toggle("is-active", state === "active");
  trackingStatus.classList.toggle("is-error", state === "error");
}

function handleHandState(state: HandControlState): void {
  handDetected = state.detected;
  input.setHandState(state);
  overlay.draw(state);

  if (!state.detected) {
    gestureDebouncer.reset();
    if (cameraRunning) setTrackingStatus("寻找手掌");
    handLabel.textContent = "NO HAND";
    handLabel.style.color = "";
    gestureLabel.textContent = "请将一只手放入画面";
    return;
  }

  const isLeft = state.handedness === "Left";
  handLabel.textContent = `${isLeft ? "LEFT / 左手" : "RIGHT / 右手"} · ${Math.round(state.confidence * 100)}%${state.stale ? " · 续帧" : ""}`;
  handLabel.style.color = isLeft ? "#ff6370" : "#6ba5ff";
  gestureLabel.textContent = state.distanceCalibrating
    ? "正在校准距离…"
    : `${gestureText(state.gesture)} · 速度 ×${state.speedScale.toFixed(1)}`;
  setTrackingStatus(state.stale ? "保持追踪" : `${isLeft ? "左手" : "右手"}已识别`, "active");

  if (state.stale) return;
  const committed = gestureDebouncer.update(state.gesture, state.gestureConfidence, performance.now());
  if (committed === "Open_Palm") setPaused(false);
  if (committed === "Closed_Fist") setPaused(true);
}

function showCameraError(message: string): void {
  cameraRunning = false;
  handDetected = false;
  introPanel.classList.remove("is-dismissed");
  introPanel.setAttribute("aria-hidden", "false");
  cameraPlaceholder.classList.remove("is-off");
  cameraStart.disabled = false;
  cameraStart.textContent = "重新启动摄像头";
  introError.textContent = message;
  setTrackingStatus("摄像头不可用", "error");
}

cameraStart.addEventListener("click", async () => {
  cameraStart.disabled = true;
  cameraStart.textContent = "正在加载识别模型…";
  introError.textContent = "";
  setTrackingStatus("正在启动");
  try {
    if (!tracker) {
      const { HandTracker } = await import("./hand-tracker");
      tracker = new HandTracker(video, handleHandState, showCameraError);
    }
    await tracker.start();
    cameraRunning = true;
    cameraPlaceholder.classList.add("is-off");
    introPanel.classList.add("is-dismissed");
    introPanel.setAttribute("aria-hidden", "true");
    cameraStart.textContent = "摄像头已启动";
    setTrackingStatus("寻找手掌");
  } catch (error) {
    const rawMessage = error instanceof Error ? error.message : String(error);
    const message =
      error instanceof DOMException && error.name === "NotAllowedError"
        ? "摄像头权限被拒绝。请在浏览器地址栏设置中允许摄像头后重试。"
        : rawMessage;
    showCameraError(message);
  }
});

cameraHide.addEventListener("click", () => {
  cameraPanel.classList.add("is-hidden");
  cameraPanel.setAttribute("aria-hidden", "true");
  cameraShow.classList.remove("is-concealed");
});

cameraShow.addEventListener("click", () => {
  cameraPanel.classList.remove("is-hidden");
  cameraPanel.setAttribute("aria-hidden", "false");
  cameraShow.classList.add("is-concealed");
});

pauseToggle.addEventListener("click", () => setPaused(!tunnel.isPaused()));

window.addEventListener("keydown", (event) => {
  if (event.code !== "Space" || event.repeat) return;
  event.preventDefault();
  setPaused(!tunnel.isPaused());
});

app.addEventListener("pointermove", (event) => {
  if ((event.target as Element).closest("button")) return;
  input.setPointer(event.clientX, event.clientY, window.innerWidth, window.innerHeight);
});
app.addEventListener("pointerleave", () => input.releasePointer());
app.addEventListener("pointercancel", () => input.releasePointer());

function animate(now: number): void {
  requestAnimationFrame(animate);
  const delta = Math.min((now - lastFrameAt) / 1000, 0.05);
  lastFrameAt = now;
  const control = input.update(delta);
  tunnel.setSteering(control.steering);
  tunnel.setRoll(control.roll);
  tunnel.setSpeedScale(control.speedScale);
  tunnel.render(delta);

  fpsFrames += 1;
  const fpsElapsed = now - fpsWindowStarted;
  if (fpsElapsed >= 1000) {
    const fps = Math.round((fpsFrames * 1000) / fpsElapsed);
    fpsStatus.textContent = `${fps} FPS`;
    fpsStatus.style.color = fps < 45 ? "#ffb56b" : "";
    fpsWindowStarted = now;
    fpsFrames = 0;
  }

  if (!handDetected && cameraRunning) input.setHandState({
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
  });
}

window.addEventListener("pagehide", () => tracker?.stop());
updatePauseButton();
requestAnimationFrame(animate);
