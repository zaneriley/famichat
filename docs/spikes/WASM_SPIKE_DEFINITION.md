# OpenMLS → WASM Spike Definition

**Date:** 2026-03-01
**Decision gate:** Path C (SPA + OpenMLS WASM as E2EE solution) is **locked in** only if this spike succeeds.
**Timebox:** 2–3 days max; if blocked, reassess architecture immediately.

---

## What Must Be Proven

**Ordered by criticality.** Only what actually gates the go/no-go decision.

1. **OpenMLS 0.8.1 compiles to WASM with the `js` feature flag**
   - Binary pass/fail: code compiles cleanly with `wasm-bindgen` tooling
   - If blocked: deployment model reverts to server-side NIF (Path D or rearchitect)

2. **WASM binary is small enough to ship in a browser**
   - Rule of thumb: <1.5 MB uncompressed, <500 KB gzipped
   - If oversized: evaluate bundling strategy, tree-shaking, or architecture split

3. **JavaScript bindings expose the minimal MLS API we need**
   - Specifically: `new_message` → `ciphertext` and `ciphertext` → `plaintext`
   - If API shape is wrong or requires significant wrapper code: document gap and continue (not fatal)

4. **Crypto randomness works in the browser environment**
   - Verify that OpenMLS's crypto calls use the platform's RNG (not JavaScript `Math.random()`)
   - If blocked: evaluate whether we can inject `SubtleCrypto` or custom RNG

5. **No blocking dependency on server-side state**
   - MLS state serialization → browser storage (IndexedDB or LocalStorage) is feasible
   - If state blob format is incompatible with browser storage limits: document and continue

---

## Success Criteria

Criteria are split into two groups: **product/security** (what the spike is for) and **technical** (whether it's feasible to ship).

### Product & Security Criteria

#### P1. Keys never leave the device
**What it proves:** The core security promise. If private key material appears in any outbound network request, Path C doesn't deliver what we claimed it would.
**Pass:** Log all network calls made during the test. No private key bytes appear in any request body, header, or URL. Ciphertext goes out; keys do not.
**Fail:** Any private key material observable in outbound traffic. Hard stop — Path C doesn't achieve the security goal.

#### P2. Server only ever sees ciphertext
**What it proves:** A compromised server cannot read messages — even with full access to what it stores and routes.
**Pass:** Everything the server receives is opaque bytes. Decoding those bytes without the client's private key produces garbage. Verify by attempting to decode a "server-received" blob without key material — it must fail.
**Fail:** Server receives anything that decodes to readable plaintext without client keys.

#### P3. Messages survive a browser session ending
**What it proves:** A user can close and reopen the app and still decrypt prior messages. If this fails, every browser restart loses history — unusable before multi-device is even a concern.
**Pass:** Serialize MLS state to a string (simulating localStorage/IndexedDB write), discard all in-memory state, restore from the string, decrypt a message that was encrypted before the "session end." Plaintext matches.
**Fail:** Restoration from serialized state fails or produces wrong plaintext.

#### P4. Encrypt/decrypt within the 50ms budget
**What it proves:** The product requires <200ms end-to-end. Encryption is budgeted at ≤50ms. WASM runs slower than native — this must be measured before committing.
**Pass:** `create_message()` + `process_message()` both complete in <50ms measured in Node.js (conservative — browser will be similar or faster with JIT).
**Soft warning:** 50–150ms — document, continue, but flag as a risk for mobile.
**Fail:** >150ms with no clear path to optimization. Reassess.

---

### Technical Criteria

#### T1. Compilation
**Pass:** New `mls_wasm` crate (not `mls_nif`) compiles cleanly to `wasm32-unknown-unknown` with `wasm-pack build --target nodejs`.
**Fail:** Unresolvable compilation errors in OpenMLS or its dependencies.

#### T2. Binary size
**Pass:** `wasm-opt -Oz` output <1.5 MB uncompressed.
**Soft warning:** 1.5–2.5 MB — document, continue.
**Fail:** >2.5 MB with no clear path to reduction.

#### T3. JavaScript API callable
**Pass:** `create_message()` and `process_message()` callable from JavaScript with no uncaught exceptions, types behave as documented.
**Fail:** API shape requires fundamental rework before it's usable from JS.

---

## Failure Criteria

Stop and reassess Path C if **any** of these occur:

| Scenario | Action |
|---|---|
| Compilation fails on dependency blocker (e.g., OpenMLS requires features incompatible with WASM) | Pause spike; document blocker; escalate for architecture decision |
| Final binary >3 MB after `wasm-opt -Oz` and no path to <2 MB exists | Continue spike (bundling strategies exist), but document risk |
| JavaScript binding API requires >200 LOC of wrapper code just to match our current NIF interface | Document, continue; plan for careful API design |
| RNG uses non-cryptographic source (JavaScript `Math.random()`) with no override mechanism | Fail immediately; reassess whether WASM is viable for crypto |
| State serialization requires persistent server-side cache (defeats privacy goal) | Fail immediately; rules out Path C |

---

## What We Are Explicitly NOT Proving

**Out of scope.** These are implementation details for the real SPA, not spike concerns.

- UI/UX for key recovery ("wife gets a new phone")
- Device pairing or QR code integration
- Multi-device message history sync
- Production readiness of OpenMLS itself (e.g., whether 0.8.1 is stable enough for L2+)
- Performance of WASM decryption in the browser (ballpark is fine; we're not benchmarking)
- Electron, React, or any specific SPA framework choice
- WebAuthn integration (auth is server-side; E2EE is client-side)
- IndexedDB or any specific browser storage backend
- Offline capability or sync conflict resolution
- Real conversation history transfer; spike uses synthetic small test vectors

---

## Timebox & Decision Rule

**Timebox:** 2–3 days (work day units).
- **End of Day 1:** Code compiles (criterion #1)
- **End of Day 2:** API tested and binary size measured (criteria #2–3)
- **End of Day 3:** Randomness and state persistence vetted (criteria #4–5); spike complete or escalated

**Decision rule at end:**
- **All 5 criteria pass:** Path C is locked in. Begin L1 UI work. Rust NIF remains as reference; mark as "WASM target TBD" in roadmap.
- **4 of 5 pass, 1 is "soft warning" (oversized binary, large state):** Path C is locked in conditionally. Document the risk. Continue.
- **Any "hard fail" scenario:** Call pause on Path C. Document blocker and escalate for 1-hour architecture discussion. Options: extend spike 1–2 days to explore mitigations, revert to Path A (LiveView WASM, multi-device gap), or rearchitect.

---

## Spike Deliverables

1. **Compile report** (`SPIKE_REPORT.md`)
   - Compilation command and output (clean or errors)
   - Binary size (before and after `wasm-opt`)
   - Any build flag or dependency changes needed

2. **API test** (JavaScript test file, e.g., `spike_test.js`)
   - Imports the WASM module
   - Tests one full encrypt → decrypt round-trip
   - Captures any errors or surprising behavior

3. **Analysis** (paragraph in `SPIKE_REPORT.md`)
   - RNG source (confirmed or flagged)
   - State serialization format
   - Any breaking changes from NIF API surface

4. **Decision** (clearly stated in `SPIKE_REPORT.md`)
   - Which criteria passed/failed
   - Go/no-go on Path C
   - Next action (proceed to L1 UI, extend spike, reassess)

---

## Key Files

- Spike workspace: `backend/infra/mls_wasm/` (new crate, sibling to `mls_nif/` — do not modify `mls_nif`)
- Report location: `docs/spikes/WASM_SPIKE_REPORT.md` (created during spike)
- Reference NIF: `backend/infra/mls_nif/src/lib.rs` (read for API shape; do not edit)
- Reference bindings: `openmls/openmls-wasm/` in OpenMLS repo (their existing WASM stubs)
- Design decision: `docs/SPEC.md` § "E2EE Migration Plan (Path C)"

---

## References

- SPEC.md: "Security & Trust Model" and "E2EE Migration Plan (Path C)"
- NOW.md: "Immediate next steps (in order)" — this spike is step 2
- OpenMLS release notes: 0.8.1 added `js` feature flag in January 2026
- Wire core-crypto: reference implementation using same pattern (production)
