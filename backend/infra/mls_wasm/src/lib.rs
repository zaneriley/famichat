// Famichat OpenMLS → WASM Spike
// Minimal implementation proving P1-P4 criteria from WASM_SPIKE_DEFINITION.md
// This is a throwaway spike — correct, not clever. All state travels as base64 through JS boundary.
//
// State serialization strategy:
//   OpenMLS 0.8.1 stores group state inside a StorageProvider (MemoryStorage).
//   The provider's `values` field is a pub RwLock<HashMap<Vec<u8>, Vec<u8>>>.
//   We serialize it by base64-encoding every key and value into a JSON map.
//   On restore we rebuild the HashMap and inject it into a fresh OpenMlsRustCrypto,
//   then call MlsGroup::load() to recover the group.
//
// JS interop note:
//   serde-wasm-bindgen v0.4 returns JS Map objects, not plain {}.
//   Instead we use js_sys::JSON::parse on serde_json strings to get real JS objects.
//
// Architecture: extract-and-wrap pattern
//   Every public API has an `_inner` function (returns Result<serde_json::Value, String>)
//   that contains all the real logic and is testable from `cargo test` without a JS runtime.
//   The `#[wasm_bindgen]` export is a thin wrapper that converts the inner result to JsValue.

use base64::{engine::general_purpose::STANDARD as B64, Engine as _};
use openmls::prelude::{
    tls_codec::Deserialize, BasicCredential, Ciphersuite, CredentialWithKey, GroupId, KeyPackage,
    MlsGroup, MlsGroupCreateConfig, MlsGroupJoinConfig, MlsMessageIn, OpenMlsProvider,
    ProcessedMessageContent, ProtocolVersion, StagedWelcome,
};
use openmls_basic_credential::SignatureKeyPair;
use openmls_rust_crypto::OpenMlsRustCrypto;
use serde::{Deserialize as SerdeDeserialize, Serialize as SerdeSerialize};
use std::collections::HashMap;
use wasm_bindgen::prelude::*;

// ============================================================================
// Error handling (P1-P4 require errors to be structured, not panics)
// ============================================================================

fn to_js(value: &serde_json::Value) -> Result<JsValue, JsValue> {
    use js_sys::JSON;
    let json_str = serde_json::to_string(value)
        .map_err(|e| JsValue::from_str(&format!("json serialize: {}", e)))?;
    JSON::parse(&json_str)
}

fn err_js(code: &str, msg: &str) -> JsValue {
    let j = serde_json::json!({ "error": msg, "code": code });
    to_js(&j).unwrap_or_else(|_| JsValue::from_str(msg))
}

// ============================================================================
// Serialization wrappers for group state (proves P1: keys never leave device)
// All state is serialized to base64; caller holds it, passes it back.
// No static HashMap, no global state in Rust → keys live in blob caller holds.
//
// SerializedGroupState JSON layout:
//   {
//     "storage": { "<base64_key>": "<base64_value>", ... },
//     "signer_bytes": "<base64>",
//     "group_id": "<base64>",
//   }
// ============================================================================

#[derive(SerdeSerialize, SerdeDeserialize)]
struct SerializedGroupState {
    /// Base64-encoded key→value pairs from MemoryStorage.values
    storage: HashMap<String, String>,
    /// TLS-serialized SignatureKeyPair (base64)
    signer_bytes: String,
    /// Raw group_id bytes (base64) — needed to call MlsGroup::load(storage, group_id)
    group_id: String,
}

/// MemberState: pre-group state for a member who has key material but hasn't joined yet.
/// Used by create_member() to carry Bob's crypto material across the JS boundary.
#[derive(SerdeSerialize, SerdeDeserialize)]
struct MemberState {
    /// Base64-encoded key→value pairs from MemoryStorage.values (contains KeyPackage data)
    storage: HashMap<String, String>,
    /// TLS-serialized SignatureKeyPair (base64)
    signer_bytes: String,
}

fn serialize_group_state(
    provider: &OpenMlsRustCrypto,
    signer: &SignatureKeyPair,
    group_id: &GroupId,
) -> Result<String, String> {
    // Serialize storage HashMap
    let values = provider
        .storage()
        .values
        .read()
        .map_err(|e| format!("storage lock poisoned: {}", e))?;
    let mut storage_map: HashMap<String, String> = HashMap::new();
    for (k, v) in values.iter() {
        storage_map.insert(B64.encode(k), B64.encode(v));
    }
    drop(values);

    // TLS-serialize the signer
    use openmls::prelude::tls_codec::Serialize as TlsSerialize;
    let signer_bytes = signer
        .tls_serialize_detached()
        .map_err(|e| format!("signer serialize failed: {:?}", e))?;

    let state = SerializedGroupState {
        storage: storage_map,
        signer_bytes: B64.encode(&signer_bytes),
        group_id: B64.encode(group_id.as_slice()),
    };

    serde_json::to_string(&state).map_err(|e| format!("json serialize: {}", e))
}

fn deserialize_group_state(
    state_json: &str,
) -> Result<(MlsGroup, SignatureKeyPair, OpenMlsRustCrypto), String> {
    let state: SerializedGroupState =
        serde_json::from_str(state_json).map_err(|e| format!("json parse: {}", e))?;

    // Rebuild the storage HashMap
    let mut map: HashMap<Vec<u8>, Vec<u8>> = HashMap::new();
    for (k_b64, v_b64) in &state.storage {
        let k = B64
            .decode(k_b64)
            .map_err(|e| format!("key b64 decode: {}", e))?;
        let v = B64
            .decode(v_b64)
            .map_err(|e| format!("val b64 decode: {}", e))?;
        map.insert(k, v);
    }

    // Inject into a fresh OpenMlsRustCrypto provider
    let provider = OpenMlsRustCrypto::default();
    {
        let mut values = provider
            .storage()
            .values
            .write()
            .map_err(|e| format!("storage lock poisoned: {}", e))?;
        *values = map;
    }

    // Recover group_id
    let group_id_bytes = B64
        .decode(&state.group_id)
        .map_err(|e| format!("group_id b64 decode: {}", e))?;
    let group_id = GroupId::from_slice(&group_id_bytes);

    // Load the MlsGroup from the provider's storage
    let group = MlsGroup::load(provider.storage(), &group_id)
        .map_err(|e| format!("group load from storage: {:?}", e))?
        .ok_or_else(|| "group not found in restored storage".to_string())?;

    // Deserialize signer
    let signer_bytes = B64
        .decode(&state.signer_bytes)
        .map_err(|e| format!("signer b64 decode: {}", e))?;
    let signer = SignatureKeyPair::tls_deserialize(&mut signer_bytes.as_slice())
        .map_err(|e| format!("signer deserialize: {:?}", e))?;

    Ok((group, signer, provider))
}

// ============================================================================
// API 1: health_check() → proves WASM + OpenMLS loads
// ============================================================================

#[wasm_bindgen]
pub fn health_check() -> JsValue {
    let j = serde_json::json!({
        "status": "ok",
        "reason": "wasm_openmls_initialized",
        "ciphersuite": "MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519",
    });
    to_js(&j).unwrap_or_else(|_| JsValue::from_str("health_check_ok"))
}

// ============================================================================
// API 2: create_group(identity, group_id) → creates real OpenMLS group
// Returns: { group_state: string (JSON blob), identity: string, group_id: string }
// Proves: T1 (compiles), P1 (no global state), P3 setup (caller holds state)
// ============================================================================

fn create_group_inner(identity: &str, group_id: &str) -> Result<serde_json::Value, String> {
    if identity.is_empty() || group_id.is_empty() {
        return Err("identity and group_id required".to_string());
    }
    if group_id.len() > 256 {
        return Err("group_id must be <=256 bytes (prevents NUL attacks)".to_string());
    }

    // Create crypto provider (fresh per call; no global state)
    let provider = OpenMlsRustCrypto::default();

    // Create signer
    let ciphersuite = Ciphersuite::MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519;
    let signer = SignatureKeyPair::new(ciphersuite.signature_algorithm())
        .map_err(|e| format!("signer creation: {:?}", e))?;

    // Create credential
    let credential = BasicCredential::new(identity.as_bytes().to_vec());
    let credential_with_key = CredentialWithKey {
        credential: credential.into(),
        signature_key: signer.public().into(),
    };

    // Create group with explicit group_id
    let group_id_raw = GroupId::from_slice(group_id.as_bytes());
    let group_config = MlsGroupCreateConfig::builder()
        .ciphersuite(ciphersuite)
        .use_ratchet_tree_extension(true)
        .build();

    let _group = MlsGroup::new_with_group_id(
        &provider,
        &signer,
        &group_config,
        group_id_raw.clone(),
        credential_with_key,
    )
    .map_err(|e| format!("group creation: {:?}", e))?;

    // Serialize state (proves no global storage; all state in blob)
    let state_json = serialize_group_state(&provider, &signer, &group_id_raw)?;

    Ok(serde_json::json!({
        "group_state": state_json,
        "identity": identity,
        "group_id": group_id,
    }))
}

#[wasm_bindgen]
pub fn create_group(identity: &str, group_id: &str) -> Result<JsValue, JsValue> {
    create_group_inner(identity, group_id)
        .map_err(|e| err_js("invalid_input", &e))
        .and_then(|v| to_js(&v).map_err(|_| err_js("serialization_failed", "json_to_js")))
}

// ============================================================================
// API 3: encrypt_message(group_state, plaintext)
// Returns: { ciphertext: base64, new_group_state: string }
// Proves: P3 (state updates persist; caller simulates session end by discarding),
//         P4 (timing <50ms for create_message)
// ============================================================================

fn encrypt_message_inner(group_state: &str, plaintext: &str) -> Result<serde_json::Value, String> {
    if group_state.is_empty() || plaintext.is_empty() {
        return Err("group_state and plaintext required".to_string());
    }

    // Deserialize group (proves stateless: only caller's blob holds state)
    let (mut group, signer, provider) =
        deserialize_group_state(group_state).map_err(|e| format!("state deserialize: {}", e))?;

    // Encrypt — create_message(provider, signer, message_bytes)
    let mls_msg_out = group
        .create_message(&provider, &signer, plaintext.as_bytes())
        .map_err(|e| format!("encrypt failed: {:?}", e))?;

    let ciphertext_bytes = mls_msg_out
        .to_bytes()
        .map_err(|e| format!("message serialize: {:?}", e))?;

    // Recover group_id from the group
    let gid = group.group_id().clone();

    // Serialize new state (updated after create_message)
    let new_state_json = serialize_group_state(&provider, &signer, &gid)?;

    Ok(serde_json::json!({
        "ciphertext": B64.encode(&ciphertext_bytes),
        "new_group_state": new_state_json,
    }))
}

#[wasm_bindgen]
pub fn encrypt_message(group_state: &str, plaintext: &str) -> Result<JsValue, JsValue> {
    encrypt_message_inner(group_state, plaintext)
        .map_err(|e| err_js("invalid_input", &e))
        .and_then(|v| to_js(&v).map_err(|_| err_js("serialization_failed", "json_to_js")))
}

// ============================================================================
// API 4: decrypt_message(group_state, ciphertext)
// Returns: { plaintext: string, new_group_state: string }
// Proves: P3 (restoration from serialized state works), P4 (timing <50ms for process_message)
// ============================================================================

fn decrypt_message_inner(group_state: &str, ciphertext: &str) -> Result<serde_json::Value, String> {
    if group_state.is_empty() || ciphertext.is_empty() {
        return Err("group_state and ciphertext required".to_string());
    }

    // Deserialize group (proves P3: state restores correctly)
    let (mut group, signer, provider) =
        deserialize_group_state(group_state).map_err(|e| format!("state deserialize: {}", e))?;

    // Decode ciphertext from base64
    let ciphertext_bytes = B64
        .decode(ciphertext)
        .map_err(|e| format!("ciphertext decode: {}", e))?;

    // Deserialize MlsMessageIn using TLS codec
    let message = MlsMessageIn::tls_deserialize(&mut ciphertext_bytes.as_slice())
        .map_err(|e| format!("message parse: {:?}", e))?;

    // Convert to ProtocolMessage (required by process_message)
    let protocol_msg = message
        .try_into_protocol_message()
        .map_err(|e| format!("message unwrap: {:?}", e))?;

    // Decrypt
    let processed = group
        .process_message(&provider, protocol_msg)
        .map_err(|e| format!("decrypt failed: {:?}", e))?;

    // Extract plaintext from ProcessedMessageContent
    let plaintext = match processed.into_content() {
        ProcessedMessageContent::ApplicationMessage(content) => {
            String::from_utf8(content.into_bytes()).map_err(|e| format!("utf8 decode: {}", e))?
        }
        ProcessedMessageContent::ProposalMessage(_) => {
            return Err("received proposal, expected application message".to_string());
        }
        ProcessedMessageContent::ExternalJoinProposalMessage(_) => {
            return Err(
                "received external join proposal, expected application message".to_string(),
            );
        }
        ProcessedMessageContent::StagedCommitMessage(_) => {
            return Err("received staged commit, expected application message".to_string());
        }
    };

    // Recover group_id and serialize new state
    let gid = group.group_id().clone();
    let new_state_json = serialize_group_state(&provider, &signer, &gid)?;

    Ok(serde_json::json!({
        "plaintext": plaintext,
        "new_group_state": new_state_json,
    }))
}

#[wasm_bindgen]
pub fn decrypt_message(group_state: &str, ciphertext: &str) -> Result<JsValue, JsValue> {
    decrypt_message_inner(group_state, ciphertext)
        .map_err(|e| err_js("crypto_failure", &e))
        .and_then(|v| to_js(&v).map_err(|_| err_js("serialization_failed", "json_to_js")))
}

// ============================================================================
// API 5: create_member(identity) → creates key material for a new member (Bob)
// Returns: { key_package: base64, member_state: json_string }
// The key_package is passed to add_member(); member_state is passed to join_group().
// ============================================================================

fn create_member_inner(identity: &str) -> Result<serde_json::Value, String> {
    if identity.is_empty() {
        return Err("identity required".to_string());
    }

    let provider = OpenMlsRustCrypto::default();
    let ciphersuite = Ciphersuite::MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519;

    // Create signer
    let signer = SignatureKeyPair::new(ciphersuite.signature_algorithm())
        .map_err(|e| format!("signer creation: {:?}", e))?;

    // Create credential
    let credential = BasicCredential::new(identity.as_bytes().to_vec());
    let credential_with_key = CredentialWithKey {
        credential: credential.into(),
        signature_key: signer.public().into(),
    };

    // Build a KeyPackage
    let key_package = KeyPackage::builder()
        .build(ciphersuite, &provider, &signer, credential_with_key)
        .map_err(|e| format!("key_package build: {:?}", e))?;

    // TLS-serialize the KeyPackage
    use openmls::prelude::tls_codec::Serialize as TlsSerialize;
    let kp_bytes = key_package
        .key_package()
        .tls_serialize_detached()
        .map_err(|e| format!("key_package serialize: {:?}", e))?;

    // TLS-serialize the signer
    let signer_bytes = signer
        .tls_serialize_detached()
        .map_err(|e| format!("signer serialize: {:?}", e))?;

    // Serialize provider storage
    let values = provider
        .storage()
        .values
        .read()
        .map_err(|e| format!("storage lock: {}", e))?;
    let mut storage_map: HashMap<String, String> = HashMap::new();
    for (k, v) in values.iter() {
        storage_map.insert(B64.encode(k), B64.encode(v));
    }
    drop(values);

    let member_state = MemberState {
        storage: storage_map,
        signer_bytes: B64.encode(&signer_bytes),
    };
    let member_state_json = serde_json::to_string(&member_state)
        .map_err(|e| format!("member_state serialize: {}", e))?;

    Ok(serde_json::json!({
        "key_package": B64.encode(&kp_bytes),
        "member_state": member_state_json,
    }))
}

#[wasm_bindgen]
pub fn create_member(identity: &str) -> Result<JsValue, JsValue> {
    create_member_inner(identity)
        .map_err(|e| err_js("invalid_input", &e))
        .and_then(|v| to_js(&v).map_err(|_| err_js("serialization_failed", "json_to_js")))
}

// ============================================================================
// API 6: add_member(group_state, key_package_b64) → Alice adds Bob to the group
// Returns: { welcome: base64, ratchet_tree: base64, commit: base64, new_group_state: json_string }
// ============================================================================

fn add_member_inner(group_state: &str, key_package_b64: &str) -> Result<serde_json::Value, String> {
    if group_state.is_empty() || key_package_b64.is_empty() {
        return Err("group_state and key_package_b64 required".to_string());
    }

    // Restore Alice's group
    let (mut group, signer, provider) =
        deserialize_group_state(group_state).map_err(|e| format!("state deserialize: {}", e))?;

    // Decode and TLS-deserialize the KeyPackage
    let kp_bytes = B64
        .decode(key_package_b64)
        .map_err(|e| format!("key_package b64 decode: {}", e))?;

    use openmls::prelude::KeyPackageIn;
    let key_package_in = KeyPackageIn::tls_deserialize(&mut kp_bytes.as_slice())
        .map_err(|e| format!("key_package tls_deserialize: {:?}", e))?;

    // Validate the KeyPackage
    let key_package = key_package_in
        .validate(provider.crypto(), ProtocolVersion::Mls10)
        .map_err(|e| format!("key_package validate: {:?}", e))?;

    // Add member — returns (commit_msg, welcome, _group_info)
    let (commit_msg, welcome, _group_info) = group
        .add_members(&provider, &signer, &[key_package])
        .map_err(|e| format!("add_members: {:?}", e))?;

    // Merge commit to advance Alice's epoch
    group
        .merge_pending_commit(&provider)
        .map_err(|e| format!("merge_pending_commit: {:?}", e))?;

    // TLS-serialize the commit message
    use openmls::prelude::tls_codec::Serialize as TlsSerialize;
    let commit_bytes = commit_msg
        .to_bytes()
        .map_err(|e| format!("commit serialize: {:?}", e))?;

    // TLS-serialize the Welcome
    let welcome_bytes = welcome
        .tls_serialize_detached()
        .map_err(|e| format!("welcome serialize: {:?}", e))?;

    // Export ratchet tree — export_ratchet_tree() returns RatchetTreeIn
    let ratchet_tree = group.export_ratchet_tree();
    let ratchet_tree_bytes = ratchet_tree
        .tls_serialize_detached()
        .map_err(|e| format!("ratchet_tree serialize: {:?}", e))?;

    // Serialize Alice's new group state
    let gid = group.group_id().clone();
    let new_group_state = serialize_group_state(&provider, &signer, &gid)?;

    Ok(serde_json::json!({
        "welcome": B64.encode(&welcome_bytes),
        "ratchet_tree": B64.encode(&ratchet_tree_bytes),
        "commit": B64.encode(&commit_bytes),
        "new_group_state": new_group_state,
    }))
}

#[wasm_bindgen]
pub fn add_member(group_state: &str, key_package_b64: &str) -> Result<JsValue, JsValue> {
    add_member_inner(group_state, key_package_b64)
        .map_err(|e| err_js("invalid_input", &e))
        .and_then(|v| to_js(&v).map_err(|_| err_js("serialization_failed", "json_to_js")))
}

// ============================================================================
// API 7: join_group(welcome_b64, ratchet_tree_b64, member_state) → Bob joins
// Returns: { group_state: json_string }
// ============================================================================

fn join_group_inner(
    welcome_b64: &str,
    ratchet_tree_b64: &str,
    member_state: &str,
) -> Result<serde_json::Value, String> {
    if welcome_b64.is_empty() || member_state.is_empty() {
        return Err("welcome_b64 and member_state required".to_string());
    }

    // Parse member_state
    let ms: MemberState =
        serde_json::from_str(member_state).map_err(|e| format!("member_state parse: {}", e))?;

    // Rebuild Bob's provider with his stored key material
    let provider = OpenMlsRustCrypto::default();
    {
        let mut map: HashMap<Vec<u8>, Vec<u8>> = HashMap::new();
        for (k_b64, v_b64) in &ms.storage {
            let k = B64
                .decode(k_b64)
                .map_err(|e| format!("storage key b64: {}", e))?;
            let v = B64
                .decode(v_b64)
                .map_err(|e| format!("storage val b64: {}", e))?;
            map.insert(k, v);
        }
        let mut values = provider
            .storage()
            .values
            .write()
            .map_err(|e| format!("storage lock: {}", e))?;
        *values = map;
    }

    // Deserialize Bob's signer
    let signer_bytes = B64
        .decode(&ms.signer_bytes)
        .map_err(|e| format!("signer b64 decode: {}", e))?;
    let signer = SignatureKeyPair::tls_deserialize(&mut signer_bytes.as_slice())
        .map_err(|e| format!("signer deserialize: {:?}", e))?;

    // TLS-deserialize the Welcome from the raw bytes
    let welcome_bytes = B64
        .decode(welcome_b64)
        .map_err(|e| format!("welcome b64 decode: {}", e))?;

    use openmls::prelude::MlsMessageBodyIn;
    let welcome_msg = MlsMessageIn::tls_deserialize(&mut welcome_bytes.as_slice())
        .map_err(|e| format!("welcome tls_deserialize: {:?}", e))?;
    let welcome = match welcome_msg.extract() {
        MlsMessageBodyIn::Welcome(w) => w,
        _ => {
            return Err("expected Welcome message, got something else".to_string());
        }
    };

    // TLS-deserialize the ratchet tree (if provided)
    let ratchet_tree = if ratchet_tree_b64.is_empty() {
        None
    } else {
        use openmls::prelude::RatchetTreeIn;
        let rt_bytes = B64
            .decode(ratchet_tree_b64)
            .map_err(|e| format!("ratchet_tree b64 decode: {}", e))?;
        let rt = RatchetTreeIn::tls_deserialize(&mut rt_bytes.as_slice())
            .map_err(|e| format!("ratchet_tree deserialize: {:?}", e))?;
        Some(rt)
    };

    // Bob joins via StagedWelcome
    let staged_welcome = StagedWelcome::new_from_welcome(
        &provider,
        &MlsGroupJoinConfig::default(),
        welcome,
        ratchet_tree,
    )
    .map_err(|e| format!("StagedWelcome::new_from_welcome: {:?}", e))?;

    let group = staged_welcome
        .into_group(&provider)
        .map_err(|e| format!("staged_welcome.into_group: {:?}", e))?;

    // Serialize Bob's group state
    let gid = group.group_id().clone();
    let group_state = serialize_group_state(&provider, &signer, &gid)?;

    Ok(serde_json::json!({
        "group_state": group_state,
    }))
}

#[wasm_bindgen]
pub fn join_group(
    welcome_b64: &str,
    ratchet_tree_b64: &str,
    member_state: &str,
) -> Result<JsValue, JsValue> {
    join_group_inner(welcome_b64, ratchet_tree_b64, member_state)
        .map_err(|e| err_js("invalid_input", &e))
        .and_then(|v| to_js(&v).map_err(|_| err_js("serialization_failed", "json_to_js")))
}

// ============================================================================
// API 8: process_commit(group_state, commit_b64) → apply a commit from another member
// Returns: { new_group_state: json_string }
// Used by non-committer members (e.g. Bob) to process Alice's add_member commit
// and advance their own epoch so they can decrypt post-commit messages.
// ============================================================================

fn process_commit_inner(group_state: &str, commit_b64: &str) -> Result<serde_json::Value, String> {
    if group_state.is_empty() || commit_b64.is_empty() {
        return Err("group_state and commit_b64 required".to_string());
    }

    let (mut group, signer, provider) = deserialize_group_state(group_state)?;

    let commit_bytes = B64
        .decode(commit_b64)
        .map_err(|e| format!("commit b64 decode: {}", e))?;

    let message = MlsMessageIn::tls_deserialize(&mut commit_bytes.as_slice())
        .map_err(|e| format!("commit tls_deserialize: {:?}", e))?;

    let protocol_msg = message
        .try_into_protocol_message()
        .map_err(|e| format!("commit unwrap: {:?}", e))?;

    let processed = group
        .process_message(&provider, protocol_msg)
        .map_err(|e| format!("process_message: {:?}", e))?;

    match processed.into_content() {
        ProcessedMessageContent::StagedCommitMessage(staged_commit) => {
            group
                .merge_staged_commit(&provider, *staged_commit)
                .map_err(|e| format!("merge_staged_commit: {:?}", e))?;
            // merge_staged_commit writes the updated group state to provider.storage() as a side effect.
            // serialize_group_state reads from that storage, so the returned state reflects the new epoch.
        }
        ProcessedMessageContent::ApplicationMessage(_) => {
            return Err("expected StagedCommit in process_commit, got ApplicationMessage — pass ciphertext to decrypt_message instead".to_string());
        }
        ProcessedMessageContent::ProposalMessage(_) => {
            return Err("expected StagedCommit in process_commit, got ProposalMessage".to_string());
        }
        ProcessedMessageContent::ExternalJoinProposalMessage(_) => {
            return Err(
                "expected StagedCommit in process_commit, got ExternalJoinProposalMessage"
                    .to_string(),
            );
        }
    }

    let gid = group.group_id().clone();
    let new_state = serialize_group_state(&provider, &signer, &gid)?;

    Ok(serde_json::json!({
        "new_group_state": new_state,
    }))
}

#[wasm_bindgen]
pub fn process_commit(group_state: &str, commit_b64: &str) -> Result<JsValue, JsValue> {
    process_commit_inner(group_state, commit_b64)
        .map_err(|e| err_js("crypto_failure", &e))
        .and_then(|v| to_js(&v).map_err(|_| err_js("serialization_failed", "json_to_js")))
}

// ============================================================================
// Unit tests — run with: cargo test (no WASM compilation or JS runtime needed)
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    // -------------------------------------------------------------------------
    // Helpers — unique group IDs to avoid cross-test conflicts when run in parallel
    // -------------------------------------------------------------------------

    fn unique_group_id(prefix: &str) -> String {
        use std::sync::atomic::{AtomicU64, Ordering};
        static COUNTER: AtomicU64 = AtomicU64::new(0);
        let n = COUNTER.fetch_add(1, Ordering::Relaxed);
        format!("{}-{}", prefix, n)
    }

    fn alice_group_with_id(gid: &str) -> (serde_json::Value, String) {
        let result = create_group_inner("alice@test", gid).expect("create_group_inner failed");
        let state = result["group_state"].as_str().unwrap().to_string();
        (result, state)
    }

    fn alice_group() -> (serde_json::Value, String) {
        alice_group_with_id(&unique_group_id("test-group"))
    }

    fn two_member_group() -> (String, String) {
        let (_, alice_state) = alice_group();
        let bob = create_member_inner("bob@test").expect("create_member_inner failed");
        let bob_kp = bob["key_package"].as_str().unwrap();
        let add = add_member_inner(&alice_state, bob_kp).expect("add_member_inner failed");
        let alice_new = add["new_group_state"].as_str().unwrap().to_string();
        let bob_result = join_group_inner(
            add["welcome"].as_str().unwrap(),
            add["ratchet_tree"].as_str().unwrap(),
            bob["member_state"].as_str().unwrap(),
        )
        .expect("join_group_inner failed");
        let bob_state = bob_result["group_state"].as_str().unwrap().to_string();
        (alice_new, bob_state)
    }

    // P6 — State serialization is faithful
    #[test]
    fn state_round_trip_produces_functional_group() {
        let (alice_state, bob_state) = two_member_group();

        // Round-trip: deserialize then re-serialize both states
        let (alice_group, alice_signer, alice_provider) =
            deserialize_group_state(&alice_state).expect("alice deserialize");
        let alice_rt =
            serialize_group_state(&alice_provider, &alice_signer, alice_group.group_id())
                .expect("alice re-serialize");

        let (bob_group, bob_signer, bob_provider) =
            deserialize_group_state(&bob_state).expect("bob deserialize");
        let bob_rt = serialize_group_state(&bob_provider, &bob_signer, bob_group.group_id())
            .expect("bob re-serialize");

        // After round-trip, encrypt/decrypt must still work — two messages to exercise
        // ratchet state: if serialization loses forward-secrecy state, the second message fails.
        let enc1 = encrypt_message_inner(&alice_rt, "round-trip-message-1")
            .expect("encrypt msg1 after alice round-trip");
        let alice_rt2 = enc1["new_group_state"].as_str().unwrap().to_string();
        let dec1 = decrypt_message_inner(&bob_rt, enc1["ciphertext"].as_str().unwrap())
            .expect("decrypt msg1 after bob round-trip");
        assert_eq!(dec1["plaintext"].as_str().unwrap(), "round-trip-message-1");

        let bob_rt2 = dec1["new_group_state"].as_str().unwrap().to_string();
        let enc2 = encrypt_message_inner(&alice_rt2, "round-trip-message-2")
            .expect("encrypt msg2 after alice round-trip");
        let dec2 = decrypt_message_inner(&bob_rt2, enc2["ciphertext"].as_str().unwrap())
            .expect("decrypt msg2 after bob round-trip");
        assert_eq!(dec2["plaintext"].as_str().unwrap(), "round-trip-message-2");
    }

    // P6 — Corrupted state blob fails loudly (not silent corruption)
    #[test]
    fn corrupted_state_blob_fails_with_clear_error() {
        let err = deserialize_group_state("not-valid-json-at-all{{{");
        assert!(err.is_err(), "corrupted JSON should fail");
        let msg = err.unwrap_err();
        assert!(!msg.is_empty(), "error message must not be empty");
    }

    #[test]
    fn truncated_state_blob_fails_with_clear_error() {
        let err =
            deserialize_group_state("{\"storage\":{},\"signer_bytes\":\"x\",\"group_id\":\"y\"}");
        assert!(err.is_err(), "invalid base64 in state should fail");
    }

    // P2 — Two-member encrypt/decrypt round-trip works
    #[test]
    fn two_member_encrypt_decrypt_round_trip() {
        let (alice_state, bob_state) = two_member_group();
        let plaintext = "hello from alice to bob";

        let enc = encrypt_message_inner(&alice_state, plaintext).expect("encrypt failed");
        let ciphertext = enc["ciphertext"].as_str().unwrap();

        // Ciphertext must not contain plaintext
        let raw = B64.decode(ciphertext).unwrap();
        assert!(
            !raw.windows(plaintext.len())
                .any(|w| w == plaintext.as_bytes()),
            "ciphertext must not contain plaintext bytes"
        );

        let dec = decrypt_message_inner(&bob_state, ciphertext).expect("decrypt failed");
        assert_eq!(dec["plaintext"].as_str().unwrap(), plaintext);
    }

    // P2 — Non-member (Eve) with a different group cannot decrypt
    #[test]
    fn wrong_group_state_cannot_decrypt() {
        let (alice_state, _bob_state) = two_member_group();

        // Eve has her own separate group — never added to Alice's group
        let (_, eve_state) = alice_group(); // Eve's isolated single-member group

        let enc =
            encrypt_message_inner(&alice_state, "secret message").expect("alice encrypt failed");
        let ciphertext = enc["ciphertext"].as_str().unwrap();

        // Eve's state should NOT be able to decrypt Alice's ciphertext
        let result = decrypt_message_inner(&eve_state, ciphertext);
        assert!(
            result.is_err(),
            "non-member must not decrypt: got {:?}",
            result
        );
    }

    // P5 + P7 — process_commit advances epoch; member with stale state cannot decrypt post-commit messages
    #[test]
    fn process_commit_advances_epoch_and_enables_post_commit_decryption() {
        // Setup: Alice, Bob in group. Carol creates member state but hasn't joined.
        let (alice_state, bob_state) = two_member_group();
        let carol = create_member_inner("carol@test").expect("carol create_member failed");

        // Alice adds Carol — returns commit + welcome
        let add = add_member_inner(&alice_state, carol["key_package"].as_str().unwrap())
            .expect("add carol failed");

        let commit_b64 = add["commit"].as_str()
            .expect("add_member must return a commit field — if missing, the commit gap fix was not applied");
        let alice_new_state = add["new_group_state"].as_str().unwrap();

        // Bob must process the commit to stay in sync
        let bob_after_commit =
            process_commit_inner(&bob_state, commit_b64).expect("bob process_commit failed");
        let bob_new_state = bob_after_commit["new_group_state"].as_str().unwrap();

        // Carol joins
        let carol_result = join_group_inner(
            add["welcome"].as_str().unwrap(),
            add["ratchet_tree"].as_str().unwrap(),
            carol["member_state"].as_str().unwrap(),
        )
        .expect("carol join failed");
        let carol_state = carol_result["group_state"].as_str().unwrap();

        // Alice sends a message in the new epoch
        let enc = encrypt_message_inner(alice_new_state, "post-commit message")
            .expect("alice encrypt post-commit failed");
        let ciphertext = enc["ciphertext"].as_str().unwrap();

        // Bob (after processing commit) can decrypt
        let dec_bob = decrypt_message_inner(bob_new_state, ciphertext)
            .expect("bob must decrypt post-commit message");
        assert_eq!(
            dec_bob["plaintext"].as_str().unwrap(),
            "post-commit message"
        );

        // Carol (newly joined) can decrypt
        let dec_carol = decrypt_message_inner(carol_state, ciphertext)
            .expect("carol must decrypt post-commit message");
        assert_eq!(
            dec_carol["plaintext"].as_str().unwrap(),
            "post-commit message"
        );
    }

    // P5 — Stale state (pre-commit) cannot decrypt post-commit messages
    #[test]
    fn stale_state_cannot_decrypt_post_commit_message() {
        let (alice_state, bob_state_pre_commit) = two_member_group();
        let carol = create_member_inner("carol@test-stale").unwrap();

        let add = add_member_inner(&alice_state, carol["key_package"].as_str().unwrap())
            .expect("add carol failed");
        let alice_new_state = add["new_group_state"].as_str().unwrap();

        // Alice sends a message AFTER the commit (new epoch)
        let enc = encrypt_message_inner(alice_new_state, "new epoch message")
            .expect("alice encrypt new epoch failed");
        let ciphertext = enc["ciphertext"].as_str().unwrap();

        // Bob with STALE state (pre-commit, old epoch) should NOT be able to decrypt
        let result = decrypt_message_inner(&bob_state_pre_commit, ciphertext);
        assert!(
            result.is_err(),
            "stale state must not decrypt post-commit message: got {:?}",
            result
        );
    }

    // Validation — empty inputs return clear errors
    #[test]
    fn empty_inputs_return_clear_errors() {
        assert!(create_group_inner("", "g1").is_err());
        assert!(create_group_inner("alice", "").is_err());
        assert!(encrypt_message_inner("", "msg").is_err());
        assert!(encrypt_message_inner("state", "").is_err());
        assert!(decrypt_message_inner("", "ciphertext").is_err());
        assert!(process_commit_inner("", "commit").is_err());
        assert!(process_commit_inner("state", "").is_err());
    }
}
