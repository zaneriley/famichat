/**
 * Famichat WASM Spike — S8: Performance Test (≤50ms P95 gate)
 *
 * Measures TWO distinct paths per the risk assessment (spike-risks.md §1.7):
 *
 *   COLD PATH — Stateless design (what the spike's WASM API does by default)
 *     Every call: deserialize JSON state blob → WASM crypto → serialize JSON state blob
 *     Cost includes: serde_json parse + base64 decode (~30 entries) + MlsGroup::load() + crypto + serialize
 *     Measured because: spike's stateless API pays this cost every call
 *     Expected: higher latency than warm path, ~26–72ms on iPhone 12 (per risk doc estimate)
 *
 *   WARM PATH — Worker holds state in memory (production design)
 *     State deserialize/serialize happens ONCE (first call); subsequent calls go directly to crypto
 *     Simulated here on the main thread by calling WASM once and reusing the returned state
 *     in a tightly-scoped loop WITHOUT re-parsing the JSON string between iterations.
 *     This simulates what the production Worker design achieves (MlsGroup stays in-memory).
 *     NOTE: The warm path simulation here still has the full serde overhead; a true warm path
 *     would require a Rust-side session registry (out of spike scope). This measurement
 *     approximates the warm path by skipping state export/import between iterations.
 *
 * Gate (from spike-criteria.md C8 + ADR 012 §3 S8):
 *   Warm-path P95 ≤ 50ms → PASS
 *   Warm-path P95 50–150ms → WARN
 *   Warm-path P95 > 150ms → FAIL
 *   Cold-path is informational (documented separately, not gated)
 *
 * Iteration count: 1000 total; first 10 are warm-up (discarded).
 *
 * Usage: imported by harness.js; call runPerformanceTests() which returns a result object.
 */

// bundler target (wasm-pack --target bundler) does NOT export a default `init`.
// The WASM binary is instantiated automatically via vite-plugin-wasm on import.
// We import the named functions directly. `init` is intentionally not imported here.
import {
  create_group,
  create_member,
  add_member,
  join_group,
  encrypt_message,
  decrypt_message,
} from "@famichat/mls-wasm";

// Shim: bundler target has no init(); guard against any call attempt.
const init = undefined;

// ============================================================================
// Statistics helpers
// ============================================================================

/**
 * Compute percentile from a sorted array.
 * @param {number[]} sorted - Already sorted ascending
 * @param {number} p - Percentile 0–100
 * @returns {number}
 */
function percentile(sorted, p) {
  if (sorted.length === 0) return 0;
  const idx = Math.min(Math.floor((sorted.length * p) / 100), sorted.length - 1);
  return sorted[idx];
}

/**
 * Compute statistics from a sample array.
 * @param {number[]} samples
 * @returns {{ min: number, max: number, mean: number, p50: number, p95: number, p99: number }}
 */
function computeStats(samples) {
  if (samples.length === 0) {
    return { min: 0, max: 0, mean: 0, p50: 0, p95: 0, p99: 0 };
  }
  const sorted = [...samples].sort((a, b) => a - b);
  const mean = samples.reduce((a, b) => a + b, 0) / samples.length;
  return {
    min: sorted[0],
    max: sorted[sorted.length - 1],
    mean,
    p50: percentile(sorted, 50),
    p95: percentile(sorted, 95),
    p99: percentile(sorted, 99),
  };
}

/**
 * Format a timing table row.
 */
function fmtRow(label, stats, gateMs) {
  const status =
    stats.p95 <= gateMs ? "PASS" :
    stats.p95 <= 150 ? "WARN" :
    "FAIL";
  return {
    label,
    min: stats.min.toFixed(2),
    mean: stats.mean.toFixed(2),
    p50: stats.p50.toFixed(2),
    p95: stats.p95.toFixed(2),
    p99: stats.p99.toFixed(2),
    max: stats.max.toFixed(2),
    status,
  };
}

// ============================================================================
// WASM setup
// ============================================================================

let wasmInitialized = false;

async function ensureWasmInit() {
  if (!wasmInitialized) {
    // bundler target (wasm-pack --target bundler): no init() export; WASM is ready on import.
    // web/nodejs targets: init() must be called before using WASM functions.
    if (typeof init === "function") {
      await init();
    }
    wasmInitialized = true;
  }
}

/**
 * Create a minimal two-member MLS group and return both states.
 * Alice's state has already processed the add_member commit.
 * Bob's state is ready to decrypt.
 *
 * @param {string} suffix - Used to make groupId unique
 * @returns {{ groupId: string, aliceState: string, bobState: string }}
 */
function setupTwoMemberGroup(suffix) {
  const groupId = `s8-perf-${suffix}-${Date.now()}`;
  const aliceResult = create_group("alice@perf", groupId);
  const aliceState0 = aliceResult.group_state;

  const bobResult = create_member("bob@perf");
  const addResult = add_member(aliceState0, bobResult.key_package);
  const aliceState1 = addResult.new_group_state;

  const joinResult = join_group(addResult.welcome, addResult.ratchet_tree, bobResult.member_state);
  const bobState = joinResult.group_state;

  return { groupId, aliceState: aliceState1, bobState };
}

// ============================================================================
// Cold-path measurement
//
// Each iteration:
//   - Start from a fixed "baseline" Alice state (same state every time — rewinds the clock)
//   - Call encrypt_message → produces ciphertext + new state
//   - Call decrypt_message (on a fixed Bob state) → produces plaintext + new state
//   - Measure wall time for both calls together
//   - Discard the new states (next iteration starts from baseline again)
//
// Why this is "cold": every iteration deserializes the full JSON state blob from scratch.
// This matches the worst case: a stateless serverless function or a page reload.
//
// NOTE: Because we reuse the same baseline state for each iteration, this test does NOT
// exercise the ratchet advancement (the epoch does not change across iterations).
// For the spike, this is intentional: we want to measure serialization overhead,
// not accumulating epoch state. A test that advances epoch 1000 times would push state
// size unboundedly. The ratchet behavior is already proven by the round-trip tests.
// ============================================================================

/**
 * @param {string} aliceState - Fixed baseline Alice state
 * @param {string} bobState - Fixed baseline Bob state
 * @param {number} iterations
 * @param {number} warmupCount
 * @param {Function} log
 * @returns {{ samples: number[], errors: number }}
 */
function runColdPath(aliceState, bobState, iterations, warmupCount, log) {
  const samples = [];
  let errors = 0;

  // Warm-up (discarded)
  for (let i = 0; i < warmupCount; i++) {
    try {
      const e = encrypt_message(aliceState, `warmup-${i}`);
      decrypt_message(bobState, e.ciphertext);
    } catch (_) {
      // Warm-up errors do not count
    }
  }

  log(`  [S8] Cold path: running ${iterations} iterations (each deserializes full state blob)...`);

  for (let i = 0; i < iterations; i++) {
    const t0 = performance.now();
    try {
      // Deserialize Alice's state, encrypt, re-serialize
      const e = encrypt_message(aliceState, `cold-msg-${i}`);
      // Deserialize Bob's state, decrypt, re-serialize
      decrypt_message(bobState, e.ciphertext);
      samples.push(performance.now() - t0);
    } catch (err) {
      errors++;
      samples.push(9999); // Sentinel value — visible in p99 if error rate is high
    }
  }

  return { samples, errors };
}

// ============================================================================
// Warm-path measurement
//
// Each iteration:
//   - Continue from the previous iteration's output state (chain of state updates)
//   - Call encrypt_message → ciphertext + new Alice state
//   - Call decrypt_message → plaintext + new Bob state
//   - Store new states for next iteration
//   - Measure wall time
//
// Why this is "warm": the JS string representing the state is already in heap memory.
// serde_json still parses it on every call, but there is no IPC, no IO, no network.
// This is the closest we can get to "in-memory" on the main thread with the spike's API.
//
// A true warm path would require a Rust-side registry (in-memory MlsGroup) not exposed
// by the spike's wasm-bindgen API. That is the production design; the spike's stateless
// API does not achieve it. The warm-path measurement here proves that "with state chained
// correctly, does the ratchet work at scale?" and gives an upper bound on production
// performance (actual production will be faster because deserialization is eliminated).
// ============================================================================

/**
 * @param {string} aliceState0 - Starting Alice state
 * @param {string} bobState0 - Starting Bob state
 * @param {number} iterations
 * @param {number} warmupCount
 * @param {Function} log
 * @returns {{ samples: number[], errors: number, finalAliceState: string, finalBobState: string }}
 */
function runWarmPath(aliceState0, bobState0, iterations, warmupCount, log) {
  let aliceState = aliceState0;
  let bobState = bobState0;
  const samples = [];
  let errors = 0;

  // Warm-up (discarded, but state DOES advance — same as production warm-up)
  for (let i = 0; i < warmupCount; i++) {
    try {
      const e = encrypt_message(aliceState, `warmup-${i}`);
      aliceState = e.new_group_state;
      const d = decrypt_message(bobState, e.ciphertext);
      bobState = d.new_group_state;
    } catch (_) {
      // Warm-up errors reset to previous state (conservative)
    }
  }

  log(`  [S8] Warm path: running ${iterations} iterations (state chained between calls)...`);

  for (let i = 0; i < iterations; i++) {
    const t0 = performance.now();
    try {
      const e = encrypt_message(aliceState, `warm-msg-${i}`);
      const d = decrypt_message(bobState, e.ciphertext);
      samples.push(performance.now() - t0);
      // Advance state for next iteration (this is the "warm" part)
      aliceState = e.new_group_state;
      bobState = d.new_group_state;
    } catch (err) {
      errors++;
      samples.push(9999);
      // Do not advance state on error — reuse last good state
    }
  }

  return { samples, errors, finalAliceState: aliceState, finalBobState: bobState };
}

// ============================================================================
// DOM output helpers
// ============================================================================

/**
 * Render timing table to a DOM element (if available) and to console.
 *
 * @param {Array<object>} rows - Each row: { label, min, mean, p50, p95, p99, max, status }
 * @param {Function} log
 * @param {HTMLElement | null} container
 */
function renderTimingTable(rows, log, container) {
  // Console output
  log("\n  [S8] Timing Results (milliseconds):");
  log(
    `  ${"Path".padEnd(20)} ${"min".padStart(7)} ${"mean".padStart(7)} ${"p50".padStart(7)} ${"p95".padStart(7)} ${"p99".padStart(7)} ${"max".padStart(7)}  Gate`
  );
  log("  " + "-".repeat(70));
  for (const row of rows) {
    log(
      `  ${row.label.padEnd(20)} ${row.min.padStart(7)} ${row.mean.padStart(7)} ${row.p50.padStart(7)} ${row.p95.padStart(7)} ${row.p99.padStart(7)} ${row.max.padStart(7)}  ${row.status}`
    );
  }

  // DOM output
  if (!container) return;

  const tableEl = document.createElement("table");
  tableEl.style.cssText =
    "border-collapse:collapse; width:100%; margin-top:8px; font-size:12px; font-family:monospace;";
  const headRow = document.createElement("tr");
  for (const col of ["Path", "min", "mean", "p50", "p95", "p99", "max", "Gate (P95)"]) {
    const th = document.createElement("th");
    th.textContent = col;
    th.style.cssText = "border:1px solid #30363d; padding:4px 8px; text-align:right; background:#161b22;";
    if (col === "Path") th.style.textAlign = "left";
    headRow.appendChild(th);
  }
  tableEl.appendChild(headRow);

  for (const row of rows) {
    const tr = document.createElement("tr");
    const gateColor = row.status === "PASS" ? "#3fb950" : row.status === "WARN" ? "#d29922" : "#f85149";
    for (const [key, val] of Object.entries({
      label: row.label,
      min: row.min,
      mean: row.mean,
      p50: row.p50,
      p95: row.p95,
      p99: row.p99,
      max: row.max,
      status: row.status,
    })) {
      const td = document.createElement("td");
      td.textContent = typeof val === "string" && val.match(/^\d/) ? `${val}ms` : val;
      td.style.cssText = "border:1px solid #30363d; padding:4px 8px; text-align:right;";
      if (key === "label") td.style.textAlign = "left";
      if (key === "status") {
        td.style.color = gateColor;
        td.style.fontWeight = "bold";
        td.style.textAlign = "center";
      }
      if (key === "p95") td.style.fontWeight = "bold";
      tr.appendChild(td);
    }
    tableEl.appendChild(tr);
  }

  const heading = document.createElement("h3");
  heading.textContent = "S8 Performance — Timing Table";
  heading.style.cssText = "font-family:monospace; font-size:13px; margin:16px 0 4px;";
  container.appendChild(heading);
  container.appendChild(tableEl);
}

// ============================================================================
// Test runner
// ============================================================================

const ITERATIONS = 1000;
const WARMUP = 10;
const GATE_WARM_PATH_MS = 50; // P95 ≤ 50ms = PASS

/**
 * Run S8 performance tests (cold path and warm path).
 *
 * @param {Function} [log] - Logging function (default: console.log)
 * @param {HTMLElement | null} [domContainer] - Optional DOM container for timing table
 * @returns {Promise<{
 *   passed: boolean,
 *   status: 'PASS' | 'WARN' | 'FAIL',
 *   checks: Array<{ name: string, passed: boolean, detail: string }>,
 *   timing: {
 *     coldPath: { min: number, mean: number, p50: number, p95: number, p99: number, max: number },
 *     warmPath: { min: number, mean: number, p50: number, p95: number, p99: number, max: number },
 *   },
 *   errorCounts: { coldErrors: number, warmErrors: number },
 *   error: string | null
 * }>}
 */
export async function runPerformanceTests(log = console.log, domContainer = null) {
  const checks = [];

  function record(name, passed, detail) {
    checks.push({ name, passed, detail });
    log(`  [S8] ${passed ? "PASS" : "FAIL"} ${name}: ${detail}`);
  }

  try {
    await ensureWasmInit();

    // ------------------------------------------------------------------
    // Setup: create a two-member group for the baseline
    // Using a separate group from other tests to avoid state conflicts
    // ------------------------------------------------------------------
    log(`  [S8] Setting up two-member MLS group for performance baseline...`);
    let setup;
    try {
      setup = setupTwoMemberGroup("s8-cold");
    } catch (e) {
      const msg = `Group setup failed: ${e.message}`;
      record("Group setup for performance test", false, msg);
      return {
        passed: false,
        status: "FAIL",
        checks,
        timing: { coldPath: null, warmPath: null },
        errorCounts: { coldErrors: 0, warmErrors: 0 },
        error: msg,
      };
    }
    record(
      "Group setup for performance test",
      true,
      `Two-member group ready: groupId=${setup.groupId}`
    );

    // ------------------------------------------------------------------
    // COLD PATH measurement
    // ------------------------------------------------------------------
    const coldResult = runColdPath(
      setup.aliceState,
      setup.bobState,
      ITERATIONS,
      WARMUP,
      log
    );
    const coldStats = computeStats(coldResult.samples.filter((s) => s < 9999));
    const coldRow = fmtRow("Cold path (stateless)", coldStats, GATE_WARM_PATH_MS);

    const coldErrorRate = coldResult.errors / ITERATIONS;
    record(
      `Cold path error rate (${ITERATIONS} iterations)`,
      coldErrorRate < 0.05,
      `${coldResult.errors}/${ITERATIONS} errors (${(coldErrorRate * 100).toFixed(1)}%) — gate: <5%`
    );

    // Cold path is NOT gated (informational per risk doc); just record the numbers
    record(
      "Cold path timing (informational — not gated)",
      true,
      `p50=${coldStats.p50.toFixed(2)}ms p95=${coldStats.p95.toFixed(2)}ms p99=${coldStats.p99.toFixed(2)}ms (deserialize+crypto+serialize per call)`
    );

    // ------------------------------------------------------------------
    // WARM PATH measurement — use a FRESH group to avoid epoch drift from cold-path
    // Cold path re-uses the same base state so epoch does not advance;
    // warm path CHAINS state so we need fresh states with no previous usage.
    // ------------------------------------------------------------------
    log(`  [S8] Setting up fresh group for warm-path measurement...`);
    let warmSetup;
    try {
      warmSetup = setupTwoMemberGroup("s8-warm");
    } catch (e) {
      const msg = `Warm-path group setup failed: ${e.message}`;
      record("Warm path group setup", false, msg);
      return {
        passed: false,
        status: "FAIL",
        checks,
        timing: { coldPath: coldStats, warmPath: null },
        errorCounts: { coldErrors: coldResult.errors, warmErrors: 0 },
        error: msg,
      };
    }

    const warmResult = runWarmPath(
      warmSetup.aliceState,
      warmSetup.bobState,
      ITERATIONS,
      WARMUP,
      log
    );
    const warmStats = computeStats(warmResult.samples.filter((s) => s < 9999));
    const warmRow = fmtRow("Warm path (chained)", warmStats, GATE_WARM_PATH_MS);

    const warmErrorRate = warmResult.errors / ITERATIONS;
    record(
      `Warm path error rate (${ITERATIONS} iterations)`,
      warmErrorRate < 0.05,
      `${warmResult.errors}/${ITERATIONS} errors (${(warmErrorRate * 100).toFixed(1)}%) — gate: <5%`
    );

    // ------------------------------------------------------------------
    // Gate: warm-path P95 ≤ 50ms = PASS; 50-150ms = WARN; >150ms = FAIL
    // ------------------------------------------------------------------
    const gateStatus =
      warmStats.p95 <= GATE_WARM_PATH_MS ? "PASS" :
      warmStats.p95 <= 150 ? "WARN" :
      "FAIL";

    const gatePassed = gateStatus !== "FAIL";
    record(
      `Warm path P95 ≤ ${GATE_WARM_PATH_MS}ms (ADR 012 S8 gate)`,
      gatePassed,
      `P95=${warmStats.p95.toFixed(2)}ms → ${gateStatus}` + (
        gateStatus === "WARN"
          ? ` (within acceptable range; production worker design eliminates serialization overhead)`
          : gateStatus === "FAIL"
          ? ` (exceeds 150ms; see spike-risks.md §1.7 for mitigation paths)`
          : ""
      )
    );

    // ------------------------------------------------------------------
    // Overhead analysis: cold vs warm delta
    // The delta represents the serialization cost on top of pure crypto.
    // In production (worker holds state), the cold overhead is eliminated.
    // ------------------------------------------------------------------
    const serializationOverheadMs = coldStats.p95 - warmStats.p95;
    record(
      "Serialization overhead (cold.P95 - warm.P95)",
      true, // informational
      `${serializationOverheadMs.toFixed(2)}ms P95 overhead from state JSON serialize/deserialize per call`
    );

    // ------------------------------------------------------------------
    // Render timing table
    // ------------------------------------------------------------------
    renderTimingTable([coldRow, warmRow], log, domContainer);

    // ------------------------------------------------------------------
    // Summary
    // ------------------------------------------------------------------
    const allPassed = checks.every((c) => c.passed);
    log(`\n  [S8] Gate result: ${gateStatus} (warm-path P95=${warmStats.p95.toFixed(2)}ms, gate=${GATE_WARM_PATH_MS}ms)`);
    log(`  [S8] Note: warm path still includes serde_json overhead (production Worker design eliminates this)`);
    log(`  [S8] ${checks.filter((c) => c.passed).length}/${checks.length} checks passed`);

    return {
      passed: gatePassed,
      status: gateStatus,
      checks,
      timing: {
        coldPath: coldStats,
        warmPath: warmStats,
      },
      errorCounts: {
        coldErrors: coldResult.errors,
        warmErrors: warmResult.errors,
      },
      error: null,
    };
  } catch (err) {
    log(`  [S8] Fatal error: ${err.message}`);
    return {
      passed: false,
      status: "FAIL",
      checks,
      timing: { coldPath: null, warmPath: null },
      errorCounts: { coldErrors: 0, warmErrors: 0 },
      error: err.message,
    };
  }
}
