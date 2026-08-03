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

now_stamp() {
  date +"%Y%m%d-%H%M%S"
}
