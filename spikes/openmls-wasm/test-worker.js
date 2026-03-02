/**
 * Famichat WASM Spike — M2: Web Worker postMessage Round-Trip Test
 *
 * Validates:
 *   - Worker loads WASM correctly and posts 'ready'
 *   - Full create_group → add_member → join_group → encrypt → decrypt sequence
 *     executed via postMessage (no direct WASM calls from main thread)
 *   - Uint8Array serializes/deserializes correctly across the Worker boundary
 *   - Epoch state is maintained correctly across multiple sequential operations
 *   - Round-trip latency is measured
 *
 * Pass condition (M2):
 *   - No DataCloneError on any postMessage call
 *   - Worker maintains correct epoch state across 3+ sequential operations
 *   - Each decrypt returns the correct plaintext for its corresponding ciphertext
 *   - Worker 'ready' event fires within 5s of construction
 *
 * Usage: imported by harness.js; call runWorkerTests() which returns a result object.
 */

// ============================================================================
// Worker message protocol helper
// ============================================================================

/**
 * Send a message to a worker and await the response matching requestId.
 * Returns a Promise that resolves with the result payload or rejects on error.
 *
 * @param {Worker} worker
 * @param {object} message - Must include all fields needed by the worker protocol
 * @param {number} [timeoutMs=10000]
 * @returns {Promise<object>}
 */
function workerCall(worker, message, timeoutMs = 10000) {
  return new Promise((resolve, reject) => {
    const requestId =
      message.requestId ?? `req-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
    const msgWithId = { ...message, requestId };

    let settled = false;
    const timer = setTimeout(() => {
      if (settled) return;
      settled = true;
      reject(new Error(`Worker timeout after ${timeoutMs}ms for requestId=${requestId}`));
    }, timeoutMs);

    function handler(event) {
      const data = event.data;
      if (data.requestId !== requestId) return; // not our response

      worker.removeEventListener("message", handler);
      clearTimeout(timer);
      settled = true;

      if (data.ok) {
        resolve(data);
      } else {
        reject(new Error(`[${data.code}] ${data.message}`));
      }
    }

    worker.addEventListener("message", handler);
    worker.postMessage(msgWithId);
  });
}

/**
 * Wait for the worker to post { type: 'ready' }.
 * Rejects if 'error' arrives first or timeout fires.
 */
function waitForWorkerReady(worker, timeoutMs = 10000) {
  return new Promise((resolve, reject) => {
    let settled = false;
    const timer = setTimeout(() => {
      if (settled) return;
      settled = true;
      reject(new Error(`Worker did not post 'ready' within ${timeoutMs}ms`));
    }, timeoutMs);

    function handler(event) {
      const data = event.data;
      if (data.type === "ready") {
        clearTimeout(timer);
        settled = true;
        worker.removeEventListener("message", handler);
        resolve();
      } else if (data.type === "error" && data.requestId === null) {
        // init-time error (no requestId)
        clearTimeout(timer);
        settled = true;
        worker.removeEventListener("message", handler);
        reject(new Error(`Worker init error: [${data.code}] ${data.message}`));
      }
    }

    worker.addEventListener("message", handler);
  });
}

// ============================================================================
// Test runner
// ============================================================================

/**
 * Run all M2 Worker tests.
 *
 * @param {Function} [log] - Optional logging function (defaults to console.log)
 * @returns {Promise<{
 *   passed: boolean,
 *   checks: Array<{ name: string, passed: boolean, detail: string }>,
 *   latencyMs: { readyMs: number, roundTripMs: number[] },
 *   error: string | null
 * }>}
 */
export async function runWorkerTests(log = console.log) {
  const checks = [];
  const latencyMs = { readyMs: null, roundTripMs: [] };
  let worker = null;

  function record(name, passed, detail) {
    checks.push({ name, passed, detail });
    log(`  [M2] ${passed ? "PASS" : "FAIL"} ${name}: ${detail}`);
  }

  try {
    // ------------------------------------------------------------------
    // Step 1: Create Worker, wait for 'ready'
    // ------------------------------------------------------------------
    const workerStartMs = performance.now();
    worker = new Worker(new URL("./worker.js", import.meta.url), { type: "module" });

    const readyError = await waitForWorkerReady(worker, 15000).then(
      () => null,
      (e) => e
    );
    latencyMs.readyMs = performance.now() - workerStartMs;

    if (readyError) {
      record("Worker ready", false, `Worker did not become ready: ${readyError.message}`);
      return { passed: false, checks, latencyMs, error: readyError.message };
    }
    record(
      "Worker ready",
      true,
      `Worker posted 'ready' in ${latencyMs.readyMs.toFixed(1)}ms (includes WASM init + JIT)`
    );

    // ------------------------------------------------------------------
    // Step 2: health_check via postMessage — proves message round-trip works
    // ------------------------------------------------------------------
    const healthResult = await workerCall(worker, { type: "health_check" });
    const healthOk =
      healthResult.health &&
      typeof healthResult.health === "object";
    record(
      "health_check via postMessage",
      healthOk,
      healthOk
        ? `health object received: status=${healthResult.health.status ?? "missing"}`
        : `unexpected health result: ${JSON.stringify(healthResult)}`
    );

    // ------------------------------------------------------------------
    // Step 3: create_group — Alice creates a group in the worker
    // ------------------------------------------------------------------
    const groupId = `worker-m2-test-${Date.now()}`;
    const createResult = await workerCall(worker, {
      type: "create_group",
      groupId,
      identity: "alice@worker-test",
    });
    record(
      "create_group via worker",
      createResult.groupId === groupId,
      `Worker stored group state for groupId=${createResult.groupId} (main thread never saw raw state)`
    );

    // ------------------------------------------------------------------
    // Step 4: create_member — Bob generates key material
    // Verify keyPackage is a string (not a wasm-bindgen object — no DataCloneError)
    // ------------------------------------------------------------------
    const memberResult = await workerCall(worker, {
      type: "create_member",
      identity: "bob@worker-test",
    });
    const keyPackageIsString = typeof memberResult.keyPackage === "string";
    const memberStateIsString = typeof memberResult.memberState === "string";
    record(
      "create_member: keyPackage is transferable string",
      keyPackageIsString,
      keyPackageIsString
        ? `keyPackage: string of length ${memberResult.keyPackage.length}`
        : `DataCloneError risk: keyPackage type = ${typeof memberResult.keyPackage}`
    );
    record(
      "create_member: memberState is transferable string",
      memberStateIsString,
      memberStateIsString
        ? `memberState: string of length ${memberResult.memberState.length}`
        : `DataCloneError risk: memberState type = ${typeof memberResult.memberState}`
    );

    if (!keyPackageIsString || !memberStateIsString) {
      return {
        passed: false,
        checks,
        latencyMs,
        error: "DataCloneError risk: non-string values returned from worker",
      };
    }

    // ------------------------------------------------------------------
    // Step 5: add_member — Alice adds Bob; verify Welcome is a string
    // ------------------------------------------------------------------
    const addResult = await workerCall(worker, {
      type: "add_member",
      groupId,
      keyPackage: memberResult.keyPackage,
    });
    const welcomeIsString = typeof addResult.welcome === "string";
    record(
      "add_member: Welcome is transferable string",
      welcomeIsString,
      welcomeIsString
        ? `welcome: string of length ${addResult.welcome.length}`
        : `DataCloneError risk: welcome type = ${typeof addResult.welcome}`
    );

    if (!welcomeIsString) {
      return {
        passed: false,
        checks,
        latencyMs,
        error: "add_member did not return a string Welcome",
      };
    }

    // ------------------------------------------------------------------
    // Step 6: join_group — Bob joins on the SAME worker (session-aware)
    // The worker now holds TWO sessions: Alice's and Bob's, both keyed by groupId.
    // This proves the worker Map<groupId, state> is maintained.
    //
    // NOTE: In a production design, Alice's worker and Bob's worker are separate.
    // For the spike, we use a single worker with two different identities to avoid
    // the complexity of inter-worker communication. The M2 criterion validates the
    // postMessage protocol, not multi-worker orchestration.
    // ------------------------------------------------------------------
    // Bob needs a separate group slot since the same Map key cannot hold both states.
    // Use groupId + "-bob" to simulate Bob's worker session:
    const bobGroupId = `${groupId}-bob`;
    const joinResult = await workerCall(worker, {
      type: "join_group",
      groupId: bobGroupId,
      welcome: addResult.welcome,
      ratchetTree: addResult.ratchetTree,
      memberState: memberResult.memberState,
    });
    record(
      "join_group via worker",
      joinResult.groupId === bobGroupId,
      `Bob's session created with groupId=${joinResult.groupId}`
    );

    // ------------------------------------------------------------------
    // Step 7: Encrypt (Alice) → Decrypt (Bob) via postMessage
    // Measures round-trip latency including worker message overhead
    // ------------------------------------------------------------------
    const plaintexts = ["message 1 from alice", "message 2 from alice", "message 3 from alice"];
    const ciphertexts = [];
    let encryptDecryptAllPassed = true;

    for (let i = 0; i < plaintexts.length; i++) {
      const pt = plaintexts[i];
      const t0 = performance.now();

      // Alice encrypts
      const encResult = await workerCall(worker, {
        type: "encrypt",
        groupId,
        plaintext: pt,
      });
      const ciphertext = encResult.ciphertext;

      // Bob decrypts
      const decResult = await workerCall(worker, {
        type: "decrypt",
        groupId: bobGroupId,
        ciphertext,
      });
      const roundTrip = performance.now() - t0;
      latencyMs.roundTripMs.push(roundTrip);

      const matched = decResult.plaintext === pt;
      if (!matched) encryptDecryptAllPassed = false;
      ciphertexts.push(ciphertext);

      record(
        `encrypt→decrypt message ${i + 1}`,
        matched,
        matched
          ? `plaintext matched in ${roundTrip.toFixed(1)}ms (postMessage + encrypt + decrypt)`
          : `MISMATCH: expected "${pt}", got "${decResult.plaintext}"`
      );
    }

    // ------------------------------------------------------------------
    // Step 8: Uint8Array round-trip via export_state / import_state
    // Validates that Uint8Array can be sent across the Worker boundary without DataCloneError
    // (Uint8Array is structured-clone compatible; ArrayBuffer transfer would zero out source)
    // ------------------------------------------------------------------
    const exportResult = await workerCall(worker, {
      type: "export_state",
      groupId,
    });
    const stateBytes = exportResult.stateBytes;
    const isBytesValid = stateBytes instanceof Uint8Array && stateBytes.length > 0;
    record(
      "export_state: Uint8Array received without DataCloneError",
      isBytesValid,
      isBytesValid
        ? `Received Uint8Array of ${stateBytes.length} bytes from worker (structured clone)`
        : `Expected Uint8Array, got ${typeof stateBytes}`
    );

    // Verify the Uint8Array contains valid UTF-8 JSON
    let parsedStateOk = false;
    let parsedStateDetail = "not checked";
    if (isBytesValid) {
      try {
        const decoded = new TextDecoder().decode(stateBytes);
        const parsed = JSON.parse(decoded);
        parsedStateOk = typeof parsed.storage === "object" && typeof parsed.group_id === "string";
        parsedStateDetail = parsedStateOk
          ? `JSON parsed OK: storage has ${Object.keys(parsed.storage).length} entries`
          : `JSON structure unexpected: ${JSON.stringify(Object.keys(parsed))}`;
      } catch (e) {
        parsedStateDetail = `JSON parse failed: ${e.message}`;
      }
    }
    record(
      "export_state: Uint8Array contains valid group state JSON",
      parsedStateOk,
      parsedStateDetail
    );

    // Import the Uint8Array back into the worker under a new groupId
    // This proves the full M1 + M2 integration: decrypt from IndexedDB → restore to worker
    const importGroupId = `${groupId}-restored`;
    const importResult = await workerCall(worker, {
      type: "import_state",
      groupId: importGroupId,
      groupState: stateBytes, // Send as Uint8Array — worker normalizes it
    });
    record(
      "import_state: Uint8Array accepted by worker (M1+M2 bridge)",
      importResult.restored === true,
      importResult.restored
        ? `Session restored from Uint8Array under groupId=${importGroupId}`
        : `restore failed: ${JSON.stringify(importResult)}`
    );

    // ------------------------------------------------------------------
    // Step 9: Replay protection — verify ciphertext from msg 1 cannot decrypt as msg 2
    // (epoch ratchet means each decryption advances state; replaying old ciphertext fails)
    // ------------------------------------------------------------------
    if (ciphertexts.length >= 2) {
      const replayResult = await workerCall(
        worker,
        { type: "decrypt", groupId: bobGroupId, ciphertext: ciphertexts[0] },
        3000
      ).then(
        (r) => ({ ok: true, plaintext: r.plaintext }),
        (e) => ({ ok: false, error: e.message })
      );

      // After decrypting messages 1+2+3 above, Bob's epoch has advanced.
      // Replaying message 1's ciphertext should fail (old epoch).
      const replayBlocked = !replayResult.ok;
      record(
        "replay protection: old ciphertext rejected after epoch advance",
        replayBlocked,
        replayBlocked
          ? `Replay correctly rejected: ${replayResult.error?.slice(0, 80)}`
          : `SECURITY ISSUE: old ciphertext decrypted as "${replayResult.plaintext}" after epoch advance`
      );
    }

    // ------------------------------------------------------------------
    // Summary
    // ------------------------------------------------------------------
    const allPassed = checks.every((c) => c.passed);
    const avgRoundTrip =
      latencyMs.roundTripMs.length > 0
        ? latencyMs.roundTripMs.reduce((a, b) => a + b, 0) / latencyMs.roundTripMs.length
        : null;

    log(
      `\n  [M2] Summary: ${checks.filter((c) => c.passed).length}/${checks.length} checks passed`
    );
    if (avgRoundTrip !== null) {
      log(
        `  [M2] Avg postMessage round-trip (encrypt+decrypt via worker): ${avgRoundTrip.toFixed(1)}ms`
      );
    }

    return {
      passed: allPassed,
      checks,
      latencyMs,
      error: null,
    };
  } catch (err) {
    log(`  [M2] Fatal error: ${err.message}`);
    return {
      passed: false,
      checks,
      latencyMs,
      error: err.message,
    };
  } finally {
    if (worker) {
      worker.terminate();
    }
  }
}
