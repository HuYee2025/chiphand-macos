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
const panelShell = required<HTMLElement>("#panel-shell");
const compactToggle = required<HTMLButtonElement>("#compact-toggle");
const directionButtons = Array.from(document.querySelectorAll<HTMLButtonElement>("[data-direction]"));

const overlay = new CameraOverlay(video, canvas);
const detector = new SwipeDetector();
let tracker: HandTracker | null = null;
let running = false;
let compact = false;
let collapseTimer: number | null = null;
const AUTO_COLLAPSE_MS = 5_000;
const FULL_WINDOW = { width: 390, height: 720 };
const COMPACT_WINDOW = { width: 92, height: 142 };
const targetTabId = (() => {
  const value = Number(new URLSearchParams(window.location.search).get("tabId"));
  return Number.isInteger(value) && value > 0 ? value : null;
})();

const directionText: Record<SwipeDirection, string> = {
  up: "向上",
  down: "向下",
  left: "向左",
  right: "向右",
};

function clearAutoCollapse(): void {
  if (collapseTimer !== null) window.clearTimeout(collapseTimer);
  collapseTimer = null;
}

async function resizeController(compactMode: boolean): Promise<void> {
  try {
    const currentWindow = await chrome.windows.getCurrent();
    if (currentWindow.id === undefined) return;
    const size = compactMode ? COMPACT_WINDOW : FULL_WINDOW;
    const left = Math.round(window.screen.availWidth - size.width);
    const top = compactMode
      ? Math.round(Math.max(72, (window.screen.availHeight - size.height) / 2))
      : undefined;
    await chrome.windows.update(currentWindow.id, { ...size, left, ...(top === undefined ? {} : { top }) });
  } catch {
    // 窗口在关闭或系统拒绝改尺寸时，仍保留可点击的页面内收起状态。
  }
}

async function setCompact(nextCompact: boolean): Promise<void> {
  compact = nextCompact;
  panelShell.classList.toggle("is-compact", compact);
  compactToggle.textContent = compact ? "展开" : "收起";
  compactToggle.setAttribute("aria-label", compact ? "展开手势控制" : "收起手势控制");
  await resizeController(compact);
}

function scheduleAutoCollapse(): void {
  clearAutoCollapse();
  collapseTimer = window.setTimeout(() => {
    if (running && !compact) void setCompact(true);
  }, AUTO_COLLAPSE_MS);
}

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
  if (targetTabId === null) {
    showMessage("没有关联网页。请回到目标网页后，从插件图标重新打开控制窗口。", true);
    return;
  }
  const request: ExtensionRequest = {
    type: "gesture-action",
    action: swipeDirectionToAction(direction),
    direction,
    timestamp: Date.now(),
    tabId: targetTabId,
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
  clearAutoCollapse();
  tracker?.stop();
  detector.reset();
  running = false;
  placeholder.classList.remove("is-hidden");
  toggle.textContent = "启动摄像头";
  handStatus.textContent = "等待摄像头";
  gestureStatus.textContent = "挥动手掌控制网页";
  setStatus("已停止");
  if (compact) void setCompact(false);
}

function handleTrackerError(text: string): void {
  stopCamera();
  setStatus("启动失败", "error");
  showMessage(text, true);
}

async function connectCurrentTab(): Promise<void> {
  if (targetTabId === null) {
    showMessage("摄像头已启动，但没有关联网页。请从目标网页点击插件图标。", true);
    return;
  }
  const activation = await sendRequest({ type: "activate-tab", tabId: targetTabId });
  if (activation.ok) {
    showMessage("摄像头和当前网页已连接，张开手掌开始挥动。");
    return;
  }
  showMessage(`摄像头已启动，但网页暂未连接。${activation.message}`, true);
}

async function startCamera(): Promise<void> {
  toggle.disabled = true;
  setStatus("加载模型");
  showMessage("正在请求摄像头权限并加载本机模型…");
  try {
    tracker ??= new HandTracker(video, handleHandState, handleTrackerError);
    await tracker.start();
    running = true;
    placeholder.classList.add("is-hidden");
    toggle.textContent = "停止摄像头";
    setStatus("识别中", "active");
    showMessage("摄像头已启动，正在连接当前网页…");
    void connectCurrentTab();
    scheduleAutoCollapse();
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

compactToggle.addEventListener("click", () => {
  if (compact) {
    void setCompact(false);
    if (running) scheduleAutoCollapse();
    return;
  }
  clearAutoCollapse();
  void setCompact(true);
});

window.addEventListener("pagehide", () => {
  clearAutoCollapse();
  stopCamera();
});
