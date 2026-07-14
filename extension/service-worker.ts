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
let creatingOffscreenDocument: Promise<void> | null = null;

async function getActiveTabId(): Promise<number> {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (tab?.id === undefined) throw new Error("没有找到当前标签页。");
  return tab.id;
}

async function ensureContentScript(tabId: number): Promise<void> {
  try {
    const ping: ContentScriptRequest = { type: "gesture-control-ping" };
    await chrome.tabs.sendMessage(tabId, ping);
    return;
  } catch {
    try {
      await chrome.scripting.executeScript({
        target: { tabId },
        files: ["content-script.js"],
      });
    } catch {
      throw new Error("当前页面不允许插件控制。请打开普通网页，并在该标签页重新点击插件图标。");
    }
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
  if (request.type === "start-background-tracking") return startBackgroundTracking(request);
  if (request.type === "stop-background-tracking") return stopBackgroundTracking();
  if (request.type === "get-background-tracker-status") return getBackgroundTrackingStatus();

  const tabId = request.tabId ?? (await getActiveTabId());
  await ensureContentScript(tabId);
  if (request.type === "activate-tab") return { ok: true, message: "当前标签页已连接。" };

  if (request.type === "pinch-scroll") {
    const pinchRequest: ContentScriptRequest = { type: "execute-pinch-scroll", deltaY: request.deltaY };
    const response = (await chrome.tabs.sendMessage(tabId, pinchRequest)) as ExtensionResponse | undefined;
    return response ?? { ok: false, message: "网页没有返回捏合滚动结果。" };
  }

  const contentRequest: ContentScriptRequest = {
    type: "execute-gesture-action",
    action: request.action,
  };
  const response = (await chrome.tabs.sendMessage(tabId, contentRequest)) as ExtensionResponse | undefined;
  return response ?? { ok: false, message: "网页没有返回动作结果。" };
}

async function forwardTrackerEvent(event: TrackerEvent): Promise<void> {
  if (event.type === "background-hand-state") return;
  if (event.tabId === undefined) return;
  const request: ContentScriptRequest =
    event.type === "background-tracker-status"
      ? { type: "gesture-overlay-status", active: event.active, message: event.message }
      : { type: "gesture-overlay-gesture", direction: event.direction };
  try {
    await chrome.tabs.sendMessage(event.tabId, request);
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
  await chrome.windows.create({
    url: chrome.runtime.getURL(`sidepanel.html?tabId=${tab.id}`),
    type: "popup",
    width: 390,
    height: 720,
    focused: true,
  });
}

chrome.action.onClicked.addListener((tab) => {
  void openControllerWindow(tab);
});

chrome.runtime.onMessage.addListener((request: unknown, _sender, sendResponse: (response: ExtensionResponse) => void) => {
  if (isTrackerEvent(request)) {
    void forwardTrackerEvent(request);
    return;
  }
  if (!isExtensionRequest(request)) return;
  void handleRequest(request)
    .then(sendResponse)
    .catch((error: unknown) => {
      sendResponse({
        ok: false,
        message: error instanceof Error ? error.message : "当前标签页控制失败。",
      });
    });
  return true;
});
