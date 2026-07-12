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

if (!(await exists(modelPath))) {
  try {
    const response = await fetch(modelUrl, { signal: AbortSignal.timeout(15_000) });
    if (!response.ok) {
      throw new Error(`HTTP ${response.status} ${response.statusText}`);
    }
    await writeFile(modelPath, Buffer.from(await response.arrayBuffer()));
  } catch (error) {
    const fallback = spawnSync("curl", ["-fL", modelUrl, "-o", modelPath], {
      stdio: "inherit",
    });
    if (fallback.status !== 0) {
      throw new Error(`MediaPipe model download failed: ${String(error)}`);
    }
  }
}

console.log("MediaPipe WASM and hand model are ready in public/mediapipe.");
