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

use base64::{engine::general_purpose::STANDARD as B64, Engine as _};
use js_sys::JSON;
use openmls::prelude::{
    tls_codec::Deserialize,
    BasicCredential, Ciphersuite, CredentialWithKey, GroupId, KeyPackage, MlsGroup,
    MlsGroupCreateConfig, MlsGroupJoinConfig, MlsMessageIn, OpenMlsProvider,
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
        let k = B64.decode(k_b64).map_err(|e| format!("key b64 decode: {}", e))?;
        let v = B64.decode(v_b64).map_err(|e| format!("val b64 decode: {}", e))?;
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

#[wasm_bindgen]
pub fn create_group(identity: &str, group_id: &str) -> Result<JsValue, JsValue> {
    // Validate inputs
    if identity.is_empty() || group_id.is_empty() {
        return Err(err_js("invalid_input", "identity and group_id required"));
    }
    if group_id.len() > 256 {
        return Err(err_js(
            "invalid_input",
            "group_id must be ≤256 bytes (prevents NUL attacks)",
        ));
    }

    // Create crypto provider (fresh per call; no global state)
    let provider = OpenMlsRustCrypto::default();

    // Create signer
    let ciphersuite = Ciphersuite::MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519;
    let signer = SignatureKeyPair::new(ciphersuite.signature_algorithm())
        .map_err(|e| err_js("crypto_failure", &format!("signer creation: {:?}", e)))?;

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
    .map_err(|e| err_js("crypto_failure", &format!("group creation: {:?}", e)))?;

    // Serialize state (proves no global storage; all state in blob)
    let state_json = serialize_group_state(&provider, &signer, &group_id_raw)
        .map_err(|e| err_js("serialization_failed", &e))?;

    let response = serde_json::json!({
        "group_state": state_json,
        "identity": identity,
        "group_id": group_id,
    });

    to_js(&response).map_err(|e| err_js("serialization_failed", &format!("{:?}", e)))
}

// ============================================================================
// API 3: encrypt_message(group_state, plaintext)
// Returns: { ciphertext: base64, new_group_state: string }
// Proves: P3 (state updates persist; caller simulates session end by discarding),
//         P4 (timing <50ms for create_message)
// ============================================================================

#[wasm_bindgen]
pub fn encrypt_message(group_state: &str, plaintext: &str) -> Result<JsValue, JsValue> {
    if group_state.is_empty() || plaintext.is_empty() {
        return Err(err_js("invalid_input", "group_state and plaintext required"));
    }

    // Deserialize group (proves stateless: only caller's blob holds state)
    let (mut group, signer, provider) = deserialize_group_state(group_state)
        .map_err(|e| err_js("invalid_input", &format!("state deserialize: {}", e)))?;

    // Encrypt — create_message(provider, signer, message_bytes)
    let mls_msg_out = group
        .create_message(&provider, &signer, plaintext.as_bytes())
        .map_err(|e| err_js("crypto_failure", &format!("encrypt failed: {:?}", e)))?;

    let ciphertext_bytes = mls_msg_out
        .to_bytes()
        .map_err(|e| err_js("crypto_failure", &format!("message serialize: {:?}", e)))?;

    // Recover group_id from the group
    let gid = group.group_id().clone();

    // Serialize new state (updated after create_message)
    let new_state_json = serialize_group_state(&provider, &signer, &gid)
        .map_err(|e| err_js("serialization_failed", &e))?;

    let response = serde_json::json!({
        "ciphertext": B64.encode(&ciphertext_bytes),
        "new_group_state": new_state_json,
    });

    to_js(&response).map_err(|e| err_js("serialization_failed", &format!("{:?}", e)))
}

// ============================================================================
// API 4: decrypt_message(group_state, ciphertext)
// Returns: { plaintext: string, new_group_state: string }
// Proves: P3 (restoration from serialized state works), P4 (timing <50ms for process_message)
// ============================================================================

#[wasm_bindgen]
pub fn decrypt_message(group_state: &str, ciphertext: &str) -> Result<JsValue, JsValue> {
    if group_state.is_empty() || ciphertext.is_empty() {
        return Err(err_js("invalid_input", "group_state and ciphertext required"));
    }

    // Deserialize group (proves P3: state restores correctly)
    let (mut group, signer, provider) = deserialize_group_state(group_state)
        .map_err(|e| err_js("invalid_input", &format!("state deserialize: {}", e)))?;

    // Decode ciphertext from base64
    let ciphertext_bytes = B64
        .decode(ciphertext)
        .map_err(|e| err_js("invalid_input", &format!("ciphertext decode: {}", e)))?;

    // Deserialize MlsMessageIn using TLS codec
    let message = openmls::prelude::MlsMessageIn::tls_deserialize(&mut ciphertext_bytes.as_slice())
        .map_err(|e| err_js("crypto_failure", &format!("message parse: {:?}", e)))?;

    // Convert to ProtocolMessage (required by process_message)
    let protocol_msg = message
        .try_into_protocol_message()
        .map_err(|e| err_js("crypto_failure", &format!("message unwrap: {:?}", e)))?;

    // Decrypt
    let processed = group
        .process_message(&provider, protocol_msg)
        .map_err(|e| err_js("crypto_failure", &format!("decrypt failed: {:?}", e)))?;

    // Extract plaintext from ProcessedMessageContent
    let plaintext = match processed.into_content() {
        ProcessedMessageContent::ApplicationMessage(content) => {
            String::from_utf8(content.into_bytes())
                .map_err(|e| err_js("crypto_failure", &format!("utf8 decode: {}", e)))?
        }
        ProcessedMessageContent::ProposalMessage(_) => {
            return Err(err_js(
                "invalid_input",
                "received proposal, expected application message",
            ))
        }
        ProcessedMessageContent::ExternalJoinProposalMessage(_) => {
            return Err(err_js(
                "invalid_input",
                "received external join proposal, expected application message",
            ))
        }
        ProcessedMessageContent::StagedCommitMessage(_) => {
            return Err(err_js(
                "invalid_input",
                "received staged commit, expected application message",
            ))
        }
    };

    // Recover group_id and serialize new state
    let gid = group.group_id().clone();
    let new_state_json = serialize_group_state(&provider, &signer, &gid)
        .map_err(|e| err_js("serialization_failed", &e))?;

    let response = serde_json::json!({
        "plaintext": plaintext,
        "new_group_state": new_state_json,
    });

    to_js(&response).map_err(|e| err_js("serialization_failed", &format!("{:?}", e)))
}

// ============================================================================
// API 5: create_member(identity) → creates key material for a new member (Bob)
// Returns: { key_package: base64, member_state: json_string }
// The key_package is passed to add_member(); member_state is passed to join_group().
// ============================================================================

#[wasm_bindgen]
pub fn create_member(identity: &str) -> Result<JsValue, JsValue> {
    if identity.is_empty() {
        return Err(err_js("invalid_input", "identity required"));
    }

    let provider = OpenMlsRustCrypto::default();
    let ciphersuite = Ciphersuite::MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519;

    // Create signer
    let signer = SignatureKeyPair::new(ciphersuite.signature_algorithm())
        .map_err(|e| err_js("crypto_failure", &format!("signer creation: {:?}", e)))?;

    // Create credential
    let credential = BasicCredential::new(identity.as_bytes().to_vec());
    let credential_with_key = CredentialWithKey {
        credential: credential.into(),
        signature_key: signer.public().into(),
    };

    // Build a KeyPackage
    let key_package = KeyPackage::builder()
        .build(ciphersuite, &provider, &signer, credential_with_key)
        .map_err(|e| err_js("crypto_failure", &format!("key_package build: {:?}", e)))?;

    // TLS-serialize the KeyPackage
    use openmls::prelude::tls_codec::Serialize as TlsSerialize;
    let kp_bytes = key_package
        .key_package()
        .tls_serialize_detached()
        .map_err(|e| err_js("crypto_failure", &format!("key_package serialize: {:?}", e)))?;

    // TLS-serialize the signer
    let signer_bytes = signer
        .tls_serialize_detached()
        .map_err(|e| err_js("crypto_failure", &format!("signer serialize: {:?}", e)))?;

    // Serialize provider storage
    let values = provider
        .storage()
        .values
        .read()
        .map_err(|e| err_js("crypto_failure", &format!("storage lock: {}", e)))?;
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
        .map_err(|e| err_js("serialization_failed", &format!("member_state serialize: {}", e)))?;

    let response = serde_json::json!({
        "key_package": B64.encode(&kp_bytes),
        "member_state": member_state_json,
    });

    to_js(&response).map_err(|e| err_js("serialization_failed", &format!("{:?}", e)))
}

// ============================================================================
// API 6: add_member(group_state, key_package_b64) → Alice adds Bob to the group
// Returns: { welcome: base64, ratchet_tree: base64, new_group_state: json_string }
// ============================================================================

#[wasm_bindgen]
pub fn add_member(group_state: &str, key_package_b64: &str) -> Result<JsValue, JsValue> {
    if group_state.is_empty() || key_package_b64.is_empty() {
        return Err(err_js(
            "invalid_input",
            "group_state and key_package_b64 required",
        ));
    }

    // Restore Alice's group
    let (mut group, signer, provider) = deserialize_group_state(group_state)
        .map_err(|e| err_js("invalid_input", &format!("state deserialize: {}", e)))?;

    // Decode and TLS-deserialize the KeyPackage
    let kp_bytes = B64
        .decode(key_package_b64)
        .map_err(|e| err_js("invalid_input", &format!("key_package b64 decode: {}", e)))?;

    use openmls::prelude::KeyPackageIn;
    let key_package_in = KeyPackageIn::tls_deserialize(&mut kp_bytes.as_slice())
        .map_err(|e| err_js("invalid_input", &format!("key_package tls_deserialize: {:?}", e)))?;

    // Validate the KeyPackage
    let key_package = key_package_in
        .validate(provider.crypto(), ProtocolVersion::Mls10)
        .map_err(|e| err_js("invalid_input", &format!("key_package validate: {:?}", e)))?;

    // Add member — returns (commit_msg, welcome, _group_info)
    let (_commit_msg, welcome, _group_info) = group
        .add_members(&provider, &signer, &[key_package])
        .map_err(|e| err_js("crypto_failure", &format!("add_members: {:?}", e)))?;

    // Merge commit to advance Alice's epoch
    group
        .merge_pending_commit(&provider)
        .map_err(|e| err_js("crypto_failure", &format!("merge_pending_commit: {:?}", e)))?;

    // TLS-serialize the Welcome
    use openmls::prelude::tls_codec::Serialize as TlsSerialize;
    let welcome_bytes = welcome
        .tls_serialize_detached()
        .map_err(|e| err_js("crypto_failure", &format!("welcome serialize: {:?}", e)))?;

    // Export ratchet tree — export_ratchet_tree() returns RatchetTreeIn
    let ratchet_tree = group.export_ratchet_tree();
    let ratchet_tree_bytes = ratchet_tree
        .tls_serialize_detached()
        .map_err(|e| err_js("crypto_failure", &format!("ratchet_tree serialize: {:?}", e)))?;

    // Serialize Alice's new group state
    let gid = group.group_id().clone();
    let new_group_state = serialize_group_state(&provider, &signer, &gid)
        .map_err(|e| err_js("serialization_failed", &e))?;

    let response = serde_json::json!({
        "welcome": B64.encode(&welcome_bytes),
        "ratchet_tree": B64.encode(&ratchet_tree_bytes),
        "new_group_state": new_group_state,
    });

    to_js(&response).map_err(|e| err_js("serialization_failed", &format!("{:?}", e)))
}

// ============================================================================
// API 7: join_group(welcome_b64, ratchet_tree_b64, member_state) → Bob joins
// Returns: { group_state: json_string }
// ============================================================================

#[wasm_bindgen]
pub fn join_group(
    welcome_b64: &str,
    ratchet_tree_b64: &str,
    member_state: &str,
) -> Result<JsValue, JsValue> {
    if welcome_b64.is_empty() || member_state.is_empty() {
        return Err(err_js(
            "invalid_input",
            "welcome_b64 and member_state required",
        ));
    }

    // Parse member_state
    let ms: MemberState = serde_json::from_str(member_state)
        .map_err(|e| err_js("invalid_input", &format!("member_state parse: {}", e)))?;

    // Rebuild Bob's provider with his stored key material
    let provider = OpenMlsRustCrypto::default();
    {
        let mut map: HashMap<Vec<u8>, Vec<u8>> = HashMap::new();
        for (k_b64, v_b64) in &ms.storage {
            let k = B64
                .decode(k_b64)
                .map_err(|e| err_js("invalid_input", &format!("storage key b64: {}", e)))?;
            let v = B64
                .decode(v_b64)
                .map_err(|e| err_js("invalid_input", &format!("storage val b64: {}", e)))?;
            map.insert(k, v);
        }
        let mut values = provider
            .storage()
            .values
            .write()
            .map_err(|e| err_js("crypto_failure", &format!("storage lock: {}", e)))?;
        *values = map;
    }

    // Deserialize Bob's signer
    let signer_bytes = B64
        .decode(&ms.signer_bytes)
        .map_err(|e| err_js("invalid_input", &format!("signer b64 decode: {}", e)))?;
    let signer = SignatureKeyPair::tls_deserialize(&mut signer_bytes.as_slice())
        .map_err(|e| err_js("invalid_input", &format!("signer deserialize: {:?}", e)))?;

    // TLS-deserialize the Welcome from the raw bytes
    let welcome_bytes = B64
        .decode(welcome_b64)
        .map_err(|e| err_js("invalid_input", &format!("welcome b64 decode: {}", e)))?;

    use openmls::prelude::MlsMessageBodyIn;
    let welcome_msg = MlsMessageIn::tls_deserialize(&mut welcome_bytes.as_slice())
        .map_err(|e| err_js("invalid_input", &format!("welcome tls_deserialize: {:?}", e)))?;
    let welcome = match welcome_msg.extract() {
        MlsMessageBodyIn::Welcome(w) => w,
        _ => {
            return Err(err_js(
                "invalid_input",
                "expected Welcome message, got something else",
            ))
        }
    };

    // TLS-deserialize the ratchet tree (if provided)
    let ratchet_tree = if ratchet_tree_b64.is_empty() {
        None
    } else {
        use openmls::prelude::RatchetTreeIn;
        let rt_bytes = B64
            .decode(ratchet_tree_b64)
            .map_err(|e| err_js("invalid_input", &format!("ratchet_tree b64 decode: {}", e)))?;
        let rt = RatchetTreeIn::tls_deserialize(&mut rt_bytes.as_slice())
            .map_err(|e| err_js("invalid_input", &format!("ratchet_tree deserialize: {:?}", e)))?;
        Some(rt)
    };

    // Bob joins via StagedWelcome
    let staged_welcome = StagedWelcome::new_from_welcome(
        &provider,
        &MlsGroupJoinConfig::default(),
        welcome,
        ratchet_tree,
    )
    .map_err(|e| err_js("crypto_failure", &format!("StagedWelcome::new_from_welcome: {:?}", e)))?;

    let group = staged_welcome
        .into_group(&provider)
        .map_err(|e| err_js("crypto_failure", &format!("staged_welcome.into_group: {:?}", e)))?;

    // Serialize Bob's group state
    let gid = group.group_id().clone();
    let group_state = serialize_group_state(&provider, &signer, &gid)
        .map_err(|e| err_js("serialization_failed", &e))?;

    let response = serde_json::json!({
        "group_state": group_state,
    });

    to_js(&response).map_err(|e| err_js("serialization_failed", &format!("{:?}", e)))
}
