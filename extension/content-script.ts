import type { ContentScriptRequest, ExtensionRequest, ExtensionResponse } from "./message-types";
import type { GestureAction, HandControlState, PageActionAdapter, SwipeDirection } from "../src/types";

declare global {
  interface Window {
    __gestureBrowserControlInstalled?: boolean;
  }
}

const OVERLAY_ID = "__gesture_browser_indicator__";
const PINCH_DOT_ID = "__gesture_browser_pinch_dot__";

// Content Script 通过 chrome.scripting.executeScript 注入。保持它不依赖
// 运行时 import，确保每次注入都是独立、可执行的单文件。
function isContentScriptRequest(message: unknown): message is ContentScriptRequest {
  if (!message || typeof message !== "object" || !("type" in message)) return false;
  const type = (message as { type?: unknown }).type;
  return (
    type === "gesture-control-ping" ||
    type === "execute-gesture-action" ||
    type === "execute-pinch-scroll" ||
    type === "gesture-overlay-status" ||
    type === "gesture-overlay-gesture" ||
    type === "gesture-overlay-hand-state" ||
    type === "gesture-overlay-controller" ||
    type === "gesture-overlay-settings"
  );
}

function pinchDeltaToScrollPixels(deltaY: number, viewportHeight: number): number {
  const bounded = Math.max(-0.12, Math.min(0.12, deltaY));
  return -bounded * viewportHeight * 1.8;
}

type GestureIndicator = {
  setTracking(active: boolean, message: string): void;
  flash(direction: SwipeDirection): void;
  drawHand(state: HandControlState): void;
  setControllerExpanded(expanded: boolean): void;
  setDeveloperOverlays(showHandGrid: boolean, showPinchDot: boolean): void;
};

const HAND_CONNECTIONS: ReadonlyArray<readonly [number, number]> = [
  [0, 1], [1, 2], [2, 3], [3, 4],
  [0, 5], [5, 6], [6, 7], [7, 8],
  [0, 9], [9, 10], [10, 11], [11, 12],
  [0, 13], [13, 14], [14, 15], [15, 16],
  [0, 17], [17, 18], [18, 19], [19, 20],
  [5, 9], [9, 13], [13, 17],
];

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
      #feedback-overlay { position: fixed; inset: 0; width: 100%; height: 100%; pointer-events: none; }
      #indicator {
        position: fixed; right: 6px; top: calc(50% + 132px); width: 28px; height: 28px; cursor: pointer;
        border: 1px solid #161616; border-radius: 50%; background: #090909;
        box-shadow: 0 3px 12px rgba(0,0,0,.18); pointer-events: auto; transform: scale(1);
        transform-origin: center; transition: opacity .24s ease, transform .24s cubic-bezier(.2,.9,.25,1);
      }
      #indicator.is-expanded { opacity: 0; transform: scale(11); pointer-events: none; }
      #indicator:focus-visible { outline: 2px solid #7ee49a; outline-offset: 3px; }
      @media (prefers-reduced-motion: reduce) { #indicator { transition: none; } }
    </style>
    <canvas id="feedback-overlay" aria-hidden="true"></canvas>
    <div id="indicator" aria-label="手势浏览识别状态，点击查看摄像头" role="button" tabindex="0">
    </div>
  `;
  document.documentElement.append(host);

  const root = shadow.querySelector<HTMLElement>("#indicator");
  const feedbackOverlay = shadow.querySelector<HTMLCanvasElement>("#feedback-overlay");
  const handContext = feedbackOverlay?.getContext("2d");
  if (!root || !feedbackOverlay || !handContext) throw new Error("无法创建手势状态提示。");

  // Shadow DOM establishes an isolated compositing group, so blend modes there
  // cannot see page pixels. The cursor must be a light-DOM sibling to invert
  // what is actually rendered beneath it.
  let pinchDot = document.getElementById(PINCH_DOT_ID) as HTMLElement | null;
  if (!pinchDot) {
    pinchDot = document.createElement("div");
    pinchDot.id = PINCH_DOT_ID;
    pinchDot.setAttribute("aria-hidden", "true");
    pinchDot.style.cssText = [
      "position:fixed",
      "width:28px",
      "height:28px",
      "border-radius:50%",
      "pointer-events:none",
      "z-index:2147483647",
      "opacity:0",
      "background:rgba(255,255,255,.001)",
      "backdrop-filter:invert(1)",
      "-webkit-backdrop-filter:invert(1)",
      "will-change:transform",
      "transform:translate3d(-100px,-100px,0) translate(-50%,-50%)",
    ].join(";");
    document.documentElement.append(pinchDot);
  }

  let tracking = false;
  let gestureTimer: number | null = null;
  let latestHandState: HandControlState | null = null;
  let activeDirection: Extract<SwipeDirection, "left" | "right"> | null = null;
  let targetPinchPoint: { x: number; y: number } | null = null;
  let renderedPinchPoint: { x: number; y: number } | null = null;
  let renderFrame: number | null = null;
  let showHandGrid = false;
  let showPinchDot = false;
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

  const renderFeedback = (): void => {
    const width = window.innerWidth;
    const height = window.innerHeight;
    const pixelRatio = window.devicePixelRatio || 1;
    const targetWidth = Math.max(1, Math.round(width * pixelRatio));
    const targetHeight = Math.max(1, Math.round(height * pixelRatio));
    if (feedbackOverlay.width !== targetWidth || feedbackOverlay.height !== targetHeight) {
      feedbackOverlay.width = targetWidth;
      feedbackOverlay.height = targetHeight;
    }
    handContext.setTransform(pixelRatio, 0, 0, pixelRatio, 0, 0);
    handContext.clearRect(0, 0, width, height);
    const landmarks = latestHandState?.landmarks;
    if (showHandGrid && latestHandState?.detected && !latestHandState.stale && landmarks && landmarks.length >= 21) {
      handContext.save();
      handContext.strokeStyle = "rgba(80, 154, 255, .8)";
      handContext.fillStyle = "rgba(112, 178, 255, .9)";
      handContext.lineWidth = 2;
      handContext.lineCap = "round";
      for (const [from, to] of HAND_CONNECTIONS) {
        const first = landmarks[from];
        const second = landmarks[to];
        if (!first || !second) continue;
        handContext.beginPath();
        handContext.moveTo((1 - first.x) * width, first.y * height);
        handContext.lineTo((1 - second.x) * width, second.y * height);
        handContext.stroke();
      }
      for (const point of landmarks) {
        handContext.beginPath();
        handContext.arc((1 - point.x) * width, point.y * height, 3, 0, Math.PI * 2);
        handContext.fill();
      }
      handContext.restore();
    }
    if (activeDirection === null) return;
    const size = Math.min(width * 0.34, height * 0.34);
    handContext.save();
    handContext.translate(width / 2, height / 2);
    if (activeDirection === "right") handContext.rotate(Math.PI);
    handContext.beginPath();
    handContext.moveTo(0, -size * 0.52);
    handContext.lineTo(-size * 0.42, -size * 0.1);
    handContext.lineTo(-size * 0.18, -size * 0.1);
    handContext.lineTo(-size * 0.18, size * 0.5);
    handContext.lineTo(size * 0.18, size * 0.5);
    handContext.lineTo(size * 0.18, -size * 0.1);
    handContext.lineTo(size * 0.42, -size * 0.1);
    handContext.closePath();
    handContext.strokeStyle = "rgba(101, 217, 133, .82)";
    handContext.lineWidth = Math.max(4, Math.min(11, size * 0.028));
    handContext.lineCap = "round";
    handContext.lineJoin = "round";
    handContext.stroke();
    handContext.restore();
  };

  const updatePinchTarget = (): void => {
    const state = latestHandState;
    if (!state?.detected || state.stale || state.gesture !== "Pinch" || state.landmarks.length <= 8) {
      targetPinchPoint = null;
      renderedPinchPoint = null;
      return;
    }
    const thumb = state.landmarks[4];
    const index = state.landmarks[8];
    if (!thumb || !index) {
      targetPinchPoint = null;
      renderedPinchPoint = null;
      return;
    }
    targetPinchPoint = {
      x: (1 - (thumb.x + index.x) / 2) * window.innerWidth,
      y: ((thumb.y + index.y) / 2) * window.innerHeight,
    };
    renderedPinchPoint ??= { ...targetPinchPoint };
  };

  const scheduleRender = (): void => {
    if (renderFrame !== null) return;
    renderFrame = window.requestAnimationFrame(() => {
      renderFrame = null;
      let needsAnotherFrame = false;
      if (targetPinchPoint && renderedPinchPoint) {
        const distance = Math.hypot(targetPinchPoint.x - renderedPinchPoint.x, targetPinchPoint.y - renderedPinchPoint.y);
        renderedPinchPoint.x += (targetPinchPoint.x - renderedPinchPoint.x) * 0.52;
        renderedPinchPoint.y += (targetPinchPoint.y - renderedPinchPoint.y) * 0.52;
        needsAnotherFrame = distance > 0.35;
      }
      if (renderedPinchPoint && showPinchDot) {
        pinchDot.style.transform = `translate3d(${renderedPinchPoint.x}px, ${renderedPinchPoint.y}px, 0) translate(-50%, -50%)`;
        pinchDot.style.opacity = "1";
      } else {
        pinchDot.style.opacity = "0";
      }
      renderFeedback();
      if (needsAnotherFrame) scheduleRender();
    });
  };

  const drawHand = (state: HandControlState): void => {
    latestHandState = state;
    updatePinchTarget();
    scheduleRender();
  };
  window.addEventListener("resize", () => {
    if (!latestHandState) return;
    updatePinchTarget();
    scheduleRender();
  });

  const indicator: GestureIndicator = {
    setTracking(active, _detail): void {
      tracking = active;
      root.setAttribute("aria-label", active ? "手势识别中，点击查看摄像头" : "手势识别已停止，点击打开控制窗口");
      if (!active) {
        activeDirection = null;
        latestHandState = null;
        targetPinchPoint = null;
        renderedPinchPoint = null;
        if (gestureTimer !== null) window.clearTimeout(gestureTimer);
        scheduleRender();
      }
    },
    flash(direction): void {
      if (!tracking || (direction !== "left" && direction !== "right")) return;
      activeDirection = direction;
      scheduleRender();
      if (gestureTimer !== null) window.clearTimeout(gestureTimer);
      gestureTimer = window.setTimeout(() => {
        activeDirection = null;
        scheduleRender();
      }, 550);
    },
    drawHand,
    setControllerExpanded(expanded): void {
      root.classList.toggle("is-expanded", expanded);
    },
    setDeveloperOverlays(handGrid, pinchDotVisible): void {
      showHandGrid = handGrid;
      showPinchDot = pinchDotVisible;
      scheduleRender();
    },
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

const genericAdapter: PageActionAdapter = {
  id: "generic-page",
  canHandle: () => true,
  execute(action: GestureAction): boolean {
    if (action === "scroll-up" || action === "scroll-down") {
      const direction = action === "scroll-up" ? -1 : 1;
      window.scrollBy({ top: direction * window.innerHeight * 0.75, behavior: "smooth" });
      return true;
    }
    return false;
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
    message: "页面已滚动。",
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
      request: unknown,
      _sender,
      sendResponse: (response: ExtensionResponse) => void,
    ) => {
      if (!isContentScriptRequest(request)) return;
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
      if (request.type === "gesture-overlay-controller") {
        indicator.setControllerExpanded(request.expanded);
        sendResponse({ ok: true, message: "控制窗口动效已更新。" });
        return;
      }
      if (request.type === "gesture-overlay-settings") {
        indicator.setDeveloperOverlays(request.showHandGrid, request.showPinchDot);
        sendResponse({ ok: true, message: "网页开发者叠层已更新。" });
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
