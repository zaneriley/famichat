/**
 * Famichat WASM Spike — Playwright end-to-end test
 *
 * Opens the Vite harness at http://localhost:5173, waits for all tests to complete,
 * then captures the result table and console output for each criterion:
 *   S1 (build, confirmed from file), S2 (size, confirmed from file),
 *   S3, S4, S5, S6, S8, M1, M2, M4.
 *
 * Saves results to spike-results-playwright.json.
 */

import { test, expect } from "@playwright/test";
import * as fs from "fs";
import * as path from "path";

const CRITERIA = ["S3", "S4", "S5", "S6", "M4", "M1", "M2", "S8"];

test("WASM spike harness — all criteria", async ({ page }) => {
  const consoleLogs = [];
  const consoleErrors = [];

  page.on("console", (msg) => {
    const text = `[console.${msg.type()}] ${msg.text()}`;
    consoleLogs.push(text);
    if (msg.type() === "error") {
      consoleErrors.push(text);
    }
    // Mirror to test output so we can see real-time progress
    process.stdout.write(text + "\n");
  });

  page.on("pageerror", (err) => {
    const text = `[pageerror] ${err.message}`;
    consoleLogs.push(text);
    consoleErrors.push(text);
    process.stdout.write(text + "\n");
  });

  // Navigate to the Vite harness
  await page.goto("http://localhost:5173");

  // Wait for the #results-complete sentinel — set by main.js when all tests finish.
  // Timeout is 280s (S8 does 1000 iterations; give it plenty of room).
  console.log("[spec] Waiting for #results-complete ...");
  await page.waitForSelector("#results-complete", {
    state: "visible",
    timeout: 280_000,
  });
  console.log("[spec] #results-complete appeared — tests finished");

  // Read the verdict from the sentinel element
  const verdict = await page.locator("#results-complete").textContent();
  console.log("[spec] Harness verdict:", verdict);

  // Capture the full JSON output from the page
  const jsonText = await page.locator("#json-output").textContent();
  let spikeResults = {};
  try {
    spikeResults = JSON.parse(jsonText || "{}");
  } catch (e) {
    console.error("[spec] Could not parse spike-results JSON:", e);
  }

  // Capture each criterion's DOM result
  const domResults = {};
  for (const criterion of CRITERIA) {
    try {
      const resultText = await page.locator(`#result-${criterion}`).textContent();
      const detailText = await page.locator(`#detail-${criterion}`).textContent();
      domResults[criterion] = { dom_result: resultText?.trim(), dom_detail: detailText?.trim() };
    } catch (_) {
      domResults[criterion] = { dom_result: "element-not-found", dom_detail: "" };
    }
  }

  // Capture the status banner
  const statusText = await page.locator("#status").textContent();
  console.log("[spec] Status banner:", statusText);

  // Build the combined output document
  const combinedOutput = {
    timestamp: new Date().toISOString(),
    url: "http://localhost:5173",
    verdict: verdict?.trim() || spikeResults.verdict || "UNKNOWN",
    status_banner: statusText?.trim(),
    user_agent: spikeResults.userAgent,
    criteria_from_dom: domResults,
    spike_results: spikeResults,
    console_log_count: consoleLogs.length,
    console_error_count: consoleErrors.length,
    console_errors: consoleErrors,
    console_logs: consoleLogs,
  };

  // Save to spike-results-playwright.json in the spike directory
  const outputPath = path.join(import.meta.dirname, "spike-results-playwright.json");
  fs.writeFileSync(outputPath, JSON.stringify(combinedOutput, null, 2));
  console.log("[spec] Results saved to", outputPath);

  // Assertions — test FAILS if any criterion failed (not just skipped)
  for (const criterion of CRITERIA) {
    const result = spikeResults[criterion];
    if (result) {
      const status = result.status;
      // WARN is acceptable (not a hard failure)
      expect(
        status,
        `Criterion ${criterion} failed: ${result.detail}`
      ).not.toBe("FAIL");
    }
  }

  // Overall verdict: GO or GO_WITH_PENDING are acceptable; STOP is a test failure
  expect(
    combinedOutput.verdict,
    `Overall verdict is STOP — one or more criteria failed`
  ).not.toBe("STOP");
});
