import {
  isExtensionRequest,
  isTrackerEvent,
  type ContentScriptRequest,
  type ExtensionRequest,
  type ExtensionResponse,
  type OffscreenRequest,
  type OffscreenResponse,
  type TrackerEvent,
} from "./message-types";

const OFFSCREEN_DOCUMENT = "offscreen.html";
const CONTROLLER_WIDTH = 300;
const CONTROLLER_HEIGHT = 400;
let creatingOffscreenDocument: Promise<void> | null = null;
const controllerWindowByTab = new Map<number, number>();

async function getActiveTabId(): Promise<number> {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (tab?.id === undefined) throw new Error("没有找到当前标签页。");
  return tab.id;
}

async function ensureContentScript(tabId: number): Promise<void> {
  const ping: ContentScriptRequest = { type: "gesture-control-ping" };
  try {
    await chrome.tabs.sendMessage(tabId, ping);
    return;
  } catch {
    try {
      await chrome.scripting.executeScript({
        target: { tabId },
        files: ["content-script.js"],
      });
      // executeScript 完成不表示接收器已经就绪；再 ping 一次才能确认。
      await chrome.tabs.sendMessage(tabId, ping);
    } catch {
      throw new Error("当前页面不允许插件控制。请打开普通网页，并在该标签页重新点击插件图标。");
    }
  }
}

async function sendToPage(tabId: number, request: ContentScriptRequest): Promise<ExtensionResponse> {
  try {
    const response = (await chrome.tabs.sendMessage(tabId, request)) as ExtensionResponse | undefined;
    return response ?? { ok: false, message: "网页没有返回动作结果。" };
  } catch {
    // 页面可能刚跳转，旧脚本已随文档销毁。补注入后只重试一次。
    await ensureContentScript(tabId);
    const response = (await chrome.tabs.sendMessage(tabId, request)) as ExtensionResponse | undefined;
    return response ?? { ok: false, message: "网页没有返回动作结果。" };
  }
}

function isExistingOffscreenError(error: unknown): boolean {
  return /single offscreen|already exists/i.test(error instanceof Error ? error.message : String(error));
}

async function ensureOffscreenDocument(): Promise<void> {
  if (creatingOffscreenDocument) return creatingOffscreenDocument;
  creatingOffscreenDocument = chrome.offscreen
    .createDocument({
      url: OFFSCREEN_DOCUMENT,
      reasons: ["USER_MEDIA", "WORKERS"],
      justification: "Keep local camera hand-gesture recognition active while the user reads a webpage.",
    })
    .catch((error: unknown) => {
      if (!isExistingOffscreenError(error)) throw error;
    })
    .finally(() => {
      creatingOffscreenDocument = null;
    });
  return creatingOffscreenDocument;
}

async function sendToOffscreen(request: OffscreenRequest): Promise<OffscreenResponse> {
  const response = (await chrome.runtime.sendMessage(request)) as OffscreenResponse | undefined;
  if (!response) throw new Error("后台识别模块没有响应。");
  return response;
}

function toExtensionResponse(response: OffscreenResponse): ExtensionResponse {
  return {
    ok: response.ok,
    message: response.message,
    trackingActive: response.active,
    ...(response.tabId === undefined ? {} : { tabId: response.tabId }),
  };
}

async function startBackgroundTracking(request: Extract<ExtensionRequest, { type: "start-background-tracking" }>): Promise<ExtensionResponse> {
  const tabId = request.tabId ?? (await getActiveTabId());
  await ensureContentScript(tabId);
  await ensureOffscreenDocument();
  return toExtensionResponse(await sendToOffscreen({ type: "offscreen-start-tracking", tabId }));
}

async function stopBackgroundTracking(): Promise<ExtensionResponse> {
  try {
    const response = await sendToOffscreen({ type: "offscreen-stop-tracking" });
    await chrome.offscreen.closeDocument();
    return toExtensionResponse(response);
  } catch {
    return { ok: true, message: "摄像头已停止。", trackingActive: false };
  }
}

async function getBackgroundTrackingStatus(): Promise<ExtensionResponse> {
  try {
    return toExtensionResponse(await sendToOffscreen({ type: "offscreen-get-tracker-status" }));
  } catch {
    return { ok: true, message: "摄像头未启动。", trackingActive: false };
  }
}

async function handleRequest(request: ExtensionRequest): Promise<ExtensionResponse> {
  if (request.type === "open-controller") {
    const tabId = request.tabId ?? (await getActiveTabId());
    const tab = await chrome.tabs.get(tabId);
    await openControllerWindow(tab);
    return { ok: true, message: "控制窗口已打开。", tabId };
  }
  if (request.type === "start-background-tracking") return startBackgroundTracking(request);
  if (request.type === "stop-background-tracking") return stopBackgroundTracking();
  if (request.type === "get-background-tracker-status") return getBackgroundTrackingStatus();

  const tabId = request.tabId ?? (await getActiveTabId());
  if (request.type === "activate-tab") {
    await ensureContentScript(tabId);
    return { ok: true, message: "当前标签页已连接。" };
  }

  if (request.type === "pinch-scroll") {
    const pinchRequest: ContentScriptRequest = { type: "execute-pinch-scroll", deltaY: request.deltaY };
    return sendToPage(tabId, pinchRequest);
  }

  const contentRequest: ContentScriptRequest = {
    type: "execute-gesture-action",
    action: request.action,
  };
  return sendToPage(tabId, contentRequest);
}

async function forwardTrackerEvent(event: TrackerEvent): Promise<void> {
  if (event.tabId === undefined) return;
  const request: ContentScriptRequest =
    event.type === "background-hand-state"
      ? { type: "gesture-overlay-hand-state", state: event.state }
      : event.type === "background-tracker-status"
        ? { type: "gesture-overlay-status", active: event.active, message: event.message }
        : { type: "gesture-overlay-gesture", direction: event.direction };
  try {
    await sendToPage(event.tabId, request);
  } catch {
    // 页面已关闭、跳转或受保护时，后台识别仍继续，只是没有页面内反馈。
  }
}

async function openControllerWindow(tab: chrome.tabs.Tab): Promise<void> {
  if (tab.id === undefined) return;
  try {
    await ensureContentScript(tab.id);
  } catch {
    // 后台识别仍可启动，控制窗口会明确提示当前网页不能执行动作。
  }
  const existingWindowId = controllerWindowByTab.get(tab.id);
  if (existingWindowId !== undefined) {
    try {
      await chrome.windows.update(existingWindowId, { focused: true });
      void sendToPage(tab.id, { type: "gesture-overlay-controller", expanded: true }).catch(() => undefined);
      return;
    } catch {
      controllerWindowByTab.delete(tab.id);
    }
  }

  const options: chrome.windows.CreateData = {
    url: chrome.runtime.getURL(`sidepanel.html?tabId=${tab.id}`),
    type: "popup",
    width: CONTROLLER_WIDTH,
    height: CONTROLLER_HEIGHT,
    focused: true,
  };
  try {
    const parentWindow = await chrome.windows.get(tab.windowId);
    if (
      typeof parentWindow.left === "number" &&
      typeof parentWindow.top === "number" &&
      typeof parentWindow.width === "number" &&
      typeof parentWindow.height === "number"
    ) {
      options.left = parentWindow.left + parentWindow.width - CONTROLLER_WIDTH - 20;
      options.top = parentWindow.top + Math.round((parentWindow.height - CONTROLLER_HEIGHT) / 2);
    }
  } catch {
    // 无法读取宿主窗口坐标时，让 Chrome 采用自己的安全位置。
  }
  const controllerWindow = await chrome.windows.create(options);
  if (controllerWindow?.id !== undefined) controllerWindowByTab.set(tab.id, controllerWindow.id);
  void sendToPage(tab.id, { type: "gesture-overlay-controller", expanded: true }).catch(() => undefined);
}

chrome.action.onClicked.addListener((tab) => {
  void openControllerWindow(tab);
});

chrome.windows.onRemoved.addListener((windowId) => {
  for (const [tabId, controllerWindowId] of controllerWindowByTab) {
    if (controllerWindowId !== windowId) continue;
    controllerWindowByTab.delete(tabId);
    void sendToPage(tabId, { type: "gesture-overlay-controller", expanded: false }).catch(() => undefined);
    break;
  }
});

chrome.runtime.onMessage.addListener((request: unknown, sender, sendResponse: (response: ExtensionResponse) => void) => {
  if (isTrackerEvent(request)) {
    void forwardTrackerEvent(request);
    return;
  }
  if (!isExtensionRequest(request)) return;
  const resolvedRequest =
    request.type === "open-controller" && sender.tab?.id !== undefined ? { ...request, tabId: sender.tab.id } : request;
  void handleRequest(resolvedRequest)
    .then(sendResponse)
    .catch((error: unknown) => {
      sendResponse({
        ok: false,
        message: error instanceof Error ? error.message : "当前标签页控制失败。",
      });
    });
  return true;
});
