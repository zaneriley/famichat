#![forbid(unsafe_code)]

use std::collections::BTreeMap;

pub type Payload = BTreeMap<String, String>;

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

impl MlsError {
    #[must_use]
    pub fn unsupported(operation: &str) -> Self {
        let mut details = Payload::new();
        details.insert("operation".to_owned(), operation.to_owned());
        details.insert("reason".to_owned(), "not_implemented".to_owned());

        Self {
            code: ErrorCode::UnsupportedCapability,
            details,
        }
    }

    #[must_use]
    pub fn invalid_input(details: Payload) -> Self {
        Self {
            code: ErrorCode::InvalidInput,
            details,
        }
    }
}

pub fn nif_version() -> MlsResult {
    let mut payload = Payload::new();
    payload.insert("crate".to_owned(), env!("CARGO_PKG_NAME").to_owned());
    payload.insert("version".to_owned(), env!("CARGO_PKG_VERSION").to_owned());
    payload.insert("status".to_owned(), "scaffold".to_owned());
    Ok(payload)
}

pub fn nif_health() -> MlsResult {
    let mut payload = Payload::new();
    payload.insert("status".to_owned(), "degraded".to_owned());
    payload.insert("reason".to_owned(), "openmls_not_wired".to_owned());
    Ok(payload)
}

pub fn create_key_package(_params: &Payload) -> MlsResult {
    placeholder("create_key_package")
}

pub fn create_group(params: &Payload) -> MlsResult {
    require_keys("create_group", params, &["group_id", "ciphersuite"])?;
    placeholder("create_group")
}

pub fn join_from_welcome(_params: &Payload) -> MlsResult {
    placeholder("join_from_welcome")
}

pub fn process_incoming(_params: &Payload) -> MlsResult {
    placeholder("process_incoming")
}

pub fn commit_to_pending(_params: &Payload) -> MlsResult {
    placeholder("commit_to_pending")
}

pub fn merge_staged_commit(_params: &Payload) -> MlsResult {
    placeholder("merge_staged_commit")
}

pub fn clear_pending_commit(_params: &Payload) -> MlsResult {
    placeholder("clear_pending_commit")
}

pub fn create_application_message(_params: &Payload) -> MlsResult {
    placeholder("create_application_message")
}

pub fn export_group_info(_params: &Payload) -> MlsResult {
    placeholder("export_group_info")
}

pub fn export_ratchet_tree(_params: &Payload) -> MlsResult {
    placeholder("export_ratchet_tree")
}

fn placeholder(operation: &str) -> MlsResult {
    Err(MlsError::unsupported(operation))
}

fn require_keys(operation: &str, params: &Payload, required: &[&str]) -> Result<(), MlsError> {
    let mut details = Payload::new();

    for key in required {
        if !params.contains_key(*key) {
            details.insert((*key).to_owned(), "is required".to_owned());
        }
    }

    if details.is_empty() {
        Ok(())
    } else {
        details.insert("operation".to_owned(), operation.to_owned());
        Err(MlsError::invalid_input(details))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    type Operation = fn(&Payload) -> MlsResult;

    fn payload(entries: &[(&str, &str)]) -> Payload {
        entries
            .iter()
            .map(|(k, v)| ((*k).to_owned(), (*v).to_owned()))
            .collect()
    }

    fn assert_unsupported(operation: &str, result: MlsResult) {
        let error = result.expect_err("unsupported capability");
        assert_eq!(error.code, ErrorCode::UnsupportedCapability);
        assert_eq!(error.details.get("operation"), Some(&operation.to_owned()));
        assert_eq!(
            error.details.get("reason"),
            Some(&"not_implemented".to_owned())
        );
    }

    #[test]
    fn version_is_exposed_with_scaffold_status() {
        let result = nif_version().expect("version payload");
        assert_eq!(result.get("crate"), Some(&"mls_nif".to_owned()));
        assert_eq!(result.get("status"), Some(&"scaffold".to_owned()));
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
    fn placeholder_operations_fail_closed() {
        let empty = Payload::new();
        let group_params = payload(&[("group_id", "g1"), ("ciphersuite", "suite1")]);
        let operations: [(&str, Operation); 10] = [
            ("create_key_package", create_key_package),
            ("create_group", create_group),
            ("join_from_welcome", join_from_welcome),
            ("process_incoming", process_incoming),
            ("commit_to_pending", commit_to_pending),
            ("merge_staged_commit", merge_staged_commit),
            ("clear_pending_commit", clear_pending_commit),
            ("create_application_message", create_application_message),
            ("export_group_info", export_group_info),
            ("export_ratchet_tree", export_ratchet_tree),
        ];

        for (operation, call) in operations {
            let params = if operation == "create_group" {
                &group_params
            } else {
                &empty
            };
            assert_unsupported(operation, call(params));
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
