import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import messages from "./src/messages.json" with { type: "json" };

const catalog = JSON.parse(
  readFileSync(
    fileURLToPath(new URL("../../Localization/Strings.json", import.meta.url)),
    "utf8",
  ),
);
const translations = Object.fromEntries(
  ["en", "zh-Hans", "zh-Hant"].map((language) => [
    language,
    Object.fromEntries(
      Object.entries(messages).map(([id, key]) => {
        if (!catalog[key]?.[language])
          throw new Error(`Missing ${language} translation: ${key}`);
        return [id, catalog[key][language]];
      }),
    ),
  ]),
);

export default defineConfig({
  plugins: [react()],
  define: { __UPLOAD_TRANSLATIONS__: JSON.stringify(translations) },
  base: "/",
  build: {
    target: "es2022",
    assetsDir: "",
    sourcemap: false,
    rolldownOptions: {
      output: {
        entryFileNames: "upload-[name]-[hash].js",
        chunkFileNames: "upload-[name]-[hash].js",
        assetFileNames: "upload-[name]-[hash][extname]",
      },
    },
  },
  server: {
    proxy: Object.fromEntries(
      ["/api", "/pair", "/upload"].map((path) => [
        path,
        {
          target: process.env.IMUSIC_UPLOAD_SERVER ?? "http://127.0.0.1:8080",
          changeOrigin: true,
          // Development only: align Origin with the proxy Host for the server's same-origin check.
          configure(proxy) {
            proxy.on("proxyReq", (request) => {
              request.removeHeader("origin");
            });
          },
        },
      ]),
    ),
  },
  test: {
    environment: "jsdom",
    setupFiles: ["./src/test-setup.ts"],
    restoreMocks: true,
  },
});
