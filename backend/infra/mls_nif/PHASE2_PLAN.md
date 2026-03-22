# MLS NIF — Phase 2 Plan: Type Safety and API Improvements

**Date**: 2026-03-21
**Scope**: `backend/infra/mls_nif/src/lib.rs` (2104 lines)
**Assumes**: Phase 1 correctness fixes (TOCTOU races, error source chains, lock-poison consistency) are already merged.

---

## Critical constraint: NIF wire format is immutable in this phase

The Elixir-facing NIF boundary communicates via `HashMap<String, String>`. Every NIF shim calls `payload_from_nif(params)` to convert the incoming map and `encode_result(env, ...)` to encode the outgoing map. **Nothing in Phase 2 may change the key names or value encoding visible to the Elixir caller.** All typed structs introduced in this phase are purely internal — they exist between the parse boundary and the encode boundary. The five snapshot string keys (`session_sender_storage`, `session_recipient_storage`, `session_sender_signer`, `session_recipient_signer`, `session_cache`) are especially sensitive: they are persisted by the Elixir layer and round-tripped back on every warm-start; any change to their format or names is a breaking migration, not a Phase 2 task.

---

## Fix overview and dependency graph

```
F19 (error case normalization)           — no dependencies, do first
F7  (non_empty / required_non_empty return &str)
F12 (with_required_group closure &str)   — depends on F7
F15 (GroupId newtype)                    — depends on F12 (shares with_required_group)
F16 (Ciphersuite newtype/enum)           — no dependencies
F17/F20 (SessionSnapshot struct)         — depends on F7 (uses non_empty internally)
F8  (parse boundary in NIF shims)        — depends on F15, F16, F17/F20 (all field types must exist first)
F22 (ensure_session_loaded helper)       — depends on F15 (GroupId), independent of F8
```

Recommended sequencing across pull requests, from safest to most impactful:

1. PR-A: F19 (string normalization, zero-risk rename)
2. PR-B: F7 + F12 (lifetime chain; these are coupled)
3. PR-C: F15 + F16 (newtypes; can be reviewed independently but share the same zone)
4. PR-D: F17/F20 (SessionSnapshot struct; the most internal change)
5. PR-E: F22 (helper extraction, refactor only)
6. PR-F: F8 (parse boundary; highest coordination risk, land last)

---

## F19 — Error reason case normalization

**Audit finding**: #19 (medium)

### What changes

Eight `with_code(...)` call sites pass a `reason` string in `SCREAMING_SNAKE_CASE` while all other sites use `snake_case`. The affected strings are:

| Current string | Corrected string | Location |
|---|---|---|
| `"INVALID_GROUP_ID"` | `"invalid_group_id"` | lib.rs:173, 245, 332, 1013 |
| `"INVALID_GROUP_ID_NULL_BYTE"` | `"invalid_group_id_null_byte"` | lib.rs:178, 249, 338, 1019 |

No other files are affected in the Rust crate. The Elixir adapter (`backend/lib/famichat/chat/crypto/mls.ex`) must be audited for pattern-matches on these exact strings before the change lands; if any Elixir clause matches the old strings, the Elixir change must be in the same PR.

### How to verify

1. `cargo test` passes (existing tests do not assert on these specific reason strings).
2. Grep the Elixir codebase for `"INVALID_GROUP_ID"` and confirm zero matches after the coordinated Elixir change.
3. Add a new test that calls `create_group` with a group ID longer than 256 bytes and asserts `error.details["reason"] == "invalid_group_id"`.

### Dependencies

None. This is a pure string rename with no structural change.

### Risk

Low on the Rust side. Moderate on the Elixir side if any clause pattern-matches on the old string. The audit found no other callers, but a grep of the full repo is required before merging.

---

## F7 — `non_empty` / `required_non_empty` return `&str` instead of `String`

**Audit finding**: #7 (high)

### What changes

**`non_empty` (lib.rs:1048-1053)**

Current signature: `fn non_empty(params: &Payload, key: &str) -> Option<String>`
Target signature: `fn non_empty<'a>(params: &'a Payload, key: &str) -> Option<&'a str>`

Current body clones via `.cloned()`. New body: `params.get(key).filter(|v| !v.trim().is_empty()).map(String::as_str)`.

**`required_non_empty` (lib.rs:1034-1046)**

Current signature: `fn required_non_empty(params: &Payload, key: &str, details: &mut Payload) -> Option<String>`
Target signature: `fn required_non_empty<'a>(params: &'a Payload, key: &str, details: &mut Payload) -> Option<&'a str>`

Current body calls `.to_owned()`. New body: match on `params.get(key)`, return `.as_str()` on the `Some` arm.

**Call-site changes**

The 50+ call sites that currently receive `Option<String>` (or `String`) will now receive `Option<&str>` (or `&str`). Sites that need an owned `String` — primarily `HashMap::insert(...)` calls and anywhere ownership is moved — must add `.to_owned()` or `.map(str::to_owned)` locally. Sites that only test for presence (`.is_some()`, pattern-match on value, pass as `&str`) require no change and lose one allocation each.

The most affected call sites:

- `has_complete_session_snapshot` (lib.rs:1055-1060): currently calls `non_empty` 4 times and discards all results. After F7 these become zero-allocation `params.contains_key` checks — but this function is better replaced entirely by F22. No intermediate fix is needed here; it can remain as-is until F22.
- `parse_bool` (lib.rs:1062-1068): currently clones then calls `.as_str()`. After F7 it receives `&str` directly; the `.as_str()` call is removed.
- `restore_group_session_from_snapshot` (lib.rs:1469-1473): currently calls `non_empty` and stores the result in `let sender_storage: Option<String>`. After F7 the type becomes `Option<&str>`. The downstream `deserialize_storage_map(sender_storage.as_deref().unwrap(), ...)` calls on lines 1497-1501 currently use `.as_deref()` to convert `Option<String>` to `&str`. After F7, these become `sender_storage.unwrap()` directly (already `&str`).
- `create_group` (lib.rs:195): `non_empty(params, "credential_identity").map(|s| s.into_bytes())` — after F7 this becomes `.map(|s: &str| s.as_bytes().to_vec())`.
- `join_from_welcome` (lib.rs:231): `non_empty(params, "rejoin_token").or_else(|| non_empty(params, "welcome"))` then used as `format!("rejoin:{}", token)` and in two `format!` calls. After F7, `token` is `&str` and all `format!` calls accept `&str` already — no change needed.
- `with_required_group` (lib.rs:999-1032): receives `group_id: String` from `required_non_empty`. After F7 it receives `group_id: &str` and must `.to_owned()` before calling `on_group(group_id.to_owned())`. This is the transition point; see F12 for removing that owned copy.

**`has_complete_session_snapshot` low-hanging follow-on**

After F7 is in place, `has_complete_session_snapshot` (lib.rs:1055-1060) can be simplified without waiting for F22:

```
// Before (calls non_empty 4x, each clones a String just to test .is_some())
fn has_complete_session_snapshot(params: &Payload) -> bool {
    non_empty(params, SNAPSHOT_SENDER_STORAGE_KEY).is_some() && ...
}

// After F7 (still calls non_empty but now borrows rather than clones)
// — zero allocation, no structural change needed
```

The allocation is already eliminated once `non_empty` returns `&str`. No further change to `has_complete_session_snapshot` is needed until F22.

### How to verify

1. `cargo build` passes (lifetime errors would surface immediately).
2. `cargo test` passes with no behavior change.
3. `cargo clippy -- -W clippy::perf` should produce zero `unnecessary_to_owned` or `clone_on_ref_ptr` warnings on these functions after the change.
4. Verify with a before/after benchmark on `process_incoming` using a pre-existing snapshot — the 50+ allocation reduction should be measurable, though not required for merge acceptance.

### Dependencies

None. This fix has no prerequisite.

### Risk

Medium. The lifetime annotation `'a` on both functions ties the returned `&str` to the lifetime of `params`. Any call site that currently holds an `Option<String>` across a mutable borrow of `params` — or passes the result into a `HashMap::insert` — will fail to compile. This is caught entirely at compile time; there is no silent behavior change. The snapshot-restore path on lines 1497-1501 currently uses `.as_deref().unwrap()` which will need adjustment. The fix is mechanical but must be done carefully: start by changing the function signature, then fix every compile error.

---

## F12 — `with_required_group` closure takes `&str` instead of `String`

**Audit finding**: #12 (medium)

### What changes

**`with_required_group` (lib.rs:999-1032)**

Current bound: `F: Fn(String) -> MlsResult`
Target bound: `F: Fn(&str) -> MlsResult`

The function extracts `group_id` from params. Currently it passes `group_id: String` to the closure, forcing 8 call-site closures that need to move `group_id` into a `Payload::insert(...)` to clone it first. After this change, the closure receives `group_id: &str` (borrowed from `params`), and call sites that need to insert it into a payload call `.to_owned()` once at the point of use.

**Call-site closures affected** (all 8 closures passed to `with_required_group`):

- `commit_to_pending` (lib.rs:479): `payload.insert("group_id".to_owned(), group_id)` becomes `payload.insert("group_id".to_owned(), group_id.to_owned())`.
- `mls_remove` (lib.rs:508): the closure captures `group_id: &str`; calls to `GROUP_SESSIONS.contains_key(&group_id)` and `GROUP_SESSIONS.insert(group_id.clone(), ...)` become `GROUP_SESSIONS.contains_key(group_id)` (DashMap accepts `&str` key lookup via Borrow) and `GROUP_SESSIONS.insert(group_id.to_owned(), ...)`.
- `merge_staged_commit` (lib.rs:690): same pattern.
- `create_application_message` (lib.rs:836): same.
- `export_group_info` (lib.rs:890): same.
- `export_ratchet_tree` (lib.rs:929): same.
- `list_member_credentials` (lib.rs:942): same.
- `clear_pending_commit` (lib.rs:816): same.

Note: `lifecycle_ok` (lib.rs:984) calls `with_required_group` internally; its own closure bound must change to match.

**Important**: DashMap's `get`, `get_mut`, and `contains_key` all accept `Q: Hash + Eq` where `String: Borrow<Q>`, so `&str` works directly for lookups without converting to `String`. Only `insert` requires an owned `String` key.

### How to verify

1. `cargo build` passes.
2. `cargo test` passes with no behavior change.
3. Manually inspect that no `.clone()` call on `group_id` inside any closure survives after the change.

### Dependencies

F7 must land first. `with_required_group` calls `required_non_empty`, which after F7 returns `Option<&str>`. The received `group_id` is already `&str` at that point; the closure bound change in F12 is the natural follow-on.

### Risk

Low. All changes are within Rust's borrow checker and caught at compile time. The NIF wire format is unaffected — the Elixir caller still passes `"group_id"` as a string key in the input map.

---

## F15 — `GroupId` newtype with validated constructor

**Audit finding**: #15 (medium)

### What changes

Introduce a newtype `struct ValidatedGroupId(String)` (name suggestion; use `ValidatedGroupId` to avoid shadowing the OpenMLS `GroupId` type already imported).

The validated constructor encapsulates the three checks currently copy-pasted at lib.rs:169-182, 241-254, 330-343, and 1011-1024:

```
- is_empty() || len() > 256  →  ErrorCode::InvalidInput, "invalid_group_id"
- contains('\0')              →  ErrorCode::InvalidInput, "invalid_group_id_null_byte"
```

The constructor signature: `ValidatedGroupId::new(raw: &str, operation: &str) -> Result<Self, MlsError>`.

The inner `String` is accessible only via a `fn as_str(&self) -> &str` method (no public field, no `DerefMut`). This prevents bypass of validation.

**Remove the 4 duplicated validation blocks** and replace each with a single `ValidatedGroupId::new(group_id, operation)?` call.

Specifically:
- `create_group` (lib.rs:169-182): the validation block runs after `CreateGroupParams::try_from`. Replace with `ValidatedGroupId::new(&parsed.group_id, "create_group")?`.
- `join_from_welcome` (lib.rs:241-254): replace the inline block; `group_id` is a local `String` at that point.
- `process_incoming` (lib.rs:330-343): same.
- `with_required_group` (lib.rs:1011-1024): this is the canonical location; the three others all route through here via `with_required_group` or are direct callers that also inline the check. After F12, `group_id` inside `with_required_group` is `&str` — the validation call becomes `ValidatedGroupId::new(group_id, operation)?`.

Note that `process_incoming` does not go through `with_required_group`; it has its own inline block. After F15, it calls `ValidatedGroupId::new(&group_id, operation)?` directly.

`CreateGroupParams.group_id` field type can remain `String` since `CreateGroupParams` is a parse helper that exists before validation.

`ValidatedGroupId::as_str()` replaces all uses of the raw `group_id: String` or `group_id: &str` in the internal logic. For DashMap operations: `GROUP_SESSIONS.insert(validated.as_str().to_owned(), session)` and `GROUP_SESSIONS.get(validated.as_str())`.

### How to verify

1. `cargo build` passes.
2. `cargo test` passes.
3. Add a unit test for `ValidatedGroupId::new` covering: empty string, 257-byte string, NUL-containing string (all should error), and a valid 36-byte UUID-format string (should succeed).
4. Confirm with `grep -n "group_id.is_empty\|group_id.len() > 256\|group_id.contains"` that zero matches remain in lib.rs after the change.

### Dependencies

F12 should land first so that `with_required_group` already receives `&str` before `ValidatedGroupId` wraps it. F19 should land first so the error reason strings in the validated constructor are already normalized.

### Risk

Low. Purely internal. The NIF wire format sends `"group_id"` as a plain string key; it never sees `ValidatedGroupId`. The only external surface change is that error `reason` strings for invalid group IDs now originate from one place — consistent with F19.

---

## F16 — Ciphersuite newtype/enum

**Audit finding**: #16 (medium)

### What changes

Introduce `enum MlsCiphersuite` with variants matching the three currently supported ciphersuites:

```
MlsCiphersuite::Mls128DhkemX25519Aes128GcmSha256Ed25519
MlsCiphersuite::Mls128DhkemP256Aes128GcmSha256P256
MlsCiphersuite::Mls128DhkemX25519ChaCha20Poly1305Sha256Ed25519
```

Add `impl TryFrom<&str> for MlsCiphersuite` containing the body of the current `parse_ciphersuite` function, returning `Err(())` for unknown strings. Add `fn to_openmls(&self) -> Ciphersuite` that maps each variant to the corresponding OpenMLS constant.

`parse_ciphersuite` (lib.rs:1093-1106) can either be removed (replaced by `TryFrom`) or made a thin wrapper; remove it.

**Affected locations**:

- `CreateGroupParams.ciphersuite: String` (lib.rs:62): change type to `MlsCiphersuite`.
- `TryFrom<&Payload> for CreateGroupParams` (lib.rs:1886-1905): after extracting the `ciphersuite` string from the payload via `required_non_empty`, parse it with `MlsCiphersuite::try_from(raw_str).map_err(|_| ...)`. Assign the typed value to the struct.
- `create_group` (lib.rs:184-192): the current `parse_ciphersuite(...)` call and its error handling are replaced by `parsed.ciphersuite.to_openmls()` (no fallibility at this point — parsing already failed earlier).
- The `payload.insert("ciphersuite".to_owned(), parsed.ciphersuite)` at lib.rs:217: change to `payload.insert("ciphersuite".to_owned(), parsed.ciphersuite.as_str().to_owned())` where `as_str()` is a new method returning the canonical label string. **This is critical**: the Elixir caller round-trips the ciphersuite string from the response payload back into subsequent requests. The string value in the wire payload must not change. `as_str()` must return exactly the same label strings that `parse_ciphersuite` currently accepts.
- `DEFAULT_CIPHERSUITE` (lib.rs:85) remains an OpenMLS `Ciphersuite` constant — it is used in non-create paths where no string parsing is involved. Optionally add a `DEFAULT_MLS_CIPHERSUITE: MlsCiphersuite` constant if it aids readability, but this is not required.

### How to verify

1. `cargo test` passes including the existing `create_group` tests.
2. Add a test: `MlsCiphersuite::try_from("MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519")` succeeds; `MlsCiphersuite::try_from("unknown")` errors.
3. Add a test: a full round-trip of `create_group` → extract `ciphersuite` from response payload → pass back into a second call → verify no error. This guards wire-format stability.
4. `grep -n "parse_ciphersuite"` returns zero matches after removal.

### Dependencies

None. This is self-contained. F7 is helpful (so `required_non_empty` returns `&str` directly to `TryFrom::try_from`) but not required.

### Risk

Medium. The wire format risk is **specifically in the ciphersuite value written to the response payload** at lib.rs:217. If `MlsCiphersuite::as_str()` returns a different string than the current `parsed.ciphersuite` (which came directly from the input), the Elixir round-trip breaks. Mitigate by: (a) defining `as_str()` to return the identical labels currently accepted by `parse_ciphersuite`, (b) adding the round-trip test described above, and (c) reviewing the Elixir `mls.ex` to confirm which ciphersuite string it passes.

---

## F17/F20 — `SessionSnapshot` struct for the 5 snapshot fields

**Audit findings**: #17, #20 (both medium)

These two findings describe the same problem from different angles (#17 from the API perspective, #20 from the structural perspective) and are resolved by a single change.

### What changes

Introduce `struct SessionSnapshot` with five named fields corresponding to the five snapshot Payload keys:

```
struct SessionSnapshot {
    sender_storage: String,
    recipient_storage: String,
    sender_signer: String,
    recipient_signer: String,
    cache: String,
}
```

**Wire format note**: `SessionSnapshot` is purely an internal representation. It does not replace the `Payload` at the wire boundary. The five constant strings (`SNAPSHOT_SENDER_STORAGE_KEY` etc.) remain in use as the Payload keys when serializing to and from the HashMap.

**`SessionSnapshot::from_payload(params: &Payload) -> Option<Self>`**: extracts all five fields from a `Payload`, returning `None` if any required field is absent. This replaces the logic currently scattered across `has_complete_session_snapshot` (lib.rs:1055), `restore_group_session_from_snapshot` (lib.rs:1469-1479), and the inline `sender_storage.is_none() || ...` check (lib.rs:1485-1494).

**`SessionSnapshot::into_payload(self) -> Payload`**: converts the struct back into a `Payload`, inserting exactly the five keys with the same names currently used in `serialize_snapshot_raw_data` (lib.rs:1434-1444). This replaces the five `payload.insert(SNAPSHOT_*_KEY.to_owned(), ...)` calls.

**Affected functions**:

- `serialize_snapshot_raw_data` (lib.rs:1404-1447): currently returns `Payload`. Intermediate step: keep return type `Payload`, but build a `SessionSnapshot` internally and call `into_payload()` at the end. Optional further step: change return type to `SessionSnapshot` and let callers call `payload.extend(snapshot.into_payload())`.
- `restore_group_session_from_snapshot` (lib.rs:1464-1611): the opening lines 1469-1495 that extract and validate the five fields are replaced by `SessionSnapshot::from_payload(params)` followed by an `ok_or_else(|| MlsError::with_code(..., "incomplete_session_snapshot"))` for the case where `any_snapshot_field_present` is true but not all fields are present. The five `let sender_storage = ...` bindings become struct field accesses.
- `has_complete_session_snapshot` (lib.rs:1055-1060): this function becomes `SessionSnapshot::from_payload(params).is_some()` — or it is inlined away entirely once callers use `SessionSnapshot::from_payload` directly (see F22).
- All call sites of `build_group_session_snapshot` and `extract_snapshot_raw_data` / `serialize_snapshot_raw_data` receive `SessionSnapshot` (or `Payload` if the return type stays `Payload`) and call `payload.extend(snapshot.into_payload())` — the same pattern already used today.

**`cache` field handling**: the current code uses `non_empty(...).unwrap_or_default()` for the cache field, treating absence as an empty string. `SessionSnapshot` can represent this by making `cache` a `String` (possibly empty) while the other four fields are required. Alternatively, define a `SessionSnapshotBuilder` or use `Option<String>` for cache. The simplest approach: `from_payload` always succeeds for the cache field (using `unwrap_or_default`), and only fails if any of the four storage/signer fields are absent while at least one is present.

### How to verify

1. `cargo test` passes, especially the snapshot round-trip tests.
2. Add a unit test for `SessionSnapshot::from_payload`: verify that a payload with all five keys returns `Some`, a payload with four keys returns `None` (incomplete), and an empty payload returns `None`.
3. Add a unit test for `SessionSnapshot::into_payload`: verify that the five key names in the output map exactly match the five `SNAPSHOT_*_KEY` constants.
4. Run the full session-snapshot integration path (create_group → extract snapshot → restore from snapshot via `restore_group_session_from_snapshot`) and assert the session is identical.
5. `grep -n "has_complete_session_snapshot"` should return zero matches after F22 (or remain as a thin wrapper calling `SessionSnapshot::from_payload(...).is_some()` if F22 is not yet done).

### Dependencies

F7 should land first so that `non_empty` returns `&str`, which `SessionSnapshot::from_payload` can borrow and `.to_owned()` only for the fields it needs to store.

### Risk

Medium. The five snapshot key names and the string values they hold must be identical before and after. `into_payload()` must insert keys using the identical constant strings (`SNAPSHOT_SENDER_STORAGE_KEY` etc.). The risk is mechanical: a typo in `into_payload` would cause a snapshot restore failure at runtime. Mitigate with the key-name unit test described above, and by reusing the existing constants rather than repeating string literals.

---

## F8 — Parse boundary in NIF shim layer

**Audit finding**: #8 (high)

This is the highest-coordination item and lands last.

### What changes

Currently every NIF shim follows this pattern:

```rust
fn some_nif<'a>(env: Env<'a>, params: HashMap<String, String>) -> Term<'a> {
    let payload = payload_from_nif(params);  // identity conversion
    encode_result(env, some_operation(&payload))
}
```

`payload_from_nif` (lib.rs:1944) is a no-op (`params.into_iter().collect()`). The `Payload` type alias then flows through the entire call stack.

The goal of F8 is to push `HashMap<String, String>` input parsing into the NIF shim layer so that the internal logic operates on typed request structs. The `Payload` type alias remains in use at the boundary only.

**Typed request structs** (one per NIF that has meaningful required fields):

| NIF | Required fields | New struct |
|-----|----------------|------------|
| `create_group` | `group_id`, `ciphersuite` | `CreateGroupRequest` (already exists as `CreateGroupParams` — rename) |
| `process_incoming` | `group_id`, `ciphertext` or `message`; optional `message_id`, `pending_commit`, `incoming_type`, snapshot fields | `ProcessIncomingRequest` |
| `create_application_message` | `group_id`, optional `body`, optional `pending_proposals`, snapshot fields | `CreateMessageRequest` |
| `mls_remove` | `group_id`, `leaf_index` or `remove_target`, snapshot fields | `RemoveMemberRequest` |
| `merge_staged_commit` | `group_id`, `commit_ciphertext`, `staged_commit_validated`, snapshot fields | `MergeStagedCommitRequest` |
| `join_from_welcome` | `rejoin_token` or `welcome`, optional `group_id`, snapshot fields | `JoinFromWelcomeRequest` |

Simpler NIFs (`commit_to_pending`, `mls_commit`, `mls_update`, `mls_add`, `clear_pending_commit`, `export_group_info`, `export_ratchet_tree`, `list_member_credentials`) only require `group_id` validation, which is already handled by `with_required_group`. For these, the shim layer change is minimal: parse `group_id` via `ValidatedGroupId::new` (from F15) directly in the shim before calling the internal function. No new structs are needed.

**Each request struct** implements `TryFrom<&Payload>` (or `TryFrom<HashMap<String, String>>` — the latter is preferable since it avoids the intermediate `Payload` construction). The `TryFrom` impl extracts and validates all fields, calling `ValidatedGroupId::new` for the group ID field (F15), `MlsCiphersuite::try_from` for ciphersuite fields (F16), and `SessionSnapshot::from_payload` for snapshot fields (F17/F20).

**Typed response structs** are out of scope for Phase 2. Response types remain `Payload`/`HashMap<String, String>` since the wire encoding is the concern; the internal functions already assemble payloads with known keys. Typed responses belong in a future Phase 3 or the module-split work.

**`payload_from_nif`** becomes dead code after F8. Remove it.

**Elixir impact**: none. The Elixir caller sees identical wire format. The parse happens on the Rust side, entirely before the internal logic.

### How to verify

1. `cargo build` passes.
2. `cargo test` passes.
3. `payload_from_nif` is gone from lib.rs.
4. For each new request struct, add a unit test verifying: (a) a valid input map produces `Ok(struct)`, (b) a map missing a required field produces `Err(MlsError)` with `ErrorCode::InvalidInput` and the expected `details` key.
5. Integration test: construct a `HashMap<String, String>` as the Elixir side would (all strings), call the NIF shim, verify the response map keys are unchanged from current behavior.

### Dependencies

F15 (`ValidatedGroupId`), F16 (`MlsCiphersuite`), and F17/F20 (`SessionSnapshot`) must all land before F8. F7 and F12 are also prerequisites because the internal functions that the shims delegate to will already expect `&str` parameters.

### Risk

High relative to other Phase 2 items, but contained within Rust. The main risks:

1. **Snapshot field handling in `TryFrom`**: request structs for operations that accept a snapshot (e.g. `ProcessIncomingRequest`) must treat snapshot fields as optional in the request parse — a call without snapshot fields is valid (the session will be looked up in `GROUP_SESSIONS`). `SessionSnapshot::from_payload` returning `Option<SessionSnapshot>` is the right primitive here.
2. **Error payload format**: the `TryFrom` implementations must produce `MlsError` with the same `details` key structure that the current `required_non_empty` pattern produces (i.e., `details["some_field"] = "is required"`). Existing tests assert on this format; they guard against regression.
3. **No Elixir change required**: the wire format does not change. The risk is entirely in the Rust compile/test boundary.

---

## F22 — `ensure_session_loaded` helper

**Audit finding**: #22 (medium/structure)

### What changes

The pattern of "restore from snapshot if snapshot present OR if session not in GROUP_SESSIONS" appears in 6 functions:

```rust
// Pattern appears at:
// join_from_welcome (lib.rs:256-264)
// process_incoming  (lib.rs:345-354)
// mls_remove        (lib.rs:509-515)
// merge_staged_commit (lib.rs:691-697)
// create_application_message (lib.rs:839-845)
// list_member_credentials   (lib.rs:943-949)
// export_group_info         (lib.rs:891-898)
```

Extract a helper:

```rust
fn ensure_session_loaded(
    group_id: &ValidatedGroupId,
    params: &Payload,
    operation: &str,
) -> Result<(), MlsError>
```

The helper encapsulates: check `has_complete_session_snapshot(params) || !GROUP_SESSIONS.contains_key(group_id.as_str())`, attempt restore, insert on success. The 7 inline copies are replaced by a single call.

After F17/F20 lands, `has_complete_session_snapshot` inside the helper is replaced by `SessionSnapshot::from_payload(params).is_some()`, making `has_complete_session_snapshot` itself dead code that can be removed.

**Note**: this helper does not resolve the Phase 1 TOCTOU race (that is F1 in the audit, a Phase 1 item). The `contains_key` / `insert` race remains until the Phase 1 DashMap entry-API fix. F22 consolidates the pattern so the Phase 1 fix only needs to be applied in one place rather than seven.

### How to verify

1. `cargo build` passes.
2. `cargo test` passes with no behavior change.
3. `grep -n "has_complete_session_snapshot\|restore_group_session_from_snapshot"` shows each called from exactly one location (the helper) in production code.
4. The 7 inline copies are gone.

### Dependencies

F15 (`ValidatedGroupId`) must land first so the helper accepts a typed group ID. F7 is helpful but not required. F17/F20 is optional for the first iteration (the helper can still call `has_complete_session_snapshot` internally; cleaning that up is a follow-on within F22's PR).

### Risk

Low. This is a pure refactor — no logic changes. The behavior before and after is identical. The only risk is introducing a subtle change in the order of operations; careful reading of each call site before extraction is required.

---

## Summary table

| Fix | Audit # | Severity | PR | Depends on | Elixir coordination needed | Wire format risk |
|-----|---------|----------|----|------------|---------------------------|-----------------|
| F19 | #19 | Medium | PR-A | none | Yes — grep for old strings | Low |
| F7  | #7  | High    | PR-B | none | No | None |
| F12 | #12 | Medium  | PR-B | F7 | No | None |
| F16 | #16 | Medium  | PR-C | F7 (helpful) | No | Medium (ciphersuite round-trip) |
| F15 | #15 | Medium  | PR-C | F7, F19 | No | None |
| F17/F20 | #17, #20 | Medium | PR-D | F7 | No | Medium (snapshot key names) |
| F22 | #22 | Medium  | PR-E | F15 | No | None |
| F8  | #8  | High    | PR-F | F7, F12, F15, F16, F17/F20 | No | High (parse errors must match) |

---

## Items explicitly out of scope for Phase 2

The following audit findings are noted here for completeness but belong in other phases or parallel tracks:

- **#9 (module split)**: splitting lib.rs into multiple files is a structural change that requires all Phase 2 refactors to be complete first, otherwise every PR conflicts. Plan as Phase 3.
- **#10 (Clippy lint configuration)**: add `[lints.clippy]` to `Cargo.toml` as a prerequisite to Phase 2 PRs, not after — it will surface additional issues during the Phase 2 work. This is a one-line Cargo.toml change; do it before PR-A.
- **#13 (`Payload::with_capacity`)**: a standalone low-risk change that can accompany any Phase 2 PR as a drive-by fix.
- **#18 (`pub` → `pub(crate)`)**: straightforward but should wait until after the module split (Phase 3) to avoid churn.
- **#21 (docs)**: add `///` and `# Errors` sections to any new struct/impl introduced in Phase 2 at the same time they are created; do not defer to a separate PR.
- **#1–#6 (Phase 1 items)**: already addressed; not revisited here.
