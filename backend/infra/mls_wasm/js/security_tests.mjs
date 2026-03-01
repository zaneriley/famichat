#!/usr/bin/env node
/**
 * security_tests.mjs — Security property tests for the Famichat MLS WASM module
 *
 * Organized by security property from E2EE_INTEGRATION.md:
 *   P1: Server never holds plaintext (no network APIs in WASM/glue)
 *   P2: Non-members cannot decrypt
 *   P5: Epoch ordering enforced
 *   P6: State serialization is faithful and fails loudly on corruption
 *   P7: Commit flow is complete (add_member returns commit; process_commit works)
 *
 * P3 (removed members): Requires remove_member export — marked skip.
 * P4 (key packages single-use): Requires backend DB tables — marked skip.
 *
 * Run from backend/infra/mls_wasm/:
 *   node --test js/security_tests.mjs
 *   node --experimental-test-coverage --test js/security_tests.mjs
 */

import { describe, it, before } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// ============================================================================
// MONOTONIC COUNTER FOR UNIQUE GROUP IDs
// ============================================================================

// Monotonic counter for unique group IDs — Date.now() alone can collide when tests run fast.
let _groupCounter = 0;
function nextGroupId(prefix) {
  return `${prefix}-${++_groupCounter}-${Date.now()}`;
}

/**
 * Extract a non-empty error description from anything thrown.
 * wasm-bindgen throws plain objects {error, code} when Rust returns Err(JsValue).
 * This function handles both that shape and standard Error instances.
 */
function extractErrorMessage(thrown) {
  if (!thrown) return '(null/undefined thrown)';
  if (typeof thrown === 'string') return thrown;
  if (thrown instanceof Error) return thrown.message || thrown.toString();
  // wasm-bindgen error object: { error: "message text", code: "code_string" }
  if (typeof thrown === 'object') {
    return thrown.error || thrown.message || thrown.code || JSON.stringify(thrown);
  }
  return String(thrown);
}

// ============================================================================
// PATHS
// ============================================================================

const WASM_JS_PATH   = path.join(__dirname, '..', 'pkg', 'mls_wasm.js');
const WASM_BIN_PATH  = path.join(__dirname, '..', 'pkg', 'mls_wasm_bg.wasm');

// ============================================================================
// MODULE-LEVEL WASM HANDLE
// Loaded once in a top-level before(); all describe blocks share the reference.
// ============================================================================

/** @type {Record<string, Function>} */
let wasm = null;

// Pre-flight: fail immediately with a clear message if pkg/ is absent.
// This runs synchronously before any tests are registered so the error is
// visible at the top of the output rather than buried in a test failure.
before(() => {
  if (!fs.existsSync(WASM_JS_PATH)) {
    throw new Error(
      'WASM not built. Run:\n' +
      '  cd backend/infra/mls_wasm && wasm-pack build --target nodejs --no-opt'
    );
  }
  if (!fs.existsSync(WASM_BIN_PATH)) {
    throw new Error(
      `WASM binary not found at ${WASM_BIN_PATH}.\n` +
      'Run: wasm-pack build --target nodejs --no-opt'
    );
  }
});

// Async WASM import — must be done in an async before().
before(async () => {
  wasm = await import(WASM_JS_PATH);
});

// ============================================================================
// HELPER: makeTwoMemberGroup
//
// Creates a fresh two-member group (Alice + Bob) and returns their group
// states.  Each call produces an isolated group — tests that use this helper
// do not share any mutable state.
//
// @param {string} suffix  Unique suffix appended to identity strings and the
//                         group ID to prevent collisions across test runs.
// @returns {{ aliceState: string, bobState: string, groupId: string }}
// ============================================================================

async function makeTwoMemberGroup(suffix) {
  const groupId = nextGroupId(`tg-${suffix}`);

  // Alice creates the group.
  const aliceCreate = wasm.create_group(`alice-${suffix}@test`, groupId);
  let aliceState = aliceCreate.group_state;

  // Bob creates his key material (key package + pre-join member_state).
  const bobMember = wasm.create_member(`bob-${suffix}@test`);

  // Alice adds Bob; this must return welcome, ratchet_tree, commit, new_group_state.
  const addResult = wasm.add_member(aliceState, bobMember.key_package);
  aliceState = addResult.new_group_state;

  // Bob joins via the Welcome message.
  const bobJoin = wasm.join_group(
    addResult.welcome,
    addResult.ratchet_tree,
    bobMember.member_state
  );
  const bobState = bobJoin.group_state;

  return { aliceState, bobState, groupId };
}

// ============================================================================
// P1: No network exfiltration possible
//
// Security invariant: private keys and plaintext can only be exfiltrated if
// the WASM module (or the generated JS glue) can make outbound network calls.
// WASM can only access the host environment through explicitly imported
// functions — inspecting the import table proves no network path exists.
// ============================================================================

describe('P1: No network exfiltration possible', () => {

  // P1.1 — WASM binary import table check.
  // The WebAssembly.Module.imports() API returns every host function that the
  // binary depends on.  Network APIs (fetch, XHR, sendBeacon, WebSocket) are
  // NOT available to WASM unless explicitly imported from the host.  If none
  // of them appear in the import table, the module is structurally incapable
  // of exfiltrating data over the network from within WASM execution.
  it('P1: WASM binary imports no network APIs', () => {
    const wasmBytes = fs.readFileSync(WASM_BIN_PATH);
    const wasmMod   = new WebAssembly.Module(wasmBytes);
    const imports   = WebAssembly.Module.imports(wasmMod);

    const NETWORK_NAMES = ['fetch', 'xmlhttprequest', 'sendbeacon', 'websocket'];

    const networkImports = imports.filter(imp =>
      NETWORK_NAMES.some(n => imp.name.toLowerCase().includes(n))
    );

    assert.strictEqual(
      networkImports.length,
      0,
      `WASM binary imports network API(s): ${networkImports.map(i => i.name).join(', ')}`
    );
  });

  // P1.2 — Generated JS glue check.
  // wasm-pack generates a JS shim (mls_wasm.js) that bridges the JS and WASM
  // worlds.  Even if the binary itself is clean, a compromised or hand-edited
  // glue file could exfiltrate keys.  We verify the generated file does not
  // contain any call to network APIs.
  it('P1: Generated JS glue contains no network API calls', () => {
    const glue = fs.readFileSync(WASM_JS_PATH, 'utf8');

    const NETWORK_PATTERNS = ['fetch(', 'XMLHttpRequest', 'sendBeacon', 'WebSocket('];
    const hits = NETWORK_PATTERNS.filter(p => glue.includes(p));

    assert.strictEqual(
      hits.length,
      0,
      `JS glue (mls_wasm.js) contains network API call(s): ${hits.join(', ')}`
    );
  });
});

// ============================================================================
// P2: Non-members cannot decrypt
//
// Security invariant: MLS ciphertexts are bound to the group epoch key
// schedule.  A device that was never added to the group — even one running the
// same WASM module — must not be able to recover plaintext from a ciphertext
// produced by group members.
// ============================================================================

describe('P2: Non-members cannot decrypt', () => {

  // P2.1 — Eve (a device with her own unrelated group) cannot decrypt Alice's
  // ciphertext.  This is the primary access-control test.  If WASM were just
  // doing symmetric encryption with a hard-coded key, Eve would succeed here.
  it('P2: Eve (separate isolated group) cannot decrypt Alice\'s ciphertext', async () => {
    const { aliceState } = await makeTwoMemberGroup('p2-1');

    // Alice encrypts a secret message.
    const plaintext = 'alice-secret-42';
    const encResult = wasm.encrypt_message(aliceState, plaintext);
    assert.ok(encResult.ciphertext, 'encrypt_message must return a ciphertext');

    // Eve creates her OWN group — she was never added to Alice+Bob's group.
    const eveCreate = wasm.create_group('eve@test', nextGroupId('eve-group'));
    const eveState  = eveCreate.group_state;

    // Decryption with Eve's unrelated group state MUST throw.
    let decryptSucceeded = false;
    let recoveredPlaintext = null;
    try {
      const decResult = wasm.decrypt_message(eveState, encResult.ciphertext);
      // If we reach this line, the security property is violated.
      decryptSucceeded = true;
      recoveredPlaintext = decResult.plaintext;
    } catch (_err) {
      // Expected: decryption must fail.
    }

    assert.ok(
      !decryptSucceeded,
      `Eve (non-member) must NOT be able to decrypt Alice's ciphertext. ` +
      `Got plaintext: "${recoveredPlaintext}"`
    );
  });

  // P2.2 — Ciphertext bytes must not contain the plaintext.
  // Even if decryption fails correctly above, we double-check that the wire
  // format does not accidentally leak the plaintext in plaintext (e.g., as a
  // base64 substring or in the raw bytes).  This guards against accidentally
  // using a no-op "encrypt" implementation.
  it('P2: Ciphertext bytes do not contain the plaintext', async () => {
    const { aliceState } = await makeTwoMemberGroup('p2-2');

    const plaintext = 'alice-secret-42';
    const encResult = wasm.encrypt_message(aliceState, plaintext);
    const ciphertext = encResult.ciphertext;

    // Check raw bytes (decoded from base64) do not contain the plaintext as UTF-8.
    const rawBytes  = Buffer.from(ciphertext, 'base64');
    const rawAsUtf8 = rawBytes.toString('utf8');

    assert.ok(
      !rawAsUtf8.includes(plaintext),
      'Raw ciphertext bytes (decoded from base64) must not contain the plaintext as a UTF-8 substring'
    );

    // Also check the base64 string itself does not embed the plaintext.
    assert.ok(
      !ciphertext.includes(plaintext),
      'base64-encoded ciphertext must not contain the plaintext as a substring'
    );
  });

  // P2.3 — An empty group state must be rejected, not silently treated as a
  // valid state.  Calling decrypt with "" must throw a clear error.  This
  // guards against implementations that fall back to a default/null group.
  it('P2: Empty group state blob is rejected with an error', async () => {
    const { aliceState } = await makeTwoMemberGroup('p2-3');

    const encResult = wasm.encrypt_message(aliceState, 'alice-secret-42');
    const ciphertext = encResult.ciphertext;

    let threw = false;
    let errorMessage = '';
    try {
      wasm.decrypt_message('', ciphertext);
    } catch (err) {
      threw = true;
      errorMessage = extractErrorMessage(err);
    }

    assert.ok(
      threw,
      'decrypt_message("", ciphertext) must throw; it did not'
    );
    assert.ok(
      errorMessage.length > 0,
      'The thrown error must have a non-empty message'
    );
  });
});

// ============================================================================
// P5: Epoch ordering is enforced
//
// Security invariant: MLS group keys are rotated at every Commit.  A member
// who has not processed a Commit cannot decrypt messages produced after that
// Commit.  This ensures that a member removed via a future Commit has no path
// to recover post-removal messages even if they hold a stale group_state blob.
// ============================================================================

describe('P5: Epoch ordering enforced', () => {

  // P5.1 — Pre-commit state cannot decrypt post-commit messages.
  // We snapshot Bob's state BEFORE Alice adds Carol (which advances the
  // epoch), then confirm the old state cannot decrypt Alice's post-Commit
  // message.  This is the key epoch-isolation invariant.
  it('P5: Pre-commit state cannot decrypt post-commit messages', async () => {
    const { aliceState, bobState } = await makeTwoMemberGroup('p5-1');

    // Record Bob's state BEFORE Carol is added (pre-commit epoch).
    const bobPreCommitState = bobState;

    // Alice adds Carol — epoch advances.
    const carolMember = wasm.create_member('carol-p5-1@test');
    const addResult   = wasm.add_member(aliceState, carolMember.key_package);
    const alicePostCommitState = addResult.new_group_state;

    // Alice sends a message in the NEW epoch.
    const postCommitPlaintext = 'post-commit-secret';
    const encResult = wasm.encrypt_message(alicePostCommitState, postCommitPlaintext);
    const postCommitCiphertext = encResult.ciphertext;

    // Bob with the OLD (pre-commit) state must NOT be able to decrypt.
    let decryptSucceeded = false;
    let recoveredPlaintext = null;
    try {
      const decResult = wasm.decrypt_message(bobPreCommitState, postCommitCiphertext);
      decryptSucceeded = true;
      recoveredPlaintext = decResult.plaintext;
    } catch (_err) {
      // Expected: epoch mismatch must cause decryption to fail.
    }

    assert.ok(
      !decryptSucceeded,
      `Bob's pre-commit state must NOT decrypt a post-commit message. ` +
      `Got plaintext: "${recoveredPlaintext}"`
    );
  });

  // P5.2 — After process_commit, the member CAN decrypt post-commit messages.
  // This is the positive counterpart to P5.1 and validates the recovery path:
  // a member who receives and processes the Commit catches up to the new epoch
  // and can then read subsequent messages.  If process_commit is absent, this
  // test is skipped (not failed) because the fix may still be in progress.
  it('P5: After process_commit, member can decrypt post-commit messages', async (t) => {
    if (typeof wasm.process_commit !== 'function') {
      t.skip('process_commit export not yet implemented — apply lib.rs fix');
      return;
    }

    const { aliceState, bobState } = await makeTwoMemberGroup('p5-2');

    // Snapshot Bob's pre-commit state.
    const bobPreCommitState = bobState;

    // Alice adds Carol — epoch advances.  Commit is broadcast to existing members.
    const carolMember = wasm.create_member('carol-p5-2@test');
    const addResult   = wasm.add_member(aliceState, carolMember.key_package);
    assert.ok(addResult.commit, 'add_member must return a commit field (P7 regression guard)');

    const alicePostCommitState = addResult.new_group_state;

    // Alice sends a message in the new epoch.
    const postCommitPlaintext = 'post-commit-secret-p5-2';
    const encResult = wasm.encrypt_message(alicePostCommitState, postCommitPlaintext);
    const postCommitCiphertext = encResult.ciphertext;

    // Bob processes the Commit — this advances his epoch.
    const processResult = wasm.process_commit(bobPreCommitState, addResult.commit);
    assert.ok(
      processResult.new_group_state,
      'process_commit must return new_group_state'
    );
    const bobPostCommitState = processResult.new_group_state;

    // Bob with the NEW (post-commit) state MUST succeed.
    let decResult = null;
    try {
      decResult = wasm.decrypt_message(bobPostCommitState, postCommitCiphertext);
    } catch (err) {
      assert.fail(
        `Bob's post-commit state should decrypt successfully but threw: ${err.message}`
      );
    }

    assert.ok(decResult, 'decrypt_message must return a result object');
    assert.strictEqual(
      decResult.plaintext,
      postCommitPlaintext,
      'Decrypted plaintext must match the original message'
    );
  });
});

// ============================================================================
// P6: State serialization is faithful and fails loudly on corruption
//
// Security invariant: the group_state blob is the sole persistence mechanism
// for MLS state between page loads (it lives in IndexedDB).  If serialization
// is lossy or if corrupted blobs are silently ignored, the security guarantees
// collapse: the system might fall back to a stale key schedule or accept
// attacker-controlled state.
// ============================================================================

describe('P6: State serialization faithful and fails loudly', () => {

  // P6.1 — Full round-trip.
  // Take a group_state blob, use it to encrypt a message, pass the blob again
  // to decrypt (simulating a page reload where only the blob persists), and
  // verify the plaintext is recovered correctly.  This is the happy path that
  // must always work.
  it('P6: Full round-trip: group_state → encrypt → decrypt → plaintext matches', async () => {
    const { aliceState, bobState } = await makeTwoMemberGroup('p6-1');

    const originalPlaintext = 'round-trip-secret-p6';

    // Alice encrypts message 1. Two messages exercise ratchet state — if serialization
    // loses forward-secrecy state, the second message will fail even if the first works.
    const encResult1 = wasm.encrypt_message(aliceState, originalPlaintext);
    assert.ok(encResult1.ciphertext,      'encrypt msg1 must return ciphertext');
    assert.ok(encResult1.new_group_state, 'encrypt msg1 must return new_group_state');

    // Bob decrypts message 1.
    const decResult1 = wasm.decrypt_message(bobState, encResult1.ciphertext);
    assert.ok(decResult1, 'decrypt msg1 must return a result object');
    assert.strictEqual(decResult1.plaintext, originalPlaintext,
      'Decrypted msg1 plaintext must exactly match the original');

    // Alice sends a second message with the advanced state.
    const encResult2 = wasm.encrypt_message(encResult1.new_group_state, 'round-trip-secret-p6-msg2');
    assert.ok(encResult2.ciphertext, 'encrypt msg2 must return ciphertext');

    // Bob decrypts message 2 from his advanced state.
    const decResult2 = wasm.decrypt_message(decResult1.new_group_state, encResult2.ciphertext);
    assert.ok(decResult2, 'decrypt msg2 must return a result object');
    assert.strictEqual(decResult2.plaintext, 'round-trip-secret-p6-msg2',
      'Decrypted msg2 plaintext must exactly match the original');
  });

  // P6.2 — Invalid JSON blob fails loudly.
  // Passing a non-JSON string as group_state must throw.  Silent acceptance of
  // garbage state would be a critical failure: the module might proceed with
  // an uninitialized or default group, producing plaintext that appears correct
  // but uses the wrong key schedule.
  it('P6: Corrupted state blob (invalid JSON) fails with a clear error', async () => {
    const { aliceState } = await makeTwoMemberGroup('p6-2');
    const encResult = wasm.encrypt_message(aliceState, 'p6-2-plaintext');

    let threw = false;
    let errorMessage = '';
    try {
      wasm.decrypt_message('not-valid-json', encResult.ciphertext);
    } catch (err) {
      threw = true;
      errorMessage = extractErrorMessage(err);
    }

    assert.ok(
      threw,
      'decrypt_message with invalid JSON state must throw; it did not'
    );
    assert.ok(
      errorMessage.length > 0,
      'The thrown error must have a non-empty message string'
    );
  });

  // P6.3 — Valid JSON with missing required fields fails loudly.
  // A partial blob (e.g., IndexedDB entry truncated mid-write, or an attacker
  // providing a minimal JSON object) must be rejected rather than silently
  // proceeding with partial state.  The blob {"storage":{}} is well-formed
  // JSON but is missing signer_bytes, group_id, and epoch — fields required
  // for any meaningful crypto operation.
  it('P6: Truncated state blob (valid JSON, missing fields) fails with a clear error', async () => {
    const { aliceState } = await makeTwoMemberGroup('p6-3');
    const encResult = wasm.encrypt_message(aliceState, 'p6-3-plaintext');

    let threw = false;
    let errorMessage = '';
    try {
      wasm.decrypt_message('{"storage":{}}', encResult.ciphertext);
    } catch (err) {
      threw = true;
      errorMessage = extractErrorMessage(err);
    }

    assert.ok(
      threw,
      'decrypt_message with a truncated state blob must throw; it did not'
    );
    assert.ok(
      errorMessage.length > 0,
      'The thrown error must have a non-empty message string'
    );
  });
});

// ============================================================================
// P7: Commit flow is complete
//
// Security invariant: when a new member is added to a group, the Commit
// message must be produced and returned to the caller so it can be broadcast
// to existing members.  If the Commit is discarded inside the WASM module
// (as was the case with the `_commit_msg` bug at lib.rs:451), existing members
// silently fall behind — they hold an epoch-N state while the group is at
// epoch-N+1, and all subsequent messages are undecryptable for them.
//
// These tests are regression guards for the commit-gap fix.
// ============================================================================

describe('P7: Commit flow is complete', () => {

  // P7.1 — add_member MUST return a `commit` field.
  // This is the direct regression test for the bug at lib.rs:451 where
  // `_commit_msg` was discarded.  If this test fails, the fix was not applied.
  it('P7: add_member returns a commit field (regression guard for commit-gap bug)', () => {
    const groupId = nextGroupId('p7-1-group');
    const aliceCreate = wasm.create_group('alice-p7-1@test', groupId);
    const bobMember   = wasm.create_member('bob-p7-1@test');

    const addResult = wasm.add_member(aliceCreate.group_state, bobMember.key_package);

    // All four fields must be present.
    assert.ok(
      addResult.welcome,
      'add_member must return welcome'
    );
    assert.ok(
      addResult.ratchet_tree,
      'add_member must return ratchet_tree'
    );
    assert.ok(
      addResult.commit,
      'add_member must return commit — FAIL means commit-gap fix was NOT applied to lib.rs'
    );
    assert.ok(
      addResult.new_group_state,
      'add_member must return new_group_state'
    );

    // commit must be a non-empty base64 string.
    assert.ok(
      typeof addResult.commit === 'string' && addResult.commit.length > 0,
      `commit must be a non-empty base64 string, got: ${JSON.stringify(addResult.commit)}`
    );
  });

  // P7.2 — process_commit export must exist and be callable.
  // Without this export, existing members have no way to advance their epoch
  // when a Commit arrives, making multi-member groups unusable.
  it('P7: process_commit export exists and is callable', () => {
    assert.strictEqual(
      typeof wasm.process_commit,
      'function',
      'process_commit must be exported from the WASM module as a function'
    );
  });

  // P7.3 — Full three-member commit flow.
  // This is the end-to-end test of the complete member-add protocol:
  //   1. Alice has a two-member group with Bob.
  //   2. Alice adds Carol — gets commit + welcome.
  //   3. Bob processes the commit — advances to the new epoch.
  //   4. Carol joins via the welcome.
  //   5. Alice sends a post-commit message.
  //   6. Both Bob (post-commit) AND Carol can decrypt it.
  //
  // If any step fails, multi-member E2EE is broken.
  it('P7: Three-member commit flow — Bob and Carol can both decrypt post-commit message', async (t) => {
    if (typeof wasm.process_commit !== 'function') {
      t.skip('process_commit export not yet implemented — apply lib.rs fix');
      return;
    }

    const { aliceState, bobState } = await makeTwoMemberGroup('p7-3');

    // Step 1: Alice adds Carol.
    const carolMember = wasm.create_member('carol-p7-3@test');
    const addResult   = wasm.add_member(aliceState, carolMember.key_package);

    assert.ok(addResult.commit,          'add_member must return commit');
    assert.ok(addResult.welcome,         'add_member must return welcome');
    assert.ok(addResult.ratchet_tree,    'add_member must return ratchet_tree');
    assert.ok(addResult.new_group_state, 'add_member must return new_group_state');

    const alicePostCommitState = addResult.new_group_state;

    // Step 2: Bob processes the commit — advances from epoch N to epoch N+1.
    const bobProcessResult = wasm.process_commit(bobState, addResult.commit);
    assert.ok(
      bobProcessResult.new_group_state,
      'process_commit must return new_group_state for Bob'
    );
    const bobPostCommitState = bobProcessResult.new_group_state;

    // Step 3: Carol joins via the Welcome message.
    const carolJoinResult = wasm.join_group(
      addResult.welcome,
      addResult.ratchet_tree,
      carolMember.member_state
    );
    assert.ok(
      carolJoinResult.group_state,
      'join_group must return group_state for Carol'
    );
    const carolGroupState = carolJoinResult.group_state;

    // Step 4: Alice sends a post-commit message in the new epoch.
    const postCommitPlaintext = 'post-commit-three-member-secret';
    const encResult = wasm.encrypt_message(alicePostCommitState, postCommitPlaintext);
    assert.ok(encResult.ciphertext, 'Alice must be able to encrypt post-commit');

    // Step 5a: Bob (with post-commit state) must decrypt successfully.
    let bobDecResult = null;
    try {
      bobDecResult = wasm.decrypt_message(bobPostCommitState, encResult.ciphertext);
    } catch (err) {
      assert.fail(`Bob (post-commit) failed to decrypt: ${err.message}`);
    }
    assert.strictEqual(
      bobDecResult.plaintext,
      postCommitPlaintext,
      'Bob post-commit plaintext must match original'
    );

    // Step 5b: Carol (who joined via welcome) must also decrypt successfully.
    let carolDecResult = null;
    try {
      carolDecResult = wasm.decrypt_message(carolGroupState, encResult.ciphertext);
    } catch (err) {
      assert.fail(`Carol (new member) failed to decrypt: ${err.message}`);
    }
    assert.strictEqual(
      carolDecResult.plaintext,
      postCommitPlaintext,
      'Carol plaintext must match original'
    );
  });
});

// ============================================================================
// P3 / P4: Skipped — require features not yet present in this WASM module
// ============================================================================

describe('P3: Removed members lose access (skipped — remove_member not exported)', () => {
  it('P3: removed member cannot decrypt post-removal messages', (t) => {
    t.skip(
      'Requires remove_member(group_state, leaf_index) export — ' +
      'not yet implemented in mls_wasm/src/lib.rs'
    );
  });
});

describe('P4: Key packages are single-use (skipped — requires backend DB)', () => {
  it('P4: second claim attempt returns 404', (t) => {
    t.skip(
      'Requires key_packages table + /api/v1/devices/:id/key_packages/claim endpoint — ' +
      'backend integration test scope, not WASM unit test scope'
    );
  });
});
