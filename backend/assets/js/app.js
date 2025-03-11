import "phoenix_html";
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import topbar from "topbar";

import ThemeSwitcherHook from "./hooks/theme_switcher_hook";
import MessageChannelHook from "./hooks/message_channel_hook";

// More advanced debugging
if (window.location.search.includes("debug=1")) {
  window.debugMode = true;
  console.log("[App] Debug mode enabled");
}

// Global error handler for debugging
window.addEventListener("error", (event) => {
  console.error("[App] Global error:", event.error || event.message);

  if (window.debugMode) {
    // Create a visible error indicator in debug mode
    const errorElement = document.createElement("div");
    errorElement.style.position = "fixed";
    errorElement.style.bottom = "10px";
    errorElement.style.right = "10px";
    errorElement.style.backgroundColor = "rgba(255, 0, 0, 0.7)";
    errorElement.style.color = "white";
    errorElement.style.padding = "10px";
    errorElement.style.borderRadius = "5px";
    errorElement.style.zIndex = "9999";
    errorElement.textContent = `Error: ${event.error?.message || event.message}`;
    document.body.appendChild(errorElement);
  }
});

// Define hooks before using them
const Hooks = {
  ThemeSwitcher: ThemeSwitcherHook,
  MessageChannel: MessageChannelHook,
};

// Get CSRF token
const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  ?.getAttribute("content");

if (!csrfToken) {
  console.error("[App] CSRF token meta tag not found");
}

// Initialize LiveSocket
const liveSocket = new LiveSocket("/live", Socket, {
  hooks: Hooks,
  params: { _csrf_token: csrfToken },
});

// Log LiveSocket state for debugging
console.log("[App] LiveSocket initialized", {
  host: window.location.host,
  hasCsrfToken: !!csrfToken,
  socketPath: "/live",
  hooksCount: Object.keys(Hooks).length,
});

// Topbar loader during page loading
topbar.config({
  barColors: { 0: "#C4FB50" },
  shadowColor: "rgba(0, 0, 0, .3)",
});

let topBarScheduled = undefined;
window.addEventListener("phx:page-loading-start", () => {
  if (!topBarScheduled) {
    topBarScheduled = setTimeout(() => topbar.show(), 200);
  }
});
window.addEventListener("phx:page-loading-stop", () => {
  clearTimeout(topBarScheduled);
  topBarScheduled = undefined;
  topbar.hide();
});

// Page transition animations
window.addEventListener("phx:page-loading-start", (info) => {
  if (info.detail.kind === "redirect") {
    document
      .querySelector("[data-main-view]")
      .classList.add("phx-page-loading");
  }
});

window.addEventListener("phx:page-loading-stop", (info) => {
  document
    .querySelector("[data-main-view]")
    .classList.remove("phx-page-loading");
});

// Connect to the LiveSocket
liveSocket.connect();

// Enable debug
liveSocket.enableDebug();

// Uncomment to enable latency simulation
// liveSocket.enableLatencySim(1000);

// Expose liveSocket to window for debugging
window.liveSocket = liveSocket;

window.addEventListener("phx:live_reload:attached", ({ detail: reloader }) => {
  // Enable server log streaming to client.
  // Disable with reloader.disableServerLogs()
  reloader.enableServerLogs();
  window.liveReloader = reloader;
});

// REMOVE FOR PRODUCTION
// This logs the time to first contentful paint (FCP) to the console.
new PerformanceObserver((entryList) => {
  for (const entry of entryList.getEntriesByName("first-contentful-paint")) {
    console.log("FCP candidate:", entry.startTime, entry);
  }
}).observe({ type: "paint", buffered: true });
