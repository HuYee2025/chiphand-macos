import "./sidepanel.css";
import type { SwipeDirection } from "../src/types";
import { isTrackerEvent, type ExtensionRequest, type ExtensionResponse } from "./message-types";

function required<T extends Element>(selector: string): T {
  const element = document.querySelector<T>(selector);
  if (!element) throw new Error(`缺少插件界面元素：${selector}`);
  return element;
}

const placeholder = required<HTMLElement>("#camera-placeholder");
const placeholderLabel = required<HTMLElement>("#camera-placeholder-label");
const toggle = required<HTMLButtonElement>("#camera-toggle");
const runtimeStatus = required<HTMLElement>("#runtime-status");
const handStatus = required<HTMLElement>("#hand-status");
const gestureStatus = required<HTMLElement>("#gesture-status");
const lastAction = required<HTMLElement>("#last-action");
const message = required<HTMLElement>("#panel-message");
const panelShell = required<HTMLElement>("#panel-shell");
const compactActiveGesture = required<HTMLElement>("#compact-active-gesture");
const directionIndicators = Array.from(document.querySelectorAll<HTMLElement>("[data-direction]"));

let running = false;
let compact = false;
let collapseTimer: number | null = null;
const AUTO_COLLAPSE_MS = 5_000;
const LEAVE_COLLAPSE_MS = 450;
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

const directionArrow: Record<SwipeDirection, string> = {
  up: "↑",
  down: "↓",
  left: "←",
  right: "→",
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
    const top = Math.round(Math.max(72, (window.screen.availHeight - size.height) / 2));
    await chrome.windows.update(currentWindow.id, { ...size, left, top });
  } catch {
    // 窗口关闭或系统拒绝改尺寸时，后台识别仍会继续。
  }
}

async function setCompact(nextCompact: boolean): Promise<void> {
  compact = nextCompact;
  panelShell.classList.toggle("is-compact", compact);
  await resizeController(compact);
}

function scheduleAutoCollapse(delay = AUTO_COLLAPSE_MS): void {
  clearAutoCollapse();
  collapseTimer = window.setTimeout(() => {
    if (running && !compact) void setCompact(true);
  }, delay);
}

function expandOnHover(): void {
  if (!compact) return;
  clearAutoCollapse();
  void setCompact(false);
  scheduleAutoCollapse();
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
  for (const indicator of directionIndicators) {
    indicator.classList.toggle("is-active", indicator.dataset.direction === direction);
  }
  compactActiveGesture.textContent = directionArrow[direction];
  compactActiveGesture.classList.add("is-active");
  window.setTimeout(() => {
    for (const indicator of directionIndicators) indicator.classList.remove("is-active");
    compactActiveGesture.classList.remove("is-active");
  }, 620);
  window.setTimeout(() => {
    if (!compactActiveGesture.classList.contains("is-active")) compactActiveGesture.textContent = "";
  }, 820);
}

async function sendRequest(request: ExtensionRequest): Promise<ExtensionResponse> {
  try {
    const response = (await chrome.runtime.sendMessage(request)) as ExtensionResponse | undefined;
    return response ?? { ok: false, message: "插件后台没有响应。" };
  } catch {
    return { ok: false, message: "插件后台连接失败，请重新打开插件。" };
  }
}

function setRunning(active: boolean, detail?: string): void {
  running = active;
  if (active) {
    placeholder.classList.remove("is-hidden");
    placeholderLabel.textContent = "BACKGROUND ACTIVE";
    toggle.textContent = "停止摄像头";
    handStatus.textContent = "后台识别中";
    gestureStatus.textContent = "点击网页不会中断手势";
    setStatus("识别中", "active");
    if (detail) showMessage(detail);
    scheduleAutoCollapse();
    return;
  }
  clearAutoCollapse();
  placeholder.classList.remove("is-hidden");
  placeholderLabel.textContent = "CAMERA OFF";
  toggle.textContent = "启动摄像头";
  handStatus.textContent = "等待摄像头";
  gestureStatus.textContent = "挥动手掌控制网页";
  setStatus("已停止");
  if (compact) void setCompact(false);
  if (detail) showMessage(detail);
}

async function requestCameraPermission(): Promise<void> {
  const stream = await navigator.mediaDevices.getUserMedia({
    audio: false,
    video: { facingMode: "user", width: { ideal: 640 }, height: { ideal: 480 }, frameRate: { ideal: 30, max: 30 } },
  });
  stream.getTracks().forEach((track) => track.stop());
}

async function startCamera(): Promise<void> {
  if (targetTabId === null) {
    showMessage("没有关联网页。请回到目标网页后，从插件图标重新打开控制窗口。", true);
    return;
  }
  toggle.disabled = true;
  setStatus("授权摄像头");
  showMessage("正在授权摄像头，并把识别移入后台…");
  try {
    await requestCameraPermission();
    const response = await sendRequest({ type: "start-background-tracking", tabId: targetTabId });
    if (!response.ok) throw new Error(response.message);
    setRunning(true, "后台识别已启动。现在可以直接点击网页。\n");
  } catch (error) {
    const text =
      error instanceof DOMException && error.name === "NotAllowedError"
        ? "摄像头权限被拒绝，请在 Chrome 设置中允许后重试。"
        : error instanceof Error
          ? error.message
          : String(error);
    setRunning(false);
    setStatus("启动失败", "error");
    showMessage(text, true);
  } finally {
    toggle.disabled = false;
  }
}

async function stopCamera(): Promise<void> {
  toggle.disabled = true;
  const response = await sendRequest({ type: "stop-background-tracking" });
  setRunning(false, response.message);
  toggle.disabled = false;
}

async function refreshBackgroundStatus(): Promise<void> {
  const response = await sendRequest({ type: "get-background-tracker-status" });
  if (response.trackingActive) setRunning(true, response.message);
}

toggle.addEventListener("click", () => {
  if (running) void stopCamera();
  else void startCamera();
});

panelShell.addEventListener("pointerenter", () => {
  if (running) expandOnHover();
});

panelShell.addEventListener("pointerleave", () => {
  if (running && !compact) scheduleAutoCollapse(LEAVE_COLLAPSE_MS);
});

chrome.runtime.onMessage.addListener((event: unknown) => {
  if (!isTrackerEvent(event)) return;
  if (event.type === "background-tracker-status") {
    if (event.active) setRunning(true, event.message);
    else {
      setRunning(false);
      setStatus("启动失败", "error");
      showMessage(event.message, true);
    }
    return;
  }
  lastAction.textContent = directionText[event.direction];
  flashDirection(event.direction);
  showMessage(event.message, !event.ok);
});

window.addEventListener("pagehide", clearAutoCollapse);
void refreshBackgroundStatus();
