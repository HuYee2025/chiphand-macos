import "./sidepanel.css";
import { CameraOverlay } from "../src/camera-overlay";
import { EMPTY_HAND_STATE, type SwipeDirection } from "../src/types";
import { isTrackerEvent, type ExtensionRequest, type ExtensionResponse } from "./message-types";

function required<T extends Element>(selector: string): T {
  const element = document.querySelector<T>(selector);
  if (!element) throw new Error(`缺少插件界面元素：${selector}`);
  return element;
}

const placeholder = required<HTMLElement>("#camera-placeholder");
const placeholderLabel = required<HTMLElement>("#camera-placeholder-label");
const previewVideo = required<HTMLVideoElement>("#camera-video");
const previewCanvas = required<HTMLCanvasElement>("#landmark-canvas");
const toggle = required<HTMLButtonElement>("#camera-toggle");
const runtimeStatus = required<HTMLElement>("#runtime-status");
const handStatus = required<HTMLElement>("#hand-status");
const gestureStatus = required<HTMLElement>("#gesture-status");
const lastAction = required<HTMLElement>("#last-action");
const message = required<HTMLElement>("#panel-message");
const panelShell = required<HTMLElement>("#panel-shell");
const directionIndicators = Array.from(document.querySelectorAll<HTMLElement>("[data-direction]"));
const cameraOverlay = new CameraOverlay(previewVideo, previewCanvas);

let running = false;
let pointerInside = false;
let closeTimer: number | null = null;
let previewStream: MediaStream | null = null;
let previewStarting: Promise<void> | null = null;
const AUTO_CLOSE_MS = 5_000;
const LEAVE_CLOSE_MS = 450;
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

function clearAutoClose(): void {
  if (closeTimer !== null) window.clearTimeout(closeTimer);
  closeTimer = null;
}

function scheduleAutoClose(delay = AUTO_CLOSE_MS): void {
  clearAutoClose();
  closeTimer = window.setTimeout(() => {
    if (running && !pointerInside && !panelShell.matches(":hover")) window.close();
  }, delay);
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
  window.setTimeout(() => {
    for (const indicator of directionIndicators) indicator.classList.remove("is-active");
  }, 620);
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
    placeholder.classList.toggle("is-hidden", previewStream !== null);
    placeholderLabel.textContent = "BACKGROUND ACTIVE";
    toggle.textContent = "停止摄像头";
    handStatus.textContent = "后台识别中";
    gestureStatus.textContent = "点击网页不会中断手势";
    setStatus("识别中", "active");
    if (detail) showMessage(detail);
    if (previewStream === null) {
      void ensurePreview().then(
        () => {
          if (running) setRunning(true);
        },
        () => {
          if (running) showMessage("后台识别正在运行，但这个控制窗口暂时无法显示预览。请点击“停止摄像头”后重新启动。", true);
        },
      );
    }
    if (!pointerInside && !panelShell.matches(":hover")) scheduleAutoClose();
    return;
  }
  clearAutoClose();
  stopPreview();
  placeholder.classList.remove("is-hidden");
  placeholderLabel.textContent = "CAMERA OFF";
  toggle.textContent = "启动摄像头";
  handStatus.textContent = "等待摄像头";
  gestureStatus.textContent = "挥动手掌控制网页";
  setStatus("已停止");
  if (detail) showMessage(detail);
}

async function ensurePreview(): Promise<void> {
  if (previewStream !== null) return;
  if (previewStarting !== null) return previewStarting;
  previewStarting = (async () => {
    const stream = await navigator.mediaDevices.getUserMedia({
      audio: false,
      video: { facingMode: "user", width: { ideal: 640 }, height: { ideal: 480 }, frameRate: { ideal: 30, max: 30 } },
    });
    previewStream = stream;
    previewVideo.srcObject = stream;
    await previewVideo.play();
    placeholder.classList.add("is-hidden");
  })().finally(() => {
    previewStarting = null;
  });
  return previewStarting;
}

function stopPreview(): void {
  previewStream?.getTracks().forEach((track) => track.stop());
  previewStream = null;
  previewStarting = null;
  previewVideo.srcObject = null;
  cameraOverlay.draw(EMPTY_HAND_STATE);
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
    await ensurePreview();
    const response = await sendRequest({ type: "start-background-tracking", tabId: targetTabId });
    if (!response.ok) throw new Error(response.message);
    setRunning(true, "摄像头预览已打开；后台识别已启动。现在可以直接点击网页。");
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
  pointerInside = true;
  clearAutoClose();
});

panelShell.addEventListener("pointerleave", () => {
  pointerInside = false;
  if (running) scheduleAutoClose(LEAVE_CLOSE_MS);
});

chrome.runtime.onMessage.addListener((event: unknown) => {
  if (!isTrackerEvent(event)) return;
  if (event.type === "background-hand-state") {
    cameraOverlay.draw(event.state);
    if (event.state.detected) {
      handStatus.textContent = `已检测到${event.state.handedness === "Left" ? "左手" : "右手"} ${Math.round(event.state.confidence * 100)}%`;
      gestureStatus.textContent =
        event.state.gesture === "Pinch"
          ? "已捏合 · 上下拖动页面"
          : event.state.gesture === "Open_Palm"
            ? "张开手掌，可左右挥动翻页"
            : "张开手掌翻页，或拇指食指捏合滚动";
    } else {
      handStatus.textContent = "寻找手掌";
      gestureStatus.textContent = "请把一只手完整放入画面";
    }
    return;
  }
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

window.addEventListener("pagehide", () => {
  clearAutoClose();
  stopPreview();
});
void refreshBackgroundStatus();
