import type { ContentScriptRequest, ExtensionRequest, ExtensionResponse } from "./message-types";
import { pinchDeltaToScrollPixels } from "../src/pinch-scroll-detector";
import type { GestureAction, HandControlState, PageActionAdapter, SwipeDirection } from "../src/types";

declare global {
  interface Window {
    __gestureBrowserControlInstalled?: boolean;
  }
}

const OVERLAY_ID = "__gesture_browser_indicator__";

type GestureIndicator = {
  setTracking(active: boolean, message: string): void;
  flash(direction: SwipeDirection): void;
  drawHand(state: HandControlState): void;
};

const HAND_CONNECTIONS = [
  [0, 1], [1, 2], [2, 3], [3, 4],
  [0, 5], [5, 6], [6, 7], [7, 8],
  [5, 9], [9, 10], [10, 11], [11, 12],
  [9, 13], [13, 14], [14, 15], [15, 16],
  [13, 17], [17, 18], [18, 19], [19, 20], [0, 17],
] as const;

function createIndicator(): GestureIndicator {
  const existing = document.getElementById(OVERLAY_ID);
  if (existing?.shadowRoot) {
    const indicator = (existing.shadowRoot.querySelector("#indicator") as HTMLElement | null)?.__gestureIndicator;
    if (indicator) return indicator;
  }

  const host = document.createElement("div");
  host.id = OVERLAY_ID;
  host.style.cssText = "position:fixed;inset:0;z-index:2147483647;pointer-events:none;";
  const shadow = host.attachShadow({ mode: "open" });
  shadow.innerHTML = `
    <style>
      :host { all: initial; }
      #hand-overlay { position: fixed; inset: 0; width: 100%; height: 100%; pointer-events: none; }
      #indicator {
        position: fixed; right: 14px; top: 50%; width: 88px; height: 88px; display: grid; place-items: center; overflow: hidden;
        border: 1px solid #171717; border-radius: 9px; background: #090909; color: #c0ffd0;
        box-shadow: 0 8px 24px rgba(0,0,0,.22); cursor: pointer;
        font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
        transition: border-color .2s ease, background .2s ease;
      }
      #arrow { color: #c0ffd0; font: 700 58px/1 system-ui, sans-serif; opacity: 0; transform: scale(.72); transition: opacity .15s ease, transform .15s ease, text-shadow .15s ease; }
      #indicator.is-gesture { border-color: #3e7450; background: #0e1710; }
      #indicator.is-gesture #arrow { opacity: 1; transform: scale(1); text-shadow: 0 0 18px #65d985; }
      #status { position: absolute; bottom: 13px; width: 100%; color: #85827a; font: 700 9px/1.35 ui-monospace, SFMono-Regular, Menlo, monospace; transition: opacity .15s ease; text-align: center; }
      #indicator.is-gesture #status { opacity: 0; }
      @media (prefers-reduced-motion: reduce) { #indicator, #arrow, #status { transition: none; } }
    </style>
    <canvas id="hand-overlay" aria-hidden="true"></canvas>
    <div id="indicator" aria-label="手势浏览识别状态，点击查看摄像头" role="button" tabindex="0">
      <span id="arrow" aria-hidden="true"></span>
      <span id="status">未启动</span>
    </div>
  `;
  document.documentElement.append(host);

  const root = shadow.querySelector<HTMLElement>("#indicator");
  const arrow = shadow.querySelector<HTMLElement>("#arrow");
  const status = shadow.querySelector<HTMLElement>("#status");
  const handOverlay = shadow.querySelector<HTMLCanvasElement>("#hand-overlay");
  const handContext = handOverlay?.getContext("2d");
  if (!root || !arrow || !status || !handOverlay || !handContext) throw new Error("无法创建手势状态提示。");

  let tracking = false;
  let gestureTimer: number | null = null;
  let latestHandState: HandControlState | null = null;
  const openController = (): void => {
    const request: ExtensionRequest = { type: "open-controller" };
    void chrome.runtime.sendMessage(request).catch(() => undefined);
  };
  root.addEventListener("click", openController);
  root.addEventListener("keydown", (event) => {
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      openController();
    }
  });

  const drawHand = (state: HandControlState): void => {
    latestHandState = state;
    const width = window.innerWidth;
    const height = window.innerHeight;
    const pixelRatio = window.devicePixelRatio || 1;
    const targetWidth = Math.max(1, Math.round(width * pixelRatio));
    const targetHeight = Math.max(1, Math.round(height * pixelRatio));
    if (handOverlay.width !== targetWidth || handOverlay.height !== targetHeight) {
      handOverlay.width = targetWidth;
      handOverlay.height = targetHeight;
    }
    handContext.setTransform(pixelRatio, 0, 0, pixelRatio, 0, 0);
    handContext.clearRect(0, 0, width, height);
    if (!state.detected || state.landmarks.length === 0) return;

    const pointAt = (index: number): { x: number; y: number } | null => {
      const landmark = state.landmarks[index];
      return landmark ? { x: (1 - landmark.x) * width, y: landmark.y * height } : null;
    };
    handContext.save();
    handContext.globalAlpha = state.stale ? 0.28 : 0.5;
    handContext.strokeStyle = "#71d78d";
    handContext.lineWidth = 2;
    handContext.lineCap = "round";
    handContext.lineJoin = "round";
    for (const [startIndex, endIndex] of HAND_CONNECTIONS) {
      const start = pointAt(startIndex);
      const end = pointAt(endIndex);
      if (!start || !end) continue;
      handContext.beginPath();
      handContext.moveTo(start.x, start.y);
      handContext.lineTo(end.x, end.y);
      handContext.stroke();
    }
    handContext.fillStyle = "#b7f5c7";
    for (let index = 0; index < state.landmarks.length; index += 1) {
      const point = pointAt(index);
      if (!point) continue;
      handContext.beginPath();
      handContext.arc(point.x, point.y, index === 0 ? 4 : 2.5, 0, Math.PI * 2);
      handContext.fill();
    }
    if (state.gesture === "Pinch") {
      const thumb = pointAt(4);
      const index = pointAt(8);
      if (thumb && index) {
        const x = (thumb.x + index.x) / 2;
        const y = (thumb.y + index.y) / 2;
        handContext.globalAlpha = 1;
        handContext.beginPath();
        handContext.arc(x, y, 11, 0, Math.PI * 2);
        handContext.fillStyle = "#f8d84e";
        handContext.shadowColor = "#f8d84e";
        handContext.shadowBlur = 20;
        handContext.fill();
        handContext.lineWidth = 2;
        handContext.strokeStyle = "#fff6b0";
        handContext.stroke();
      }
    }
    handContext.restore();
  };
  window.addEventListener("resize", () => {
    if (latestHandState) drawHand(latestHandState);
  });

  const indicator: GestureIndicator = {
    setTracking(active, detail): void {
      tracking = active;
      status.textContent = active ? "手势识别中" : "已停止";
      root.setAttribute("aria-label", active ? "手势识别中，点击查看摄像头" : "手势识别已停止，点击打开控制窗口");
      if (!active) {
        root.classList.remove("is-gesture");
        arrow.textContent = "";
      }
      if (detail && active) root.title = detail;
    },
    flash(direction): void {
      if (!tracking) return;
      const arrows: Record<SwipeDirection, string> = { up: "↑", down: "↓", left: "←", right: "→" };
      arrow.textContent = arrows[direction];
      root.classList.add("is-gesture");
      if (gestureTimer !== null) window.clearTimeout(gestureTimer);
      gestureTimer = window.setTimeout(() => {
        root.classList.remove("is-gesture");
        arrow.textContent = "";
      }, 620);
    },
    drawHand,
  };
  root.__gestureIndicator = indicator;
  return indicator;
}

declare global {
  interface HTMLElement {
    __gestureIndicator?: GestureIndicator;
  }
}

function isEditable(element: Element | null): boolean {
  if (!(element instanceof HTMLElement)) return false;
  return (
    element.isContentEditable ||
    element instanceof HTMLInputElement ||
    element instanceof HTMLTextAreaElement ||
    element instanceof HTMLSelectElement ||
    Boolean(element.closest("[contenteditable='true'], [role='textbox']"))
  );
}

function dispatchArrow(key: "ArrowLeft" | "ArrowRight"): void {
  const target = document.activeElement instanceof HTMLElement ? document.activeElement : document.body;
  const keyCode = key === "ArrowLeft" ? 37 : 39;
  const options: KeyboardEventInit = {
    key,
    code: key,
    keyCode,
    which: keyCode,
    bubbles: true,
    cancelable: true,
    composed: true,
  };
  target.dispatchEvent(new KeyboardEvent("keydown", options));
  target.dispatchEvent(new KeyboardEvent("keyup", options));
}

const genericAdapter: PageActionAdapter = {
  id: "generic-page",
  canHandle: () => true,
  execute(action: GestureAction): boolean {
    if (action === "scroll-up" || action === "scroll-down") {
      const direction = action === "scroll-up" ? -1 : 1;
      window.scrollBy({ top: direction * window.innerHeight * 0.75, behavior: "smooth" });
      return true;
    }
    dispatchArrow(action === "page-prev" ? "ArrowLeft" : "ArrowRight");
    return true;
  },
};

const adapters: PageActionAdapter[] = [genericAdapter];

function executeAction(action: GestureAction): ExtensionResponse {
  if (isEditable(document.activeElement)) {
    return { ok: false, message: "正在编辑文字，已忽略手势。" };
  }
  const url = new URL(window.location.href);
  const adapter = adapters.find((candidate) => candidate.canHandle(action, url));
  if (!adapter || !adapter.execute(action)) {
    return { ok: false, message: "当前网页不支持这个动作。" };
  }
  return {
    ok: true,
    message: action.startsWith("scroll") ? "页面已滚动。" : "已发送左右翻页动作。",
    adapterId: adapter.id,
  };
}

function executePinchScroll(deltaY: number): ExtensionResponse {
  if (isEditable(document.activeElement)) {
    return { ok: false, message: "正在编辑文字，已忽略捏合滚动。" };
  }
  if (Math.abs(deltaY) < 0.003) return { ok: true, message: "捏合已就位。" };
  window.scrollBy({ top: pinchDeltaToScrollPixels(deltaY, window.innerHeight), behavior: "auto" });
  return { ok: true, message: "捏合滚动中。", adapterId: "generic-page" };
}

if (!window.__gestureBrowserControlInstalled) {
  window.__gestureBrowserControlInstalled = true;
  const indicator = createIndicator();
  chrome.runtime.onMessage.addListener(
    (
      request: ContentScriptRequest | Extract<ExtensionRequest, { type: "open-controller" }>,
      _sender,
      sendResponse: (response: ExtensionResponse) => void,
    ) => {
      if (request.type === "open-controller") return;
      if (request.type === "gesture-control-ping") {
        sendResponse({ ok: true, message: "网页控制已连接。" });
        return;
      }
      if (request.type === "gesture-overlay-status") {
        indicator.setTracking(request.active, request.message);
        sendResponse({ ok: true, message: "页面内提示已更新。" });
        return;
      }
      if (request.type === "gesture-overlay-gesture") {
        indicator.flash(request.direction);
        sendResponse({ ok: true, message: "页面内手势提示已更新。" });
        return;
      }
      if (request.type === "gesture-overlay-hand-state") {
        indicator.drawHand(request.state);
        sendResponse({ ok: true, message: "网页手势坐标已更新。" });
        return;
      }
      if (request.type === "execute-pinch-scroll") {
        sendResponse(executePinchScroll(request.deltaY));
        return;
      }
      sendResponse(executeAction(request.action));
    },
  );
}
