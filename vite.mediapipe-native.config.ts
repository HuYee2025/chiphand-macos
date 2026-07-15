import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { defineConfig } from "vite";

const projectRoot = fileURLToPath(new URL(".", import.meta.url));

export default defineConfig({
  base: "./",
  publicDir: false,
  build: {
    outDir: resolve(projectRoot, "macos-app/Resources/MediaPipeRecognizer"),
    emptyOutDir: true,
    rollupOptions: {
      input: resolve(projectRoot, "native-recognizer.html"),
    },
  },
});
