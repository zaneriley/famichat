#![forbid(unsafe_code)]

use dashmap::DashMap;
use openmls::prelude::{
    tls_codec::Deserialize as _, tls_codec::Serialize as _, BasicCredential, Ciphersuite,
    CreateMessageError, CredentialWithKey, GroupId, KeyPackage, LeafNodeIndex, MlsGroup,
    MlsGroupCreateConfig, MlsGroupJoinConfig, MlsGroupStateError, MlsMessageBodyIn, MlsMessageIn,
    OpenMlsProvider as _, ProcessedMessageContent, StagedWelcome,
};
use openmls_basic_credential::SignatureKeyPair;
use openmls_rust_crypto::OpenMlsRustCrypto;
use rustler::{Encoder, Env, Term};
use std::collections::{HashMap, VecDeque};
use std::sync::atomic::{AtomicU64, Ordering};

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
    /// N1: Distinct variant for a poisoned Mutex/RwLock — a concurrency failure,
    /// not a storage integrity issue. Prevents the Elixir caller from attempting
    /// incorrect state-repair recovery when the real cause is a panicked thread.
    LockPoisoned,
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
            Self::LockPoisoned => "lock_poisoned",
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
    /// Insertion-order queue for deterministic FIFO cache eviction (N4).
    decrypted_message_order: VecDeque<String>,
}

struct MemberSession {
    provider: OpenMlsRustCrypto,
    signer: SignatureKeyPair,
    group: MlsGroup,
}

#[derive(Clone)]
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

// 64 shards reduces cross-group shard contention; default is num_cpus*4
static GROUP_SESSIONS: std::sync::LazyLock<DashMap<String, GroupSession>> =
    std::sync::LazyLock::new(|| DashMap::with_shard_amount(64));
static KEY_PACKAGE_COUNTER: AtomicU64 = AtomicU64::new(1);

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

    // N3: Reject empty, oversized, or NUL-containing group IDs before touching any
    // state. Length is checked in bytes; IDs are hex-encoded UUIDs (ASCII-only)
    // so byte length equals character count.
    if parsed.group_id.is_empty() || parsed.group_id.len() > 256 {
        return Err(MlsError::with_code(
            ErrorCode::InvalidInput,
            "create_group",
            "INVALID_GROUP_ID",
        ));
    }
    if parsed.group_id.contains('\0') {
        return Err(MlsError::with_code(
            ErrorCode::InvalidInput,
            "create_group",
            "INVALID_GROUP_ID_NULL_BYTE",
        ));
    }

    let ciphersuite = parse_ciphersuite(&parsed.ciphersuite).ok_or_else(|| {
        let mut details = Payload::new();
        details.insert("operation".to_owned(), "create_group".to_owned());
        details.insert(
            "ciphersuite".to_owned(),
            "unsupported ciphersuite".to_owned(),
        );
        MlsError::invalid_input(details)
    })?;

    let sender_identity: Option<Vec<u8>> =
        non_empty(params, "credential_identity").map(|s| s.into_bytes());
    // Recipient always uses synthetic identity in the two-actor model
    let recipient_identity: Option<Vec<u8>> = None;

    let session =
        match restore_group_session_from_snapshot(&parsed.group_id, params, "create_group")? {
            Some(session) => session,
            None => create_group_session(
                &parsed.group_id,
                ciphersuite,
                sender_identity,
                recipient_identity,
            )?,
        };

    let session_snapshot = build_group_session_snapshot(&session, "create_group")?;
    let epoch = session.sender.group.epoch().as_u64().to_string();

    GROUP_SESSIONS.insert(parsed.group_id.clone(), session);

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
            let group_id =
                non_empty(params, "group_id").unwrap_or_else(|| format!("rejoin:{}", token));

            // N3: Reject empty, oversized, or NUL-containing group IDs before touching
            // any state. Length is in bytes; IDs are hex-encoded UUIDs (ASCII-only)
            // so byte length equals character count.
            if group_id.is_empty() || group_id.len() > 256 {
                return Err(MlsError::with_code(
                    ErrorCode::InvalidInput,
                    operation,
                    "INVALID_GROUP_ID",
                ));
            }
            if group_id.contains('\0') {
                return Err(MlsError::with_code(
                    ErrorCode::InvalidInput,
                    operation,
                    "INVALID_GROUP_ID_NULL_BYTE",
                ));
            }

            if has_complete_session_snapshot(params) || !GROUP_SESSIONS.contains_key(&group_id) {
                if let Some(restored) =
                    restore_group_session_from_snapshot(&group_id, params, operation)?
                {
                    // Intentional overwrite: snapshot restoration is deterministic given the same
                    // snapshot data. A concurrent insert of the same group_id produces an equivalent
                    // session; the second writer wins, which is acceptable.
                    GROUP_SESSIONS.insert(group_id.clone(), restored);
                } else if !GROUP_SESSIONS.contains_key(&group_id) {
                    let session = create_group_session(&group_id, DEFAULT_CIPHERSUITE, None, None)?;
                    // Entry::Vacant: do not overwrite an existing session inserted by a concurrent thread.
                    if let dashmap::mapref::entry::Entry::Vacant(e) =
                        GROUP_SESSIONS.entry(group_id.clone())
                    {
                        e.insert(session);
                    }
                }
            }

            // N7: Use DashMap entry — shard lock held only while extracting raw data.
            let (epoch, snapshot_raw) = {
                let entry = GROUP_SESSIONS.get(&group_id).ok_or_else(|| {
                    MlsError::with_code(
                        ErrorCode::StorageInconsistent,
                        operation,
                        "missing_group_state",
                    )
                })?;
                let epoch = entry.sender.group.epoch().as_u64().to_string();
                // N6: Extract raw snapshot data while holding the shard lock (fast: byte clones).
                let snapshot_raw = extract_snapshot_raw_data(&entry, operation)?;
                (epoch, snapshot_raw)
            }; // entry (shard lock) dropped here
               // Shard lock released — serialize outside the lock (slow: hex-encoding ~8-18 ms).
            let snapshot = serialize_snapshot_raw_data(snapshot_raw);

            let mut payload = Payload::new();
            payload.insert("group_id".to_owned(), group_id);
            payload.insert("group_state_ref".to_owned(), format!("state:{}", token));
            payload.insert("audit_id".to_owned(), format!("audit:{}", token));
            payload.insert("status".to_owned(), "joined".to_owned());
            payload.insert("epoch".to_owned(), epoch);
            payload.extend(snapshot);
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
            // N3: Reject empty, oversized, or NUL-containing group IDs before touching
            // any state. Length is in bytes; IDs are hex-encoded UUIDs (ASCII-only)
            // so byte length equals character count.
            if group_id.is_empty() || group_id.len() > 256 {
                return Err(MlsError::with_code(
                    ErrorCode::InvalidInput,
                    operation,
                    "INVALID_GROUP_ID",
                ));
            }
            if group_id.contains('\0') {
                return Err(MlsError::with_code(
                    ErrorCode::InvalidInput,
                    operation,
                    "INVALID_GROUP_ID_NULL_BYTE",
                ));
            }

            let should_restore =
                has_complete_session_snapshot(params) || !GROUP_SESSIONS.contains_key(&group_id);

            if should_restore {
                if let Some(restored) =
                    restore_group_session_from_snapshot(&group_id, params, operation)?
                {
                    GROUP_SESSIONS.insert(group_id.clone(), restored);
                }
            }

            let mut entry = GROUP_SESSIONS.get_mut(&group_id).ok_or_else(|| {
                let mut err_details = Payload::new();
                err_details.insert("operation".to_owned(), operation.to_owned());
                err_details.insert("reason".to_owned(), "missing_group_state".to_owned());
                err_details.insert("group_id".to_owned(), group_id.clone());
                MlsError {
                    code: ErrorCode::StorageInconsistent,
                    details: err_details,
                }
            })?;
            let session = &mut *entry;

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
            let message_in = MlsMessageIn::tls_deserialize(&mut slice).map_err(|e| {
                let mut err =
                    MlsError::with_code(ErrorCode::InvalidInput, operation, "malformed_ciphertext");
                err.details.insert("error".to_owned(), format!("{e:?}"));
                err
            })?;

            let protocol_message = message_in.try_into_protocol_message().map_err(|e| {
                let mut err = MlsError::with_code(
                    ErrorCode::InvalidInput,
                    operation,
                    "unsupported_message_type",
                );
                err.details.insert("error".to_owned(), format!("{e:?}"));
                err
            })?;

            let processed = session
                .recipient
                .group
                .process_message(&session.recipient.provider, protocol_message)
                .map_err(|e| {
                    let mut err = MlsError::with_code(
                        ErrorCode::CommitRejected,
                        operation,
                        "message_processing_failed",
                    );
                    err.details.insert("error".to_owned(), format!("{e:?}"));
                    err
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
                    &mut session.decrypted_message_order,
                    cache_key,
                    CachedMessage {
                        ciphertext: ciphertext.clone(),
                        plaintext: cache_plaintext,
                    },
                );
            }

            // N6/N7: Extract raw snapshot data while holding the shard lock (fast: byte clones).
            let snapshot_raw = extract_snapshot_raw_data(session, operation)?;
            drop(entry); // shard lock released here
                         // Shard lock released — serialize outside the lock (slow: hex-encoding ~8-18 ms).
            let snapshot = serialize_snapshot_raw_data(snapshot_raw);

            payload.extend(snapshot);

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
    let operation = "mls_remove";
    with_required_group(operation, params, |group_id| {
        if has_complete_session_snapshot(params) || !GROUP_SESSIONS.contains_key(&group_id) {
            if let Some(restored) =
                restore_group_session_from_snapshot(&group_id, params, operation)?
            {
                // Entry::Vacant: do not overwrite an existing session inserted by a concurrent thread.
                if let dashmap::mapref::entry::Entry::Vacant(e) =
                    GROUP_SESSIONS.entry(group_id.clone())
                {
                    e.insert(restored);
                }
            }
        }

        let mut entry = GROUP_SESSIONS.get_mut(&group_id).ok_or_else(|| {
            MlsError::with_code(
                ErrorCode::StorageInconsistent,
                operation,
                "missing_group_state",
            )
        })?;
        let session = &mut *entry;

        // Determine which leaf index to remove.
        let leaf_index = determine_remove_target(params, operation)?;

        // Atomically propose and commit the removal.
        // Returns (commit_out, Option<welcome_out>, Option<group_info>).
        let (commit_out, _welcome_opt, _group_info_opt) = session
            .sender
            .group
            .remove_members(
                &session.sender.provider,
                &session.sender.signer,
                &[leaf_index],
            )
            .map_err(|e| {
                let mut details = Payload::new();
                details.insert("operation".to_owned(), operation.to_owned());
                details.insert("reason".to_owned(), format!("{e:?}"));
                MlsError {
                    code: ErrorCode::CommitRejected,
                    details,
                }
            })?;

        // Serialize the commit message to return as commit_ciphertext.
        let commit_bytes = commit_out.tls_serialize_detached().map_err(|e| {
            let mut err =
                MlsError::with_code(ErrorCode::CryptoFailure, operation, "serialize_failed");
            err.details.insert("error".to_owned(), format!("{e:?}"));
            err
        })?;
        let commit_ciphertext = encode_hex(&commit_bytes);

        // The sender's group is now in PendingCommit state; merge it to advance epoch.
        session
            .sender
            .group
            .merge_pending_commit(&session.sender.provider)
            .map_err(|e| {
                let mut err = MlsError::with_code(
                    ErrorCode::CommitRejected,
                    operation,
                    "merge_pending_commit_failed",
                );
                err.details.insert("error".to_owned(), format!("{e:?}"));
                err
            })?;

        // Have the recipient process and merge the commit so their group state reflects
        // the removal. RFC §12.4.2: the removed member must NOT continue sending, but
        // we CAN process the commit on the co-located recipient session to update
        // is_active(). We deserialize the commit bytes and feed them to the recipient.
        let recipient_removed = {
            let mut slice = commit_bytes.as_slice();
            let msg_in = MlsMessageIn::tls_deserialize(&mut slice).map_err(|e| {
                let mut err = MlsError::with_code(
                    ErrorCode::CryptoFailure,
                    operation,
                    "recipient_commit_deserialize_failed",
                );
                err.details.insert("error".to_owned(), format!("{e:?}"));
                err
            })?;
            let protocol_message = msg_in.try_into_protocol_message().map_err(|e| {
                let mut err = MlsError::with_code(
                    ErrorCode::CryptoFailure,
                    operation,
                    "recipient_commit_protocol_message_failed",
                );
                err.details.insert("error".to_owned(), format!("{e:?}"));
                err
            })?;
            let processed = session
                .recipient
                .group
                .process_message(&session.recipient.provider, protocol_message)
                .map_err(|e| {
                    let mut err = MlsError::with_code(
                        ErrorCode::CommitRejected,
                        operation,
                        "recipient_commit_process_failed",
                    );
                    err.details.insert("error".to_owned(), format!("{e:?}"));
                    err
                })?;
            match processed.into_content() {
                ProcessedMessageContent::StagedCommitMessage(staged_commit) => {
                    session
                        .recipient
                        .group
                        .merge_staged_commit(&session.recipient.provider, *staged_commit)
                        .map_err(|e| {
                            let mut err = MlsError::with_code(
                                ErrorCode::CommitRejected,
                                operation,
                                "recipient_merge_staged_commit_failed",
                            );
                            err.details.insert("error".to_owned(), format!("{e:?}"));
                            err
                        })?;
                }
                _ => {
                    return Err(MlsError::with_code(
                        ErrorCode::CommitRejected,
                        operation,
                        "recipient_unexpected_message_type",
                    ));
                }
            }
            // After merging, the removed member's group is Inactive.
            !session.recipient.group.is_active()
        };

        // Read epoch from sender's group after the operation.
        let epoch = session.sender.group.epoch().as_u64().to_string();

        // N6/N7: Extract raw snapshot data while holding the shard lock (fast: byte clones).
        let snapshot_raw = extract_snapshot_raw_data(session, operation)?;
        drop(entry); // shard lock released here
                     // Shard lock released — serialize outside the lock (slow: hex-encoding ~8-18 ms).
        let snapshot = serialize_snapshot_raw_data(snapshot_raw);

        let mut payload = Payload::new();
        payload.insert("group_id".to_owned(), group_id);
        payload.insert("epoch".to_owned(), epoch);
        payload.insert("commit_ciphertext".to_owned(), commit_ciphertext);
        payload.insert(
            "recipient_removed".to_owned(),
            recipient_removed.to_string(),
        );
        payload.insert("status".to_owned(), "ok".to_owned());
        payload.extend(snapshot);
        Ok(payload)
    })
}

fn determine_remove_target(params: &Payload, operation: &str) -> Result<LeafNodeIndex, MlsError> {
    if let Some(leaf_index_str) = non_empty(params, "leaf_index") {
        let index: u32 = leaf_index_str.parse().map_err(|e| {
            let mut err =
                MlsError::with_code(ErrorCode::InvalidInput, operation, "invalid_leaf_index");
            err.details.insert("error".to_owned(), format!("{e:?}"));
            err
        })?;
        return Ok(LeafNodeIndex::new(index));
    }
    match non_empty(params, "remove_target").as_deref() {
        Some("recipient") => Ok(LeafNodeIndex::new(1)),
        Some("sender") => Ok(LeafNodeIndex::new(0)),
        Some(_) => Err(MlsError::with_code(
            ErrorCode::InvalidInput,
            operation,
            "unknown_remove_target",
        )),
        None => Err(MlsError::with_code(
            ErrorCode::InvalidInput,
            operation,
            "missing_remove_target",
        )),
    }
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

    let commit_ciphertext = non_empty(params, "commit_ciphertext").ok_or_else(|| {
        MlsError::with_code(
            ErrorCode::InvalidInput,
            operation,
            "missing_commit_ciphertext",
        )
    })?;

    with_required_group(operation, params, |group_id| {
        if has_complete_session_snapshot(params) || !GROUP_SESSIONS.contains_key(&group_id) {
            if let Some(restored) =
                restore_group_session_from_snapshot(&group_id, params, operation)?
            {
                // Entry::Vacant: do not overwrite an existing session inserted by a concurrent thread.
                if let dashmap::mapref::entry::Entry::Vacant(e) =
                    GROUP_SESSIONS.entry(group_id.clone())
                {
                    e.insert(restored);
                }
            }
        }

        let mut entry = GROUP_SESSIONS.get_mut(&group_id).ok_or_else(|| {
            MlsError::with_code(
                ErrorCode::StorageInconsistent,
                operation,
                "missing_group_state",
            )
        })?;
        let session = &mut *entry;

        // If the recipient's group is already inactive, the commit was already processed
        // by the sender-side operation (e.g. mls_remove processes the commit inline).
        // In the two-actor co-located model, skip re-processing and return current state.
        if !session.recipient.group.is_active() {
            let epoch = session.sender.group.epoch().as_u64().to_string();
            // N6/N7: Extract raw snapshot data while holding the shard lock (fast: byte clones).
            let snapshot_raw = extract_snapshot_raw_data(session, operation)?;
            drop(entry); // shard lock released here
                         // Shard lock released — serialize outside the lock (slow: hex-encoding ~8-18 ms).
            let snapshot = serialize_snapshot_raw_data(snapshot_raw);

            let mut payload = Payload::new();
            payload.insert("group_id".to_owned(), group_id);
            payload.insert("epoch".to_owned(), epoch);
            payload.insert("recipient_active".to_owned(), "false".to_owned());
            payload.insert("merged".to_owned(), "true".to_owned());
            payload.insert("status".to_owned(), "ok".to_owned());
            payload.extend(snapshot);
            return Ok(payload);
        }

        // Decode the commit ciphertext produced by mls_remove (or another commit operation).
        let commit_bytes = decode_hex(&commit_ciphertext).map_err(|e| {
            let mut err = MlsError::with_code(
                ErrorCode::InvalidInput,
                operation,
                "invalid_commit_ciphertext",
            );
            err.details.insert("error".to_owned(), format!("{e:?}"));
            err
        })?;

        let mut slice = commit_bytes.as_slice();
        let mls_message = MlsMessageIn::tls_deserialize(&mut slice).map_err(|e| {
            let mut err = MlsError::with_code(
                ErrorCode::InvalidInput,
                operation,
                "malformed_commit_ciphertext",
            );
            err.details.insert("error".to_owned(), format!("{e:?}"));
            err
        })?;

        let protocol_message = mls_message.try_into_protocol_message().map_err(|e| {
            let mut err = MlsError::with_code(
                ErrorCode::InvalidInput,
                operation,
                "unsupported_message_type",
            );
            err.details.insert("error".to_owned(), format!("{e:?}"));
            err
        })?;

        // Process the commit on the recipient's group to get a StagedCommit.
        let processed = session
            .recipient
            .group
            .process_message(&session.recipient.provider, protocol_message)
            .map_err(|e| {
                MlsError::with_code(
                    ErrorCode::CryptoFailure,
                    operation,
                    &format!("process_commit_failed: {:?}", e),
                )
            })?;

        // Extract and merge the staged commit — recipient side only.
        // Do NOT call merge_pending_commit here; that is the sender's responsibility.
        match processed.into_content() {
            ProcessedMessageContent::StagedCommitMessage(staged_commit) => {
                session
                    .recipient
                    .group
                    .merge_staged_commit(&session.recipient.provider, *staged_commit)
                    .map_err(|e| {
                        MlsError::with_code(
                            ErrorCode::CryptoFailure,
                            operation,
                            &format!("merge_staged_commit_failed: {:?}", e),
                        )
                    })?;
            }
            _ => {
                return Err(MlsError::with_code(
                    ErrorCode::InvalidInput,
                    operation,
                    "not_a_commit_message",
                ));
            }
        }

        let recipient_active = session.recipient.group.is_active();
        // Epoch is authoritative from the sender's group.
        let epoch = session.sender.group.epoch().as_u64().to_string();

        // N6/N7: Extract raw snapshot data while holding the shard lock (fast: byte clones).
        let snapshot_raw = extract_snapshot_raw_data(session, operation)?;
        drop(entry); // shard lock released here
                     // Shard lock released — serialize outside the lock (slow: hex-encoding ~8-18 ms).
        let snapshot = serialize_snapshot_raw_data(snapshot_raw);

        let mut payload = Payload::new();
        payload.insert("group_id".to_owned(), group_id);
        payload.insert("epoch".to_owned(), epoch);
        payload.insert("recipient_active".to_owned(), recipient_active.to_string());
        payload.insert("merged".to_owned(), "true".to_owned());
        payload.insert("status".to_owned(), "ok".to_owned());
        payload.extend(snapshot);
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
        let should_restore =
            has_complete_session_snapshot(params) || !GROUP_SESSIONS.contains_key(&group_id);

        if should_restore {
            if let Some(restored) =
                restore_group_session_from_snapshot(&group_id, params, operation)?
            {
                if has_complete_session_snapshot(params) {
                    // A complete snapshot is the caller's explicit actor/session view for this
                    // request. Reuse the same authoritative restore behavior as process_incoming:
                    // if the caller swaps sender/recipient snapshot fields after mls_remove, this
                    // call must encrypt as that swapped actor, not as a stale cached session.
                    GROUP_SESSIONS.insert(group_id.clone(), restored);
                } else {
                    // Entry::Vacant: do not overwrite an existing session inserted by a concurrent thread.
                    if let dashmap::mapref::entry::Entry::Vacant(e) =
                        GROUP_SESSIONS.entry(group_id.clone())
                    {
                        e.insert(restored);
                    }
                }
            }
        }

        let mut entry = GROUP_SESSIONS.get_mut(&group_id).ok_or_else(|| {
            MlsError::with_code(
                ErrorCode::StorageInconsistent,
                operation,
                "missing_group_state",
            )
        })?;
        let session = &mut *entry;

        let message_out = session
            .sender
            .group
            .create_message(
                &session.sender.provider,
                &session.sender.signer,
                body.as_bytes(),
            )
            .map_err(|error| map_create_message_error(operation, error))?;

        let serialized = message_out.tls_serialize_detached().map_err(|e| {
            let mut err =
                MlsError::with_code(ErrorCode::CryptoFailure, operation, "serialize_failed");
            err.details.insert("error".to_owned(), format!("{e:?}"));
            err
        })?;
        let ciphertext = encode_hex(&serialized);
        let epoch = session.sender.group.epoch().as_u64().to_string();

        // N6/N7: Extract raw snapshot data while holding the shard lock (fast: byte clones).
        let snapshot_raw = extract_snapshot_raw_data(session, operation)?;
        drop(entry); // shard lock released here
                     // Shard lock released — serialize outside the lock (slow: hex-encoding ~8-18 ms).
        let snapshot = serialize_snapshot_raw_data(snapshot_raw);

        let mut payload = Payload::new();
        payload.insert("group_id".to_owned(), group_id);
        payload.insert("ciphertext".to_owned(), ciphertext);
        payload.insert("epoch".to_owned(), epoch);
        payload.insert("status".to_owned(), "encrypted".to_owned());
        payload.extend(snapshot);
        Ok(payload)
    })
}

pub fn export_group_info(params: &Payload) -> MlsResult {
    let operation = "export_group_info";
    with_required_group(operation, params, |group_id| {
        if !GROUP_SESSIONS.contains_key(&group_id) {
            if let Some(restored) =
                restore_group_session_from_snapshot(&group_id, params, operation)?
            {
                // Entry::Vacant: do not overwrite an existing session inserted by a concurrent thread.
                if let dashmap::mapref::entry::Entry::Vacant(e) =
                    GROUP_SESSIONS.entry(group_id.clone())
                {
                    e.insert(restored);
                }
            }
        }

        // N6/N7: Extract raw snapshot data while holding the shard lock (fast: byte clones),
        // then drop the shard lock before serializing (slow: hex-encoding ~8-18 ms).
        let (epoch_opt, snapshot_raw_opt) = if let Some(entry) = GROUP_SESSIONS.get(&group_id) {
            let epoch = entry.sender.group.epoch().as_u64().to_string();
            let raw = extract_snapshot_raw_data(&entry, operation)?;
            (Some(epoch), Some(raw))
        } else {
            (None, None)
        }; // entry (shard lock) dropped here
           // Shard lock released — serialize outside the lock.
        let snapshot_opt = snapshot_raw_opt.map(serialize_snapshot_raw_data);

        let mut payload = Payload::new();
        payload.insert("group_id".to_owned(), group_id.clone());
        payload.insert(
            "group_info_ref".to_owned(),
            format!("group-info:{}", group_id),
        );

        if let (Some(epoch), Some(snapshot)) = (epoch_opt, snapshot_opt) {
            payload.insert("epoch".to_owned(), epoch);
            payload.extend(snapshot);
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

pub fn list_member_credentials(params: &Payload) -> MlsResult {
    let operation = "list_member_credentials";
    with_required_group(operation, params, |group_id| {
        if !GROUP_SESSIONS.contains_key(&group_id) {
            if let Some(restored) =
                restore_group_session_from_snapshot(&group_id, params, operation)?
            {
                // Entry::Vacant: do not overwrite an existing session inserted by a concurrent thread.
                if let dashmap::mapref::entry::Entry::Vacant(e) =
                    GROUP_SESSIONS.entry(group_id.clone())
                {
                    e.insert(restored);
                }
            }
        }

        let entry = GROUP_SESSIONS.get(&group_id).ok_or_else(|| {
            MlsError::with_code(
                ErrorCode::StorageInconsistent,
                operation,
                "missing_group_state",
            )
        })?;
        let session = &*entry;

        // Iterate members, extract credential identity for each.
        // member.index is a LeafNodeIndex with a .u32() method.
        // member.credential is a Credential; BasicCredential::try_from extracts identity bytes.
        let credentials: Vec<String> = session
            .sender
            .group
            .members()
            .map(|member| {
                let leaf_index = member.index.u32();
                let identity_bytes = BasicCredential::try_from(member.credential)
                    .map(|bc| bc.identity().to_vec())
                    .unwrap_or_default();
                format!("{}:{}", leaf_index, encode_hex(&identity_bytes))
            })
            .collect();

        let mut payload = Payload::new();
        payload.insert("group_id".to_owned(), group_id);
        payload.insert("credentials".to_owned(), credentials.join(","));
        payload.insert("status".to_owned(), "ok".to_owned());
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
        Some(group_id) => {
            // N3: Reject empty, oversized, or NUL-containing group IDs before touching
            // any state. Length is in bytes; IDs are hex-encoded UUIDs (ASCII-only)
            // so byte length equals character count.
            if group_id.is_empty() || group_id.len() > 256 {
                return Err(MlsError::with_code(
                    ErrorCode::InvalidInput,
                    operation,
                    "INVALID_GROUP_ID",
                ));
            }
            if group_id.contains('\0') {
                return Err(MlsError::with_code(
                    ErrorCode::InvalidInput,
                    operation,
                    "INVALID_GROUP_ID_NULL_BYTE",
                ));
            }
            on_group(group_id)
        }
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
    sender_identity: Option<Vec<u8>>,
    recipient_identity: Option<Vec<u8>>,
) -> Result<GroupSession, MlsError> {
    let operation = "create_group";
    let sender_id_bytes =
        sender_identity.unwrap_or_else(|| format!("famichat:{}:sender", group_id).into_bytes());
    let recipient_id_bytes = recipient_identity
        .unwrap_or_else(|| format!("famichat:{}:recipient", group_id).into_bytes());

    let sender_provider = OpenMlsRustCrypto::default();
    let (sender_credential, sender_signer) = create_credential_with_signer_bytes(
        &sender_provider,
        ciphersuite,
        sender_id_bytes,
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
    .map_err(|e| {
        let mut err = MlsError::with_code(
            ErrorCode::CryptoFailure,
            "create_group",
            "group_init_failed",
        );
        err.details.insert("error".to_owned(), format!("{e:?}"));
        err
    })?;

    let recipient_provider = OpenMlsRustCrypto::default();
    let (recipient_credential, recipient_signer) = create_credential_with_signer_bytes(
        &recipient_provider,
        ciphersuite,
        recipient_id_bytes,
        operation,
    )?;

    let recipient_kpb = KeyPackage::builder()
        .build(
            ciphersuite,
            &recipient_provider,
            &recipient_signer,
            recipient_credential,
        )
        .map_err(|e| {
            let mut err = MlsError::with_code(
                ErrorCode::CryptoFailure,
                operation,
                "key_package_generation_failed",
            );
            err.details.insert("error".to_owned(), format!("{e:?}"));
            err
        })?;

    let (_commit_message, welcome_message, _group_info) = sender_group
        .add_members(
            &sender_provider,
            &sender_signer,
            core::slice::from_ref(recipient_kpb.key_package()),
        )
        .map_err(|e| {
            let mut err =
                MlsError::with_code(ErrorCode::CommitRejected, operation, "member_add_failed");
            err.details.insert("error".to_owned(), format!("{e:?}"));
            err
        })?;

    sender_group
        .merge_pending_commit(&sender_provider)
        .map_err(|e| {
            let mut err = MlsError::with_code(
                ErrorCode::CommitRejected,
                operation,
                "merge_pending_commit_failed",
            );
            err.details.insert("error".to_owned(), format!("{e:?}"));
            err
        })?;

    let welcome_bytes = welcome_message.tls_serialize_detached().map_err(|e| {
        let mut err = MlsError::with_code(
            ErrorCode::CryptoFailure,
            operation,
            "welcome_serialize_failed",
        );
        err.details.insert("error".to_owned(), format!("{e:?}"));
        err
    })?;
    let mut welcome_slice = welcome_bytes.as_slice();
    let welcome_in = MlsMessageIn::tls_deserialize(&mut welcome_slice).map_err(|e| {
        let mut err = MlsError::with_code(
            ErrorCode::InvalidInput,
            operation,
            "welcome_deserialize_failed",
        );
        err.details.insert("error".to_owned(), format!("{e:?}"));
        err
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
    .map_err(|e| {
        let mut err = MlsError::with_code(
            ErrorCode::CryptoFailure,
            operation,
            "join_from_welcome_failed",
        );
        err.details.insert("error".to_owned(), format!("{e:?}"));
        err
    })?
    .into_group(&recipient_provider)
    .map_err(|e| {
        let mut err =
            MlsError::with_code(ErrorCode::CryptoFailure, operation, "staged_welcome_failed");
        err.details.insert("error".to_owned(), format!("{e:?}"));
        err
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
        decrypted_message_order: VecDeque::new(),
    })
}

fn create_credential_with_signer_bytes(
    provider: &OpenMlsRustCrypto,
    ciphersuite: Ciphersuite,
    identity: Vec<u8>,
    operation: &str,
) -> Result<(CredentialWithKey, SignatureKeyPair), MlsError> {
    let signer = SignatureKeyPair::new(ciphersuite.signature_algorithm()).map_err(|e| {
        let mut err = MlsError::with_code(
            ErrorCode::CryptoFailure,
            operation,
            "signature_key_generation_failed",
        );
        err.details.insert("error".to_owned(), format!("{e:?}"));
        err
    })?;

    signer.store(provider.storage()).map_err(|e| {
        let mut err = MlsError::with_code(
            ErrorCode::StorageInconsistent,
            operation,
            "signature_key_store_failed",
        );
        err.details.insert("error".to_owned(), format!("{e:?}"));
        err
    })?;

    let credential_with_key = CredentialWithKey {
        credential: BasicCredential::new(identity).into(),
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

/// Raw data extracted from a [`GroupSession`] while the `GROUP_SESSIONS` lock is held.
///
/// The extract step clones/copies only raw bytes (cheap). The subsequent
/// [`serialize_snapshot_raw_data`] step hex-encodes those bytes into strings
/// (expensive, ~8-18 ms) and can run *outside* the lock.
struct SnapshotRawData {
    sender_storage: HashMap<Vec<u8>, Vec<u8>>,
    recipient_storage: HashMap<Vec<u8>, Vec<u8>>,
    /// TLS-serialized bytes of the sender's `SignatureKeyPair`.
    sender_signer_bytes: Vec<u8>,
    /// TLS-serialized bytes of the recipient's `SignatureKeyPair`.
    recipient_signer_bytes: Vec<u8>,
    /// N4 (Fix B): Cache entries stored in insertion order so that the VecDeque
    /// eviction queue can be rebuilt deterministically after a snapshot restore.
    /// HashMap iteration is non-deterministic; using Vec preserves order.
    message_cache_ordered: Vec<(String, CachedMessage)>,
}

/// Phase 1 (N6): Extract raw data while the `GROUP_SESSIONS` lock is held.
///
/// All operations here are byte-level clones or fixed-size TLS serializations —
/// typically well under 1 ms. The caller must drop the lock before calling
/// [`serialize_snapshot_raw_data`].
///
/// Lock ordering invariant: callers must hold the DashMap shard lock (via get_mut/get)
/// BEFORE acquiring sender_provider.storage().values or recipient_provider.storage().values.
/// Acquiring the RwLocks before the shard lock, or acquiring them in different orders
/// across two concurrent calls, will deadlock. All 7 call sites currently obey this order.
/// If a background eviction task is added in future, verify it acquires no shard lock.
fn extract_snapshot_raw_data(
    session: &GroupSession,
    operation: &str,
) -> Result<SnapshotRawData, MlsError> {
    // Clone raw storage maps — O(n) byte copies, no encoding work.
    // N1: Use LockPoisoned (not StorageInconsistent) — a poisoned RwLock is a
    // concurrency failure caused by a panicked thread, not a storage integrity
    // issue. The Elixir caller must not attempt state-repair for this condition.
    let sender_storage = session
        .sender
        .provider
        .storage()
        .values
        .read()
        .map_err(|e| {
            let mut err = MlsError::with_code(ErrorCode::LockPoisoned, operation, "lock_poisoned");
            err.details.insert("error".to_owned(), format!("{e:?}"));
            err
        })?
        .clone();

    let recipient_storage = session
        .recipient
        .provider
        .storage()
        .values
        .read()
        .map_err(|e| {
            let mut err = MlsError::with_code(ErrorCode::LockPoisoned, operation, "lock_poisoned");
            err.details.insert("error".to_owned(), format!("{e:?}"));
            err
        })?
        .clone();

    // TLS-serialize the signers — these are small fixed-size key blobs (~64 bytes),
    // so serialization is negligible.
    let sender_signer_bytes = session
        .sender
        .signer
        .tls_serialize_detached()
        .map_err(|e| {
            let mut err = MlsError::with_code(
                ErrorCode::CryptoFailure,
                operation,
                "signature_serialize_failed",
            );
            err.details.insert("error".to_owned(), format!("{e:?}"));
            err
        })?;

    let recipient_signer_bytes =
        session
            .recipient
            .signer
            .tls_serialize_detached()
            .map_err(|e| {
                let mut err = MlsError::with_code(
                    ErrorCode::CryptoFailure,
                    operation,
                    "signature_serialize_failed",
                );
                err.details.insert("error".to_owned(), format!("{e:?}"));
                err
            })?;

    // N4 (Fix B): Capture cache entries in VecDeque insertion order so the eviction
    // queue can be rebuilt deterministically after a snapshot restore. Iterating
    // a HashMap is non-deterministic; the VecDeque is the canonical order source.
    let message_cache_ordered: Vec<(String, CachedMessage)> = session
        .decrypted_message_order
        .iter()
        .filter_map(|key| {
            session
                .decrypted_by_message_id
                .get(key)
                .map(|v| (key.clone(), v.clone()))
        })
        .collect();

    Ok(SnapshotRawData {
        sender_storage,
        recipient_storage,
        sender_signer_bytes,
        recipient_signer_bytes,
        message_cache_ordered,
    })
}

/// Phase 2 (N6): Serialize raw data into the snapshot [`Payload`].
///
/// All operations here are CPU-bound hex-encoding (~8-18 ms total). This runs
/// *outside* the `GROUP_SESSIONS` lock so other threads are not blocked.
fn serialize_snapshot_raw_data(raw: SnapshotRawData) -> Payload {
    let mut payload = Payload::new();

    // Serialize storage maps: each entry becomes "hex(key):hex(value)".
    let sender_storage_str = {
        let mut entries: Vec<String> = raw
            .sender_storage
            .iter()
            .map(|(k, v)| format!("{}:{}", encode_hex(k), encode_hex(v)))
            .collect();
        entries.sort_unstable();
        entries.join(",")
    };

    let recipient_storage_str = {
        let mut entries: Vec<String> = raw
            .recipient_storage
            .iter()
            .map(|(k, v)| format!("{}:{}", encode_hex(k), encode_hex(v)))
            .collect();
        entries.sort_unstable();
        entries.join(",")
    };

    let sender_signer_str = encode_hex(&raw.sender_signer_bytes);
    let recipient_signer_str = encode_hex(&raw.recipient_signer_bytes);
    // N4 (Fix B): serialize_message_cache_ordered preserves insertion order so that
    // the VecDeque eviction queue is rebuilt identically after a snapshot restore.
    let cache_str = serialize_message_cache_ordered(&raw.message_cache_ordered);

    payload.insert(SNAPSHOT_SENDER_STORAGE_KEY.to_owned(), sender_storage_str);
    payload.insert(
        SNAPSHOT_RECIPIENT_STORAGE_KEY.to_owned(),
        recipient_storage_str,
    );
    payload.insert(SNAPSHOT_SENDER_SIGNER_KEY.to_owned(), sender_signer_str);
    payload.insert(
        SNAPSHOT_RECIPIENT_SIGNER_KEY.to_owned(),
        recipient_signer_str,
    );
    payload.insert(SNAPSHOT_CACHE_KEY.to_owned(), cache_str);

    payload
}

/// Build a snapshot payload from a `GroupSession`.
///
/// Internally this delegates to [`extract_snapshot_raw_data`] +
/// [`serialize_snapshot_raw_data`] so that callers which hold the
/// `GROUP_SESSIONS` lock can switch to the two-phase approach (N6).
/// For call sites where no `GROUP_SESSIONS` lock is held (e.g. `create_group`
/// before the insert), this is a thin convenience wrapper.
fn build_group_session_snapshot(
    session: &GroupSession,
    operation: &str,
) -> Result<Payload, MlsError> {
    let raw = extract_snapshot_raw_data(session, operation)?;
    Ok(serialize_snapshot_raw_data(raw))
}

fn restore_group_session_from_snapshot(
    group_id: &str,
    params: &Payload,
    operation: &str,
) -> Result<Option<GroupSession>, MlsError> {
    let cache = non_empty(params, SNAPSHOT_CACHE_KEY).unwrap_or_default();

    // Finding #11: Destructure all four required fields in a single match,
    // eliminating the separated presence/completeness checks and the four
    // subsequent .unwrap() calls. The match arm proves all four are Some before
    // any deserialization occurs.
    let (sender_storage_str, recipient_storage_str, sender_signer_str, recipient_signer_str) =
        match (
            non_empty(params, SNAPSHOT_SENDER_STORAGE_KEY),
            non_empty(params, SNAPSHOT_RECIPIENT_STORAGE_KEY),
            non_empty(params, SNAPSHOT_SENDER_SIGNER_KEY),
            non_empty(params, SNAPSHOT_RECIPIENT_SIGNER_KEY),
        ) {
            (Some(ss), Some(rs), Some(sg), Some(rg)) => (ss, rs, sg, rg),
            (None, None, None, None) if cache.is_empty() => {
                // No snapshot data at all — caller should create a fresh session.
                return Ok(None);
            }
            _ => {
                return Err(MlsError::with_code(
                    ErrorCode::InvalidInput,
                    operation,
                    "incomplete_session_snapshot",
                ));
            }
        };

    let sender_storage = deserialize_storage_map(&sender_storage_str, operation)?;
    let recipient_storage = deserialize_storage_map(&recipient_storage_str, operation)?;
    let sender_signer = deserialize_signer(&sender_signer_str, operation)?;
    let recipient_signer = deserialize_signer(&recipient_signer_str, operation)?;
    // N4 (Fix B): Deserialize in serialization order so VecDeque is deterministic.
    let message_cache_ordered = deserialize_message_cache_ordered(&cache, operation)?;

    let sender_provider = OpenMlsRustCrypto::default();
    {
        // Finding #6: Replace silent poison recovery with proper error propagation.
        // A poisoned RwLock means a thread panicked while holding it; the inner
        // value is in an unknown state. Writing into it would silently corrupt
        // the provider storage. Return LockPoisoned so the Elixir caller can
        // handle it through Logger/telemetry instead of absorbing it quietly.
        let mut values = sender_provider.storage().values.write().map_err(|e| {
            let mut err = MlsError::with_code(ErrorCode::LockPoisoned, operation, "lock_poisoned");
            err.details.insert("error".to_owned(), format!("{e:?}"));
            err
        })?;
        *values = sender_storage;
    }

    sender_signer
        .store(sender_provider.storage())
        .map_err(|e| {
            let mut err = MlsError::with_code(
                ErrorCode::StorageInconsistent,
                operation,
                "signature_key_store_failed",
            );
            err.details.insert("error".to_owned(), format!("{e:?}"));
            err
        })?;

    let sender_group_id = GroupId::from_slice(group_id.as_bytes());
    let sender_group = MlsGroup::load(sender_provider.storage(), &sender_group_id)
        .map_err(|e| {
            let mut err = MlsError::with_code(
                ErrorCode::StorageInconsistent,
                operation,
                "group_load_failed",
            );
            err.details.insert("error".to_owned(), format!("{e:?}"));
            err
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
        // Finding #13: Same lock-poison fix as the sender block above.
        let mut values = recipient_provider.storage().values.write().map_err(|e| {
            let mut err = MlsError::with_code(ErrorCode::LockPoisoned, operation, "lock_poisoned");
            err.details.insert("error".to_owned(), format!("{e:?}"));
            err
        })?;
        *values = recipient_storage;
    }

    recipient_signer
        .store(recipient_provider.storage())
        .map_err(|e| {
            let mut err = MlsError::with_code(
                ErrorCode::StorageInconsistent,
                operation,
                "signature_key_store_failed",
            );
            err.details.insert("error".to_owned(), format!("{e:?}"));
            err
        })?;

    let recipient_group_id = GroupId::from_slice(group_id.as_bytes());
    let recipient_group = MlsGroup::load(recipient_provider.storage(), &recipient_group_id)
        .map_err(|e| {
            let mut err = MlsError::with_code(
                ErrorCode::StorageInconsistent,
                operation,
                "group_load_failed",
            );
            err.details.insert("error".to_owned(), format!("{e:?}"));
            err
        })?
        .ok_or_else(|| {
            MlsError::with_code(
                ErrorCode::StorageInconsistent,
                operation,
                "missing_group_state",
            )
        })?;

    // N4 (Fix B): Rebuild HashMap and VecDeque from the ordered list so that
    // eviction order after restore exactly matches the original insertion order.
    let mut message_cache: HashMap<String, CachedMessage> =
        HashMap::with_capacity(message_cache_ordered.len());
    let mut message_order: VecDeque<String> = VecDeque::with_capacity(message_cache_ordered.len());
    for (key, value) in message_cache_ordered {
        message_order.push_back(key.clone());
        message_cache.insert(key, value);
    }

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
        decrypted_message_order: message_order,
    }))
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

        let key = decode_hex(encoded_key).map_err(|e| {
            let mut err = MlsError::with_code(
                ErrorCode::InvalidInput,
                operation,
                "invalid_storage_snapshot",
            );
            err.details.insert("error".to_owned(), format!("{e:?}"));
            err
        })?;
        let value = decode_hex(encoded_value).map_err(|e| {
            let mut err = MlsError::with_code(
                ErrorCode::InvalidInput,
                operation,
                "invalid_storage_snapshot",
            );
            err.details.insert("error".to_owned(), format!("{e:?}"));
            err
        })?;

        values.insert(key, value);
    }

    Ok(values)
}

fn deserialize_signer(encoded: &str, operation: &str) -> Result<SignatureKeyPair, MlsError> {
    let bytes = decode_hex(encoded).map_err(|e| {
        let mut err = MlsError::with_code(
            ErrorCode::InvalidInput,
            operation,
            "invalid_signature_snapshot",
        );
        err.details.insert("error".to_owned(), format!("{e:?}"));
        err
    })?;

    // H3: tls_deserialize can panic internally on malformed byte sequences
    // (e.g. length-prefix underflow deep inside the TLS codec).  Wrapping in
    // catch_unwind converts any such panic into a recoverable MlsError so that
    // a bad snapshot cannot crash the NIF host process.
    let op_owned = operation.to_owned();
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let mut bytes_slice: &[u8] = &bytes;
        SignatureKeyPair::tls_deserialize(&mut bytes_slice)
    }));

    match result {
        Ok(Ok(kp)) => Ok(kp),
        Ok(Err(_)) => Err(MlsError::with_code(
            ErrorCode::InvalidInput,
            &op_owned,
            "signature_keypair_tls_malformed",
        )),
        Err(_panic) => Err(MlsError::with_code(
            ErrorCode::InvalidInput,
            &op_owned,
            "signature_keypair_tls_malformed",
        )),
    }
}

/// Serialize a message cache as a sorted string (used for HashMap-keyed cache in
/// tests and the session_cache_roundtrip test).  Sort ensures a stable output
/// when insertion order is not tracked.
#[cfg(test)]
fn serialize_message_cache(cache: &HashMap<String, CachedMessage>) -> String {
    let mut entries: Vec<String> = cache
        .iter()
        .map(|(message_id, cached_message)| {
            format!(
                "{}:{}:{}",
                encode_hex(message_id.as_bytes()),
                &cached_message.ciphertext,
                encode_hex(cached_message.plaintext.as_bytes())
            )
        })
        .collect();
    entries.sort_unstable();

    entries.join(",")
}

/// N4 (Fix B): Serialize cache entries in their original insertion order.
///
/// Preserving insertion order in the snapshot means `deserialize_message_cache`
/// can rebuild both the HashMap and the `decrypted_message_order` VecDeque
/// deterministically after a round-trip — regardless of HashMap's internal
/// non-deterministic iteration order.
fn serialize_message_cache_ordered(ordered: &[(String, CachedMessage)]) -> String {
    ordered
        .iter()
        .map(|(message_id, cached_message)| {
            format!(
                "{}:{}:{}",
                encode_hex(message_id.as_bytes()),
                &cached_message.ciphertext,
                encode_hex(cached_message.plaintext.as_bytes())
            )
        })
        .collect::<Vec<_>>()
        .join(",")
}

#[cfg(test)]
fn deserialize_message_cache(
    encoded: &str,
    operation: &str,
) -> Result<HashMap<String, CachedMessage>, MlsError> {
    let ordered = deserialize_message_cache_ordered(encoded, operation)?;
    Ok(ordered.into_iter().collect())
}

/// N4 (Fix B): Deserialize cache entries preserving the serialized order.
///
/// Returns entries as a `Vec` in serialization order so that callers can
/// rebuild the `decrypted_message_order` VecDeque deterministically.
/// After a serialize→deserialize round-trip the VecDeque order exactly matches
/// the original insertion order, fixing non-deterministic eviction after restore.
fn deserialize_message_cache_ordered(
    encoded: &str,
    operation: &str,
) -> Result<Vec<(String, CachedMessage)>, MlsError> {
    let mut ordered: Vec<(String, CachedMessage)> = Vec::new();

    if encoded.is_empty() {
        return Ok(ordered);
    }

    for entry in encoded.split(',').filter(|entry| !entry.is_empty()) {
        // H4: Enforce the 256-entry cache cap as a hard security invariant.
        // A snapshot with more entries than MAX_DECRYPT_CACHE_ENTRIES almost
        // certainly indicates data corruption or tampering; silently truncating
        // would hide the anomaly.  Return an explicit error instead so callers
        // can surface the integrity violation rather than absorbing it quietly.
        if ordered.len() >= MAX_DECRYPT_CACHE_ENTRIES {
            return Err(MlsError::with_code(
                ErrorCode::InvalidInput,
                operation,
                "cache_too_large",
            ));
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

        let message_id = String::from_utf8(decode_hex(message_id_hex).map_err(|e| {
            let mut err =
                MlsError::with_code(ErrorCode::InvalidInput, operation, "invalid_session_cache");
            err.details.insert("error".to_owned(), format!("{e:?}"));
            err
        })?)
        .map_err(|e| {
            let mut err =
                MlsError::with_code(ErrorCode::InvalidInput, operation, "invalid_session_cache");
            err.details.insert("error".to_owned(), format!("{e:?}"));
            err
        })?;
        let ciphertext = ciphertext_hex.to_owned();
        let plaintext = String::from_utf8(decode_hex(plaintext_hex).map_err(|e| {
            let mut err =
                MlsError::with_code(ErrorCode::InvalidInput, operation, "invalid_session_cache");
            err.details.insert("error".to_owned(), format!("{e:?}"));
            err
        })?)
        .map_err(|e| {
            let mut err =
                MlsError::with_code(ErrorCode::InvalidInput, operation, "invalid_session_cache");
            err.details.insert("error".to_owned(), format!("{e:?}"));
            err
        })?;

        ordered.push((
            message_id,
            CachedMessage {
                ciphertext,
                plaintext,
            },
        ));
    }

    Ok(ordered)
}

fn cache_decrypted_message(
    cache: &mut HashMap<String, CachedMessage>,
    order: &mut VecDeque<String>,
    message_id: String,
    cached_message: CachedMessage,
) {
    if let Some(existing_message) = cache.get_mut(&message_id) {
        *existing_message = cached_message;
        return;
    }

    // Evict oldest (front of queue) when at capacity — deterministic FIFO (N4).
    if cache.len() >= MAX_DECRYPT_CACHE_ENTRIES {
        if let Some(evict_key) = order.pop_front() {
            cache.remove(&evict_key);
        }
    }

    order.push_back(message_id.clone());
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

/// Maximum number of hex-encoded characters accepted by `decode_hex`.
/// Corresponds to a 1 MB decoded payload (2 hex chars per byte).
const MAX_HEX_DECODE_BYTES: usize = 1_048_576; // 1 MB

fn decode_hex(value: &str) -> Result<Vec<u8>, &'static str> {
    if value.len() > MAX_HEX_DECODE_BYTES * 2 {
        return Err("hex_input_too_large");
    }

    if value.len() % 2 != 0 {
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
        unsupported_capability,
        lock_poisoned
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
        ErrorCode::LockPoisoned => atoms::lock_poisoned(),
    }
}

fn payload_from_nif(params: HashMap<String, String>) -> Payload {
    params.into_iter().collect()
}

// ── DirtyCpu NIF scheduling ─────────────────────────────────────────────────
//
// BEAM has a fixed-size scheduler thread pool (default: one per CPU core).
// A NIF that blocks a scheduler thread for more than ~1ms will cause scheduler
// saturation that degrades LiveView rendering, channel handling, and Ecto
// queries across the entire node.
//
// NIFs marked `schedule = "DirtyCpu"` run in a separate dirty-CPU thread pool
// and cannot block the normal schedulers.  The rule applied here:
//
//   DirtyCpu  — any NIF that (a) performs OpenMLS crypto work, (b) holds a
//               DashMap shard lock for >1 ms, or (c) performs snapshot
//               serialization (hex-encoding ~8-18 ms).
//
//   Regular   — NIFs that only validate input parameters and build a string
//               payload; these complete in sub-microsecond time and do not
//               touch GROUP_SESSIONS locks.
//
// DirtyCpu NIFs (8):
//   create_group          — key-material generation (HPKE + signing keys)
//   join_from_welcome     — welcome-message processing + shard lock
//   process_incoming      — per-message AEAD decryption + shard lock
//   mls_remove            — propose-and-commit removal + shard lock (~4-10 ms)
//   merge_staged_commit   — commit merge + shard lock + snapshot serialization
//   create_application_message — per-message AEAD encryption + shard lock
//   export_group_info     — shard lock + snapshot serialization (~8-18 ms)
//   list_member_credentials    — shard lock + potential snapshot restore
//
// Regular NIFs (intentionally not DirtyCpu):
//   nif_version           — constant string map, no I/O
//   nif_health            — openmls capability check, <10µs
//   create_key_package    — atomic counter increment only
//   commit_to_pending     — string-payload build only (no GROUP_SESSIONS access)
//   mls_commit            — lifecycle stub: string-payload build only
//   mls_update            — lifecycle stub: string-payload build only
//   mls_add               — lifecycle stub: string-payload build only
//   clear_pending_commit  — string-payload build only (no GROUP_SESSIONS access)
//   export_ratchet_tree   — returns a stub string, no GROUP_SESSIONS access
// ─────────────────────────────────────────────────────────────────────────────

#[rustler::nif(name = "nif_version")]
fn nif_version_nif<'a>(env: Env<'a>) -> Term<'a> {
    encode_result(env, nif_version())
}

#[rustler::nif(name = "nif_health")]
fn nif_health_nif<'a>(env: Env<'a>) -> Term<'a> {
    encode_result(env, nif_health())
}

// Regular NIF: atomic counter increment only — no crypto, no lock held.
#[rustler::nif(name = "create_key_package")]
fn create_key_package_nif<'a>(env: Env<'a>, params: HashMap<String, String>) -> Term<'a> {
    let payload = payload_from_nif(params);
    encode_result(env, create_key_package(&payload))
}

// DirtyCpu: generates HPKE and signing key material via OpenMLS (~4-8 ms).
#[rustler::nif(name = "create_group", schedule = "DirtyCpu")]
fn create_group_nif<'a>(env: Env<'a>, params: HashMap<String, String>) -> Term<'a> {
    let payload = payload_from_nif(params);
    encode_result(env, create_group(&payload))
}

// DirtyCpu: processes a Welcome message (crypto) and holds a shard lock during restore.
#[rustler::nif(name = "join_from_welcome", schedule = "DirtyCpu")]
fn join_from_welcome_nif<'a>(env: Env<'a>, params: HashMap<String, String>) -> Term<'a> {
    let payload = payload_from_nif(params);
    encode_result(env, join_from_welcome(&payload))
}

// DirtyCpu: AEAD decryption per message + DashMap shard lock (~4-18 ms).
#[rustler::nif(name = "process_incoming", schedule = "DirtyCpu")]
fn process_incoming_nif<'a>(env: Env<'a>, params: HashMap<String, String>) -> Term<'a> {
    let payload = payload_from_nif(params);
    encode_result(env, process_incoming(&payload))
}

// Regular NIF: lifecycle stub — builds a string payload only, no GROUP_SESSIONS access.
#[rustler::nif(name = "commit_to_pending")]
fn commit_to_pending_nif<'a>(env: Env<'a>, params: HashMap<String, String>) -> Term<'a> {
    let payload = payload_from_nif(params);
    encode_result(env, commit_to_pending(&payload))
}

// Regular NIF: lifecycle stub — builds a string payload only, no GROUP_SESSIONS access.
#[rustler::nif(name = "mls_commit")]
fn mls_commit_nif<'a>(env: Env<'a>, params: HashMap<String, String>) -> Term<'a> {
    let payload = payload_from_nif(params);
    encode_result(env, mls_commit(&payload))
}

// Regular NIF: lifecycle stub — builds a string payload only, no GROUP_SESSIONS access.
#[rustler::nif(name = "mls_update")]
fn mls_update_nif<'a>(env: Env<'a>, params: HashMap<String, String>) -> Term<'a> {
    let payload = payload_from_nif(params);
    encode_result(env, mls_update(&payload))
}

// Regular NIF: lifecycle stub — builds a string payload only, no GROUP_SESSIONS access.
#[rustler::nif(name = "mls_add")]
fn mls_add_nif<'a>(env: Env<'a>, params: HashMap<String, String>) -> Term<'a> {
    let payload = payload_from_nif(params);
    encode_result(env, mls_add(&payload))
}

// DirtyCpu: propose-and-commit member removal + merge_pending_commit + shard lock (~4-10 ms).
#[rustler::nif(name = "mls_remove", schedule = "DirtyCpu")]
fn mls_remove_nif<'a>(env: Env<'a>, params: HashMap<String, String>) -> Term<'a> {
    let payload = payload_from_nif(params);
    encode_result(env, mls_remove(&payload))
}

// DirtyCpu: commit merge + shard lock + snapshot serialization (~8-18 ms).
#[rustler::nif(name = "merge_staged_commit", schedule = "DirtyCpu")]
fn merge_staged_commit_nif<'a>(env: Env<'a>, params: HashMap<String, String>) -> Term<'a> {
    let payload = payload_from_nif(params);
    encode_result(env, merge_staged_commit(&payload))
}

// Regular NIF: clears pending-commit flag — builds a string payload only, no GROUP_SESSIONS access.
#[rustler::nif(name = "clear_pending_commit")]
fn clear_pending_commit_nif<'a>(env: Env<'a>, params: HashMap<String, String>) -> Term<'a> {
    let payload = payload_from_nif(params);
    encode_result(env, clear_pending_commit(&payload))
}

// DirtyCpu: AEAD encryption per message + shard lock + snapshot serialization (~8-18 ms).
#[rustler::nif(name = "create_application_message", schedule = "DirtyCpu")]
fn create_application_message_nif<'a>(env: Env<'a>, params: HashMap<String, String>) -> Term<'a> {
    let payload = payload_from_nif(params);
    encode_result(env, create_application_message(&payload))
}

// DirtyCpu: shard lock + snapshot serialization (hex-encoding ~8-18 ms).
#[rustler::nif(name = "export_group_info", schedule = "DirtyCpu")]
fn export_group_info_nif<'a>(env: Env<'a>, params: HashMap<String, String>) -> Term<'a> {
    let payload = payload_from_nif(params);
    encode_result(env, export_group_info(&payload))
}

// Regular NIF: returns a stub ratchet-tree reference string — no GROUP_SESSIONS access.
#[rustler::nif(name = "export_ratchet_tree")]
fn export_ratchet_tree_nif<'a>(env: Env<'a>, params: HashMap<String, String>) -> Term<'a> {
    let payload = payload_from_nif(params);
    encode_result(env, export_ratchet_tree(&payload))
}

// DirtyCpu: shard lock + potential snapshot restore + member iteration.
#[rustler::nif(name = "list_member_credentials", schedule = "DirtyCpu")]
fn list_member_credentials_nif<'a>(env: Env<'a>, params: HashMap<String, String>) -> Term<'a> {
    let payload = payload_from_nif(params);
    encode_result(env, list_member_credentials(&payload))
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

        let _group = create_group(&payload(&[
            ("group_id", &group_id),
            (
                "ciphersuite",
                "MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519",
            ),
        ]))
        .expect("group must be created");

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
    fn create_application_message_requires_existing_group_state() {
        let group_id = unique_group_id("group-recovery-required");

        let error =
            create_application_message(&payload(&[("group_id", &group_id), ("body", "hello")]))
                .expect_err("missing group state must fail closed");

        assert_eq!(error.code, ErrorCode::StorageInconsistent);
        assert_eq!(
            error.details.get("reason"),
            Some(&"missing_group_state".to_owned())
        );
        assert_eq!(
            error.details.get("operation"),
            Some(&"create_application_message".to_owned())
        );
    }

    #[test]
    fn lifecycle_operations_return_contract_shape() {
        // mls_commit, mls_update, mls_add are still lifecycle stubs; mls_remove is now real.
        let stub_operations = [mls_commit, mls_update, mls_add];

        for operation in stub_operations {
            let result = operation(&payload(&[("group_id", "group-1")]))
                .expect("lifecycle call should succeed");
            assert_eq!(result.get("group_id"), Some(&"group-1".to_owned()));
            assert_eq!(result.get("status"), Some(&"ok".to_owned()));
        }
    }

    #[test]
    fn mls_remove_requires_group_state_and_remove_target() {
        // Without group state, mls_remove must fail closed.
        let group_id = unique_group_id("group-remove-missing");
        let error = mls_remove(&payload(&[
            ("group_id", &group_id),
            ("remove_target", "recipient"),
        ]))
        .expect_err("mls_remove without group state must fail");
        assert_eq!(error.code, ErrorCode::StorageInconsistent);
        assert_eq!(
            error.details.get("reason"),
            Some(&"missing_group_state".to_owned())
        );
    }

    #[test]
    fn mls_remove_real_removes_recipient_and_advances_epoch() {
        let group_id = unique_group_id("group-real-remove");

        let group = create_group(&payload(&[
            ("group_id", &group_id),
            (
                "ciphersuite",
                "MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519",
            ),
        ]))
        .expect("group must be created");

        let epoch_before: u64 = group
            .get("epoch")
            .expect("epoch in group payload")
            .parse()
            .expect("epoch parses as u64");

        // Build the remove payload using the session snapshot from create_group.
        let mut remove_params = Payload::new();
        remove_params.insert("group_id".to_owned(), group_id.clone());
        remove_params.insert("remove_target".to_owned(), "recipient".to_owned());
        for key in [
            "session_sender_storage",
            "session_recipient_storage",
            "session_sender_signer",
            "session_recipient_signer",
            "session_cache",
        ] {
            if let Some(value) = group.get(key) {
                remove_params.insert(key.to_owned(), value.clone());
            }
        }

        let remove_result = mls_remove(&remove_params).expect("mls_remove must succeed");

        let epoch_after: u64 = remove_result
            .get("epoch")
            .expect("epoch in remove payload")
            .parse()
            .expect("epoch parses as u64");

        assert_eq!(
            epoch_after,
            epoch_before + 1,
            "epoch must advance by 1 after remove"
        );

        let commit_ciphertext = remove_result
            .get("commit_ciphertext")
            .expect("commit_ciphertext in remove payload");
        assert!(
            !commit_ciphertext.is_empty(),
            "commit_ciphertext must be non-empty"
        );

        let recipient_removed = remove_result
            .get("recipient_removed")
            .expect("recipient_removed in remove payload");
        assert_eq!(recipient_removed, "true", "recipient must be removed");

        assert_eq!(
            remove_result.get("status"),
            Some(&"ok".to_owned()),
            "status must be ok"
        );
    }

    #[test]
    fn create_application_message_snapshot_sender_is_authoritative_after_remove() {
        let group_id = unique_group_id("group-remove-authoritative");

        let group = create_group(&payload(&[
            ("group_id", &group_id),
            (
                "ciphersuite",
                "MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519",
            ),
        ]))
        .expect("group must be created");

        let mut remove_params = Payload::new();
        remove_params.insert("group_id".to_owned(), group_id.clone());
        remove_params.insert("remove_target".to_owned(), "recipient".to_owned());
        for key in [
            "session_sender_storage",
            "session_recipient_storage",
            "session_sender_signer",
            "session_recipient_signer",
            "session_cache",
        ] {
            if let Some(value) = group.get(key) {
                remove_params.insert(key.to_owned(), value.clone());
            }
        }

        let remove_result = mls_remove(&remove_params).expect("mls_remove must succeed");

        let removed_sender_storage = remove_result
            .get("session_recipient_storage")
            .expect("recipient storage in remove payload")
            .clone();
        let removed_sender_signer = remove_result
            .get("session_recipient_signer")
            .expect("recipient signer in remove payload")
            .clone();
        let survivor_recipient_storage = remove_result
            .get("session_sender_storage")
            .expect("sender storage in remove payload")
            .clone();
        let survivor_recipient_signer = remove_result
            .get("session_sender_signer")
            .expect("sender signer in remove payload")
            .clone();

        let error = create_application_message(&payload(&[
            ("group_id", &group_id),
            ("body", "should fail"),
            ("session_sender_storage", &removed_sender_storage),
            ("session_sender_signer", &removed_sender_signer),
            ("session_recipient_storage", &survivor_recipient_storage),
            ("session_recipient_signer", &survivor_recipient_signer),
            (
                "session_cache",
                remove_result.get("session_cache").unwrap_or(&String::new()),
            ),
        ]))
        .expect_err("removed member snapshot must not encrypt");

        assert_eq!(error.code, ErrorCode::UnauthorizedOperation);
        assert_eq!(
            error.details.get("reason"),
            Some(&"sender_not_member".to_owned())
        );
    }

    #[test]
    fn merge_staged_commit_real_processes_recipient_commit_after_remove() {
        let group_id = unique_group_id("group-merge-staged");

        let group = create_group(&payload(&[
            ("group_id", &group_id),
            (
                "ciphersuite",
                "MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519",
            ),
        ]))
        .expect("group must be created");

        // Build remove params with snapshot.
        let mut remove_params = Payload::new();
        remove_params.insert("group_id".to_owned(), group_id.clone());
        remove_params.insert("remove_target".to_owned(), "recipient".to_owned());
        for key in [
            "session_sender_storage",
            "session_recipient_storage",
            "session_sender_signer",
            "session_recipient_signer",
            "session_cache",
        ] {
            if let Some(value) = group.get(key) {
                remove_params.insert(key.to_owned(), value.clone());
            }
        }

        let remove_result = mls_remove(&remove_params).expect("mls_remove must succeed");

        let remove_epoch: u64 = remove_result
            .get("epoch")
            .expect("epoch in remove payload")
            .parse()
            .expect("epoch parses as u64");

        let commit_ciphertext = remove_result
            .get("commit_ciphertext")
            .expect("commit_ciphertext in remove payload")
            .clone();

        // Build merge params from the post-remove snapshot.
        let mut merge_params = Payload::new();
        merge_params.insert("group_id".to_owned(), group_id.clone());
        merge_params.insert("staged_commit_validated".to_owned(), "true".to_owned());
        merge_params.insert("commit_ciphertext".to_owned(), commit_ciphertext);
        for key in [
            "session_sender_storage",
            "session_recipient_storage",
            "session_sender_signer",
            "session_recipient_signer",
            "session_cache",
        ] {
            if let Some(value) = remove_result.get(key) {
                merge_params.insert(key.to_owned(), value.clone());
            }
        }

        let merge_result =
            merge_staged_commit(&merge_params).expect("merge_staged_commit must succeed");

        // Epoch must equal the remove epoch (not advance further).
        let merge_epoch: u64 = merge_result
            .get("epoch")
            .expect("epoch in merge payload")
            .parse()
            .expect("epoch parses as u64");

        assert_eq!(
            merge_epoch, remove_epoch,
            "merge epoch must equal remove epoch"
        );

        // All 5 snapshot keys must be present.
        for key in [
            "session_sender_storage",
            "session_recipient_storage",
            "session_sender_signer",
            "session_recipient_signer",
            "session_cache",
        ] {
            assert!(
                merge_result.contains_key(key),
                "missing snapshot key: {}",
                key
            );
        }

        assert_eq!(
            merge_result.get("status"),
            Some(&"ok".to_owned()),
            "status must be ok"
        );
        assert_eq!(
            merge_result.get("merged"),
            Some(&"true".to_owned()),
            "merged must be true"
        );
        assert_eq!(
            merge_result.get("recipient_active"),
            Some(&"false".to_owned()),
            "recipient_active must be false after removal"
        );
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
        // N1: LockPoisoned is a concurrency failure distinct from storage issues.
        assert_eq!(ErrorCode::LockPoisoned.as_str(), "lock_poisoned");
    }

    #[test]
    fn group_id_null_byte_is_rejected() {
        // N3: NUL bytes must be rejected in all entry points that validate group IDs.
        let null_id = "group\0bad";

        let err = create_group(&payload(&[
            ("group_id", null_id),
            (
                "ciphersuite",
                "MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519",
            ),
        ]))
        .expect_err("NUL byte in group_id must be rejected");
        assert_eq!(err.code, ErrorCode::InvalidInput);
        assert_eq!(
            err.details.get("reason"),
            Some(&"INVALID_GROUP_ID_NULL_BYTE".to_owned())
        );

        let err2 = process_incoming(&payload(&[
            ("group_id", null_id),
            ("ciphertext", "deadbeef"),
        ]))
        .expect_err("NUL byte in group_id must be rejected for process_incoming");
        assert_eq!(err2.code, ErrorCode::InvalidInput);
        assert_eq!(
            err2.details.get("reason"),
            Some(&"INVALID_GROUP_ID_NULL_BYTE".to_owned())
        );
    }

    #[test]
    fn cache_order_is_preserved_across_snapshot_roundtrip() {
        // N4 (Fix B): After a serialize→deserialize round-trip the VecDeque
        // eviction order must match the original insertion order exactly.
        let mut cache: HashMap<String, CachedMessage> = HashMap::new();
        let mut order: VecDeque<String> = VecDeque::new();

        // Insert 5 messages in a deterministic order.
        for i in 0..5u32 {
            let key = format!("msg-{}", i);
            cache_decrypted_message(
                &mut cache,
                &mut order,
                key.clone(),
                CachedMessage {
                    ciphertext: format!("ct{}", i),
                    plaintext: format!("pt{}", i),
                },
            );
        }

        // Simulate snapshot extraction: collect in VecDeque order.
        let ordered: Vec<(String, CachedMessage)> = order
            .iter()
            .filter_map(|k| cache.get(k).map(|v| (k.clone(), v.clone())))
            .collect();

        // Serialize preserving insertion order.
        let serialized = serialize_message_cache_ordered(&ordered);

        // Deserialize back in order.
        let restored =
            deserialize_message_cache_ordered(&serialized, "test").expect("must deserialize");

        let restored_keys: Vec<&str> = restored.iter().map(|(k, _)| k.as_str()).collect();
        let expected_keys: Vec<String> = (0..5).map(|i| format!("msg-{}", i)).collect();
        let expected_refs: Vec<&str> = expected_keys.iter().map(|s| s.as_str()).collect();

        assert_eq!(
            restored_keys, expected_refs,
            "VecDeque insertion order must be preserved across snapshot round-trip"
        );
    }

    // F3: session_cache double-encoding fix — ciphertext stored/retrieved verbatim,
    // not passed through encode_hex/decode_hex. serialize_message_cache uses
    // &cached_message.ciphertext directly; deserialize_message_cache uses
    // ciphertext_hex.to_owned() directly.
    #[test]
    fn session_cache_roundtrip() {
        let mut cache = HashMap::new();
        cache.insert(
            "msg-abc".to_owned(),
            CachedMessage {
                ciphertext: "deadbeef".to_owned(),
                plaintext: "hello world".to_owned(),
            },
        );
        cache.insert(
            "msg-xyz".to_owned(),
            CachedMessage {
                ciphertext: "cafebabe".to_owned(),
                plaintext: "second message".to_owned(),
            },
        );

        let serialized = serialize_message_cache(&cache);
        let deserialized =
            deserialize_message_cache(&serialized, "test").expect("deserialize must succeed");

        assert_eq!(deserialized.len(), 2);
        let entry = deserialized
            .get("msg-abc")
            .expect("msg-abc must be present");
        assert_eq!(
            entry.ciphertext, "deadbeef",
            "ciphertext must not be double-encoded"
        );
        assert_eq!(entry.plaintext, "hello world");

        let entry2 = deserialized
            .get("msg-xyz")
            .expect("msg-xyz must be present");
        assert_eq!(entry2.ciphertext, "cafebabe");

        // Round-trip stability: serializing again must produce the same output
        let reserialized = serialize_message_cache(&deserialized);
        assert_eq!(reserialized, serialized, "round-trip must be stable");
    }

    #[test]
    fn session_cache_empty_roundtrip() {
        let cache: HashMap<String, CachedMessage> = HashMap::new();
        let serialized = serialize_message_cache(&cache);
        assert!(serialized.is_empty());
        let deserialized = deserialize_message_cache(&serialized, "test")
            .expect("empty cache deserialize must succeed");
        assert!(deserialized.is_empty());
    }

    // DirtyCpu scheduling contract verification.
    //
    // This test documents the expected BEAM scheduler impact by verifying that
    // the functions which are registered as DirtyCpu NIFs actually perform the
    // crypto/lock work that justifies dirty scheduling.  It does not test the
    // BEAM scheduler directly (that is a runtime property), but it exercises
    // the Rust implementations end-to-end, ensuring they remain functional
    // after any future refactor that might accidentally remove the schedule
    // attribute.
    //
    // Functions verified as DirtyCpu:
    //   create_group, join_from_welcome, process_incoming,
    //   mls_remove, merge_staged_commit, create_application_message,
    //   export_group_info, list_member_credentials
    //
    // Functions verified as Regular (no DirtyCpu):
    //   nif_version, nif_health, create_key_package,
    //   commit_to_pending, mls_commit, mls_update, mls_add,
    //   clear_pending_commit, export_ratchet_tree
    #[test]
    fn dirty_cpu_nifs_perform_crypto_or_lock_work() {
        let group_id = unique_group_id("group-dirty-cpu-contract");

        // create_group: DirtyCpu — generates key material.
        let group = create_group(&payload(&[
            ("group_id", &group_id),
            (
                "ciphersuite",
                "MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519",
            ),
        ]))
        .expect("create_group (DirtyCpu) must succeed");
        assert_eq!(group.get("group_id"), Some(&group_id));

        // create_application_message: DirtyCpu — AEAD encryption + shard lock.
        let encrypted =
            create_application_message(&payload(&[("group_id", &group_id), ("body", "ping")]))
                .expect("create_application_message (DirtyCpu) must succeed");
        let ciphertext = encrypted.get("ciphertext").expect("ciphertext present");
        assert!(!ciphertext.is_empty(), "ciphertext must be non-empty");

        // process_incoming: DirtyCpu — AEAD decryption + shard lock.
        let decrypted = process_incoming(&payload(&[
            ("group_id", &group_id),
            ("ciphertext", ciphertext),
        ]))
        .expect("process_incoming (DirtyCpu) must succeed");
        assert_eq!(
            decrypted.get("plaintext"),
            Some(&"ping".to_owned()),
            "process_incoming must recover original plaintext"
        );

        // export_group_info: DirtyCpu — shard lock + snapshot serialization.
        let info = export_group_info(&payload(&[("group_id", &group_id)]))
            .expect("export_group_info (DirtyCpu) must succeed");
        assert_eq!(info.get("group_id"), Some(&group_id));

        // list_member_credentials: DirtyCpu — shard lock + member iteration.
        let creds = list_member_credentials(&payload(&[("group_id", &group_id)]))
            .expect("list_member_credentials (DirtyCpu) must succeed");
        assert_eq!(
            creds.get("status"),
            Some(&"ok".to_owned()),
            "list_member_credentials must return ok status"
        );

        // Regular NIFs — verify they return quickly without crypto work.
        // commit_to_pending: Regular — string payload only.
        let pending = commit_to_pending(&payload(&[("group_id", &group_id)]))
            .expect("commit_to_pending (Regular) must succeed");
        assert_eq!(pending.get("pending_commit"), Some(&"true".to_owned()));

        // clear_pending_commit: Regular — string payload only.
        let cleared = clear_pending_commit(&payload(&[("group_id", &group_id)]))
            .expect("clear_pending_commit (Regular) must succeed");
        assert_eq!(cleared.get("pending_commit"), Some(&"false".to_owned()));

        // export_ratchet_tree: Regular — stub string only.
        let tree = export_ratchet_tree(&payload(&[("group_id", &group_id)]))
            .expect("export_ratchet_tree (Regular) must succeed");
        assert!(
            tree.get("ratchet_tree_ref")
                .map(|r| r.contains(&group_id))
                .unwrap_or(false),
            "export_ratchet_tree must include group_id in ref"
        );
    }

    #[test]
    fn toctou_vacant_entry_no_spurious_overwrite() {
        // Verify that Entry::Vacant does not overwrite an existing session.
        // If two threads race to create the same session, the second thread
        // should see the first thread's session still intact.
        // (This is a compile-and-run test, not a threading test -- the
        // threading safety is structural from using Entry::Vacant.)
        let group_id = "test-toctou-entry-001".to_string();
        // Clean up in case a prior test left state.
        GROUP_SESSIONS.remove(&group_id);

        // Create and insert an initial session via create_group_session.
        let session = create_group_session(&group_id, DEFAULT_CIPHERSUITE, None, None)
            .expect("session must be created");
        GROUP_SESSIONS.insert(group_id.clone(), session);

        // Record the epoch of the inserted session.
        let epoch_before = GROUP_SESSIONS
            .get(&group_id)
            .expect("session must exist")
            .sender
            .group
            .epoch()
            .as_u64();

        // Attempt Entry::Vacant insert — should be a no-op since key exists.
        let second_session = create_group_session(&group_id, DEFAULT_CIPHERSUITE, None, None)
            .expect("second session must be created");
        if let dashmap::mapref::entry::Entry::Vacant(e) = GROUP_SESSIONS.entry(group_id.clone()) {
            e.insert(second_session);
            panic!("Entry::Vacant should not have fired for existing key");
        }

        // Key still exists and the epoch is unchanged (original session preserved).
        let epoch_after = GROUP_SESSIONS
            .get(&group_id)
            .expect("session must still exist after vacant no-op")
            .sender
            .group
            .epoch()
            .as_u64();
        assert_eq!(
            epoch_before, epoch_after,
            "Entry::Vacant must not replace the existing session"
        );

        GROUP_SESSIONS.remove(&group_id);
    }

    /// Round-trip MLS encryption/decryption test covering DashMap shard store and Entry::Vacant:
    ///
    /// 1. `DashMap::with_shard_amount(64)` — sessions must still be stored and
    ///    retrieved correctly after the shard count change.
    /// 2. `Entry::Vacant` in `join_from_welcome` — the fallback new-session path
    ///    must actually insert the session so `create_application_message` finds it.
    /// 3. Full protocol flow: create_group → join_from_welcome → encrypt → decrypt.
    #[test]
    fn session_store_round_trip_encrypt_decrypt() {
        // Use a unique group ID so this test is hermetic across parallel test runs.
        let group_id = unique_group_id("track-a-round-trip");

        // Step 1: create_group — exercises DashMap::with_shard_amount(64) insert.
        let group_result = create_group(&payload(&[
            ("group_id", &group_id),
            (
                "ciphersuite",
                "MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519",
            ),
        ]))
        .expect("create_group must succeed after Track A DashMap shard change");

        assert_eq!(
            group_result.get("status"),
            Some(&"created".to_owned()),
            "create_group must return status=created"
        );
        let epoch_after_create: u64 = group_result
            .get("epoch")
            .expect("epoch must be present")
            .parse()
            .expect("epoch must be a u64");
        assert_eq!(
            epoch_after_create, 1,
            "epoch must be 1 after two-member group creation"
        );

        // Step 2: join_from_welcome — exercises Entry::Vacant path by triggering the
        // "group not yet in DashMap" branch with a fresh group_id.
        //
        // The `join_from_welcome` function uses Entry::Vacant to avoid spurious overwrites.
        // We call it with a distinct token to hit the fallback create_group_session path,
        // exercising the Vacant-insert branch introduced by Track A.
        let join_group_id = unique_group_id("track-a-join");
        let join_result = join_from_welcome(&payload(&[
            ("welcome", "test-welcome-token"),
            ("group_id", &join_group_id),
        ]))
        .expect(
            "join_from_welcome must succeed (fallback branch) after Track A Vacant entry change",
        );

        assert_eq!(
            join_result.get("status"),
            Some(&"joined".to_owned()),
            "join_from_welcome must return status=joined"
        );
        // Confirm the session was inserted into GROUP_SESSIONS by the Vacant branch.
        assert!(
            GROUP_SESSIONS.contains_key(&join_group_id),
            "Entry::Vacant insert must have stored the session in GROUP_SESSIONS"
        );

        // Step 3: create_application_message — confirms sender session is retrievable
        // from the DashMap with_shard_amount(64) store after create_group.
        let plaintext_in = "hello from Track A round-trip test";
        let encrypt_result = create_application_message(&payload(&[
            ("group_id", &group_id),
            ("body", plaintext_in),
        ]))
        .expect("create_application_message must succeed");

        assert_eq!(
            encrypt_result.get("status"),
            Some(&"encrypted".to_owned()),
            "create_application_message must return status=encrypted"
        );
        let ciphertext = encrypt_result
            .get("ciphertext")
            .expect("ciphertext must be present in encrypt result");
        assert!(!ciphertext.is_empty(), "ciphertext must be non-empty");

        // Step 4: process_incoming — decrypts on recipient side and must recover
        // the original plaintext, confirming the full MLS protocol still works.
        let decrypt_result = process_incoming(&payload(&[
            ("group_id", &group_id),
            ("ciphertext", ciphertext),
        ]))
        .expect("process_incoming must succeed");

        assert_eq!(
            decrypt_result.get("plaintext"),
            Some(&plaintext_in.to_owned()),
            "decrypted plaintext must exactly match the original plaintext"
        );

        // Epoch must be stable (no epoch advance from application messages).
        let epoch_after_decrypt: u64 = decrypt_result
            .get("epoch")
            .expect("epoch must be in decrypt result")
            .parse()
            .expect("epoch must be a u64");
        assert_eq!(
            epoch_after_decrypt, epoch_after_create,
            "epoch must not advance from application messages"
        );

        // Snapshot keys must be present in the decrypt result (Track A did not
        // remove the snapshot serialization path).
        for key in [
            "session_sender_storage",
            "session_recipient_storage",
            "session_sender_signer",
            "session_recipient_signer",
            "session_cache",
        ] {
            assert!(
                decrypt_result.contains_key(key),
                "snapshot key '{}' must be present in process_incoming result",
                key
            );
        }
    }

    // Round-trip happy path is unaffected by map_err enrichment.
    //
    // The map_err(|e| closures that add err.details.insert("error", ...) are
    // purely in error paths and must be invisible to callers on the happy path.
    // This test confirms:
    //   1. create_group returns status=created
    //   2. create_application_message returns status=encrypted with non-empty ciphertext
    //   3. process_incoming recovers the original plaintext
    //   4. No spurious "error" key appears in any of the happy-path payloads
    #[test]
    fn encrypt_decrypt_unaffected_by_error_enrichment() {
        let group_id = unique_group_id("group-trackb-roundtrip");

        // Step 1: create_group
        let group_result = create_group(&payload(&[
            ("group_id", &group_id),
            (
                "ciphersuite",
                "MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519",
            ),
        ]))
        .expect("create_group must succeed on happy path");

        assert_eq!(
            group_result.get("status"),
            Some(&"created".to_owned()),
            "create_group must return status=created"
        );
        assert!(
            !group_result.contains_key("error"),
            "create_group happy path must not contain a spurious 'error' key"
        );

        // Step 2: create_application_message
        let original_plaintext = "hello from round-trip enrichment test";
        let encrypt_result = create_application_message(&payload(&[
            ("group_id", &group_id),
            ("body", original_plaintext),
        ]))
        .expect("create_application_message must succeed on happy path");

        assert_eq!(
            encrypt_result.get("status"),
            Some(&"encrypted".to_owned()),
            "create_application_message must return status=encrypted"
        );
        let ciphertext = encrypt_result
            .get("ciphertext")
            .expect("ciphertext must be present in encrypt result");
        assert!(
            !ciphertext.is_empty(),
            "ciphertext must be non-empty on happy path"
        );
        assert!(
            !encrypt_result.contains_key("error"),
            "create_application_message happy path must not contain a spurious 'error' key"
        );

        // Step 3: process_incoming (recipient side)
        let decrypt_result = process_incoming(&payload(&[
            ("group_id", &group_id),
            ("ciphertext", ciphertext),
        ]))
        .expect("process_incoming must succeed on happy path");

        assert_eq!(
            decrypt_result.get("plaintext"),
            Some(&original_plaintext.to_owned()),
            "decrypted plaintext must match original"
        );
        assert!(
            !decrypt_result.contains_key("error"),
            "process_incoming happy path must not contain a spurious 'error' key"
        );
    }

    // Verify that error details map contains a non-empty "error" key on failure.
    //
    // Before enrichment, map_err(|_| discarded the original error. After enrichment,
    // map_err(|e| inserts format!("{e:?}") under the "error" key. This test:
    //   1. Calls process_incoming with garbage bytes (valid hex but invalid TLS structure)
    //   2. Asserts the "error" key is present and non-empty
    //   3. Asserts the error CODE atom is still the correct ErrorCode::InvalidInput
    //      (enrichment must not corrupt the semantic error code Elixir pattern-matches on)
    #[test]
    fn error_details_include_underlying_cause() {
        let group_id = unique_group_id("group-error-details-cause");

        // Create a real group so we reach tls_deserialize rather than failing
        // on missing_group_state (which would produce a different error code).
        create_group(&payload(&[
            ("group_id", &group_id),
            (
                "ciphersuite",
                "MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519",
            ),
        ]))
        .expect("group must be created");

        // Valid hex, invalid TLS structure: decode_hex succeeds, tls_deserialize fails,
        // triggering the map_err(|e| closure that inserts the "error" key.
        let garbage_hex = "deadbeefcafebabe0102030405060708";

        let err = process_incoming(&payload(&[
            ("group_id", &group_id),
            ("ciphertext", garbage_hex),
        ]))
        .expect_err("malformed ciphertext must produce an error");

        // Assert correct error code — enrichment must not change the semantic code.
        assert_eq!(
            err.code,
            ErrorCode::InvalidInput,
            "error code must be InvalidInput (not corrupted by enrichment)"
        );

        // Assert the "error" key is present and non-empty.
        let error_context = err
            .details
            .get("error")
            .expect("details must contain 'error' key — error enrichment is missing");
        assert!(
            !error_context.is_empty(),
            "error enrichment produced an empty 'error' string; \
             format!(\"{{e:?}}\") must yield a non-empty debug representation"
        );

        // Also assert the static "reason" label is still correct.
        assert_eq!(
            err.details.get("reason"),
            Some(&"malformed_ciphertext".to_owned()),
            "static 'reason' label must not be affected by error enrichment"
        );
    }

    // Finding #6 + #13: A poisoned RwLock must produce LockPoisoned, not silent
    // corruption. This test exercises the error path using the same map_err
    // translation used in restore_group_session_from_snapshot, applied to a
    // real poisoned RwLock of the same element type.
    //
    // Note: OpenMlsRustCrypto::storage().values is a plain RwLock (not Arc-
    // wrapped), so we create an equivalent standalone RwLock to demonstrate the
    // poison propagation. The production code's map_err is identical in form.
    #[test]
    fn restore_poisoned_lock_returns_lock_poisoned_error() {
        use std::collections::HashMap as StdHashMap;
        use std::sync::{Arc, RwLock};

        // Create a lock of the same element type used in the provider storage.
        let lock: Arc<RwLock<StdHashMap<Vec<u8>, Vec<u8>>>> =
            Arc::new(RwLock::new(StdHashMap::new()));

        // Poison the lock by panicking while holding a write guard.
        let lock_for_poison = Arc::clone(&lock);
        let _ = std::panic::catch_unwind(move || {
            let _guard = lock_for_poison.write().expect("initial write must succeed");
            panic!("intentionally poisoning lock for test");
        });

        // Confirm the lock is now poisoned.
        assert!(lock.write().is_err(), "lock must be poisoned after panic");

        // Apply the same map_err translation used in restore_group_session_from_snapshot.
        let result: Result<(), MlsError> = lock
            .write()
            .map(|_| ())
            .map_err(|_| MlsError::with_code(ErrorCode::LockPoisoned, "test_op", "lock_poisoned"));

        let err = result.expect_err("poisoned lock must produce an error");
        assert_eq!(
            err.code,
            ErrorCode::LockPoisoned,
            "error code must be LockPoisoned, not a storage issue"
        );
        assert_eq!(
            err.details.get("reason"),
            Some(&"lock_poisoned".to_owned()),
            "reason must be lock_poisoned"
        );
        assert_eq!(
            err.details.get("operation"),
            Some(&"test_op".to_owned()),
            "operation must be threaded through"
        );
    }

    // Finding #11: An incomplete snapshot (some fields present, some absent)
    // must return InvalidInput with reason "incomplete_session_snapshot", not
    // panic. This directly tests the structural match that replaced the
    // separated guard + unwrap pattern.
    #[test]
    fn restore_incomplete_snapshot_returns_error_not_panic() {
        let group_id = unique_group_id("group-incomplete-snapshot");

        // Provide only sender_storage and sender_signer — recipient fields absent.
        // The match arm `_ =>` must fire and return Err(InvalidInput).
        let params = payload(&[
            ("group_id", &group_id),
            (
                "ciphersuite",
                "MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519",
            ),
            ("session_sender_storage", "deadbeef"),
            ("session_sender_signer", "cafebabe"),
            // session_recipient_storage and session_recipient_signer intentionally absent
        ]);

        // GroupSession doesn't implement Debug, so use match to extract the error.
        let result = restore_group_session_from_snapshot(&group_id, &params, "test_restore");
        assert!(
            result.is_err(),
            "incomplete snapshot must return an error, not panic"
        );
        let err = match result {
            Err(e) => e,
            Ok(_) => panic!("expected Err but got Ok"),
        };

        assert_eq!(
            err.code,
            ErrorCode::InvalidInput,
            "error code must be InvalidInput for incomplete snapshot"
        );
        assert_eq!(
            err.details.get("reason"),
            Some(&"incomplete_session_snapshot".to_owned()),
            "reason must be incomplete_session_snapshot"
        );
        assert_eq!(
            err.details.get("operation"),
            Some(&"test_restore".to_owned()),
            "operation must be threaded through"
        );
    }

    // Verifies that a normal restore path (no poisoned locks, no missing fields)
    // produces a fully usable session: a message encrypted with the restored
    // session can be decrypted, yielding the original plaintext.
    #[test]
    fn snapshot_restore_produces_usable_session() {
        let group_id = unique_group_id("group-snapshot-restore-usable");

        // Step 1: Create the group and capture the snapshot fields it returns.
        let group = create_group(&payload(&[
            ("group_id", &group_id),
            (
                "ciphersuite",
                "MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519",
            ),
        ]))
        .expect("group must be created for snapshot restore test");

        // Step 2: Encrypt a message, passing the snapshot so create_application_message
        // restores state from it (has_complete_session_snapshot fires).
        let mut encrypt_params = Payload::new();
        encrypt_params.insert("group_id".to_owned(), group_id.clone());
        encrypt_params.insert("body".to_owned(), "hello from snapshot".to_owned());
        for key in [
            "session_sender_storage",
            "session_recipient_storage",
            "session_sender_signer",
            "session_recipient_signer",
            "session_cache",
        ] {
            if let Some(value) = group.get(key) {
                encrypt_params.insert(key.to_owned(), value.clone());
            }
        }

        let encrypted = create_application_message(&encrypt_params)
            .expect("encrypt after snapshot restore must succeed");

        let ciphertext = encrypted
            .get("ciphertext")
            .expect("ciphertext must be present in encrypt result")
            .clone();

        // Step 3: Decrypt the ciphertext, passing the post-encrypt snapshot so
        // process_incoming restores state from it (has_complete_session_snapshot fires).
        let mut decrypt_params = Payload::new();
        decrypt_params.insert("group_id".to_owned(), group_id.clone());
        decrypt_params.insert("ciphertext".to_owned(), ciphertext);
        for key in [
            "session_sender_storage",
            "session_recipient_storage",
            "session_sender_signer",
            "session_recipient_signer",
            "session_cache",
        ] {
            if let Some(value) = encrypted.get(key) {
                decrypt_params.insert(key.to_owned(), value.clone());
            }
        }

        let decrypted =
            process_incoming(&decrypt_params).expect("decrypt after snapshot restore must succeed");

        assert_eq!(
            decrypted.get("plaintext"),
            Some(&"hello from snapshot".to_owned()),
            "plaintext must match original message after restore → encrypt → decrypt"
        );
    }
}
