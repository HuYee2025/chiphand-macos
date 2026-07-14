import type { GestureAction, HandControlState, SwipeDirection } from "../src/types";

export type ExtensionRequest =
  | { type: "activate-tab"; tabId?: number }
  | { type: "open-controller"; tabId?: number }
  | { type: "start-background-tracking"; tabId?: number }
  | { type: "stop-background-tracking" }
  | { type: "get-background-tracker-status" }
  | {
      type: "gesture-action";
      action: GestureAction;
      direction: SwipeDirection;
      timestamp: number;
      tabId?: number;
    }
  | {
      type: "pinch-scroll";
      deltaY: number;
      direction: Extract<SwipeDirection, "up" | "down">;
      timestamp: number;
      tabId?: number;
    };

export type ContentScriptRequest =
  | { type: "gesture-control-ping" }
  | { type: "execute-gesture-action"; action: GestureAction }
  | { type: "execute-pinch-scroll"; deltaY: number }
  | { type: "gesture-overlay-status"; active: boolean; message: string }
  | { type: "gesture-overlay-gesture"; direction: SwipeDirection }
  | { type: "gesture-overlay-hand-state"; state: HandControlState };

/**
 * Chrome 会把同一扩展内的 runtime 消息也送到 content script。
 * 这里必须只接收真正由 service worker 发往网页的消息，不能让
 * offscreen 的识别状态或动作请求落入网页动作处理器。
 */
export function isContentScriptRequest(message: unknown): message is ContentScriptRequest {
  if (!message || typeof message !== "object" || !("type" in message)) return false;
  const type = (message as { type?: unknown }).type;
  return (
    type === "gesture-control-ping" ||
    type === "execute-gesture-action" ||
    type === "execute-pinch-scroll" ||
    type === "gesture-overlay-status" ||
    type === "gesture-overlay-gesture" ||
    type === "gesture-overlay-hand-state"
  );
}

export type ExtensionResponse = {
  ok: boolean;
  message: string;
  adapterId?: string;
  trackingActive?: boolean;
  tabId?: number;
};

export type OffscreenRequest =
  | { type: "offscreen-start-tracking"; tabId: number }
  | { type: "offscreen-stop-tracking" }
  | { type: "offscreen-get-tracker-status" };

export type OffscreenResponse = {
  ok: boolean;
  active: boolean;
  message: string;
  tabId?: number;
};

export type TrackerEvent =
  | { type: "background-tracker-status"; active: boolean; message: string; tabId?: number }
  | { type: "background-gesture-feedback"; direction: SwipeDirection; ok: boolean; message: string; tabId?: number }
  | { type: "background-hand-state"; state: HandControlState; tabId?: number };

export function isExtensionRequest(message: unknown): message is ExtensionRequest {
  if (!message || typeof message !== "object" || !("type" in message)) return false;
  const type = (message as { type?: unknown }).type;
  return (
    type === "activate-tab" ||
    type === "open-controller" ||
    type === "start-background-tracking" ||
    type === "stop-background-tracking" ||
    type === "get-background-tracker-status" ||
    type === "gesture-action" ||
    type === "pinch-scroll"
  );
}

export function isOffscreenRequest(message: unknown): message is OffscreenRequest {
  if (!message || typeof message !== "object" || !("type" in message)) return false;
  const type = (message as { type?: unknown }).type;
  return type === "offscreen-start-tracking" || type === "offscreen-stop-tracking" || type === "offscreen-get-tracker-status";
}

export function isTrackerEvent(message: unknown): message is TrackerEvent {
  if (!message || typeof message !== "object" || !("type" in message)) return false;
  const type = (message as { type?: unknown }).type;
  return type === "background-tracker-status" || type === "background-gesture-feedback" || type === "background-hand-state";
}
