import "./sidepanel.css";
import { CameraOverlay } from "../src/camera-overlay";
import { HandTracker } from "../src/hand-tracker";
import { SwipeDetector, swipeDirectionToAction } from "../src/swipe-detector";
import type { HandControlState, SwipeDirection } from "../src/types";
import type { ExtensionRequest, ExtensionResponse } from "./message-types";

function required<T extends Element>(selector: string): T {
  const element = document.querySelector<T>(selector);
  if (!element) throw new Error(`缺少插件界面元素：${selector}`);
  return element;
}

const video = required<HTMLVideoElement>("#camera-video");
const canvas = required<HTMLCanvasElement>("#landmark-canvas");
const placeholder = required<HTMLElement>("#camera-placeholder");
const toggle = required<HTMLButtonElement>("#camera-toggle");
const runtimeStatus = required<HTMLElement>("#runtime-status");
const handStatus = required<HTMLElement>("#hand-status");
const gestureStatus = required<HTMLElement>("#gesture-status");
const lastAction = required<HTMLElement>("#last-action");
const message = required<HTMLElement>("#panel-message");
const directionButtons = Array.from(document.querySelectorAll<HTMLButtonElement>("[data-direction]"));

const overlay = new CameraOverlay(video, canvas);
const detector = new SwipeDetector();
let tracker: HandTracker | null = null;
let running = false;

const directionText: Record<SwipeDirection, string> = {
  up: "向上",
  down: "向下",
  left: "向左",
  right: "向右",
};

function setStatus(text: string, state: "idle" | "active" | "error" = "idle"): void {
  runtimeStatus.textContent = text;
  runtimeStatus.classList.toggle("is-active", state === "active");
  runtimeStatus.classList.toggle("is-error", state === "error");
}

function showMessage(text: string, isError = false): void {
  message.textContent = text;
  message.classList.toggle("is-error", isError);
}

function flashDirection(direction: SwipeDirection): void {
  for (const button of directionButtons) {
    button.classList.toggle("is-active", button.dataset.direction === direction);
  }
  window.setTimeout(() => {
    for (const button of directionButtons) button.classList.remove("is-active");
  }, 420);
}

async function sendRequest(request: ExtensionRequest): Promise<ExtensionResponse> {
  try {
    const response = (await chrome.runtime.sendMessage(request)) as ExtensionResponse | undefined;
    return response ?? { ok: false, message: "插件后台没有响应。" };
  } catch {
    return { ok: false, message: "插件后台连接失败，请重新打开侧边栏。" };
  }
}

async function executeDirection(direction: SwipeDirection): Promise<void> {
  const request: ExtensionRequest = {
    type: "gesture-action",
    action: swipeDirectionToAction(direction),
    direction,
    timestamp: Date.now(),
  };
  const response = await sendRequest(request);
  lastAction.textContent = directionText[direction];
  flashDirection(direction);
  showMessage(response.message, !response.ok);
}

function handleHandState(state: HandControlState): void {
  overlay.draw(state);
  if (!state.detected) {
    handStatus.textContent = "寻找手掌";
    gestureStatus.textContent = "请把一只手放入画面";
    detector.update(state, performance.now());
    return;
  }
  handStatus.textContent = `${state.handedness === "Left" ? "左手" : "右手"} · ${Math.round(state.confidence * 100)}%${state.stale ? " · 续帧" : ""}`;
  gestureStatus.textContent = state.gesture === "Open_Palm" ? "张开手掌，可以挥动" : "请张开手掌";
  const direction = detector.update(state, performance.now());
  if (direction) void executeDirection(direction);
}

function stopCamera(): void {
  tracker?.stop();
  detector.reset();
  running = false;
  placeholder.classList.remove("is-hidden");
  toggle.textContent = "启动摄像头";
  handStatus.textContent = "等待摄像头";
  gestureStatus.textContent = "挥动手掌控制网页";
  setStatus("已停止");
}

function handleTrackerError(text: string): void {
  stopCamera();
  setStatus("启动失败", "error");
  showMessage(text, true);
}

async function startCamera(): Promise<void> {
  toggle.disabled = true;
  setStatus("连接网页");
  showMessage("正在连接当前标签页…");
  const activation = await sendRequest({ type: "activate-tab" });
  if (!activation.ok) {
    toggle.disabled = false;
    setStatus("页面不可用", "error");
    showMessage(activation.message, true);
    return;
  }

  setStatus("加载模型");
  showMessage("正在启动本机手势模型…");
  try {
    tracker ??= new HandTracker(video, handleHandState, handleTrackerError);
    await tracker.start();
    running = true;
    placeholder.classList.add("is-hidden");
    toggle.textContent = "停止摄像头";
    setStatus("识别中", "active");
    showMessage("当前标签页已连接，张开手掌开始挥动。");
  } catch (error) {
    const text =
      error instanceof DOMException && error.name === "NotAllowedError"
        ? "摄像头权限被拒绝，请在 Chrome 设置中允许后重试。"
        : error instanceof Error
          ? error.message
          : String(error);
    handleTrackerError(text);
  } finally {
    toggle.disabled = false;
  }
}

toggle.addEventListener("click", () => {
  if (running) stopCamera();
  else void startCamera();
});

window.addEventListener("pagehide", stopCamera);
