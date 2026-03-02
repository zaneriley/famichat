/**
 * Famichat WASM Spike — M1: IndexedDB Persistence Test
 *
 * Validates the full key storage path required for production:
 *   1. Create a group (WASM) → get group state JSON blob
 *   2. Derive an AES-GCM key from a test passphrase via PBKDF2-SHA256 (WebCrypto)
 *   3. Generate a random 12-byte IV
 *   4. Encrypt the group state bytes with AES-256-GCM
 *   5. Store { encryptedBlob, salt, iv } in IndexedDB
 *   6. Retrieve from IndexedDB
 *   7. Re-derive the AES key from the same passphrase + stored salt
 *   8. Decrypt the blob → recover group state Uint8Array
 *   9. Reconstruct the group state (pass Uint8Array back to WASM decrypt path)
 *  10. Encrypt a new message using the reconstructed state → verify it succeeds
 *
 * This proves:
 *   - Group state survives a write → read → decrypt cycle (page reload simulation)
 *   - WebCrypto AES-GCM + PBKDF2 work in this browser
 *   - IndexedDB write/read works in this browser context
 *   - The Uint8Array ↔ WASM string boundary is correct
 *
 * What this does NOT test (out of scope for spike):
 *   - Survival across actual page reload (requires page reload + continuation mechanism)
 *   - Safari ITP eviction behavior in private browsing
 *   - `navigator.storage.persist()` behavior (recorded separately)
 *
 * Pass condition (M1):
 *   - Encrypt a message using state reconstructed from IndexedDB decryption
 *   - The encrypt call succeeds without error
 *
 * Usage: imported by harness.js; call runIndexedDbTests() which returns a result object.
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
// WebCrypto helpers — AES-256-GCM with PBKDF2 key derivation
// ============================================================================

const PBKDF2_ITERATIONS = 600_000; // NIST SP 800-132 recommended minimum for PBKDF2-SHA-256
const SALT_BYTES = 32;
const IV_BYTES = 12; // AES-GCM standard IV size

/**
 * Derive an AES-256-GCM key from a passphrase and salt using PBKDF2-SHA-256.
 * The key is non-extractable by design (extractable: false).
 *
 * @param {string} passphrase
 * @param {Uint8Array} salt
 * @returns {Promise<CryptoKey>}
 */
async function deriveKey(passphrase, salt) {
  const baseKey = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(passphrase),
    "PBKDF2",
    false,
    ["deriveKey"]
  );

  return crypto.subtle.deriveKey(
    {
      name: "PBKDF2",
      salt,
      iterations: PBKDF2_ITERATIONS,
      hash: "SHA-256",
    },
    baseKey,
    { name: "AES-GCM", length: 256 },
    false, // non-extractable: key bytes cannot be read out of WebCrypto
    ["encrypt", "decrypt"]
  );
}

/**
 * Encrypt plaintext bytes using AES-256-GCM.
 * Returns { encrypted: ArrayBuffer, iv: Uint8Array }
 *
 * @param {CryptoKey} key
 * @param {Uint8Array} data
 * @returns {Promise<{ encrypted: ArrayBuffer, iv: Uint8Array }>}
 */
async function aesEncrypt(key, data) {
  const iv = crypto.getRandomValues(new Uint8Array(IV_BYTES));
  const encrypted = await crypto.subtle.encrypt({ name: "AES-GCM", iv }, key, data);
  return { encrypted, iv };
}

/**
 * Decrypt an AES-256-GCM ciphertext.
 * Returns decrypted data as ArrayBuffer.
 *
 * @param {CryptoKey} key
 * @param {Uint8Array} iv
 * @param {ArrayBuffer} encrypted
 * @returns {Promise<ArrayBuffer>}
 */
async function aesDecrypt(key, iv, encrypted) {
  return crypto.subtle.decrypt({ name: "AES-GCM", iv }, key, encrypted);
}

// ============================================================================
// IndexedDB helpers
// ============================================================================

const IDB_NAME = "famichat-wasm-spike";
const IDB_STORE = "group-sessions";
const IDB_VERSION = 1;

/**
 * Open the IndexedDB database, creating the object store if needed.
 * @returns {Promise<IDBDatabase>}
 */
function openDb() {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(IDB_NAME, IDB_VERSION);
    req.onupgradeneeded = (event) => {
      const db = event.target.result;
      if (!db.objectStoreNames.contains(IDB_STORE)) {
        db.createObjectStore(IDB_STORE, { keyPath: "groupId" });
      }
    };
    req.onsuccess = (event) => resolve(event.target.result);
    req.onerror = (event) => reject(new Error(`IDB open failed: ${event.target.error}`));
  });
}

/**
 * Write a record to the object store.
 * @param {IDBDatabase} db
 * @param {object} record - Must include groupId
 * @returns {Promise<void>}
 */
function idbPut(db, record) {
  return new Promise((resolve, reject) => {
    const tx = db.transaction(IDB_STORE, "readwrite");
    const store = tx.objectStore(IDB_STORE);
    const req = store.put(record);
    req.onsuccess = () => resolve();
    req.onerror = (event) => reject(new Error(`IDB put failed: ${event.target.error}`));
  });
}

/**
 * Read a record from the object store by key.
 * @param {IDBDatabase} db
 * @param {string} key
 * @returns {Promise<object | undefined>}
 */
function idbGet(db, key) {
  return new Promise((resolve, reject) => {
    const tx = db.transaction(IDB_STORE, "readonly");
    const store = tx.objectStore(IDB_STORE);
    const req = store.get(key);
    req.onsuccess = (event) => resolve(event.target.result);
    req.onerror = (event) => reject(new Error(`IDB get failed: ${event.target.error}`));
  });
}

/**
 * Delete a record from the object store (cleanup after test).
 * @param {IDBDatabase} db
 * @param {string} key
 * @returns {Promise<void>}
 */
function idbDelete(db, key) {
  return new Promise((resolve, reject) => {
    const tx = db.transaction(IDB_STORE, "readwrite");
    const store = tx.objectStore(IDB_STORE);
    const req = store.delete(key);
    req.onsuccess = () => resolve();
    req.onerror = (event) => reject(new Error(`IDB delete failed: ${event.target.error}`));
  });
}

// ============================================================================
// WASM setup helpers
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
 * Returns { aliceGroupId, aliceState, bobState }
 */
function setupTwoMemberGroup(suffix) {
  const groupId = `m1-idb-test-${suffix}-${Date.now()}`;
  const aliceResult = create_group("alice@idb-test", groupId);
  const aliceState0 = aliceResult.group_state;

  const bobResult = create_member("bob@idb-test");
  const addResult = add_member(aliceState0, bobResult.key_package);
  const aliceState1 = addResult.new_group_state;
  const welcome = addResult.welcome;
  const ratchetTree = addResult.ratchet_tree;

  const joinResult = join_group(welcome, ratchetTree, bobResult.member_state);
  const bobState = joinResult.group_state;

  return { groupId, aliceState: aliceState1, bobState };
}

// ============================================================================
// Test runner
// ============================================================================

/**
 * Run all M1 IndexedDB persistence tests.
 *
 * @param {Function} [log] - Optional logging function
 * @returns {Promise<{
 *   passed: boolean,
 *   checks: Array<{ name: string, passed: boolean, detail: string }>,
 *   storageQuota: { used: number | null, quota: number | null, persistRequested: boolean | null },
 *   error: string | null
 * }>}
 */
export async function runIndexedDbTests(log = console.log) {
  const checks = [];
  const storageQuota = { used: null, quota: null, persistRequested: null };
  let db = null;

  function record(name, passed, detail) {
    checks.push({ name, passed, detail });
    log(`  [M1] ${passed ? "PASS" : "FAIL"} ${name}: ${detail}`);
  }

  try {
    await ensureWasmInit();

    // ------------------------------------------------------------------
    // Check 0: navigator.storage.persist() — record whether the browser
    // grants persistent storage (important for Safari ITP behavior)
    // This is informational, not a pass/fail gate for M1.
    // ------------------------------------------------------------------
    if (navigator.storage && navigator.storage.persist) {
      try {
        const persistent = await navigator.storage.persist();
        storageQuota.persistRequested = persistent;
        log(`  [M1] INFO navigator.storage.persist() = ${persistent} (true = eviction-resistant)`);
      } catch (e) {
        log(`  [M1] INFO navigator.storage.persist() threw: ${e.message}`);
      }
    }

    if (navigator.storage && navigator.storage.estimate) {
      try {
        const estimate = await navigator.storage.estimate();
        storageQuota.used = estimate.usage ?? null;
        storageQuota.quota = estimate.quota ?? null;
        log(
          `  [M1] INFO storage estimate: used=${storageQuota.used} bytes, quota=${storageQuota.quota} bytes`
        );
      } catch (e) {
        log(`  [M1] INFO storage estimate failed: ${e.message}`);
      }
    }

    // ------------------------------------------------------------------
    // Step 1: Open IndexedDB
    // ------------------------------------------------------------------
    db = await openDb().catch((e) => {
      throw new Error(`IDB open failed: ${e.message}`);
    });
    record(
      "IndexedDB open",
      true,
      `Database "${IDB_NAME}" opened, store "${IDB_STORE}" ready`
    );

    // ------------------------------------------------------------------
    // Step 2: Create a two-member MLS group and capture Alice's state
    // ------------------------------------------------------------------
    const { groupId, aliceState, bobState } = setupTwoMemberGroup("alice");

    // Verify the state is a non-empty JSON string
    const stateJson = JSON.parse(aliceState);
    const stateIsValid =
      typeof stateJson.storage === "object" &&
      typeof stateJson.signer_bytes === "string" &&
      typeof stateJson.group_id === "string";
    record(
      "Group state JSON structure is valid",
      stateIsValid,
      stateIsValid
        ? `storage has ${Object.keys(stateJson.storage).length} entries, group_id present`
        : `Unexpected structure: ${JSON.stringify(Object.keys(stateJson))}`
    );

    if (!stateIsValid) {
      return { passed: false, checks, storageQuota, error: "Group state structure invalid" };
    }

    // Convert group state string → Uint8Array (UTF-8 encoded JSON)
    const stateBytes = new TextEncoder().encode(aliceState);
    record(
      "Group state encoded to Uint8Array",
      stateBytes.length > 0,
      `${stateBytes.length} bytes (UTF-8 encoded JSON)`
    );

    // ------------------------------------------------------------------
    // Step 3: PBKDF2 key derivation
    // ------------------------------------------------------------------
    const passphrase = "test-spike-passphrase-not-for-production";
    const salt = crypto.getRandomValues(new Uint8Array(SALT_BYTES));
    let cryptoKey;
    try {
      cryptoKey = await deriveKey(passphrase, salt);
    } catch (e) {
      record("PBKDF2 key derivation", false, `Failed: ${e.message}`);
      return { passed: false, checks, storageQuota, error: e.message };
    }
    record(
      "PBKDF2 key derivation",
      true,
      `AES-256-GCM key derived from passphrase via PBKDF2-SHA-256 (${PBKDF2_ITERATIONS} iterations, non-extractable)`
    );

    // ------------------------------------------------------------------
    // Step 4: AES-GCM encrypt the group state bytes
    // ------------------------------------------------------------------
    let encrypted, iv;
    try {
      ({ encrypted, iv } = await aesEncrypt(cryptoKey, stateBytes));
    } catch (e) {
      record("AES-GCM encrypt group state", false, `Failed: ${e.message}`);
      return { passed: false, checks, storageQuota, error: e.message };
    }
    const encryptedArray = new Uint8Array(encrypted);
    record(
      "AES-GCM encrypt group state",
      encryptedArray.length > stateBytes.length,
      `Encrypted: ${encryptedArray.length} bytes (plaintext: ${stateBytes.length} bytes + 16-byte GCM tag)`
    );

    // Verify encrypted bytes do not contain the plaintext (sanity check)
    const plaintextBytes = new TextEncoder().encode('"group_id"');
    const encryptedContainsPlaintext = encryptedArray.some((_, i) =>
      i + plaintextBytes.length <= encryptedArray.length &&
      plaintextBytes.every((b, j) => encryptedArray[i + j] === b)
    );
    record(
      "Encrypted blob does not contain plaintext JSON",
      !encryptedContainsPlaintext,
      !encryptedContainsPlaintext
        ? "group_id key string not found in ciphertext (encryption working)"
        : "WARNING: plaintext visible in ciphertext — encryption may not be working"
    );

    // ------------------------------------------------------------------
    // Step 5: Write to IndexedDB
    // The stored record contains: groupId, encryptedBlob, salt, iv
    // Salt and IV must be stored alongside the blob (they are not secret)
    // ------------------------------------------------------------------
    const record_idb = {
      groupId,
      encryptedBlob: encryptedArray,    // Uint8Array: structured-clone safe
      salt: new Uint8Array(salt),       // Uint8Array: structured-clone safe
      iv: new Uint8Array(iv),           // Uint8Array: structured-clone safe
      storedAt: Date.now(),
    };

    try {
      await idbPut(db, record_idb);
    } catch (e) {
      record("IndexedDB write", false, `Failed: ${e.message}`);
      return { passed: false, checks, storageQuota, error: e.message };
    }
    record(
      "IndexedDB write",
      true,
      `Stored encrypted blob (${encryptedArray.length} bytes) + salt + iv for groupId=${groupId}`
    );

    // ------------------------------------------------------------------
    // Step 6: Read back from IndexedDB
    // ------------------------------------------------------------------
    let retrieved;
    try {
      retrieved = await idbGet(db, groupId);
    } catch (e) {
      record("IndexedDB read", false, `Failed: ${e.message}`);
      return { passed: false, checks, storageQuota, error: e.message };
    }

    const retrievedOk =
      retrieved !== undefined &&
      retrieved.encryptedBlob instanceof Uint8Array &&
      retrieved.salt instanceof Uint8Array &&
      retrieved.iv instanceof Uint8Array &&
      retrieved.encryptedBlob.length === encryptedArray.length;
    record(
      "IndexedDB read",
      retrievedOk,
      retrievedOk
        ? `Retrieved ${retrieved.encryptedBlob.length} byte blob, salt=${retrieved.salt.length} bytes, iv=${retrieved.iv.length} bytes`
        : `Retrieval mismatch: retrieved=${JSON.stringify(retrieved ? Object.keys(retrieved) : null)}`
    );

    if (!retrievedOk) {
      return { passed: false, checks, storageQuota, error: "IndexedDB retrieval failed" };
    }

    // ------------------------------------------------------------------
    // Step 7: Re-derive key from stored salt (simulates page reload — only passphrase + salt available)
    // ------------------------------------------------------------------
    let restoredKey;
    try {
      restoredKey = await deriveKey(passphrase, retrieved.salt);
    } catch (e) {
      record("PBKDF2 key re-derivation from stored salt", false, `Failed: ${e.message}`);
      return { passed: false, checks, storageQuota, error: e.message };
    }
    record(
      "PBKDF2 key re-derivation from stored salt",
      true,
      "Key re-derived using passphrase + stored salt (simulates post-reload recovery)"
    );

    // ------------------------------------------------------------------
    // Step 8: AES-GCM decrypt the retrieved blob
    // ------------------------------------------------------------------
    let decryptedBuffer;
    try {
      decryptedBuffer = await aesDecrypt(restoredKey, retrieved.iv, retrieved.encryptedBlob);
    } catch (e) {
      record("AES-GCM decrypt retrieved blob", false, `Failed: ${e.message}`);
      return { passed: false, checks, storageQuota, error: e.message };
    }

    const decryptedBytes = new Uint8Array(decryptedBuffer);
    const decryptedStr = new TextDecoder().decode(decryptedBytes);
    let restoredStateOk = false;
    let restoredStateDetail = "not checked";
    try {
      const restoredStateJson = JSON.parse(decryptedStr);
      restoredStateOk =
        typeof restoredStateJson.storage === "object" &&
        typeof restoredStateJson.signer_bytes === "string" &&
        typeof restoredStateJson.group_id === "string";
      restoredStateDetail = restoredStateOk
        ? `Decrypted ${decryptedBytes.length} bytes → valid group state JSON (storage entries: ${Object.keys(restoredStateJson.storage).length})`
        : `JSON structure unexpected after decrypt: ${JSON.stringify(Object.keys(restoredStateJson))}`;
    } catch (e) {
      restoredStateDetail = `JSON parse of decrypted bytes failed: ${e.message}`;
    }
    record("AES-GCM decrypt retrieved blob", restoredStateOk, restoredStateDetail);

    if (!restoredStateOk) {
      return { passed: false, checks, storageQuota, error: "State decryption produced invalid JSON" };
    }

    // ------------------------------------------------------------------
    // Step 9: Reconstruct MLS group from decrypted state and encrypt a new message
    // This is the critical M1 test: WASM must accept the restored state and produce
    // a valid ciphertext, proving the full storage path works end-to-end.
    // ------------------------------------------------------------------
    let postRestoreEncryptOk = false;
    let postRestoreEncryptDetail = "not attempted";
    let postRestoreCiphertext = null;
    try {
      const encResult = encrypt_message(decryptedStr, "post-restore-message");
      // encrypt_message returns { ciphertext, new_group_state }
      postRestoreCiphertext = encResult.ciphertext;
      postRestoreEncryptOk = typeof postRestoreCiphertext === "string" && postRestoreCiphertext.length > 0;
      postRestoreEncryptDetail = postRestoreEncryptOk
        ? `Encrypted successfully after state restore from IndexedDB (ciphertext: ${postRestoreCiphertext.length} chars)`
        : `encrypt_message returned unexpected result: ${JSON.stringify(encResult)}`;
    } catch (e) {
      postRestoreEncryptDetail = `encrypt_message threw after restore: ${e.message}`;
    }
    record(
      "encrypt_message succeeds on WASM state restored from IndexedDB",
      postRestoreEncryptOk,
      postRestoreEncryptDetail
    );

    // ------------------------------------------------------------------
    // Step 10: Bob decrypts the post-restore message — proves the restored state
    // is in the correct MLS epoch (not just structurally valid)
    // ------------------------------------------------------------------
    let postRestoreDecryptOk = false;
    let postRestoreDecryptDetail = "not attempted";
    if (postRestoreCiphertext && bobState) {
      try {
        const decResult = decrypt_message(bobState, postRestoreCiphertext);
        postRestoreDecryptOk = decResult.plaintext === "post-restore-message";
        postRestoreDecryptDetail = postRestoreDecryptOk
          ? `Bob decrypted Alice's post-restore message: "${decResult.plaintext}"`
          : `Plaintext mismatch: expected "post-restore-message", got "${decResult.plaintext}"`;
      } catch (e) {
        postRestoreDecryptDetail = `decrypt_message threw: ${e.message}`;
      }
    }
    record(
      "Bob decrypts Alice's post-restore message (epoch consistency)",
      postRestoreDecryptOk,
      postRestoreDecryptDetail
    );

    // ------------------------------------------------------------------
    // Cleanup: remove the test record from IndexedDB
    // ------------------------------------------------------------------
    try {
      await idbDelete(db, groupId);
      log(`  [M1] Cleaned up IndexedDB record for groupId=${groupId}`);
    } catch (e) {
      log(`  [M1] Cleanup warning: could not delete IDB record: ${e.message}`);
    }

    // ------------------------------------------------------------------
    // Summary
    // ------------------------------------------------------------------
    const allPassed = checks.every((c) => c.passed);
    log(
      `\n  [M1] Summary: ${checks.filter((c) => c.passed).length}/${checks.length} checks passed`
    );
    log(
      `  [M1] Key path: WASM state → UTF-8 → PBKDF2+AES-GCM → IndexedDB → retrieve → AES-GCM decrypt → WASM state`
    );

    return {
      passed: allPassed,
      checks,
      storageQuota,
      error: null,
    };
  } catch (err) {
    log(`  [M1] Fatal error: ${err.message}`);
    return {
      passed: false,
      checks,
      storageQuota,
      error: err.message,
    };
  } finally {
    if (db) {
      db.close();
    }
  }
}
