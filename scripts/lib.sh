#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONF_FILE="${ROOT_DIR}/config/interfaces.conf"

load_config() {
  if [[ ! -f "${CONF_FILE}" ]]; then
    echo "Missing ${CONF_FILE}. Copy interfaces.conf.example first." >&2
    exit 1
  fi

  # shellcheck disable=SC1090
  source "${CONF_FILE}"
}

need_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Missing required command: ${cmd}" >&2
    exit 1
  fi
}

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Run as root (sudo)." >&2
    exit 1
  fi
}

hci_exists() {
  local iface="$1"
  hciconfig "${iface}" >/dev/null 2>&1
}

adapter_mode() {
  local mode="${ADAPTER_MODE:-dual}"
  case "${mode}" in
    dual|single|auto)
      printf "%s\n" "${mode}"
      ;;
    *)
      echo "Unknown ADAPTER_MODE='${mode}'. Supported: dual, single, auto. Falling back to dual." >&2
      printf "%s\n" "dual"
      ;;
  esac
}

ensure_hci() {
  local iface="$1"
  if ! hci_exists "${iface}"; then
    echo "Bluetooth interface ${iface} not found." >&2
    echo "Run scripts/detect-hci.sh to discover adapter names." >&2
    exit 1
  fi
}

pick_runtime_iface() {
  local preferred="$1"
  local fallback="$2"
  local context="$3"

  if [[ -n "${preferred}" ]] && hci_exists "${preferred}"; then
    printf "%s\n" "${preferred}"
    return 0
  fi

  if [[ -n "${fallback}" ]] && hci_exists "${fallback}"; then
    echo "${context}: preferred interface ${preferred} not available; falling back to ${fallback}." >&2
    printf "%s\n" "${fallback}"
    return 0
  fi

  echo "${context}: no usable Bluetooth interface found (preferred=${preferred}, fallback=${fallback})." >&2
  echo "Run scripts/detect-hci.sh and update config/interfaces.conf." >&2
  exit 1
}

default_capture_iface() {
  local preferred="${CAPTURE_HCI:-hci0}"
  local fallback="${PRIMARY_HCI:-hci0}"
  pick_runtime_iface "${preferred}" "${fallback}" "capture"
}

default_hunt_iface() {
  local mode
  mode="$(adapter_mode)"

  local preferred
  local fallback

  case "${mode}" in
    single)
      preferred="${HUNT_HCI:-${CAPTURE_HCI:-${PRIMARY_HCI:-hci0}}}"
      fallback="${CAPTURE_HCI:-${PRIMARY_HCI:-hci0}}"
      ;;
    auto)
      if hci_exists "${SECONDARY_HCI:-hci1}"; then
        preferred="${HUNT_HCI:-${SECONDARY_HCI:-hci1}}"
      else
        preferred="${HUNT_HCI:-${CAPTURE_HCI:-${PRIMARY_HCI:-hci0}}}"
      fi
      fallback="${CAPTURE_HCI:-${PRIMARY_HCI:-hci0}}"
      ;;
    dual|*)
      preferred="${HUNT_HCI:-${SECONDARY_HCI:-hci1}}"
      fallback="${CAPTURE_HCI:-${PRIMARY_HCI:-hci0}}"
      ;;
  esac

  pick_runtime_iface "${preferred}" "${fallback}" "hunt"
}

now_stamp() {
  date +"%Y%m%d-%H%M%S"
}

# btmon is a passive observer of the HCI channel. The controller only emits
# LE Advertising Report events while an LE scan is active, so captures taken
# on an idle adapter are almost empty. These helpers turn scanning on for the
# duration of a capture and reliably tear it down afterwards.
LE_SCAN_PGID=""

start_le_scan() {
  local iface="$1"

  if ! command -v btmgmt >/dev/null 2>&1; then
    echo "warn: btmgmt not found; cannot enable LE scan automatically." >&2
    echo "warn: install bluez-tools, or run 'bluetoothctl scan on' in another shell." >&2
    return 0
  fi

  btmgmt -i "${iface}" power on >/dev/null 2>&1 || true
  btmgmt -i "${iface}" le on >/dev/null 2>&1 || true

  # 'btmgmt find' completes after one discovery window, so loop it to keep the
  # scan running. setsid puts the loop in its own process group, which lets us
  # kill the loop and any in-flight btmgmt child together.
  if command -v setsid >/dev/null 2>&1; then
    setsid bash -c 'while :; do btmgmt -i "$1" find -l >/dev/null 2>&1 || true; sleep 1; done' _ "${iface}" >/dev/null 2>&1 &
    LE_SCAN_PGID=$!
  else
    bash -c 'while :; do btmgmt -i "$1" find -l >/dev/null 2>&1 || true; sleep 1; done' _ "${iface}" >/dev/null 2>&1 &
    LE_SCAN_PGID=$!
  fi

  # Give the controller a moment to actually start scanning before capturing.
  sleep 1
}

stop_le_scan() {
  local iface="${1:-}"

  if [[ -n "${LE_SCAN_PGID}" ]]; then
    kill -- -"${LE_SCAN_PGID}" 2>/dev/null || kill "${LE_SCAN_PGID}" 2>/dev/null || true
    wait "${LE_SCAN_PGID}" 2>/dev/null || true
    LE_SCAN_PGID=""
  fi

  if [[ -n "${iface}" ]] && command -v btmgmt >/dev/null 2>&1; then
    btmgmt -i "${iface}" stop-find >/dev/null 2>&1 || true
  fi
}

# Capture btmon output for a bounded duration.
#
# 'timeout' exits 124 when it stops the command, and under 'set -o pipefail'
# plus 'set -e' that status would abort the calling script before any analysis
# stage could run. Absorb the expected statuses here so callers keep going.
#
# Usage: run_btmon_capture <iface> <duration> <outfile> [quiet|tee]
run_btmon_capture() {
  local iface="$1"
  local duration="$2"
  local outfile="$3"
  local mode="${4:-quiet}"
  local rc=0

  if [[ "${mode}" == "tee" ]]; then
    timeout "${duration}" stdbuf -oL btmon -i "${iface}" 2>/dev/null | tee "${outfile}" || rc=$?
  else
    timeout "${duration}" stdbuf -oL btmon -i "${iface}" >"${outfile}" 2>/dev/null || rc=$?
  fi

  case "${rc}" in
    0|124|143)
      # 0 = clean exit, 124 = timeout reached (expected), 143 = SIGTERM.
      :
      ;;
    *)
      echo "warn: btmon capture on ${iface} exited with status ${rc}." >&2
      echo "warn: results may be incomplete. See TROUBLESHOOTING.md." >&2
      ;;
  esac

  return 0
}

# Warn when a capture produced no usable advertising data, so an empty result
# is reported as a problem instead of looking like a quiet RF environment.
warn_if_capture_empty() {
  local logfile="$1"

  if [[ ! -s "${logfile}" ]]; then
    echo "warn: capture file is empty. The adapter may not be scanning." >&2
    return 0
  fi

  if ! grep -q "Address:" "${logfile}" 2>/dev/null; then
    echo "warn: capture contains no advertising reports." >&2
    echo "warn: check that LE scan is enabled and the adapter is up (see TROUBLESHOOTING.md)." >&2
  fi
}
