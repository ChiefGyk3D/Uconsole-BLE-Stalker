#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="${ROOT_DIR}/logs"
mkdir -p "${LOG_DIR}"

REPORT="${LOG_DIR}/toolkit-validation-$(date +%Y%m%d-%H%M%S).txt"

pass_count=0
warn_count=0
fail_count=0

log() {
  printf '%s\n' "$1" | tee -a "${REPORT}"
}

record_pass() {
  pass_count=$((pass_count + 1))
  log "PASS: $1"
}

record_warn() {
  warn_count=$((warn_count + 1))
  log "WARN: $1"
}

record_fail() {
  fail_count=$((fail_count + 1))
  log "FAIL: $1"
}

check_file() {
  local path="$1"
  if [[ -f "${ROOT_DIR}/${path}" ]]; then
    record_pass "Found ${path}"
  else
    record_fail "Missing ${path}"
  fi
}

check_shell_syntax() {
  local script="$1"
  if [[ "${script}" == *.py ]]; then
    if python3 -m py_compile "${ROOT_DIR}/${script}" >/dev/null 2>&1; then
      record_pass "Syntax OK: ${script}"
    else
      record_fail "Syntax error: ${script}"
    fi
  elif bash -n "${ROOT_DIR}/${script}" >/dev/null 2>&1; then
    record_pass "Syntax OK: ${script}"
  else
    record_fail "Syntax error: ${script}"
  fi
}

{
  echo "uConsole BLE Toolkit Validation"
  echo "generated_at=$(date -Is)"
  echo

  check_file "README.md"
  check_file "TROUBLESHOOTING.md"
  check_file "config/interfaces.conf.example"
  check_file "config/interfaces.conf"
  check_file "config/aio-features.conf.example"
  check_file "config/signatures.conf.example"
  check_file "config/signatures.conf"
  check_file "tests/test-ble-signature-tuning.sh"
  check_file "tests/test-ble-signatures.sh"
  check_file "tests/test-toolkit.sh"

  for script in \
    scripts/lib.sh \
    scripts/detect-hci.sh \
    scripts/setup-linux.sh \
    scripts/ble-signature-scan.py \
    scripts/ble-spam-watch.sh \
    scripts/capture-btmon.sh \
    scripts/foxhunt-rssi.sh \
    scripts/recover-hci.sh \
    scripts/ble-field-run.sh \
    scripts/aio-feature-profile.sh \
    scripts/set-adapter-mode.sh \
    scripts/troubleshoot-bluetooth.sh \
    scripts/diagnose-mediatek-ac1200.sh \
    scripts/validate-toolkit.sh; do
    check_shell_syntax "${script}"
  done

  if command -v python3 >/dev/null 2>&1; then
    record_pass "python3 available"
  else
    record_warn "python3 not available; GPS merge helper may be unavailable"
  fi

  echo
  echo "Summary: ${pass_count} passed, ${warn_count} warnings, ${fail_count} failed"
  echo "Validation complete"
} > "${REPORT}"

cat "${REPORT}"

if (( fail_count > 0 )); then
  exit 1
fi
