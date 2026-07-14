import "./sidepanel.css";
import { CameraOverlay } from "../src/camera-overlay";
import { DEFAULT_GESTURE_SETTINGS, normalizeGestureSettings, sensitivityLabel, type GestureSettings } from "../src/gesture-settings";
import { EMPTY_HAND_STATE } from "../src/types";
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
const advancedToggle = required<HTMLButtonElement>("#advanced-toggle");
const advancedSettings = required<HTMLElement>("#advanced-settings");
const swipeSensitivity = required<HTMLInputElement>("#swipe-sensitivity");
const pinchSensitivity = required<HTMLInputElement>("#pinch-sensitivity");
const showHandGrid = required<HTMLInputElement>("#show-hand-grid");
const showPinchDot = required<HTMLInputElement>("#show-pinch-dot");
const swipeSensitivityValue = required<HTMLOutputElement>("#swipe-sensitivity-value");
const pinchSensitivityValue = required<HTMLOutputElement>("#pinch-sensitivity-value");
const runtimeStatus = required<HTMLElement>("#runtime-status");
const handStatus = required<HTMLElement>("#hand-status");
const gestureStatus = required<HTMLElement>("#gesture-status");
const message = required<HTMLElement>("#panel-message");
const panelShell = required<HTMLElement>("#panel-shell");
const cameraOverlay = new CameraOverlay(previewVideo, previewCanvas);

let running = false;
let pointerInside = false;
let closeTimer: number | null = null;
let previewStream: MediaStream | null = null;
let previewStarting: Promise<void> | null = null;
let advancedOpen = false;
let settingsSaveTimer: number | null = null;
const LEAVE_CLOSE_MS = 450;
const targetTabId = (() => {
  const value = Number(new URLSearchParams(window.location.search).get("tabId"));
  return Number.isInteger(value) && value > 0 ? value : null;
})();

function clearAutoClose(): void {
  if (closeTimer !== null) window.clearTimeout(closeTimer);
  closeTimer = null;
}

function scheduleAutoClose(delay = LEAVE_CLOSE_MS): void {
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
  message.textContent = isError ? text : "";
  message.classList.toggle("is-error", isError);
}

function setCameraToggle(active: boolean): void {
  const label = active ? "关闭摄像头" : "开启摄像头";
  toggle.textContent = label;
  toggle.setAttribute("aria-label", label);
  toggle.title = label;
}

function formatSensitivity(value: number): string {
  return `${value} · ${sensitivityLabel(value)}`;
}

function readSettingsFromControls(): GestureSettings {
  return normalizeGestureSettings({
    swipeSensitivity: Number(swipeSensitivity.value),
    pinchSensitivity: Number(pinchSensitivity.value),
    showHandGrid: showHandGrid.checked,
    showPinchDot: showPinchDot.checked,
  });
}

function renderSettings(settings: GestureSettings): void {
  const normalized = normalizeGestureSettings(settings);
  swipeSensitivity.value = String(normalized.swipeSensitivity);
  pinchSensitivity.value = String(normalized.pinchSensitivity);
  showHandGrid.checked = normalized.showHandGrid;
  showPinchDot.checked = normalized.showPinchDot;
  swipeSensitivityValue.value = formatSensitivity(normalized.swipeSensitivity);
  pinchSensitivityValue.value = formatSensitivity(normalized.pinchSensitivity);
}

function setAdvancedOpen(expanded: boolean): void {
  advancedOpen = expanded;
  advancedSettings.hidden = !expanded;
  advancedToggle.setAttribute("aria-expanded", String(expanded));
  void sendRequest({ type: "set-controller-advanced", expanded, ...(targetTabId === null ? {} : { tabId: targetTabId }) });
}

function scheduleSettingsSave(): void {
  if (settingsSaveTimer !== null) window.clearTimeout(settingsSaveTimer);
  settingsSaveTimer = window.setTimeout(() => {
    settingsSaveTimer = null;
    void sendRequest({
      type: "update-gesture-settings",
      settings: readSettingsFromControls(),
      ...(targetTabId === null ? {} : { tabId: targetTabId }),
    }).then((response) => {
      if (!response.ok) showMessage(response.message, true);
    });
  }, 90);
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
    advancedToggle.hidden = false;
    placeholder.classList.toggle("is-hidden", previewStream !== null);
    placeholderLabel.textContent = "BACKGROUND ACTIVE";
    setCameraToggle(true);
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
    return;
  }
  clearAutoClose();
  if (advancedOpen) setAdvancedOpen(false);
  advancedToggle.hidden = true;
  stopPreview();
  placeholder.classList.remove("is-hidden");
  placeholderLabel.textContent = "CAMERA OFF";
  setCameraToggle(false);
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

advancedToggle.addEventListener("click", () => setAdvancedOpen(!advancedOpen));
for (const control of [swipeSensitivity, pinchSensitivity, showHandGrid, showPinchDot]) {
  control.addEventListener("input", () => {
    renderSettings(readSettingsFromControls());
    scheduleSettingsSave();
  });
}

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
            ? "张开手掌，可左右挥动滚动"
            : "左右挥动翻屏，或拇指食指捏合滚动";
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
  showMessage(event.message, !event.ok);
});

window.addEventListener("pagehide", () => {
  clearAutoClose();
  if (settingsSaveTimer !== null) window.clearTimeout(settingsSaveTimer);
  stopPreview();
});
window.addEventListener("blur", () => {
  if (running) scheduleAutoClose(120);
});
void (async () => {
  const response = await sendRequest({ type: "get-gesture-settings" });
  renderSettings(response.settings ?? DEFAULT_GESTURE_SETTINGS);
  await refreshBackgroundStatus();
})();
