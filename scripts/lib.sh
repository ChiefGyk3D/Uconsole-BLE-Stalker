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
  pick_runtime_iface "${CAPTURE_HCI:-hci0}" "${PRIMARY_HCI:-hci0}" "capture"
}

default_hunt_iface() {
  local preferred="${HUNT_HCI:-${SECONDARY_HCI:-hci1}}"
  local fallback="${CAPTURE_HCI:-${PRIMARY_HCI:-hci0}}"
  pick_runtime_iface "${preferred}" "${fallback}" "hunt"
}

now_stamp() {
  date +"%Y%m%d-%H%M%S"
}
