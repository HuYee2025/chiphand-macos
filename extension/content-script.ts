import type { ContentScriptRequest, ExtensionResponse } from "./message-types";
import type { GestureAction, PageActionAdapter } from "../src/types";

declare global {
  interface Window {
    __gestureBrowserControlInstalled?: boolean;
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
  chrome.runtime.onMessage.addListener(
    (request: ContentScriptRequest, _sender, sendResponse: (response: ExtensionResponse) => void) => {
      if (request.type === "gesture-control-ping") {
        sendResponse({ ok: true, message: "网页控制已连接。" });
        return;
      }
      sendResponse(executeAction(request.action));
    },
  );
}
