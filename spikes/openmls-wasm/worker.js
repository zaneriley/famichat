/**
 * Famichat WASM Spike — Web Worker (M2 criterion)
 *
 * Architecture: worker owns all MLS group state in memory.
 * Main thread never holds raw group state blobs after handing them to the worker.
 * This matches the production design described in ADR 012 and proposal-02-v2.
 *
 * State ownership model:
 *   - Worker maintains a Map<groupId, string> of serialized group states.
 *   - All WASM functions take/return base64 JSON blobs (the spike's stateless API).
 *   - The worker is the "session" — it deserializes state, calls WASM, stores updated state.
 *   - Main thread only passes groupId references and plaintext/ciphertext payloads.
 *
 * Message protocol (main → worker):
 *   { type: 'create_group', groupId: string, identity: string }
 *   { type: 'create_member', requestId: string, identity: string }
 *   { type: 'add_member', groupId: string, keyPackage: string }
 *   { type: 'join_group', requestId: string, groupId: string, welcome: string, ratchetTree: string, memberState: string }
 *   { type: 'process_commit', groupId: string, commit: string }
 *   { type: 'encrypt', groupId: string, plaintext: string, requestId: string }
 *   { type: 'decrypt', groupId: string, ciphertext: string, requestId: string }
 *   { type: 'export_state', groupId: string, requestId: string }
 *   { type: 'import_state', groupId: string, groupState: Uint8Array | string, requestId: string }
 *   { type: 'health_check', requestId: string }
 *
 * Message protocol (worker → main):
 *   { type: 'ready' }
 *   { type: 'result', requestId: string, ok: true, ...payload }
 *   { type: 'error', requestId: string, ok: false, code: string, message: string }
 *
 * Uint8Array serialization note:
 *   Group state can optionally be passed as Uint8Array (for M1 IndexedDB integration).
 *   The worker converts Uint8Array → string via TextDecoder before passing to WASM.
 *   Results are returned as plain strings (not transferred), ensuring no DataCloneError.
 */

// bundler target (wasm-pack --target bundler) does NOT export a default `init`.
// The WASM binary is instantiated automatically via vite-plugin-wasm on import.
// We import the named functions directly. `init` is intentionally not imported here.
import {
  health_check,
  create_group,
  create_member,
  add_member,
  join_group,
  process_commit,
  encrypt_message,
  decrypt_message,
} from "@famichat/mls-wasm";

// Shim: bundler target has no init(); guard against any call attempt.
const init = undefined;

// ============================================================================
// Worker state: group sessions stored by groupId
// ============================================================================

/**
 * In-memory session registry.
 * Key: groupId (string)
 * Value: serialized group state JSON string (from the WASM API)
 *
 * This is the "warm path" state — the worker keeps state alive between calls,
 * eliminating the need for callers to pass full group state blobs on every message.
 */
const groupSessions = new Map();

// ============================================================================
// Initialization
// ============================================================================

let wasmReady = false;

async function initWorker() {
  try {
    // bundler target (wasm-pack --target bundler): WASM is instantiated automatically
    // via the static `import * as wasm from "./mls_wasm_bg.wasm"` at the top of mls_wasm.js.
    // vite-plugin-wasm intercepts that import in the worker bundle too.
    // In bundler mode, `init` is NOT exported — calling init() would throw TypeError.
    // In web/nodejs targets, `init` is the default export and must be called.
    // We handle both cases by checking if init is callable before invoking it.
    if (typeof init === "function") {
      await init();
    }
    wasmReady = true;
    self.postMessage({ type: "ready" });
  } catch (err) {
    self.postMessage({
      type: "error",
      requestId: null,
      ok: false,
      code: "init_failed",
      message: String(err),
    });
  }
}

// ============================================================================
// Helper: send result or error
// ============================================================================

function respond(requestId, payload) {
  self.postMessage({ type: "result", requestId, ok: true, ...payload });
}

function respondError(requestId, code, message) {
  self.postMessage({ type: "error", requestId, ok: false, code, message });
}

function checkReady(requestId) {
  if (!wasmReady) {
    respondError(requestId, "not_ready", "WASM not yet initialized");
    return false;
  }
  return true;
}

/**
 * Normalize group state to string.
 * Accepts either a string (from WASM) or Uint8Array (from IndexedDB decryption).
 * This is the critical M1+M2 bridge: IndexedDB stores encrypted bytes,
 * after decryption we get a Uint8Array containing UTF-8 JSON, which the worker
 * decodes here before calling WASM.
 */
function normalizeGroupState(groupState) {
  if (groupState instanceof Uint8Array) {
    return new TextDecoder().decode(groupState);
  }
  if (typeof groupState === "string") {
    return groupState;
  }
  throw new Error(
    `Invalid group state type: expected string or Uint8Array, got ${typeof groupState}`
  );
}

// ============================================================================
// Message dispatch
// ============================================================================

self.onmessage = function (event) {
  const msg = event.data;
  const requestId = msg.requestId ?? null;

  if (!checkReady(requestId)) return;

  try {
    switch (msg.type) {
      // ------------------------------------------------------------------
      // health_check: verify WASM + CSPRNG + clock are operational
      // ------------------------------------------------------------------
      case "health_check": {
        const result = health_check();
        respond(requestId, { health: result });
        break;
      }

      // ------------------------------------------------------------------
      // create_group: Alice creates a new MLS group
      // Stores initial group state in worker memory
      // ------------------------------------------------------------------
      case "create_group": {
        const { groupId, identity } = msg;
        if (!groupId || !identity) {
          respondError(requestId, "invalid_input", "groupId and identity required");
          break;
        }

        const result = create_group(identity, groupId);
        // create_group returns { group_state, identity, group_id }
        const groupState = result.group_state;
        groupSessions.set(groupId, groupState);

        respond(requestId, {
          groupId,
          identity: result.identity,
        });
        break;
      }

      // ------------------------------------------------------------------
      // create_member: generate key material for a new member (Bob)
      // Returns key_package (to share with Alice) and member_state (for join_group)
      // ------------------------------------------------------------------
      case "create_member": {
        const { identity } = msg;
        if (!identity) {
          respondError(requestId, "invalid_input", "identity required");
          break;
        }

        const result = create_member(identity);
        // Returns { key_package, member_state } — no group state to store yet
        respond(requestId, {
          keyPackage: result.key_package,
          memberState: result.member_state,
        });
        break;
      }

      // ------------------------------------------------------------------
      // add_member: Alice adds Bob to the group
      // Updates Alice's stored group state; returns Welcome for Bob
      // ------------------------------------------------------------------
      case "add_member": {
        const { groupId, keyPackage } = msg;
        if (!groupId || !keyPackage) {
          respondError(requestId, "invalid_input", "groupId and keyPackage required");
          break;
        }

        const currentState = groupSessions.get(groupId);
        if (!currentState) {
          respondError(requestId, "group_not_found", `No session for groupId: ${groupId}`);
          break;
        }

        const result = add_member(currentState, keyPackage);
        // add_member returns { welcome, ratchet_tree, commit, new_group_state }
        groupSessions.set(groupId, result.new_group_state);

        respond(requestId, {
          welcome: result.welcome,
          ratchetTree: result.ratchet_tree,
          commit: result.commit,
        });
        break;
      }

      // ------------------------------------------------------------------
      // join_group: Bob joins via Welcome
      // Stores Bob's group state in worker memory
      // ------------------------------------------------------------------
      case "join_group": {
        const { groupId, welcome, ratchetTree, memberState } = msg;
        if (!groupId || !welcome || !memberState) {
          respondError(requestId, "invalid_input", "groupId, welcome, and memberState required");
          break;
        }

        const result = join_group(welcome, ratchetTree ?? "", memberState);
        // join_group returns { group_state }
        groupSessions.set(groupId, result.group_state);

        respond(requestId, { groupId });
        break;
      }

      // ------------------------------------------------------------------
      // process_commit: apply a commit from another member (epoch advance)
      // Updates stored group state
      // ------------------------------------------------------------------
      case "process_commit": {
        const { groupId, commit } = msg;
        if (!groupId || !commit) {
          respondError(requestId, "invalid_input", "groupId and commit required");
          break;
        }

        const currentState = groupSessions.get(groupId);
        if (!currentState) {
          respondError(requestId, "group_not_found", `No session for groupId: ${groupId}`);
          break;
        }

        const result = process_commit(currentState, commit);
        // process_commit returns { new_group_state }
        groupSessions.set(groupId, result.new_group_state);

        respond(requestId, { groupId });
        break;
      }

      // ------------------------------------------------------------------
      // encrypt: encrypt a plaintext message
      // Worker holds state — main thread sends groupId + plaintext only
      // Updated state stored back in worker memory (warm path)
      // ------------------------------------------------------------------
      case "encrypt": {
        const { groupId, plaintext } = msg;
        if (!groupId || !plaintext) {
          respondError(requestId, "invalid_input", "groupId and plaintext required");
          break;
        }

        const currentState = groupSessions.get(groupId);
        if (!currentState) {
          respondError(requestId, "group_not_found", `No session for groupId: ${groupId}`);
          break;
        }

        const result = encrypt_message(currentState, plaintext);
        // encrypt_message returns { ciphertext, new_group_state }
        groupSessions.set(groupId, result.new_group_state);

        respond(requestId, { ciphertext: result.ciphertext });
        break;
      }

      // ------------------------------------------------------------------
      // decrypt: decrypt a ciphertext message
      // Worker holds state — main thread sends groupId + ciphertext only
      // Updated state stored back in worker memory (warm path)
      // ------------------------------------------------------------------
      case "decrypt": {
        const { groupId, ciphertext } = msg;
        if (!groupId || !ciphertext) {
          respondError(requestId, "invalid_input", "groupId and ciphertext required");
          break;
        }

        const currentState = groupSessions.get(groupId);
        if (!currentState) {
          respondError(requestId, "group_not_found", `No session for groupId: ${groupId}`);
          break;
        }

        const result = decrypt_message(currentState, ciphertext);
        // decrypt_message returns { plaintext, new_group_state }
        groupSessions.set(groupId, result.new_group_state);

        respond(requestId, { plaintext: result.plaintext });
        break;
      }

      // ------------------------------------------------------------------
      // export_state: serialize current group state to Uint8Array for IndexedDB storage.
      // Returns the raw UTF-8 bytes of the group state JSON blob.
      // Caller encrypts these bytes with WebCrypto before writing to IndexedDB.
      // ------------------------------------------------------------------
      case "export_state": {
        const { groupId } = msg;
        if (!groupId) {
          respondError(requestId, "invalid_input", "groupId required");
          break;
        }

        const currentState = groupSessions.get(groupId);
        if (!currentState) {
          respondError(requestId, "group_not_found", `No session for groupId: ${groupId}`);
          break;
        }

        // Encode JSON string → Uint8Array (UTF-8 bytes)
        // This is what gets encrypted and stored in IndexedDB
        const stateBytes = new TextEncoder().encode(currentState);
        respond(requestId, { stateBytes });
        break;
      }

      // ------------------------------------------------------------------
      // import_state: restore group state from IndexedDB bytes.
      // Caller decrypts the IndexedDB blob with WebCrypto, then passes the
      // decrypted Uint8Array (or string) here. The worker stores it as a
      // live session so subsequent encrypt/decrypt calls work immediately.
      // ------------------------------------------------------------------
      case "import_state": {
        const { groupId, groupState } = msg;
        if (!groupId || groupState === undefined) {
          respondError(requestId, "invalid_input", "groupId and groupState required");
          break;
        }

        let stateStr;
        try {
          stateStr = normalizeGroupState(groupState);
        } catch (convErr) {
          respondError(requestId, "invalid_input", convErr.message);
          break;
        }

        // Validate that the state is parseable JSON before storing
        try {
          JSON.parse(stateStr);
        } catch {
          respondError(requestId, "invalid_input", "groupState is not valid JSON");
          break;
        }

        groupSessions.set(groupId, stateStr);
        respond(requestId, { groupId, restored: true });
        break;
      }

      // ------------------------------------------------------------------
      // Unknown message type
      // ------------------------------------------------------------------
      default:
        respondError(requestId, "unknown_type", `Unknown message type: ${msg.type}`);
    }
  } catch (err) {
    // Catch any synchronous WASM throw (not panic — panics go through console_error_panic_hook)
    respondError(requestId, "wasm_error", String(err));
  }
};

// Start initialization immediately when worker is loaded
initWorker();
