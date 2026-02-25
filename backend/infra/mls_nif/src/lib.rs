#![forbid(unsafe_code)]

use rustler::{Encoder, Env, Term};
use std::collections::HashMap;

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
    payload.insert("status".to_owned(), "degraded".to_owned());
    payload.insert("reason".to_owned(), "openmls_not_wired".to_owned());
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
                format!("kp:{}:{}", client_id, current_epoch(params)),
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
    let params = CreateGroupParams::try_from(params)?;

    let mut payload = Payload::new();
    payload.insert("group_id".to_owned(), params.group_id.clone());
    payload.insert("ciphersuite".to_owned(), params.ciphersuite);
    payload.insert("epoch".to_owned(), "1".to_owned());
    payload.insert(
        "group_state_ref".to_owned(),
        format!("state:{}", params.group_id),
    );
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

    let missing_ciphertext = ciphertext.is_none();

    match (group_id, ciphertext) {
        (Some(group_id), Some(ciphertext)) => {
            let mut payload = Payload::new();
            payload.insert("group_id".to_owned(), group_id);
            payload.insert("plaintext".to_owned(), decode_ciphertext(&ciphertext));
            payload.insert("epoch".to_owned(), current_epoch(params));
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

        let mut payload = Payload::new();
        payload.insert("group_id".to_owned(), group_id);
        payload.insert("ciphertext".to_owned(), format!("ciphertext:{}", body));
        payload.insert("epoch".to_owned(), current_epoch(params));
        Ok(payload)
    })
}

pub fn export_group_info(params: &Payload) -> MlsResult {
    let operation = "export_group_info";
    with_required_group(operation, params, |group_id| {
        let mut payload = Payload::new();
        payload.insert("group_id".to_owned(), group_id.clone());
        payload.insert(
            "group_info_ref".to_owned(),
            format!("group-info:{}", group_id),
        );
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

fn parse_bool(params: &Payload, key: &str) -> Option<bool> {
    non_empty(params, key).and_then(|value| match value.as_str() {
        "true" | "1" => Some(true),
        "false" | "0" => Some(false),
        _ => None,
    })
}

fn current_epoch(params: &Payload) -> String {
    params
        .get("epoch")
        .filter(|value| !value.trim().is_empty())
        .cloned()
        .unwrap_or_else(|| "1".to_owned())
}

fn next_epoch(params: &Payload) -> String {
    params
        .get("epoch")
        .and_then(|value| value.parse::<u64>().ok())
        .map(|value| value + 1)
        .unwrap_or(2)
        .to_string()
}

fn decode_ciphertext(ciphertext: &str) -> String {
    ciphertext
        .strip_prefix("ciphertext:")
        .unwrap_or(ciphertext)
        .to_owned()
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

    fn payload(entries: &[(&str, &str)]) -> Payload {
        entries
            .iter()
            .map(|(k, v)| ((*k).to_owned(), (*v).to_owned()))
            .collect()
    }

    #[test]
    fn version_is_exposed_with_wired_status() {
        let result = nif_version().expect("version payload");
        assert_eq!(result.get("crate"), Some(&"mls_nif".to_owned()));
        assert_eq!(result.get("status"), Some(&"wired_contract".to_owned()));
    }

    #[test]
    fn health_reports_openmls_not_wired() {
        let result = nif_health().expect("health payload");
        assert_eq!(result.get("status"), Some(&"degraded".to_owned()));
        assert_eq!(result.get("reason"), Some(&"openmls_not_wired".to_owned()));
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
    fn create_key_package_and_group_are_deterministic() {
        let kp = create_key_package(&payload(&[("client_id", "client-1")]))
            .expect("key package must be generated");
        assert_eq!(kp.get("status"), Some(&"created".to_owned()));
        assert_eq!(kp.get("key_package_ref"), Some(&"kp:client-1:1".to_owned()));

        let group = create_group(&payload(&[
            ("group_id", "group-1"),
            (
                "ciphersuite",
                "MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519",
            ),
        ]))
        .expect("group must be created");

        assert_eq!(group.get("group_id"), Some(&"group-1".to_owned()));
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
        let encrypted =
            create_application_message(&payload(&[("group_id", "group-1"), ("body", "hello")]))
                .expect("encryption success");

        let ciphertext = encrypted.get("ciphertext").expect("ciphertext payload");

        let decrypted = process_incoming(&payload(&[
            ("group_id", "group-1"),
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
