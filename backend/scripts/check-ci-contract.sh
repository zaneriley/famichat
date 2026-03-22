#!/usr/bin/env bash

set -euo pipefail

backend_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo_root="$(cd "${backend_dir}/.." && pwd)"

fail() {
  printf 'ci contract check failed: %s\n' "$1" >&2
  exit 1
}

require_match() {
  local file_path="$1"
  local pattern="$2"
  local description="$3"

  if ! grep -Fq -- "$pattern" "$file_path"; then
    fail "$description"
  fi
}

require_absent() {
  local file_path="$1"
  local pattern="$2"
  local description="$3"

  if grep -Fq -- "$pattern" "$file_path"; then
    fail "$description"
  fi
}

function_body() {
  local file_path="$1"
  local function_name="$2"

  awk -v target="function ${function_name} {" '
    $0 == target {
      in_function = 1
      next
    }

    in_function && /^function [^ ]+ \{/ {
      exit
    }

    in_function {
      print
    }
  ' "${file_path}"
}

require_function_body_match() {
  local file_path="$1"
  local function_name="$2"
  local pattern="$3"
  local description="$4"
  local body

  body="$(function_body "${file_path}" "${function_name}")"

  if [[ -z "${body}" ]]; then
    fail "${description} (function ${function_name} not found)"
  fi

  if ! grep -Fq -- "${pattern}" <<<"${body}"; then
    fail "${description}"
  fi
}

require_function_body_absent() {
  local file_path="$1"
  local function_name="$2"
  local pattern="$3"
  local description="$4"
  local body

  body="$(function_body "${file_path}" "${function_name}")"

  if [[ -z "${body}" ]]; then
    fail "${description} (function ${function_name} not found)"
  fi

  if grep -Fq -- "${pattern}" <<<"${body}"; then
    fail "${description}"
  fi
}

run_file="${backend_dir}/run"
toolchain_file="${backend_dir}/rust-toolchain.toml"
workspace_cargo="${backend_dir}/infra/Cargo.toml"
wasm_cargo="${backend_dir}/infra/mls_wasm/Cargo.toml"
nif_toolchain_file="${backend_dir}/infra/mls_nif/rust-toolchain.toml"
dockerfile="${backend_dir}/Dockerfile"
lint_workflow="${repo_root}/.github/workflows/lint.yml"
test_workflow="${repo_root}/.github/workflows/ci-test.yml"
messaging_workflow="${repo_root}/.github/workflows/messaging-qa.yml"

require_match "${run_file}" 'if [[ -f "infra/Cargo.toml" ]]; then' 'backend/run does not resolve the workspace root manifest'
require_match "${run_file}" 'echo "Rust workspace not found. Expected infra/Cargo.toml."' 'backend/run still points at the legacy Rust manifest path'
require_match "${run_file}" 'function rust:deny {' 'backend/run is missing rust:deny'
require_match "${run_file}" 'function rust:verify {' 'backend/run is missing rust:verify'
require_match "${run_file}" 'function ci:check-contract {' 'backend/run is missing ci:check-contract'
require_match "${run_file}" 'function ci:tooling-test {' 'backend/run is missing ci:tooling-test'
require_match "${run_file}" "deny_config_path=\"\${RUST_DENY_CONFIG_PATH:-infra/deny.toml}\"" 'backend/run does not support overriding the cargo-deny config path'
require_function_body_match "${run_file}" 'rust:verify' 'rust:fmt' 'backend/run rust:verify no longer runs rust:fmt'
require_function_body_match "${run_file}" 'rust:verify' 'rust:clippy' 'backend/run rust:verify no longer runs rust:clippy'
require_function_body_match "${run_file}" 'rust:verify' 'wasm:check' 'backend/run rust:verify no longer runs wasm:check'
require_function_body_match "${run_file}" 'rust:verify' 'rust:test' 'backend/run rust:verify no longer runs rust:test'
require_function_body_match "${run_file}" 'rust:verify' 'rust:deny' 'backend/run rust:verify no longer runs rust:deny'
require_function_body_match "${run_file}" 'ci:lint' 'ci:tooling-test' 'backend/run ci:lint does not include the tooling test suite'
require_function_body_match "${run_file}" 'ci:lint' 'rust:lint' 'backend/run ci:lint does not include rust:lint'
require_function_body_absent "${run_file}" 'ci:lint' 'rust:lint || echo "rust:lint: pre-existing clippy issues (advisory)"' 'backend/run still treats Rust lint as advisory'
require_function_body_match "${run_file}" 'ci:test' 'wasm:check' 'backend/run ci:test no longer runs wasm:check'
require_function_body_match "${run_file}" 'ci:test' 'rust:test' 'backend/run ci:test no longer runs rust:test'

require_match "${toolchain_file}" 'channel = "1.94.0"' 'root rust-toolchain.toml is not pinned to 1.94.0'
require_match "${toolchain_file}" 'targets = ["wasm32-unknown-unknown"]' 'root rust-toolchain.toml does not provision the wasm target'
if [[ -e "${nif_toolchain_file}" ]]; then
  fail 'nested mls_nif rust-toolchain.toml still exists and can drift from the root toolchain pin'
fi

require_match "${workspace_cargo}" '[profile.release.package.mls_wasm]' 'workspace Cargo.toml is missing the mls_wasm release override'
require_match "${workspace_cargo}" 'opt-level = "z"' 'workspace Cargo.toml is missing the mls_wasm opt-level override'
require_absent "${wasm_cargo}" '[profile.release]' 'mls_wasm Cargo.toml still carries a package-local release profile'

require_match "${dockerfile}" 'default-toolchain 1.94.0' 'Dockerfile does not install the pinned Rust toolchain'
require_match "${dockerfile}" 'rustup target add wasm32-unknown-unknown' 'Dockerfile does not install the wasm target'
require_match "${dockerfile}" 'cargo-deny' 'Dockerfile does not install cargo-deny'

require_match "${lint_workflow}" 'toolchain: 1.94.0' 'lint workflow does not pin Rust to 1.94.0'
require_match "${lint_workflow}" 'targets: wasm32-unknown-unknown' 'lint workflow does not install the wasm target'
require_match "${lint_workflow}" 'cargo-deny' 'lint workflow does not install cargo-deny'
require_match "${lint_workflow}" 'run: ./run ci:lint' 'lint workflow does not run the canonical ci:lint command'

require_match "${test_workflow}" 'toolchain: 1.94.0' 'test workflow does not pin Rust to 1.94.0'
require_match "${test_workflow}" 'targets: wasm32-unknown-unknown' 'test workflow does not install the wasm target'
require_match "${test_workflow}" 'run: ./run ci:test' 'test workflow does not run the canonical ci:test command'

require_match "${messaging_workflow}" 'run: ./run ci:setup-db' 'messaging QA workflow does not prepare the database before probes'
require_match "${messaging_workflow}" 'run: ./run qa:messaging:fast' 'messaging QA workflow does not run the canonical fast QA command'
require_match "${messaging_workflow}" 'run: ./run qa:messaging:deep' 'messaging QA workflow does not run the canonical deep QA command'
require_match "${messaging_workflow}" "expected PASS or WARN" 'messaging QA workflow no longer treats WARN as an acceptable non-blocking outcome'
require_absent "${messaging_workflow}" "expected PASS)." 'messaging QA workflow still hard-fails on WARN outcomes'

printf 'ci contract check passed\n'
