import { defineConfig } from "@playwright/test";
export default defineConfig({
  testDir: "./browser-tests", timeout: 25000, workers: 1, retries: 0,
  use: { baseURL: "http://127.0.0.1:4176", browserName: "chromium", headless: true, launchOptions: { args: ["--autoplay-policy=no-user-gesture-required", "--no-sandbox"] } },
  webServer: { command: "bunx vite --host 127.0.0.1 --port 4176 --strictPort", url: "http://127.0.0.1:4176", reuseExistingServer: false, timeout: 15000 },
});
