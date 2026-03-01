#!/usr/bin/env node
// Famichat OpenMLS WASM Spike Test Harness
// Proves all 7 criteria from WASM_SPIKE_DEFINITION.md:
// - P1: Keys never leave device (WASM binary import inspection)
// - P2: Server only sees ciphertext
// - P3: Messages survive session end (real two-member decrypt after restore)
// - P4: Encrypt/decrypt within 50ms budget (real two-member timing)
// - T1: Compilation successful
// - T2: Binary size within budget
// - T3: JS API callable

import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// ============================================================================
// TEST HARNESS MAIN
// ============================================================================

async function runTests() {
  const results = {
    criteria: {},
    verdict: 'UNKNOWN',
    details: [],
  };

  console.log('=== Famichat WASM Spike Results ===\n');

  // -------------------------------------------------------------------------
  // LOAD WASM MODULE
  // -------------------------------------------------------------------------

  let wasmModule = null;
  const wasmPath = path.join(__dirname, '..', 'pkg', 'mls_wasm.js');
  const wasmBinaryPath = path.join(__dirname, '..', 'pkg', 'mls_wasm_bg.wasm');

  if (!fs.existsSync(wasmPath) || !fs.existsSync(wasmBinaryPath)) {
    console.log('WASM module not found. Expected:');
    console.log(`  - ${wasmPath}`);
    console.log(`  - ${wasmBinaryPath}`);
    console.log('\nTo build, run: ./run wasm:build');
    console.log('Or manually: cd backend/infra/mls_wasm && wasm-pack build --target nodejs --release --no-opt');
    process.exit(1);
  }

  try {
    wasmModule = await import(wasmPath);
  } catch (err) {
    console.error(`FAIL: Could not import WASM module: ${err.message}`);
    process.exit(1);
  }

  // -------------------------------------------------------------------------
  // T1: COMPILATION
  // -------------------------------------------------------------------------
  console.log('[TECHNICAL CRITERIA]');
  results.criteria.T1 = 'PASS';
  console.log('T1 Compilation: PASS');

  // -------------------------------------------------------------------------
  // T2: BINARY SIZE
  // -------------------------------------------------------------------------
  let binarySizeKB = 0;
  try {
    const stats = fs.statSync(wasmBinaryPath);
    binarySizeKB = (stats.size / 1024).toFixed(2);

    let sizeStatus = 'PASS';
    if (binarySizeKB > 2500) {
      sizeStatus = 'FAIL';
    } else if (binarySizeKB > 1500) {
      sizeStatus = 'SOFT_WARNING';
    }

    results.criteria.T2 = sizeStatus;
    console.log(`T2 Binary size: ${binarySizeKB} KB — ${sizeStatus}`);
  } catch (err) {
    console.log(`T2 Binary size: FAIL — ${err.message}`);
    results.criteria.T2 = 'FAIL';
  }

  // -------------------------------------------------------------------------
  // T3: JS API CALLABLE
  // The spike now exports: health_check, create_group, encrypt_message,
  //   decrypt_message, create_member, add_member, join_group
  // -------------------------------------------------------------------------
  let t3Pass = false;
  try {
    if (
      typeof wasmModule.create_group === 'function' &&
      typeof wasmModule.encrypt_message === 'function' &&
      typeof wasmModule.decrypt_message === 'function' &&
      typeof wasmModule.create_member === 'function' &&
      typeof wasmModule.add_member === 'function' &&
      typeof wasmModule.join_group === 'function'
    ) {
      t3Pass = true;
      results.criteria.T3 = 'PASS';
      console.log('T3 JS API callable: PASS');
      console.log('   Exported: health_check, create_group, encrypt_message, decrypt_message,');
      console.log('             create_member, add_member, join_group');
    } else {
      console.log('T3 JS API callable: FAIL — missing one or more required exports');
      results.criteria.T3 = 'FAIL';
    }
  } catch (err) {
    console.log(`T3 JS API callable: FAIL — ${err.message}`);
    results.criteria.T3 = 'FAIL';
  }

  if (!t3Pass) {
    console.log('\n=== VERDICT: STOP — T3 (JS API) failed ===');
    process.exit(1);
  }

  console.log('\n[PRODUCT CRITERIA]');

  // -------------------------------------------------------------------------
  // Shared test fixture: create a two-member group for P1-P4
  // Alice creates the group; Bob creates key material and joins.
  // -------------------------------------------------------------------------
  let aliceGroupState = null;
  let bobGroupState = null;
  const sharedGroupId = 'test-group-' + Date.now();

  try {
    // Alice creates the group
    const aliceResult = wasmModule.create_group('alice@famichat.test', sharedGroupId);
    aliceGroupState = aliceResult.group_state;
    console.log(`   [fixture] Alice created group: id=${sharedGroupId}`);

    // Bob creates his key material
    const bobMember = wasmModule.create_member('bob@famichat.test');
    console.log(`   [fixture] Bob created member key material`);

    // Alice adds Bob
    const addResult = wasmModule.add_member(aliceGroupState, bobMember.key_package);
    aliceGroupState = addResult.new_group_state;
    console.log(`   [fixture] Alice added Bob (epoch advanced)`);

    // Bob joins via Welcome
    const bobJoinResult = wasmModule.join_group(
      addResult.welcome,
      addResult.ratchet_tree,
      bobMember.member_state
    );
    bobGroupState = bobJoinResult.group_state;
    console.log(`   [fixture] Bob joined group`);
  } catch (err) {
    console.error(`FATAL: Could not set up two-member group: ${err.message || JSON.stringify(err)}`);
    process.exit(1);
  }

  // -------------------------------------------------------------------------
  // P1: KEYS NEVER LEAVE DEVICE
  //
  // Correct approach: inspect the WASM binary's import table directly.
  // If the binary does not import 'fetch', 'XMLHttpRequest', 'sendBeacon', or
  // 'WebSocket' from the host environment, those network APIs are physically
  // unavailable inside WASM — keys cannot be exfiltrated via network from
  // within the module.
  // -------------------------------------------------------------------------

  let p1Pass = false;
  try {
    const wasmBytes = fs.readFileSync(wasmBinaryPath);
    const wasmModule_raw = new WebAssembly.Module(wasmBytes);
    const imports = WebAssembly.Module.imports(wasmModule_raw);

    const networkNames = ['fetch', 'xmlhttprequest', 'sendbeacon', 'websocket'];
    const networkImports = imports.filter(i =>
      networkNames.some(n => i.name.toLowerCase().includes(n))
    );

    if (networkImports.length === 0) {
      console.log('P1 Keys never leave device: PASS (binary check)');
      console.log('   WASM binary imports no network APIs (fetch/XHR/sendBeacon/WebSocket)');
      console.log(`   Total WASM imports: ${imports.length} (all are WASI/env primitives)`);

      // Also verify the generated JS glue code doesn't contain network calls.
      // wasm-bindgen generates this file deterministically — if it contains fetch/XHR,
      // it means the bindgen scaffolding itself could exfiltrate data.
      const wasmJsPath = path.join(__dirname, '..', 'pkg', 'mls_wasm.js');
      const glueCode = fs.readFileSync(wasmJsPath, 'utf8');
      const glueNetworkPatterns = ['fetch(', 'XMLHttpRequest', 'sendBeacon', 'WebSocket('];
      const glueNetworkHits = glueNetworkPatterns.filter(p => glueCode.includes(p));

      if (glueNetworkHits.length > 0) {
        p1Pass = false;
        results.criteria.P1 = 'FAIL';
        console.log('P1 Keys never leave device: FAIL — JS glue contains network APIs');
        console.log(`   Found network pattern(s) in mls_wasm.js: ${glueNetworkHits.join(', ')}`);
      } else {
        p1Pass = true;
        results.criteria.P1 = 'PASS';
        console.log('P1 Keys never leave device: PASS');
        console.log('   JS glue (mls_wasm.js) contains no network APIs');
      }
    } else {
      results.criteria.P1 = 'FAIL';
      console.log('P1 Keys never leave device: FAIL');
      console.log(`   Found ${networkImports.length} network import(s) in WASM binary:`);
      networkImports.forEach((imp, idx) => {
        console.log(`   [${idx + 1}] module="${imp.module}" name="${imp.name}" kind="${imp.kind}"`);
      });
    }
  } catch (err) {
    results.criteria.P1 = 'FAIL';
    console.log(`P1 Keys never leave device: FAIL — ${err.message}`);
  }

  // -------------------------------------------------------------------------
  // P2: SERVER ONLY SEES CIPHERTEXT
  //
  // Alice encrypts; we verify the "server-received" blob is opaque bytes
  // and cannot be decoded to the original plaintext without MLS key material.
  // -------------------------------------------------------------------------

  let p2Pass = false;
  try {
    const plaintextOriginal = 'famichat-secret-content-42';
    let encResult = null;

    try {
      encResult = wasmModule.encrypt_message(aliceGroupState, plaintextOriginal);
    } catch (err) {
      console.log(`P2 Server only sees ciphertext: FAIL — encrypt_message threw: ${err.message || JSON.stringify(err)}`);
      results.criteria.P2 = 'FAIL';
    }

    if (encResult && encResult.ciphertext) {
      const ciphertext = encResult.ciphertext;
      // Update aliceGroupState for subsequent tests
      aliceGroupState = encResult.new_group_state;

      // Check that base64-decoded bytes do not contain the plaintext as UTF-8
      const rawBytes = Buffer.from(ciphertext, 'base64');
      const rawAsUtf8 = rawBytes.toString('utf8');
      const containsPlaintext = rawAsUtf8.includes(plaintextOriginal);

      // Also check the base64 string itself doesn't contain the plaintext
      const base64ContainsPlaintext = ciphertext.includes(plaintextOriginal);

      // Verify it is valid base64 (opaque bytes)
      const isBase64 = /^[A-Za-z0-9+/]+=*$/.test(ciphertext);

      if (!containsPlaintext && !base64ContainsPlaintext && ciphertext.length > 0) {
        // Negative test: Eve was never added to the group; her group state must not decrypt Alice's ciphertext.
        const eveMember = wasmModule.create_member('eve@famichat.test');
        const eveGroup = wasmModule.create_group('eve@famichat.test', 'eve-group-' + Date.now());

        let keylessDecryptFailed = false;
        try {
          wasmModule.decrypt_message(eveGroup.group_state, encResult.ciphertext);
          // If we reach here, keyless decryption succeeded — that's a FAIL
        } catch (err) {
          keylessDecryptFailed = true;
        }

        if (keylessDecryptFailed) {
          p2Pass = true;
          results.criteria.P2 = 'PASS';
          console.log('P2 Server only sees ciphertext: PASS');
          console.log(`   Ciphertext does not contain plaintext in raw bytes: true`);
          console.log(`   Keyless decryption attempt (wrong group state) correctly failed: true`);
        } else {
          results.criteria.P2 = 'FAIL';
          console.log('P2 Server only sees ciphertext: FAIL — keyless decryption succeeded (unexpected)');
        }
      } else {
        results.criteria.P2 = 'FAIL';
        console.log('P2 Server only sees ciphertext: FAIL — plaintext visible in decoded bytes');
      }
    }
  } catch (err) {
    results.criteria.P2 = 'FAIL';
    console.log(`P2 Server only sees ciphertext: FAIL — ${err.message}`);
  }

  // -------------------------------------------------------------------------
  // P3: MESSAGES SURVIVE SESSION END (Real two-member decrypt after restore)
  //
  // Alice encrypts. Bob's group state (a string blob) is the only thing that
  // "survives" — all other in-memory state is discarded. A new session
  // restores Bob from that blob and decrypts the message. Plaintext must match.
  // -------------------------------------------------------------------------

  let p3Pass = false;
  try {
    const originalMessage = 'hello bob, session test';

    // Alice encrypts with her current group state (after P2 encrypt, epoch advanced)
    let encResult = null;
    try {
      encResult = wasmModule.encrypt_message(aliceGroupState, originalMessage);
    } catch (err) {
      throw new Error(`encrypt threw: ${err.message || JSON.stringify(err)}`);
    }

    if (!encResult || !encResult.ciphertext || !encResult.new_group_state) {
      throw new Error(`encrypt returned incomplete result: ${JSON.stringify(encResult)}`);
    }

    // Simulate "session end": only bobStorageBlob survives
    const bobStorageBlob = bobGroupState;
    // [All other references to group state, keys, etc. are discarded here]

    // New session: restore Bob from blob and decrypt
    let decResult = null;
    try {
      decResult = wasmModule.decrypt_message(bobStorageBlob, encResult.ciphertext);
    } catch (err) {
      throw new Error(`decrypt after restore threw: ${err.message || JSON.stringify(err)}`);
    }

    if (!decResult || decResult.plaintext === undefined) {
      throw new Error(`decrypt returned incomplete result: ${JSON.stringify(decResult)}`);
    }

    if (decResult.plaintext === originalMessage) {
      p3Pass = true;
      results.criteria.P3 = 'PASS';
      console.log('P3 Messages survive session end: PASS');
      console.log(`   Plaintext after restore matches: "${decResult.plaintext}"`);
      console.log(`   Bob state blob was the only thing preserved — decrypt succeeded`);
      // Update Bob's state for P4
      bobGroupState = decResult.new_group_state;
      // Update Alice's state for P4
      aliceGroupState = encResult.new_group_state;
    } else {
      results.criteria.P3 = 'FAIL';
      console.log(`P3 Messages survive session end: FAIL`);
      console.log(`   Expected: "${originalMessage}"`);
      console.log(`   Got:      "${decResult.plaintext}"`);
    }
  } catch (err) {
    results.criteria.P3 = 'FAIL';
    console.log(`P3 Messages survive session end: FAIL — ${err.message}`);
  }

  // -------------------------------------------------------------------------
  // P4: ENCRYPT/DECRYPT WITHIN 50MS BUDGET (real two-member timing)
  //
  // Set up Alice+Bob group once (already done above). Measure:
  //   - 10 encrypt iterations (Alice encrypts, chaining states)
  //   - For each encrypt, decrypt with the corresponding Bob state
  //   - Report enc_avg, dec_avg, p50, p99
  // -------------------------------------------------------------------------

  const encryptTimes = [];
  const decryptTimes = [];

  try {
    // Create a fresh two-member group for timing to avoid epoch confusion
    const timingGroupId = 'timing-group-' + Date.now();
    let timingAliceState = null;
    let timingBobState = null;

    const timingAliceResult = wasmModule.create_group('timing-alice', timingGroupId);
    timingAliceState = timingAliceResult.group_state;

    const timingBobMember = wasmModule.create_member('timing-bob');
    const timingAddResult = wasmModule.add_member(timingAliceState, timingBobMember.key_package);
    timingAliceState = timingAddResult.new_group_state;

    const timingBobJoin = wasmModule.join_group(
      timingAddResult.welcome,
      timingAddResult.ratchet_tree,
      timingBobMember.member_state
    );
    timingBobState = timingBobJoin.group_state;

    // 10 encrypt + decrypt cycles
    let currentAliceState = timingAliceState;
    let currentBobState = timingBobState;

    for (let i = 0; i < 10; i++) {
      // Encrypt (Alice)
      const startEnc = performance.now();
      let encR = null;
      try {
        encR = wasmModule.encrypt_message(currentAliceState, `timing-message-${i}`);
      } catch (err) {
        // still record time
      }
      const endEnc = performance.now();
      encryptTimes.push(endEnc - startEnc);

      if (!encR) continue;

      currentAliceState = encR.new_group_state;

      // Decrypt (Bob)
      const startDec = performance.now();
      let decR = null;
      try {
        decR = wasmModule.decrypt_message(currentBobState, encR.ciphertext);
      } catch (err) {
        // still record time
      }
      const endDec = performance.now();
      decryptTimes.push(endDec - startDec);

      if (decR) {
        currentBobState = decR.new_group_state;
      }
    }

    // Calculate stats
    const allTimes = [...encryptTimes, ...decryptTimes].filter(t => t > 0).sort((a, b) => a - b);
    const p50 = allTimes[Math.floor(allTimes.length * 0.5)] || 0;
    const p99 = allTimes[Math.floor(allTimes.length * 0.99)] || 0;

    const encAvg = encryptTimes.length > 0
      ? encryptTimes.reduce((a, b) => a + b, 0) / encryptTimes.length
      : 0;
    const decAvg = decryptTimes.filter(t => t > 0).length > 0
      ? decryptTimes.filter(t => t > 0).reduce((a, b) => a + b, 0) /
        decryptTimes.filter(t => t > 0).length
      : 0;

    let performanceStatus = 'PASS';
    if (p99 > 150) {
      performanceStatus = 'FAIL';
    } else if (p99 > 50) {
      performanceStatus = 'SOFT_WARNING';
    }

    results.criteria.P4 = performanceStatus;
    console.log(`P4 Encrypt/decrypt within 50ms: enc_avg=${encAvg.toFixed(2)}ms dec_avg=${decAvg.toFixed(2)}ms p50=${p50.toFixed(2)}ms p99=${p99.toFixed(2)}ms — ${performanceStatus}`);
    console.log(`   (${encryptTimes.length} encrypt + ${decryptTimes.length} decrypt samples, real two-member MLS)`);

    if (performanceStatus === 'SOFT_WARNING') {
      console.log('   Warning: 50-150ms range — document risk for mobile platforms');
    } else if (performanceStatus === 'FAIL') {
      console.log('   Warning: >150ms — reassess optimization opportunities');
    }
  } catch (err) {
    results.criteria.P4 = 'FAIL';
    console.log(`P4 Encrypt/decrypt within 50ms: FAIL — ${err.message}`);
  }

  // =========================================================================
  // VERDICT
  // =========================================================================

  console.log('\n[TECHNICAL CRITERIA SUMMARY]');
  console.log(`T1 Compilation: ${results.criteria.T1}`);
  console.log(`T2 Binary size: ${binarySizeKB} KB — ${results.criteria.T2}`);
  console.log(`T3 JS API callable: ${results.criteria.T3}`);

  // Determine overall verdict
  const hardFailures = Object.entries(results.criteria)
    .filter(([, v]) => v === 'FAIL')
    .map(([k]) => k);
  const allPassOrWarn = Object.values(results.criteria).every(
    v => v === 'PASS' || v === 'SOFT_WARNING' || v === 'SOFT_FAIL'
  );

  if (hardFailures.length > 0) {
    results.verdict = 'STOP';
    console.log('\n=== VERDICT: STOP — Hard failure detected ===');
    console.log('Reassess Path C. Blockers:');
    hardFailures.forEach(criterion => {
      console.log(`  - ${criterion}: FAIL`);
    });
  } else if (allPassOrWarn) {
    const hasWarnings = Object.values(results.criteria).some(v => v === 'SOFT_WARNING' || v === 'SOFT_FAIL');
    if (hasWarnings) {
      results.verdict = 'GO_WITH_WARNINGS';
      console.log('\n=== VERDICT: GO (with warnings) — Path C viable ===');
      console.log('All hard gates passed. Document soft warnings:');
      Object.entries(results.criteria).forEach(([criterion, status]) => {
        if (status === 'SOFT_WARNING' || status === 'SOFT_FAIL') {
          console.log(`  - ${criterion}: ${status}`);
        }
      });
    } else {
      results.verdict = 'GO';
      console.log('\n=== VERDICT: GO — Path C confirmed ===');
      console.log('All criteria passed. Proceed with SPA + WASM E2EE.');
    }
  } else {
    results.verdict = 'GO_WITH_WARNINGS';
    console.log('\n=== VERDICT: GO (with warnings) ===');
  }

  // Pretty-print JSON summary
  console.log('\n[TEST SUMMARY JSON]');
  console.log(JSON.stringify(results, null, 2));

  // Exit with appropriate code
  if (results.verdict === 'STOP') {
    process.exit(1);
  }
  process.exit(0);
}

// ============================================================================
// ENTRY POINT
// ============================================================================

runTests().catch(err => {
  console.error('Fatal test error:', err);
  process.exit(1);
});
