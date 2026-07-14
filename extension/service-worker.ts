import type { ContentScriptRequest, ExtensionRequest, ExtensionResponse } from "./message-types";

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

async function handleRequest(request: ExtensionRequest): Promise<ExtensionResponse> {
  const tabId = request.tabId ?? (await getActiveTabId());
  await ensureContentScript(tabId);
  if (request.type === "activate-tab") {
    return { ok: true, message: "当前标签页已连接。" };
  }

  const contentRequest: ContentScriptRequest = {
    type: "execute-gesture-action",
    action: request.action,
  };
  const response = (await chrome.tabs.sendMessage(tabId, contentRequest)) as ExtensionResponse | undefined;
  return response ?? { ok: false, message: "网页没有返回动作结果。" };
}

async function openControllerWindow(tab: chrome.tabs.Tab): Promise<void> {
  if (tab.id === undefined) return;
  try {
    await ensureContentScript(tab.id);
  } catch {
    // Camera tracking can still start in the controller window. It will show a
    // clear connection error instead of silently failing on protected pages.
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

chrome.runtime.onMessage.addListener(
  (request: ExtensionRequest, _sender, sendResponse: (response: ExtensionResponse) => void) => {
    void handleRequest(request)
      .then(sendResponse)
      .catch((error: unknown) => {
        sendResponse({
          ok: false,
          message: error instanceof Error ? error.message : "当前标签页控制失败。",
        });
      });
    return true;
  },
);
