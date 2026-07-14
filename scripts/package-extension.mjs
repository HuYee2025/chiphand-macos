import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, rmSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(fileURLToPath(new URL("..", import.meta.url)));
const extensionDir = resolve(root, "dist-extension");
const releaseDir = resolve(root, "releases");
const archive = resolve(releaseDir, "gesture-browser-control-v1.0.1.zip");

if (!existsSync(extensionDir)) {
  throw new Error("缺少 dist-extension。请先构建扩展。");
}

mkdirSync(releaseDir, { recursive: true });
rmSync(archive, { force: true });
execFileSync("zip", ["-q", "-r", archive, "."], { cwd: extensionDir, stdio: "inherit" });
console.log(`已生成商店提交包：${archive}`);
