import type { ContentScriptRequest, ExtensionResponse } from "./message-types";
import type { GestureAction, PageActionAdapter, SwipeDirection } from "../src/types";

declare global {
  interface Window {
    __gestureBrowserControlInstalled?: boolean;
  }
}

const OVERLAY_ID = "__gesture_browser_indicator__";

type GestureIndicator = {
  setTracking(active: boolean, message: string): void;
  flash(direction: SwipeDirection): void;
};

function createIndicator(): GestureIndicator {
  const existing = document.getElementById(OVERLAY_ID);
  if (existing?.shadowRoot) {
    const indicator = (existing.shadowRoot.querySelector("#indicator") as HTMLElement | null)?.__gestureIndicator;
    if (indicator) return indicator;
  }

  const host = document.createElement("div");
  host.id = OVERLAY_ID;
  host.style.cssText = "position:fixed;right:14px;top:50%;z-index:2147483647;pointer-events:auto;";
  const shadow = host.attachShadow({ mode: "open" });
  shadow.innerHTML = `
    <style>
      :host { all: initial; }
      #indicator {
        width: 14px; height: 68px; display: grid; place-items: center; overflow: hidden;
        border: 1px solid #171717; border-radius: 9px; background: #090909; color: #c0ffd0;
        box-shadow: 0 8px 24px rgba(0,0,0,.22); cursor: default;
        font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
        transition: width .2s ease, border-color .2s ease, background .2s ease;
      }
      #indicator.is-expanded { width: 116px; border-color: #2a2a2a; background: #0d0d0c; }
      #arrow { color: #c0ffd0; font: 700 46px/1 system-ui, sans-serif; opacity: 0; transform: scale(.72); transition: opacity .15s ease, transform .15s ease, text-shadow .15s ease; }
      #indicator.is-gesture { border-color: #3e7450; background: #0e1710; }
      #indicator.is-gesture #arrow { opacity: 1; transform: scale(1); text-shadow: 0 0 18px #65d985; }
      #status { position: absolute; width: 90px; color: #85827a; font: 700 10px/1.35 ui-monospace, SFMono-Regular, Menlo, monospace; opacity: 0; transition: opacity .15s ease; text-align: center; }
      #indicator.is-expanded #status { opacity: 1; }
      #indicator.is-expanded.is-gesture #status { opacity: 0; }
      @media (prefers-reduced-motion: reduce) { #indicator, #arrow, #status { transition: none; } }
    </style>
    <div id="indicator" aria-label="手势浏览识别状态" role="status">
      <span id="arrow" aria-hidden="true"></span>
      <span id="status">未启动</span>
    </div>
  `;
  document.documentElement.append(host);

  const root = shadow.querySelector<HTMLElement>("#indicator");
  const arrow = shadow.querySelector<HTMLElement>("#arrow");
  const status = shadow.querySelector<HTMLElement>("#status");
  if (!root || !arrow || !status) throw new Error("无法创建手势状态提示。");

  let tracking = false;
  let collapseTimer: number | null = null;
  let gestureTimer: number | null = null;
  const collapse = (): void => root.classList.remove("is-expanded");
  const scheduleCollapse = (delay: number): void => {
    if (collapseTimer !== null) window.clearTimeout(collapseTimer);
    collapseTimer = window.setTimeout(collapse, delay);
  };
  const expand = (): void => {
    if (!tracking) return;
    root.classList.add("is-expanded");
    scheduleCollapse(5_000);
  };

  root.addEventListener("pointerenter", expand);
  root.addEventListener("pointerleave", () => scheduleCollapse(450));

  const indicator: GestureIndicator = {
    setTracking(active, detail): void {
      tracking = active;
      status.textContent = active ? "手势识别中" : "已停止";
      root.setAttribute("aria-label", active ? "手势识别中" : "手势识别已停止");
      if (!active) {
        if (collapseTimer !== null) window.clearTimeout(collapseTimer);
        collapse();
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

if (!window.__gestureBrowserControlInstalled) {
  window.__gestureBrowserControlInstalled = true;
  const indicator = createIndicator();
  chrome.runtime.onMessage.addListener(
    (request: ContentScriptRequest, _sender, sendResponse: (response: ExtensionResponse) => void) => {
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
      sendResponse(executeAction(request.action));
    },
  );
}
