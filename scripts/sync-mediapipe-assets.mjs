import { cp, mkdir, stat, writeFile } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const packageWasm = resolve(root, "node_modules/@mediapipe/tasks-vision/wasm");
const publicRoot = resolve(root, "public/mediapipe");
const publicWasm = resolve(publicRoot, "wasm");
const modelPath = resolve(publicRoot, "hand_landmarker.task");
const modelUrl =
  "https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/1/hand_landmarker.task";
const gestureModelPath = resolve(publicRoot, "gesture_recognizer.task");
const gestureModelUrl =
  "https://storage.googleapis.com/mediapipe-tasks/gesture_recognizer/gesture_recognizer.task";

async function exists(path) {
  try {
    await stat(path);
    return true;
  } catch {
    return false;
  }
}

await mkdir(publicRoot, { recursive: true });
await cp(packageWasm, publicWasm, { recursive: true, force: true });

async function downloadIfMissing(path, url) {
  if (await exists(path)) return;
  try {
    const response = await fetch(url, { signal: AbortSignal.timeout(15_000) });
    if (!response.ok) {
      throw new Error(`HTTP ${response.status} ${response.statusText}`);
    }
    await writeFile(path, Buffer.from(await response.arrayBuffer()));
  } catch (error) {
    const fallback = spawnSync("curl", ["-fL", url, "-o", path], {
      stdio: "inherit",
    });
    if (fallback.status !== 0) {
      throw new Error(`MediaPipe model download failed: ${String(error)}`);
    }
  }
}

await downloadIfMissing(modelPath, modelUrl);
await downloadIfMissing(gestureModelPath, gestureModelUrl);

console.log("MediaPipe WASM, hand model, and gesture model are ready in public/mediapipe.");
