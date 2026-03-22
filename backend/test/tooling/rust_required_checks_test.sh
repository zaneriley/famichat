#!/usr/bin/env bash

set -euo pipefail

backend_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fixtures_dir_rel="test/fixtures/rust_required_checks"
tmp_root_rel=".tmp/rust_required_checks.$$"
tmp_root="${backend_dir}/${tmp_root_rel}"

mkdir -p "${backend_dir}/.tmp"

cleanup() {
  rm -rf "${tmp_root}"
}

trap cleanup EXIT

fixture_copy_rel() {
  local fixture_name="$1"

  mkdir -p "${tmp_root}"
  cp -R "${backend_dir}/${fixtures_dir_rel}/${fixture_name}" "${tmp_root}/${fixture_name}"

  printf '%s/%s' "${tmp_root_rel}" "${fixture_name}"
}

fixture_manifest() {
  local fixture_dir_rel="$1"
  printf '%s/Cargo.toml' "${fixture_dir_rel}"
}

fixture_deny_config() {
  local fixture_dir_rel="$1"
  printf '%s/deny.toml' "${fixture_dir_rel}"
}

run_success() {
  local description="$1"
  shift

  printf 'tooling test: %s\n' "${description}"
  "$@"
}

run_failure_contains() {
  local description="$1"
  local expected_output="$2"
  local output_file="${tmp_root}/failure.log"
  shift 2

  printf 'tooling test: %s\n' "${description}"

  if "$@" >"${output_file}" 2>&1; then
    printf 'tooling test failed: expected command to fail: %s\n' "${description}" >&2
    exit 1
  fi

  if ! grep -Fq -- "${expected_output}" "${output_file}"; then
    printf 'tooling test failed: missing expected output for %s\n' "${description}" >&2
    cat "${output_file}" >&2
    exit 1
  fi
}

cd "${backend_dir}"

clean_fixture_rel="$(fixture_copy_rel clean)"
fmt_failure_fixture_rel="$(fixture_copy_rel fmt_failure)"
clippy_failure_fixture_rel="$(fixture_copy_rel clippy_failure)"
test_failure_fixture_rel="$(fixture_copy_rel test_failure)"
deny_failure_fixture_rel="$(fixture_copy_rel deny_failure)"

run_success \
  "workspace passes wasm:check" \
  ./run wasm:check

run_success \
  "clean fixture passes rust:fmt" \
  env RUST_MANIFEST_PATH="$(fixture_manifest "${clean_fixture_rel}")" ./run rust:fmt

run_success \
  "clean fixture passes rust:clippy" \
  env RUST_MANIFEST_PATH="$(fixture_manifest "${clean_fixture_rel}")" ./run rust:clippy

run_success \
  "clean fixture passes rust:test" \
  env RUST_MANIFEST_PATH="$(fixture_manifest "${clean_fixture_rel}")" ./run rust:test

run_success \
  "clean fixture passes rust:deny bans" \
  env RUST_MANIFEST_PATH="$(fixture_manifest "${clean_fixture_rel}")" ./run rust:deny bans

run_failure_contains \
  "fmt_failure fixture fails rust:fmt" \
  "Diff in" \
  env RUST_MANIFEST_PATH="$(fixture_manifest "${fmt_failure_fixture_rel}")" ./run rust:fmt

run_failure_contains \
  "clippy_failure fixture fails rust:clippy" \
  "clippy::map_entry" \
  env RUST_MANIFEST_PATH="$(fixture_manifest "${clippy_failure_fixture_rel}")" ./run rust:clippy

run_failure_contains \
  "test_failure fixture fails rust:test" \
  "assertion \`left == right\` failed" \
  env RUST_MANIFEST_PATH="$(fixture_manifest "${test_failure_fixture_rel}")" ./run rust:test

run_failure_contains \
  "deny_failure fixture fails rust:deny bans with its fixture config" \
  "base64" \
  env \
    RUST_MANIFEST_PATH="$(fixture_manifest "${deny_failure_fixture_rel}")" \
    RUST_DENY_CONFIG_PATH="$(fixture_deny_config "${deny_failure_fixture_rel}")" \
    ./run rust:deny bans

printf 'rust required checks tooling test passed\n'
