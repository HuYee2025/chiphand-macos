import { cp, mkdir } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const source = resolve(root, "public/mediapipe");
const target = resolve(root, "macos-app/Resources/MediaPipeRecognizer/mediapipe");

await mkdir(target, { recursive: true });
await cp(resolve(source, "wasm"), resolve(target, "wasm"), { recursive: true, force: true });
await cp(
  resolve(source, "gesture_recognizer.task"),
  resolve(target, "gesture_recognizer.task"),
  { force: true },
);
