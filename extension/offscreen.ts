import { HandTracker } from "../src/hand-tracker";
import {
  DEFAULT_GESTURE_SETTINGS,
  normalizeGestureSettings,
  pinchContactThreshold,
  pinchReleaseThreshold,
  swipeMinimumDisplacement,
  type GestureSettings,
} from "../src/gesture-settings";
import { classifyHandGesture } from "../src/hand-gesture-math";
import { PinchScrollDetector } from "../src/pinch-scroll-detector";
import { SwipeDetector, swipeDirectionToAction } from "../src/swipe-detector";
import type { HandControlState, SwipeDirection } from "../src/types";
import {
  isOffscreenRequest,
  type ExtensionRequest,
  type ExtensionResponse,
  type OffscreenResponse,
  type TrackerEvent,
} from "./message-types";

const video = document.querySelector<HTMLVideoElement>("#background-camera");
if (!video) throw new Error("缺少后台摄像头元素。");
const backgroundVideo = video;

let gestureSettings: GestureSettings = DEFAULT_GESTURE_SETTINGS;
let detector = createSwipeDetector(gestureSettings);
let pinchScrollDetector = createPinchScrollDetector(gestureSettings);
let tracker: HandTracker | null = null;
let running = false;
let targetTabId: number | null = null;
let handPresent: boolean | null = null;
let lastPreviewUpdateAt = 0;
// 网页捏合点需要跟手，按摄像头推理的最高 30 FPS 同步；页面端再用 rAF 插值。
const PREVIEW_UPDATE_INTERVAL_MS = 1000 / 30;
const PINCH_FEEDBACK_INTERVAL_MS = 180;
let lastPinchFeedbackAt = 0;

function createSwipeDetector(settings: GestureSettings): SwipeDetector {
  return new SwipeDetector({
    allowedDirections: ["left", "right"],
    minimumDisplacement: swipeMinimumDisplacement(settings),
  });
}

function createPinchScrollDetector(settings: GestureSettings): PinchScrollDetector {
  return new PinchScrollDetector({
    pinchThreshold: pinchContactThreshold(settings),
    releaseThreshold: pinchReleaseThreshold(settings),
  });
}

function applyGestureSettings(settings: GestureSettings): GestureSettings {
  gestureSettings = normalizeGestureSettings(settings);
  detector = createSwipeDetector(gestureSettings);
  pinchScrollDetector = createPinchScrollDetector(gestureSettings);
  return gestureSettings;
}

function statusResponse(message: string, ok = true): OffscreenResponse {
  return { ok, active: running, message, ...(targetTabId === null ? {} : { tabId: targetTabId }) };
}

function publish(event: TrackerEvent): void {
  void chrome.runtime.sendMessage(event).catch(() => undefined);
}

function publishStatus(message: string): void {
  publish({ type: "background-tracker-status", active: running, message, ...(targetTabId === null ? {} : { tabId: targetTabId }) });
}

async function executeDirection(direction: SwipeDirection): Promise<void> {
  if (targetTabId === null) return;
  const request: ExtensionRequest = {
    type: "gesture-action",
    action: swipeDirectionToAction(direction),
    direction,
    timestamp: Date.now(),
    tabId: targetTabId,
  };
  try {
    const response = (await chrome.runtime.sendMessage(request)) as ExtensionResponse | undefined;
    publish({
      type: "background-gesture-feedback",
      direction,
      ok: response?.ok ?? false,
      message: response?.message ?? "网页没有返回动作结果。",
      ...(targetTabId === null ? {} : { tabId: targetTabId }),
    });
  } catch {
    publish({
      type: "background-gesture-feedback",
      direction,
      ok: false,
      message: "插件后台连接失败。",
      ...(targetTabId === null ? {} : { tabId: targetTabId }),
    });
  }
}

async function executePinchScroll(deltaY: number, direction: Extract<SwipeDirection, "up" | "down">): Promise<void> {
  if (targetTabId === null) return;
  const request: ExtensionRequest = {
    type: "pinch-scroll",
    deltaY,
    direction,
    timestamp: Date.now(),
    tabId: targetTabId,
  };
  try {
    const response = (await chrome.runtime.sendMessage(request)) as ExtensionResponse | undefined;
    const now = performance.now();
    if (now - lastPinchFeedbackAt >= PINCH_FEEDBACK_INTERVAL_MS) {
      lastPinchFeedbackAt = now;
      publish({
        type: "background-gesture-feedback",
        direction,
        ok: response?.ok ?? false,
        message: response?.message ?? "网页没有返回捏合滚动结果。",
        ...(targetTabId === null ? {} : { tabId: targetTabId }),
      });
    }
  } catch {
    publish({
      type: "background-gesture-feedback",
      direction,
      ok: false,
      message: "插件后台连接失败。",
      ...(targetTabId === null ? {} : { tabId: targetTabId }),
    });
  }
}

function handleHandState(rawState: HandControlState): void {
  // HandTracker keeps position smoothing independent from gesture thresholds.
  // Reclassify here so the user can tune pinch sensitivity without restarting
  // the camera or model worker.
  const state: HandControlState = rawState.detected
    ? { ...rawState, gesture: classifyHandGesture(rawState.landmarks, pinchContactThreshold(gestureSettings)) }
    : rawState;
  const now = performance.now();
  if (now - lastPreviewUpdateAt >= PREVIEW_UPDATE_INTERVAL_MS) {
    lastPreviewUpdateAt = now;
    publish({ type: "background-hand-state", state, ...(targetTabId === null ? {} : { tabId: targetTabId }) });
  }
  if (state.detected !== handPresent) {
    handPresent = state.detected;
    publishStatus(
      state.detected
        ? `已检测到${state.handedness === "Left" ? "左手" : "右手"}，${Math.round(state.confidence * 100)}%。`
        : "正在寻找手掌。",
    );
  }
  const pinchUpdate = pinchScrollDetector.update(state, now);
  if (pinchUpdate.direction !== null) void executePinchScroll(pinchUpdate.deltaY, pinchUpdate.direction);
  const direction = detector.update(state, now);
  if (direction) void executeDirection(direction);
}

function handleTrackerError(message: string): void {
  tracker?.stop();
  tracker = null;
  detector.reset();
  pinchScrollDetector.reset();
  running = false;
  handPresent = null;
  lastPreviewUpdateAt = 0;
  lastPinchFeedbackAt = 0;
  publishStatus(`后台识别失败：${message}`);
}

async function startTracking(tabId: number): Promise<OffscreenResponse> {
  targetTabId = tabId;
  if (running) {
    publishStatus("后台识别已连接到当前网页。");
    return statusResponse("后台识别已连接到当前网页。");
  }
  try {
    tracker ??= new HandTracker(backgroundVideo, handleHandState, handleTrackerError);
    await tracker.start();
    running = true;
    lastPreviewUpdateAt = 0;
    lastPinchFeedbackAt = 0;
    publishStatus("后台识别中；点击网页不会中断手势。");
    return statusResponse("后台识别已启动。现在可以直接点击网页。");
  } catch (error) {
    tracker = null;
    detector.reset();
    running = false;
    const message = error instanceof Error ? error.message : String(error);
    publishStatus(`后台识别失败：${message}`);
    return statusResponse(`后台识别启动失败：${message}`, false);
  }
}

function stopTracking(): OffscreenResponse {
  tracker?.stop();
  tracker = null;
  detector.reset();
  pinchScrollDetector.reset();
  running = false;
  handPresent = null;
  lastPreviewUpdateAt = 0;
  lastPinchFeedbackAt = 0;
  publishStatus("摄像头已停止。");
  return statusResponse("摄像头已停止。");
}

chrome.runtime.onMessage.addListener((message: unknown, _sender, sendResponse: (response: OffscreenResponse) => void) => {
  if (!isOffscreenRequest(message)) return;
  if (message.type === "offscreen-start-tracking") {
    void startTracking(message.tabId).then(sendResponse);
    return true;
  }
  if (message.type === "offscreen-stop-tracking") {
    sendResponse(stopTracking());
    return;
  }
  if (message.type === "offscreen-update-gesture-settings") {
    const settings = applyGestureSettings(message.settings);
    sendResponse({ ...statusResponse("手势灵敏度已更新。"), settings });
    return;
  }
  sendResponse(statusResponse(running ? "后台识别中。" : "摄像头未启动。"));
});
