#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

load_config
need_cmd sed
need_cmd grep

MODE="${1:-}"
if [[ -z "${MODE}" ]]; then
  echo "Usage: $0 <dual|single|auto|status>" >&2
  exit 1
fi

set_key() {
  local key="$1"
  local value="$2"

  if grep -q "^${key}=" "${CONF_FILE}"; then
    sed -i "s|^${key}=.*|${key}=\"${value}\"|" "${CONF_FILE}"
  else
    printf "%s=\"%s\"\n" "${key}" "${value}" >> "${CONF_FILE}"
  fi
}

print_status() {
  load_config
  echo "ADAPTER_MODE=${ADAPTER_MODE:-dual}"
  echo "PRIMARY_HCI=${PRIMARY_HCI:-hci0}"
  echo "SECONDARY_HCI=${SECONDARY_HCI:-hci1}"
  echo "CAPTURE_HCI=${CAPTURE_HCI:-hci0}"
  echo "HUNT_HCI=${HUNT_HCI:-hci1}"
}

case "${MODE}" in
  dual)
    set_key ADAPTER_MODE dual
    set_key HUNT_HCI "${SECONDARY_HCI:-hci1}"
    echo "Set adapter mode to dual (hunt prefers ${SECONDARY_HCI:-hci1})."
    ;;
  single)
    set_key ADAPTER_MODE single
    set_key HUNT_HCI "${CAPTURE_HCI:-${PRIMARY_HCI:-hci0}}"
    echo "Set adapter mode to single (hunt uses ${CAPTURE_HCI:-${PRIMARY_HCI:-hci0}})."
    ;;
  auto)
    set_key ADAPTER_MODE auto
    echo "Set adapter mode to auto (dual when hci1 exists, fallback to single-like behavior)."
    ;;
  status)
    print_status
    exit 0
    ;;
  *)
    echo "Unsupported mode: ${MODE}" >&2
    echo "Usage: $0 <dual|single|auto|status>" >&2
    exit 1
    ;;
esac

print_status
