import type { GestureAction, SwipeDirection } from "../src/types";

export type ExtensionRequest =
  | { type: "activate-tab"; tabId?: number }
  | {
      type: "gesture-action";
      action: GestureAction;
      direction: SwipeDirection;
      timestamp: number;
      tabId?: number;
    };

export type ContentScriptRequest =
  | { type: "gesture-control-ping" }
  | { type: "execute-gesture-action"; action: GestureAction };

export type ExtensionResponse = {
  ok: boolean;
  message: string;
  adapterId?: string;
};
