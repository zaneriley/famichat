#![forbid(unsafe_code)]

use openmls::prelude::{
    tls_codec::Deserialize as _, tls_codec::Serialize as _, BasicCredential, Ciphersuite,
    CreateMessageError, CredentialWithKey, GroupId, KeyPackage, MlsGroup, MlsGroupCreateConfig,
    MlsGroupJoinConfig, MlsGroupStateError, MlsMessageBodyIn, MlsMessageIn, OpenMlsProvider as _,
    ProcessedMessageContent, StagedWelcome,
};
use openmls_basic_credential::SignatureKeyPair;
use openmls_rust_crypto::OpenMlsRustCrypto;
use rustler::{Encoder, Env, Term};
use std::collections::HashMap;
use std::sync::{
    atomic::{AtomicU64, Ordering},
    Mutex, OnceLock,
};

pub type Payload = HashMap<String, String>;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ErrorCode {
    InvalidInput,
    UnauthorizedOperation,
    StaleEpoch,
    PendingProposals,
    CommitRejected,
    StorageInconsistent,
    CryptoFailure,
    UnsupportedCapability,
}

impl ErrorCode {
    #[must_use]
    pub fn as_str(self) -> &'static str {
        match self {
            Self::InvalidInput => "invalid_input",
            Self::UnauthorizedOperation => "unauthorized_operation",
            Self::StaleEpoch => "stale_epoch",
            Self::PendingProposals => "pending_proposals",
            Self::CommitRejected => "commit_rejected",
            Self::StorageInconsistent => "storage_inconsistent",
            Self::CryptoFailure => "crypto_failure",
            Self::UnsupportedCapability => "unsupported_capability",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MlsError {
    pub code: ErrorCode,
    pub details: Payload,
}

pub type MlsResult = Result<Payload, MlsError>;

#[derive(Debug, Clone, PartialEq, Eq)]
struct CreateGroupParams {
    group_id: String,
    ciphersuite: String,
}

struct GroupSession {
    sender: MemberSession,
    recipient: MemberSession,
    decrypted_by_message_id: HashMap<String, CachedMessage>,
}

struct MemberSession {
    provider: OpenMlsRustCrypto,
    signer: SignatureKeyPair,
    group: MlsGroup,
}

struct CachedMessage {
    ciphertext: String,
    plaintext: String,
}

const DEFAULT_CIPHERSUITE: Ciphersuite = Ciphersuite::MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519;
const SNAPSHOT_SENDER_STORAGE_KEY: &str = "session_sender_storage";
const SNAPSHOT_RECIPIENT_STORAGE_KEY: &str = "session_recipient_storage";
const SNAPSHOT_SENDER_SIGNER_KEY: &str = "session_sender_signer";
const SNAPSHOT_RECIPIENT_SIGNER_KEY: &str = "session_recipient_signer";
const SNAPSHOT_CACHE_KEY: &str = "session_cache";
const MAX_DECRYPT_CACHE_ENTRIES: usize = 256;

static GROUP_SESSIONS: OnceLock<Mutex<HashMap<String, GroupSession>>> = OnceLock::new();
static KEY_PACKAGE_COUNTER: AtomicU64 = AtomicU64::new(1);

fn group_sessions() -> &'static Mutex<HashMap<String, GroupSession>> {
    GROUP_SESSIONS.get_or_init(|| Mutex::new(HashMap::new()))
}

impl MlsError {
    #[must_use]
    pub fn invalid_input(details: Payload) -> Self {
        Self {
            code: ErrorCode::InvalidInput,
            details,
        }
    }

    #[must_use]
    pub fn with_code(code: ErrorCode, operation: &str, reason: &str) -> Self {
        let mut details = Payload::new();
        details.insert("operation".to_owned(), operation.to_owned());
        details.insert("reason".to_owned(), reason.to_owned());

        Self { code, details }
    }
}

pub fn nif_version() -> MlsResult {
    let mut payload = Payload::new();
    payload.insert("crate".to_owned(), env!("CARGO_PKG_NAME").to_owned());
    payload.insert("version".to_owned(), env!("CARGO_PKG_VERSION").to_owned());
    payload.insert("status".to_owned(), "wired_contract".to_owned());
    Ok(payload)
}

pub fn nif_health() -> MlsResult {
    let mut payload = Payload::new();
    match validate_openmls_runtime() {
        Ok(()) => {
            payload.insert("status".to_owned(), "ok".to_owned());
            payload.insert("reason".to_owned(), "openmls_ready".to_owned());
        }
        Err(reason) => {
            payload.insert("status".to_owned(), "degraded".to_owned());
            payload.insert("reason".to_owned(), reason);
        }
    }

    Ok(payload)
}

pub fn create_key_package(params: &Payload) -> MlsResult {
    let operation = "create_key_package";
    let mut details = Payload::new();
    let client_id = required_non_empty(params, "client_id", &mut details);

    match client_id {
        Some(client_id) => {
            let mut payload = Payload::new();
            payload.insert("client_id".to_owned(), client_id.clone());
            payload.insert(
                "key_package_ref".to_owned(),
                next_key_package_ref(&client_id),
            );
            payload.insert("status".to_owned(), "created".to_owned());
            Ok(payload)
        }
        None => {
            details.insert("operation".to_owned(), operation.to_owned());
            Err(MlsError::invalid_input(details))
        }
    }
}

pub fn create_group(params: &Payload) -> MlsResult {
    let parsed = CreateGroupParams::try_from(params)?;
    let ciphersuite = parse_ciphersuite(&parsed.ciphersuite).ok_or_else(|| {
        let mut details = Payload::new();
        details.insert("operation".to_owned(), "create_group".to_owned());
        details.insert(
            "ciphersuite".to_owned(),
            "unsupported ciphersuite".to_owned(),
        );
        MlsError::invalid_input(details)
    })?;

    let session =
        match restore_group_session_from_snapshot(&parsed.group_id, params, "create_group")? {
            Some(session) => session,
            None => create_group_session(&parsed.group_id, ciphersuite)?,
        };

    let session_snapshot = build_group_session_snapshot(&session, "create_group")?;
    let epoch = session.sender.group.epoch().as_u64().to_string();

    let mut guard = group_sessions().lock().map_err(|_| {
        MlsError::with_code(
            ErrorCode::StorageInconsistent,
            "create_group",
            "lock_poisoned",
        )
    })?;
    guard.insert(parsed.group_id.clone(), session);
    drop(guard);

    let mut payload = Payload::new();
    payload.insert("group_id".to_owned(), parsed.group_id.clone());
    payload.insert("ciphersuite".to_owned(), parsed.ciphersuite);
    payload.insert("epoch".to_owned(), epoch);
    payload.insert(
        "group_state_ref".to_owned(),
        format!("state:{}", parsed.group_id),
    );
    payload.insert("status".to_owned(), "created".to_owned());
    payload.extend(session_snapshot);
    Ok(payload)
}

pub fn join_from_welcome(params: &Payload) -> MlsResult {
    let operation = "join_from_welcome";

    let token = non_empty(params, "rejoin_token").or_else(|| non_empty(params, "welcome"));

    match token {
        Some(token) => {
            let mut payload = Payload::new();
            payload.insert("group_state_ref".to_owned(), format!("state:{}", token));
            payload.insert("audit_id".to_owned(), format!("audit:{}", token));
            payload.insert("status".to_owned(), "joined".to_owned());
            Ok(payload)
        }
        None => {
            let mut details = Payload::new();
            details.insert(
                "welcome".to_owned(),
                "welcome or rejoin_token is required".to_owned(),
            );
            details.insert("operation".to_owned(), operation.to_owned());
            Err(MlsError::invalid_input(details))
        }
    }
}

pub fn process_incoming(params: &Payload) -> MlsResult {
    let operation = "process_incoming";
    let mut details = Payload::new();

    if parse_bool(params, "pending_commit") == Some(true)
        && matches!(non_empty(params, "incoming_type"), Some(value) if value == "welcome")
    {
        return Err(MlsError::with_code(
            ErrorCode::CommitRejected,
            operation,
            "welcome_before_commit_merge",
        ));
    }

    let group_id = required_non_empty(params, "group_id", &mut details);
    let ciphertext = non_empty(params, "ciphertext").or_else(|| non_empty(params, "message"));
    let message_id = non_empty(params, "message_id");

    let missing_ciphertext = ciphertext.is_none();

    match (group_id, ciphertext) {
        (Some(group_id), Some(ciphertext)) => {
            let mut guard = group_sessions().lock().map_err(|_| {
                MlsError::with_code(ErrorCode::StorageInconsistent, operation, "lock_poisoned")
            })?;

            let should_restore =
                has_complete_session_snapshot(params) || !guard.contains_key(&group_id);

            if should_restore {
                if let Some(restored) =
                    restore_group_session_from_snapshot(&group_id, params, operation)?
                {
                    guard.insert(group_id.clone(), restored);
                }
            }

            let session = guard.get_mut(&group_id).ok_or_else(|| {
                let mut err_details = Payload::new();
                err_details.insert("operation".to_owned(), operation.to_owned());
                err_details.insert("reason".to_owned(), "missing_group_state".to_owned());
                err_details.insert("group_id".to_owned(), group_id.clone());
                MlsError {
                    code: ErrorCode::StorageInconsistent,
                    details: err_details,
                }
            })?;

            if let Some(cache_key) = message_id.as_ref() {
                if let Some(cached_message) = session.decrypted_by_message_id.get(cache_key) {
                    if cached_message.ciphertext == ciphertext {
                        let mut payload = Payload::new();
                        payload.insert("group_id".to_owned(), group_id);
                        payload.insert("plaintext".to_owned(), cached_message.plaintext.clone());
                        payload.insert(
                            "epoch".to_owned(),
                            session.recipient.group.epoch().as_u64().to_string(),
                        );
                        return Ok(payload);
                    } else {
                        return Err(MlsError::with_code(
                            ErrorCode::StorageInconsistent,
                            operation,
                            "message_id_ciphertext_mismatch",
                        ));
                    }
                }
            }

            let message_bytes = decode_hex(&ciphertext).map_err(|reason| {
                let mut err_details = Payload::new();
                err_details.insert("operation".to_owned(), operation.to_owned());
                err_details.insert("reason".to_owned(), reason.to_owned());
                MlsError {
                    code: ErrorCode::InvalidInput,
                    details: err_details,
                }
            })?;

            let mut slice = message_bytes.as_slice();
            let message_in = MlsMessageIn::tls_deserialize(&mut slice).map_err(|_| {
                MlsError::with_code(ErrorCode::InvalidInput, operation, "malformed_ciphertext")
            })?;

            let protocol_message = message_in.try_into_protocol_message().map_err(|_| {
                MlsError::with_code(
                    ErrorCode::InvalidInput,
                    operation,
                    "unsupported_message_type",
                )
            })?;

            let processed = session
                .recipient
                .group
                .process_message(&session.recipient.provider, protocol_message)
                .map_err(|_| {
                    MlsError::with_code(
                        ErrorCode::CommitRejected,
                        operation,
                        "message_processing_failed",
                    )
                })?;

            let plaintext_bytes = match processed.into_content() {
                ProcessedMessageContent::ApplicationMessage(message) => message.into_bytes(),
                _ => {
                    return Err(MlsError::with_code(
                        ErrorCode::CommitRejected,
                        operation,
                        "non_application_message",
                    ));
                }
            };

            let plaintext = String::from_utf8(plaintext_bytes)
                .unwrap_or_else(|value| String::from_utf8_lossy(value.as_bytes()).into_owned());
            let cache_plaintext = plaintext.clone();
            let epoch = session.recipient.group.epoch().as_u64().to_string();

            let mut payload = Payload::new();
            payload.insert("group_id".to_owned(), group_id);
            payload.insert("plaintext".to_owned(), plaintext);
            payload.insert("epoch".to_owned(), epoch);

            if let Some(cache_key) = message_id {
                cache_decrypted_message(
                    &mut session.decrypted_by_message_id,
                    cache_key,
                    CachedMessage {
                        ciphertext: ciphertext.clone(),
                        plaintext: cache_plaintext,
                    },
                );
            }

            payload.extend(build_group_session_snapshot(session, operation)?);

            Ok(payload)
        }
        _ => {
            if missing_ciphertext {
                details.insert("ciphertext".to_owned(), "is required".to_owned());
            }
            details.insert("operation".to_owned(), operation.to_owned());
            Err(MlsError::invalid_input(details))
        }
    }
}

pub fn commit_to_pending(params: &Payload) -> MlsResult {
    let operation = "commit_to_pending";
    with_required_group(operation, params, |group_id| {
        let mut payload = Payload::new();
        payload.insert("group_id".to_owned(), group_id);
        payload.insert("pending_commit".to_owned(), "true".to_owned());
        payload.insert("epoch".to_owned(), next_epoch(params));
        Ok(payload)
    })
}

pub fn mls_commit(params: &Payload) -> MlsResult {
    lifecycle_ok("mls_commit", params, |payload| {
        payload.insert("pending_commit".to_owned(), "true".to_owned());
    })
}

pub fn mls_update(params: &Payload) -> MlsResult {
    lifecycle_ok("mls_update", params, |payload| {
        payload.insert("staged".to_owned(), "true".to_owned());
    })
}

pub fn mls_add(params: &Payload) -> MlsResult {
    lifecycle_ok("mls_add", params, |payload| {
        payload.insert("staged".to_owned(), "true".to_owned());
    })
}

pub fn mls_remove(params: &Payload) -> MlsResult {
    lifecycle_ok("mls_remove", params, |payload| {
        payload.insert("staged".to_owned(), "true".to_owned());
    })
}

pub fn merge_staged_commit(params: &Payload) -> MlsResult {
    let operation = "merge_staged_commit";

    if parse_bool(params, "staged_commit_validated") != Some(true) {
        return Err(MlsError::with_code(
            ErrorCode::CommitRejected,
            operation,
            "staged_commit_not_validated",
        ));
    }

    with_required_group(operation, params, |group_id| {
        let mut payload = Payload::new();
        payload.insert("group_id".to_owned(), group_id);
        payload.insert("merged".to_owned(), "true".to_owned());
        payload.insert("pending_commit".to_owned(), "false".to_owned());
        payload.insert("epoch".to_owned(), next_epoch(params));
        Ok(payload)
    })
}

pub fn clear_pending_commit(params: &Payload) -> MlsResult {
    let operation = "clear_pending_commit";
    with_required_group(operation, params, |group_id| {
        let mut payload = Payload::new();
        payload.insert("group_id".to_owned(), group_id);
        payload.insert("pending_commit".to_owned(), "false".to_owned());
        payload.insert("status".to_owned(), "cleared".to_owned());
        Ok(payload)
    })
}

pub fn create_application_message(params: &Payload) -> MlsResult {
    let operation = "create_application_message";

    if parse_bool(params, "pending_proposals") == Some(true) {
        return Err(MlsError::with_code(
            ErrorCode::PendingProposals,
            operation,
            "pending_proposals",
        ));
    }

    with_required_group(operation, params, |group_id| {
        let body = params.get("body").cloned().unwrap_or_default();

        let mut guard = group_sessions().lock().map_err(|_| {
            MlsError::with_code(ErrorCode::StorageInconsistent, operation, "lock_poisoned")
        })?;

        if has_complete_session_snapshot(params) {
            if let Some(restored) =
                restore_group_session_from_snapshot(&group_id, params, operation)?
            {
                guard.insert(group_id.clone(), restored);
            }
        } else if !guard.contains_key(&group_id) {
            if let Some(restored) =
                restore_group_session_from_snapshot(&group_id, params, operation)?
            {
                guard.insert(group_id.clone(), restored);
            } else {
                let session = create_group_session(&group_id, DEFAULT_CIPHERSUITE)?;
                guard.insert(group_id.clone(), session);
            }
        }

        let session = guard.get_mut(&group_id).ok_or_else(|| {
            MlsError::with_code(
                ErrorCode::StorageInconsistent,
                operation,
                "missing_group_state",
            )
        })?;

        let message_out = session
            .sender
            .group
            .create_message(
                &session.sender.provider,
                &session.sender.signer,
                body.as_bytes(),
            )
            .map_err(|error| map_create_message_error(operation, error))?;

        let serialized = message_out.tls_serialize_detached().map_err(|_| {
            MlsError::with_code(ErrorCode::CryptoFailure, operation, "serialize_failed")
        })?;
        let ciphertext = encode_hex(&serialized);
        let epoch = session.sender.group.epoch().as_u64().to_string();

        let mut payload = Payload::new();
        payload.insert("group_id".to_owned(), group_id);
        payload.insert("ciphertext".to_owned(), ciphertext);
        payload.insert("epoch".to_owned(), epoch);
        payload.insert("status".to_owned(), "encrypted".to_owned());
        payload.extend(build_group_session_snapshot(session, operation)?);
        Ok(payload)
    })
}

pub fn export_group_info(params: &Payload) -> MlsResult {
    let operation = "export_group_info";
    with_required_group(operation, params, |group_id| {
        let mut guard = group_sessions().lock().map_err(|_| {
            MlsError::with_code(ErrorCode::StorageInconsistent, operation, "lock_poisoned")
        })?;

        if !guard.contains_key(&group_id) {
            if let Some(restored) =
                restore_group_session_from_snapshot(&group_id, params, operation)?
            {
                guard.insert(group_id.clone(), restored);
            }
        }

        let mut payload = Payload::new();
        payload.insert("group_id".to_owned(), group_id.clone());
        payload.insert(
            "group_info_ref".to_owned(),
            format!("group-info:{}", group_id),
        );

        if let Some(session) = guard.get(&group_id) {
            payload.extend(build_group_session_snapshot(session, operation)?);
        }

        Ok(payload)
    })
}

pub fn export_ratchet_tree(params: &Payload) -> MlsResult {
    let operation = "export_ratchet_tree";
    with_required_group(operation, params, |group_id| {
        let mut payload = Payload::new();
        payload.insert("group_id".to_owned(), group_id.clone());
        payload.insert(
            "ratchet_tree_ref".to_owned(),
            format!("ratchet-tree:{}", group_id),
        );
        Ok(payload)
    })
}

fn lifecycle_ok<F>(operation: &str, params: &Payload, decorate: F) -> MlsResult
where
    F: Fn(&mut Payload),
{
    with_required_group(operation, params, |group_id| {
        let mut payload = Payload::new();
        payload.insert("group_id".to_owned(), group_id);
        payload.insert("operation".to_owned(), operation.to_owned());
        payload.insert("status".to_owned(), "ok".to_owned());
        payload.insert("epoch".to_owned(), next_epoch(params));
        decorate(&mut payload);
        Ok(payload)
    })
}

fn with_required_group<F>(operation: &str, params: &Payload, on_group: F) -> MlsResult
where
    F: Fn(String) -> MlsResult,
{
    let mut details = Payload::new();
    let group_id = required_non_empty(params, "group_id", &mut details);

    match group_id {
        Some(group_id) => on_group(group_id),
        None => {
            details.insert("operation".to_owned(), operation.to_owned());
            Err(MlsError::invalid_input(details))
        }
    }
}

fn required_non_empty(params: &Payload, key: &str, details: &mut Payload) -> Option<String> {
    match params.get(key) {
        Some(value) if !value.trim().is_empty() => Some(value.to_owned()),
        Some(_) => {
            details.insert(key.to_owned(), "must not be empty".to_owned());
            None
        }
        None => {
            details.insert(key.to_owned(), "is required".to_owned());
            None
        }
    }
}

fn non_empty(params: &Payload, key: &str) -> Option<String> {
    params
        .get(key)
        .filter(|value| !value.trim().is_empty())
        .cloned()
}

fn has_complete_session_snapshot(params: &Payload) -> bool {
    non_empty(params, SNAPSHOT_SENDER_STORAGE_KEY).is_some()
        && non_empty(params, SNAPSHOT_RECIPIENT_STORAGE_KEY).is_some()
        && non_empty(params, SNAPSHOT_SENDER_SIGNER_KEY).is_some()
        && non_empty(params, SNAPSHOT_RECIPIENT_SIGNER_KEY).is_some()
}

fn parse_bool(params: &Payload, key: &str) -> Option<bool> {
    non_empty(params, key).and_then(|value| match value.as_str() {
        "true" | "1" => Some(true),
        "false" | "0" => Some(false),
        _ => None,
    })
}

fn next_key_package_ref(client_id: &str) -> String {
    let counter = KEY_PACKAGE_COUNTER.fetch_add(1, Ordering::Relaxed);
    format!("kp:{}:{}", client_id, counter)
}

fn next_epoch(params: &Payload) -> String {
    params
        .get("epoch")
        .and_then(|value| value.parse::<u64>().ok())
        .map(|value| value + 1)
        .unwrap_or(2)
        .to_string()
}

fn validate_openmls_runtime() -> Result<(), String> {
    let provider = OpenMlsRustCrypto::default();
    let signer = SignatureKeyPair::new(DEFAULT_CIPHERSUITE.signature_algorithm())
        .map_err(|_| "openmls_signer_init_failed".to_owned())?;
    signer
        .store(provider.storage())
        .map_err(|_| "openmls_signer_store_failed".to_owned())
}

fn parse_ciphersuite(label: &str) -> Option<Ciphersuite> {
    match label {
        "MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519" => {
            Some(Ciphersuite::MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519)
        }
        "MLS_128_DHKEMP256_AES128GCM_SHA256_P256" => {
            Some(Ciphersuite::MLS_128_DHKEMP256_AES128GCM_SHA256_P256)
        }
        "MLS_128_DHKEMX25519_CHACHA20POLY1305_SHA256_Ed25519" => {
            Some(Ciphersuite::MLS_128_DHKEMX25519_CHACHA20POLY1305_SHA256_Ed25519)
        }
        _ => None,
    }
}

fn create_group_session(
    group_id: &str,
    ciphersuite: Ciphersuite,
) -> Result<GroupSession, MlsError> {
    let operation = "create_group";
    let sender_provider = OpenMlsRustCrypto::default();
    let (sender_credential, sender_signer) = create_credential_with_signer(
        &sender_provider,
        ciphersuite,
        &format!("famichat:{}:sender", group_id),
        operation,
    )?;

    let config = MlsGroupCreateConfig::builder()
        .ciphersuite(ciphersuite)
        .use_ratchet_tree_extension(true)
        .build();

    let mut sender_group = MlsGroup::new_with_group_id(
        &sender_provider,
        &sender_signer,
        &config,
        GroupId::from_slice(group_id.as_bytes()),
        sender_credential,
    )
    .map_err(|_| {
        MlsError::with_code(
            ErrorCode::CryptoFailure,
            "create_group",
            "group_init_failed",
        )
    })?;

    let recipient_provider = OpenMlsRustCrypto::default();
    let (recipient_credential, recipient_signer) = create_credential_with_signer(
        &recipient_provider,
        ciphersuite,
        &format!("famichat:{}:recipient", group_id),
        operation,
    )?;

    let recipient_kpb = KeyPackage::builder()
        .build(
            ciphersuite,
            &recipient_provider,
            &recipient_signer,
            recipient_credential,
        )
        .map_err(|_| {
            MlsError::with_code(
                ErrorCode::CryptoFailure,
                operation,
                "key_package_generation_failed",
            )
        })?;

    let (_commit_message, welcome_message, _group_info) = sender_group
        .add_members(
            &sender_provider,
            &sender_signer,
            core::slice::from_ref(recipient_kpb.key_package()),
        )
        .map_err(|_| {
            MlsError::with_code(ErrorCode::CommitRejected, operation, "member_add_failed")
        })?;

    sender_group
        .merge_pending_commit(&sender_provider)
        .map_err(|_| {
            MlsError::with_code(
                ErrorCode::CommitRejected,
                operation,
                "merge_pending_commit_failed",
            )
        })?;

    let welcome_bytes = welcome_message.tls_serialize_detached().map_err(|_| {
        MlsError::with_code(
            ErrorCode::CryptoFailure,
            operation,
            "welcome_serialize_failed",
        )
    })?;
    let mut welcome_slice = welcome_bytes.as_slice();
    let welcome_in = MlsMessageIn::tls_deserialize(&mut welcome_slice).map_err(|_| {
        MlsError::with_code(
            ErrorCode::InvalidInput,
            operation,
            "welcome_deserialize_failed",
        )
    })?;
    let welcome = match welcome_in.extract() {
        MlsMessageBodyIn::Welcome(welcome) => welcome,
        _ => {
            return Err(MlsError::with_code(
                ErrorCode::InvalidInput,
                operation,
                "welcome_message_invalid",
            ))
        }
    };

    let recipient_group = StagedWelcome::new_from_welcome(
        &recipient_provider,
        &MlsGroupJoinConfig::default(),
        welcome,
        Some(sender_group.export_ratchet_tree().into()),
    )
    .map_err(|_| {
        MlsError::with_code(
            ErrorCode::CryptoFailure,
            operation,
            "join_from_welcome_failed",
        )
    })?
    .into_group(&recipient_provider)
    .map_err(|_| {
        MlsError::with_code(ErrorCode::CryptoFailure, operation, "staged_welcome_failed")
    })?;

    Ok(GroupSession {
        sender: MemberSession {
            provider: sender_provider,
            signer: sender_signer,
            group: sender_group,
        },
        recipient: MemberSession {
            provider: recipient_provider,
            signer: recipient_signer,
            group: recipient_group,
        },
        decrypted_by_message_id: HashMap::new(),
    })
}

fn create_credential_with_signer(
    provider: &OpenMlsRustCrypto,
    ciphersuite: Ciphersuite,
    identity: &str,
    operation: &str,
) -> Result<(CredentialWithKey, SignatureKeyPair), MlsError> {
    let signer = SignatureKeyPair::new(ciphersuite.signature_algorithm()).map_err(|_| {
        MlsError::with_code(
            ErrorCode::CryptoFailure,
            operation,
            "signature_key_generation_failed",
        )
    })?;

    signer.store(provider.storage()).map_err(|_| {
        MlsError::with_code(
            ErrorCode::StorageInconsistent,
            operation,
            "signature_key_store_failed",
        )
    })?;

    let credential_with_key = CredentialWithKey {
        credential: BasicCredential::new(identity.as_bytes().to_vec()).into(),
        signature_key: signer.to_public_vec().into(),
    };

    Ok((credential_with_key, signer))
}

fn map_create_message_error(operation: &str, error: CreateMessageError) -> MlsError {
    match error {
        CreateMessageError::GroupStateError(MlsGroupStateError::PendingProposal) => {
            MlsError::with_code(ErrorCode::PendingProposals, operation, "pending_proposals")
        }
        CreateMessageError::GroupStateError(MlsGroupStateError::UseAfterEviction) => {
            MlsError::with_code(
                ErrorCode::UnauthorizedOperation,
                operation,
                "sender_not_member",
            )
        }
        _ => MlsError::with_code(
            ErrorCode::CryptoFailure,
            operation,
            "message_creation_failed",
        ),
    }
}

fn build_group_session_snapshot(
    session: &GroupSession,
    operation: &str,
) -> Result<Payload, MlsError> {
    let mut payload = Payload::new();

    payload.insert(
        SNAPSHOT_SENDER_STORAGE_KEY.to_owned(),
        serialize_storage_map(session.sender.provider.storage(), operation)?,
    );
    payload.insert(
        SNAPSHOT_RECIPIENT_STORAGE_KEY.to_owned(),
        serialize_storage_map(session.recipient.provider.storage(), operation)?,
    );
    payload.insert(
        SNAPSHOT_SENDER_SIGNER_KEY.to_owned(),
        serialize_signer(&session.sender.signer, operation)?,
    );
    payload.insert(
        SNAPSHOT_RECIPIENT_SIGNER_KEY.to_owned(),
        serialize_signer(&session.recipient.signer, operation)?,
    );
    payload.insert(
        SNAPSHOT_CACHE_KEY.to_owned(),
        serialize_message_cache(&session.decrypted_by_message_id),
    );

    Ok(payload)
}

fn restore_group_session_from_snapshot(
    group_id: &str,
    params: &Payload,
    operation: &str,
) -> Result<Option<GroupSession>, MlsError> {
    let sender_storage = non_empty(params, SNAPSHOT_SENDER_STORAGE_KEY);
    let recipient_storage = non_empty(params, SNAPSHOT_RECIPIENT_STORAGE_KEY);
    let sender_signer = non_empty(params, SNAPSHOT_SENDER_SIGNER_KEY);
    let recipient_signer = non_empty(params, SNAPSHOT_RECIPIENT_SIGNER_KEY);
    let cache = non_empty(params, SNAPSHOT_CACHE_KEY).unwrap_or_default();

    let any_snapshot_field_present = sender_storage.is_some()
        || recipient_storage.is_some()
        || sender_signer.is_some()
        || recipient_signer.is_some()
        || !cache.is_empty();

    if !any_snapshot_field_present {
        return Ok(None);
    }

    if sender_storage.is_none()
        || recipient_storage.is_none()
        || sender_signer.is_none()
        || recipient_signer.is_none()
    {
        return Err(MlsError::with_code(
            ErrorCode::InvalidInput,
            operation,
            "incomplete_session_snapshot",
        ));
    }

    let sender_storage = deserialize_storage_map(sender_storage.as_deref().unwrap(), operation)?;
    let recipient_storage =
        deserialize_storage_map(recipient_storage.as_deref().unwrap(), operation)?;
    let sender_signer = deserialize_signer(sender_signer.as_deref().unwrap(), operation)?;
    let recipient_signer = deserialize_signer(recipient_signer.as_deref().unwrap(), operation)?;
    let message_cache = deserialize_message_cache(&cache, operation)?;

    let sender_provider = OpenMlsRustCrypto::default();
    {
        let mut values = sender_provider.storage().values.write().map_err(|_| {
            MlsError::with_code(ErrorCode::StorageInconsistent, operation, "lock_poisoned")
        })?;
        *values = sender_storage;
    }

    sender_signer
        .store(sender_provider.storage())
        .map_err(|_| {
            MlsError::with_code(
                ErrorCode::StorageInconsistent,
                operation,
                "signature_key_store_failed",
            )
        })?;

    let sender_group_id = GroupId::from_slice(group_id.as_bytes());
    let sender_group = MlsGroup::load(sender_provider.storage(), &sender_group_id)
        .map_err(|_| {
            MlsError::with_code(
                ErrorCode::StorageInconsistent,
                operation,
                "group_load_failed",
            )
        })?
        .ok_or_else(|| {
            MlsError::with_code(
                ErrorCode::StorageInconsistent,
                operation,
                "missing_group_state",
            )
        })?;

    let recipient_provider = OpenMlsRustCrypto::default();
    {
        let mut values = recipient_provider.storage().values.write().map_err(|_| {
            MlsError::with_code(ErrorCode::StorageInconsistent, operation, "lock_poisoned")
        })?;
        *values = recipient_storage;
    }

    recipient_signer
        .store(recipient_provider.storage())
        .map_err(|_| {
            MlsError::with_code(
                ErrorCode::StorageInconsistent,
                operation,
                "signature_key_store_failed",
            )
        })?;

    let recipient_group_id = GroupId::from_slice(group_id.as_bytes());
    let recipient_group = MlsGroup::load(recipient_provider.storage(), &recipient_group_id)
        .map_err(|_| {
            MlsError::with_code(
                ErrorCode::StorageInconsistent,
                operation,
                "group_load_failed",
            )
        })?
        .ok_or_else(|| {
            MlsError::with_code(
                ErrorCode::StorageInconsistent,
                operation,
                "missing_group_state",
            )
        })?;

    Ok(Some(GroupSession {
        sender: MemberSession {
            provider: sender_provider,
            signer: sender_signer,
            group: sender_group,
        },
        recipient: MemberSession {
            provider: recipient_provider,
            signer: recipient_signer,
            group: recipient_group,
        },
        decrypted_by_message_id: message_cache,
    }))
}

fn serialize_storage_map(
    storage: &openmls_rust_crypto::MemoryStorage,
    operation: &str,
) -> Result<String, MlsError> {
    let values = storage.values.read().map_err(|_| {
        MlsError::with_code(ErrorCode::StorageInconsistent, operation, "lock_poisoned")
    })?;

    let mut entries: Vec<String> = values
        .iter()
        .map(|(key, value)| format!("{}:{}", encode_hex(key), encode_hex(value)))
        .collect();
    entries.sort_unstable();

    Ok(entries.join(","))
}

fn deserialize_storage_map(
    encoded: &str,
    operation: &str,
) -> Result<HashMap<Vec<u8>, Vec<u8>>, MlsError> {
    let mut values = HashMap::new();

    if encoded.is_empty() {
        return Ok(values);
    }

    for entry in encoded.split(',').filter(|entry| !entry.is_empty()) {
        let Some((encoded_key, encoded_value)) = entry.split_once(':') else {
            return Err(MlsError::with_code(
                ErrorCode::InvalidInput,
                operation,
                "invalid_storage_snapshot",
            ));
        };

        let key = decode_hex(encoded_key).map_err(|_| {
            MlsError::with_code(
                ErrorCode::InvalidInput,
                operation,
                "invalid_storage_snapshot",
            )
        })?;
        let value = decode_hex(encoded_value).map_err(|_| {
            MlsError::with_code(
                ErrorCode::InvalidInput,
                operation,
                "invalid_storage_snapshot",
            )
        })?;

        values.insert(key, value);
    }

    Ok(values)
}

fn serialize_signer(signer: &SignatureKeyPair, operation: &str) -> Result<String, MlsError> {
    let bytes = signer.tls_serialize_detached().map_err(|_| {
        MlsError::with_code(
            ErrorCode::CryptoFailure,
            operation,
            "signature_serialize_failed",
        )
    })?;

    Ok(encode_hex(&bytes))
}

fn deserialize_signer(encoded: &str, operation: &str) -> Result<SignatureKeyPair, MlsError> {
    let bytes = decode_hex(encoded).map_err(|_| {
        MlsError::with_code(
            ErrorCode::InvalidInput,
            operation,
            "invalid_signature_snapshot",
        )
    })?;
    let mut bytes_slice = bytes.as_slice();

    SignatureKeyPair::tls_deserialize(&mut bytes_slice).map_err(|_| {
        MlsError::with_code(
            ErrorCode::InvalidInput,
            operation,
            "invalid_signature_snapshot",
        )
    })
}

fn serialize_message_cache(cache: &HashMap<String, CachedMessage>) -> String {
    let mut entries: Vec<String> = cache
        .iter()
        .map(|(message_id, cached_message)| {
            format!(
                "{}:{}:{}",
                encode_hex(message_id.as_bytes()),
                encode_hex(cached_message.ciphertext.as_bytes()),
                encode_hex(cached_message.plaintext.as_bytes())
            )
        })
        .collect();
    entries.sort_unstable();

    entries.join(",")
}

fn deserialize_message_cache(
    encoded: &str,
    operation: &str,
) -> Result<HashMap<String, CachedMessage>, MlsError> {
    let mut cache = HashMap::new();

    if encoded.is_empty() {
        return Ok(cache);
    }

    for entry in encoded.split(',').filter(|entry| !entry.is_empty()) {
        if cache.len() >= MAX_DECRYPT_CACHE_ENTRIES {
            break;
        }

        let mut fields = entry.splitn(3, ':');
        let Some(message_id_hex) = fields.next() else {
            return Err(MlsError::with_code(
                ErrorCode::InvalidInput,
                operation,
                "invalid_session_cache",
            ));
        };
        let Some(ciphertext_hex) = fields.next() else {
            return Err(MlsError::with_code(
                ErrorCode::InvalidInput,
                operation,
                "invalid_session_cache",
            ));
        };
        let Some(plaintext_hex) = fields.next() else {
            return Err(MlsError::with_code(
                ErrorCode::InvalidInput,
                operation,
                "invalid_session_cache",
            ));
        };

        let message_id = String::from_utf8(decode_hex(message_id_hex).map_err(|_| {
            MlsError::with_code(ErrorCode::InvalidInput, operation, "invalid_session_cache")
        })?)
        .map_err(|_| {
            MlsError::with_code(ErrorCode::InvalidInput, operation, "invalid_session_cache")
        })?;
        let ciphertext = String::from_utf8(decode_hex(ciphertext_hex).map_err(|_| {
            MlsError::with_code(ErrorCode::InvalidInput, operation, "invalid_session_cache")
        })?)
        .map_err(|_| {
            MlsError::with_code(ErrorCode::InvalidInput, operation, "invalid_session_cache")
        })?;
        let plaintext = String::from_utf8(decode_hex(plaintext_hex).map_err(|_| {
            MlsError::with_code(ErrorCode::InvalidInput, operation, "invalid_session_cache")
        })?)
        .map_err(|_| {
            MlsError::with_code(ErrorCode::InvalidInput, operation, "invalid_session_cache")
        })?;

        cache.insert(
            message_id,
            CachedMessage {
                ciphertext,
                plaintext,
            },
        );
    }

    Ok(cache)
}

fn cache_decrypted_message(
    cache: &mut HashMap<String, CachedMessage>,
    message_id: String,
    cached_message: CachedMessage,
) {
    let exists = cache.contains_key(&message_id);

    if !exists && cache.len() >= MAX_DECRYPT_CACHE_ENTRIES {
        if let Some(evict_key) = cache.keys().next().cloned() {
            cache.remove(&evict_key);
        }
    }

    cache.insert(message_id, cached_message);
}

fn encode_hex(bytes: &[u8]) -> String {
    const HEX: &[u8; 16] = b"0123456789abcdef";

    let mut encoded = String::with_capacity(bytes.len() * 2);
    for &byte in bytes {
        encoded.push(HEX[(byte >> 4) as usize] as char);
        encoded.push(HEX[(byte & 0x0f) as usize] as char);
    }

    encoded
}

fn decode_hex(value: &str) -> Result<Vec<u8>, &'static str> {
    if !value.len().is_multiple_of(2) {
        return Err("invalid_ciphertext_encoding");
    }

    let mut decoded = Vec::with_capacity(value.len() / 2);
    let bytes = value.as_bytes();
    let mut index = 0;

    while index < bytes.len() {
        let high = hex_nibble(bytes[index]).ok_or("invalid_ciphertext_encoding")?;
        let low = hex_nibble(bytes[index + 1]).ok_or("invalid_ciphertext_encoding")?;
        decoded.push((high << 4) | low);
        index += 2;
    }

    Ok(decoded)
}

fn hex_nibble(byte: u8) -> Option<u8> {
    match byte {
        b'0'..=b'9' => Some(byte - b'0'),
        b'a'..=b'f' => Some(byte - b'a' + 10),
        b'A'..=b'F' => Some(byte - b'A' + 10),
        _ => None,
    }
}

impl TryFrom<&Payload> for CreateGroupParams {
    type Error = MlsError;

    fn try_from(params: &Payload) -> Result<Self, Self::Error> {
        let operation = "create_group";
        let mut details = Payload::new();
        let group_id = required_non_empty(params, "group_id", &mut details);
        let ciphersuite = required_non_empty(params, "ciphersuite", &mut details);

        if let (Some(group_id), Some(ciphersuite)) = (group_id, ciphersuite) {
            return Ok(Self {
                group_id,
                ciphersuite,
            });
        }

        details.insert("operation".to_owned(), operation.to_owned());
        Err(MlsError::invalid_input(details))
    }
}

mod atoms {
    rustler::atoms! {
        ok,
        error,
        invalid_input,
        unauthorized_operation,
        stale_epoch,
        pending_proposals,
        commit_rejected,
        storage_inconsistent,
        crypto_failure,
        unsupported_capability
    }
}

fn encode_result<'a>(env: Env<'a>, result: MlsResult) -> Term<'a> {
    match result {
        Ok(payload) => (atoms::ok(), payload).encode(env),
        Err(error) => (atoms::error(), error_atom(error.code), error.details).encode(env),
    }
}

fn error_atom(code: ErrorCode) -> rustler::types::atom::Atom {
    match code {
        ErrorCode::InvalidInput => atoms::invalid_input(),
        ErrorCode::UnauthorizedOperation => atoms::unauthorized_operation(),
        ErrorCode::StaleEpoch => atoms::stale_epoch(),
        ErrorCode::PendingProposals => atoms::pending_proposals(),
        ErrorCode::CommitRejected => atoms::commit_rejected(),
        ErrorCode::StorageInconsistent => atoms::storage_inconsistent(),
        ErrorCode::CryptoFailure => atoms::crypto_failure(),
        ErrorCode::UnsupportedCapability => atoms::unsupported_capability(),
    }
}

fn payload_from_nif(params: HashMap<String, String>) -> Payload {
    params.into_iter().collect()
}

#[rustler::nif(name = "nif_version")]
fn nif_version_nif<'a>(env: Env<'a>) -> Term<'a> {
    encode_result(env, nif_version())
}

#[rustler::nif(name = "nif_health")]
fn nif_health_nif<'a>(env: Env<'a>) -> Term<'a> {
    encode_result(env, nif_health())
}

#[rustler::nif(name = "create_key_package")]
fn create_key_package_nif<'a>(env: Env<'a>, params: HashMap<String, String>) -> Term<'a> {
    let payload = payload_from_nif(params);
    encode_result(env, create_key_package(&payload))
}

#[rustler::nif(name = "create_group")]
fn create_group_nif<'a>(env: Env<'a>, params: HashMap<String, String>) -> Term<'a> {
    let payload = payload_from_nif(params);
    encode_result(env, create_group(&payload))
}

#[rustler::nif(name = "join_from_welcome")]
fn join_from_welcome_nif<'a>(env: Env<'a>, params: HashMap<String, String>) -> Term<'a> {
    let payload = payload_from_nif(params);
    encode_result(env, join_from_welcome(&payload))
}

#[rustler::nif(name = "process_incoming")]
fn process_incoming_nif<'a>(env: Env<'a>, params: HashMap<String, String>) -> Term<'a> {
    let payload = payload_from_nif(params);
    encode_result(env, process_incoming(&payload))
}

#[rustler::nif(name = "commit_to_pending")]
fn commit_to_pending_nif<'a>(env: Env<'a>, params: HashMap<String, String>) -> Term<'a> {
    let payload = payload_from_nif(params);
    encode_result(env, commit_to_pending(&payload))
}

#[rustler::nif(name = "mls_commit")]
fn mls_commit_nif<'a>(env: Env<'a>, params: HashMap<String, String>) -> Term<'a> {
    let payload = payload_from_nif(params);
    encode_result(env, mls_commit(&payload))
}

#[rustler::nif(name = "mls_update")]
fn mls_update_nif<'a>(env: Env<'a>, params: HashMap<String, String>) -> Term<'a> {
    let payload = payload_from_nif(params);
    encode_result(env, mls_update(&payload))
}

#[rustler::nif(name = "mls_add")]
fn mls_add_nif<'a>(env: Env<'a>, params: HashMap<String, String>) -> Term<'a> {
    let payload = payload_from_nif(params);
    encode_result(env, mls_add(&payload))
}

#[rustler::nif(name = "mls_remove")]
fn mls_remove_nif<'a>(env: Env<'a>, params: HashMap<String, String>) -> Term<'a> {
    let payload = payload_from_nif(params);
    encode_result(env, mls_remove(&payload))
}

#[rustler::nif(name = "merge_staged_commit")]
fn merge_staged_commit_nif<'a>(env: Env<'a>, params: HashMap<String, String>) -> Term<'a> {
    let payload = payload_from_nif(params);
    encode_result(env, merge_staged_commit(&payload))
}

#[rustler::nif(name = "clear_pending_commit")]
fn clear_pending_commit_nif<'a>(env: Env<'a>, params: HashMap<String, String>) -> Term<'a> {
    let payload = payload_from_nif(params);
    encode_result(env, clear_pending_commit(&payload))
}

#[rustler::nif(name = "create_application_message")]
fn create_application_message_nif<'a>(env: Env<'a>, params: HashMap<String, String>) -> Term<'a> {
    let payload = payload_from_nif(params);
    encode_result(env, create_application_message(&payload))
}

#[rustler::nif(name = "export_group_info")]
fn export_group_info_nif<'a>(env: Env<'a>, params: HashMap<String, String>) -> Term<'a> {
    let payload = payload_from_nif(params);
    encode_result(env, export_group_info(&payload))
}

#[rustler::nif(name = "export_ratchet_tree")]
fn export_ratchet_tree_nif<'a>(env: Env<'a>, params: HashMap<String, String>) -> Term<'a> {
    let payload = payload_from_nif(params);
    encode_result(env, export_ratchet_tree(&payload))
}

rustler::init!("Elixir.Famichat.Crypto.MLS.NifBridge");

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU64, Ordering};

    static GROUP_COUNTER: AtomicU64 = AtomicU64::new(1);

    fn payload(entries: &[(&str, &str)]) -> Payload {
        entries
            .iter()
            .map(|(k, v)| ((*k).to_owned(), (*v).to_owned()))
            .collect()
    }

    fn unique_group_id(prefix: &str) -> String {
        let index = GROUP_COUNTER.fetch_add(1, Ordering::Relaxed);
        format!("{}-{}", prefix, index)
    }

    #[test]
    fn version_is_exposed_with_wired_status() {
        let result = nif_version().expect("version payload");
        assert_eq!(result.get("crate"), Some(&"mls_nif".to_owned()));
        assert_eq!(result.get("status"), Some(&"wired_contract".to_owned()));
    }

    #[test]
    fn health_reports_openmls_ready() {
        let result = nif_health().expect("health payload");
        assert_eq!(result.get("status"), Some(&"ok".to_owned()));
        assert_eq!(result.get("reason"), Some(&"openmls_ready".to_owned()));
    }

    #[test]
    fn create_group_requires_group_id_and_ciphersuite() {
        let error = create_group(&Payload::new()).expect_err("invalid input error");
        assert_eq!(error.code, ErrorCode::InvalidInput);
        assert_eq!(
            error.details.get("group_id"),
            Some(&"is required".to_owned())
        );
        assert_eq!(
            error.details.get("ciphersuite"),
            Some(&"is required".to_owned())
        );
        assert_eq!(
            error.details.get("operation"),
            Some(&"create_group".to_owned())
        );
    }

    #[test]
    fn create_key_package_refs_are_unique_and_group_create_is_stable() {
        let first = create_key_package(&payload(&[("client_id", "client-1")]))
            .expect("key package must be generated");
        let second = create_key_package(&payload(&[("client_id", "client-1")]))
            .expect("key package must be generated");

        assert_eq!(first.get("status"), Some(&"created".to_owned()));
        assert_eq!(second.get("status"), Some(&"created".to_owned()));

        let first_ref = first.get("key_package_ref").expect("first key package ref");
        let second_ref = second
            .get("key_package_ref")
            .expect("second key package ref");

        assert!(first_ref.starts_with("kp:client-1:"));
        assert!(second_ref.starts_with("kp:client-1:"));
        assert_ne!(first_ref, second_ref);

        let group_id = unique_group_id("group-kp");

        let group = create_group(&payload(&[
            ("group_id", &group_id),
            (
                "ciphersuite",
                "MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519",
            ),
        ]))
        .expect("group must be created");

        assert_eq!(group.get("group_id"), Some(&group_id));
        assert_eq!(group.get("epoch"), Some(&"1".to_owned()));
    }

    #[test]
    fn join_from_welcome_recovery_is_deterministic() {
        let first = join_from_welcome(&payload(&[("rejoin_token", "token-123")]))
            .expect("join must succeed");
        let second = join_from_welcome(&payload(&[("rejoin_token", "token-123")]))
            .expect("join must succeed");

        assert_eq!(first, second);
        assert_eq!(
            first.get("group_state_ref"),
            Some(&"state:token-123".to_owned())
        );
        assert_eq!(first.get("audit_id"), Some(&"audit:token-123".to_owned()));
    }

    #[test]
    fn application_message_round_trip_is_stable() {
        let group_id = unique_group_id("group-roundtrip");

        let encrypted =
            create_application_message(&payload(&[("group_id", &group_id), ("body", "hello")]))
                .expect("encryption success");

        let ciphertext = encrypted.get("ciphertext").expect("ciphertext payload");

        let decrypted = process_incoming(&payload(&[
            ("group_id", &group_id),
            ("ciphertext", ciphertext),
        ]))
        .expect("decryption success");

        assert_eq!(decrypted.get("plaintext"), Some(&"hello".to_owned()));
    }

    #[test]
    fn protocol_invariants_are_enforced() {
        let pending_error = create_application_message(&payload(&[
            ("group_id", "group-1"),
            ("body", "hello"),
            ("pending_proposals", "true"),
        ]))
        .expect_err("pending proposals must be rejected");

        assert_eq!(pending_error.code, ErrorCode::PendingProposals);
        assert_eq!(
            pending_error.details.get("reason"),
            Some(&"pending_proposals".to_owned())
        );

        let merge_error = merge_staged_commit(&payload(&[("group_id", "group-1")]))
            .expect_err("merge requires validation");

        assert_eq!(merge_error.code, ErrorCode::CommitRejected);
        assert_eq!(
            merge_error.details.get("reason"),
            Some(&"staged_commit_not_validated".to_owned())
        );
    }

    #[test]
    fn lifecycle_operations_return_contract_shape() {
        let operations = [mls_commit, mls_update, mls_add, mls_remove];

        for operation in operations {
            let result = operation(&payload(&[("group_id", "group-1")]))
                .expect("lifecycle call should succeed");
            assert_eq!(result.get("group_id"), Some(&"group-1".to_owned()));
            assert_eq!(result.get("status"), Some(&"ok".to_owned()));
        }
    }

    #[test]
    fn error_codes_match_contract_values() {
        assert_eq!(ErrorCode::InvalidInput.as_str(), "invalid_input");
        assert_eq!(
            ErrorCode::UnauthorizedOperation.as_str(),
            "unauthorized_operation"
        );
        assert_eq!(ErrorCode::StaleEpoch.as_str(), "stale_epoch");
        assert_eq!(ErrorCode::PendingProposals.as_str(), "pending_proposals");
        assert_eq!(ErrorCode::CommitRejected.as_str(), "commit_rejected");
        assert_eq!(
            ErrorCode::StorageInconsistent.as_str(),
            "storage_inconsistent"
        );
        assert_eq!(ErrorCode::CryptoFailure.as_str(), "crypto_failure");
        assert_eq!(
            ErrorCode::UnsupportedCapability.as_str(),
            "unsupported_capability"
        );
    }
}
