import { copyFile, mkdir } from "node:fs/promises";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { defineConfig, type Plugin } from "vite";

const projectRoot = fileURLToPath(new URL(".", import.meta.url));
const extensionRoot = resolve(projectRoot, "extension");
const outputRoot = resolve(projectRoot, "dist-extension");

function copyManifest(): Plugin {
  return {
    name: "copy-extension-manifest",
    async closeBundle() {
      await mkdir(outputRoot, { recursive: true });
      await copyFile(resolve(extensionRoot, "manifest.json"), resolve(outputRoot, "manifest.json"));
    },
  };
}

export default defineConfig({
  root: extensionRoot,
  base: "./",
  publicDir: resolve(projectRoot, "public"),
  plugins: [copyManifest()],
  build: {
    outDir: outputRoot,
    emptyOutDir: true,
    rollupOptions: {
      input: {
        sidepanel: resolve(extensionRoot, "sidepanel.html"),
        "service-worker": resolve(extensionRoot, "service-worker.ts"),
        "content-script": resolve(extensionRoot, "content-script.ts"),
      },
      output: {
        entryFileNames: (chunk) =>
          chunk.name === "service-worker" || chunk.name === "content-script"
            ? `${chunk.name}.js`
            : "assets/[name]-[hash].js",
        chunkFileNames: "assets/[name]-[hash].js",
        assetFileNames: "assets/[name]-[hash][extname]",
      },
    },
  },
});
