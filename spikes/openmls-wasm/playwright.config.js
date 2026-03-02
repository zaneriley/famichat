import { defineConfig, devices } from "@playwright/test";

export default defineConfig({
  testDir: "./",
  testMatch: "spike.spec.js",
  timeout: 300_000, // 5 minutes — S8 does 1000 iterations + M2 worker init
  use: {
    baseURL: "http://localhost:5173",
    headless: true,
    // Allow enough time for WASM JIT + 1000-iteration perf loop
    navigationTimeout: 30_000,
    actionTimeout: 10_000,
  },
  projects: [
    {
      name: "chromium",
      use: {
        ...devices["Desktop Chrome"],
        launchOptions: {
          // Required for running headless Chrome in CI / sandboxed environments
          args: ["--no-sandbox", "--disable-setuid-sandbox", "--disable-dev-shm-usage"],
        },
      },
    },
  ],
  // Vite dev server is started externally before this runs
  webServer: {
    command: "node_modules/.bin/vite --port 5173",
    port: 5173,
    reuseExistingServer: true,
    timeout: 30_000,
  },
  reporter: [["list"], ["json", { outputFile: "playwright-results.json" }]],
});
