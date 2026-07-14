import { HandTracker } from "../src/hand-tracker";
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

const detector = new SwipeDetector();
let tracker: HandTracker | null = null;
let running = false;
let targetTabId: number | null = null;
let handPresent: boolean | null = null;

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

function handleHandState(state: HandControlState): void {
  if (state.detected !== handPresent) {
    handPresent = state.detected;
    publishStatus(
      state.detected
        ? `已检测到${state.handedness === "Left" ? "左手" : "右手"}，${Math.round(state.confidence * 100)}%。`
        : "正在寻找张开的手掌。",
    );
  }
  const direction = detector.update(state, performance.now());
  if (direction) void executeDirection(direction);
}

function handleTrackerError(message: string): void {
  tracker?.stop();
  tracker = null;
  detector.reset();
  running = false;
  handPresent = null;
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
  running = false;
  handPresent = null;
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
  sendResponse(statusResponse(running ? "后台识别中。" : "摄像头未启动。"));
});
