import { defineConfig } from "vite";
import wasm from "vite-plugin-wasm";
import topLevelAwait from "vite-plugin-top-level-await";

export default defineConfig({
  plugins: [wasm(), topLevelAwait()],
  // Apply the same plugins inside the worker bundle so workers can load WASM
  worker: {
    plugins: () => [wasm(), topLevelAwait()],
  },
  build: {
    // Match the baseline from proposal-04-v2 research
    target: ["chrome89", "safari15", "firefox89"],
  },
  // Prevent Vite from pre-bundling the WASM package (breaks binary handling)
  optimizeDeps: {
    exclude: ["@famichat/mls-wasm"],
  },
  // Resolve the WASM package from the bundler-target build output
  resolve: {
    alias: {
      "@famichat/mls-wasm": new URL(
        "../../backend/infra/mls_wasm/pkg-bundler/mls_wasm.js",
        import.meta.url
      ).pathname,
    },
  },
  server: {
    headers: {
      // M4: CSP testing — 'wasm-unsafe-eval' allows WASM compilation without full 'unsafe-eval'
      // style-src: 'unsafe-inline' required for Vite HMR overlay + JS inline style assignment
      // wasm-unsafe-eval: allows WebAssembly.compile() without full unsafe-eval
      // connect-src: Vite HMR WebSocket
      "Content-Security-Policy":
        "default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self' 'unsafe-inline'; worker-src 'self' blob:; connect-src 'self' ws:",
    },
  },
});
