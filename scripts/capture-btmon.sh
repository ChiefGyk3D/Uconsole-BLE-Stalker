#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

load_config
need_cmd btmon
need_cmd hciconfig
need_root

IFACE="${1:-}"
DURATION="${2:-${SCAN_SECONDS}}"

if [[ -z "${IFACE}" ]]; then
	IFACE="$(default_capture_iface)"
else
	ensure_hci "${IFACE}"
fi
mkdir -p "${ROOT_DIR}/logs"
OUT="${ROOT_DIR}/logs/btmon-${IFACE}-$(now_stamp).log"

echo "Capturing BLE monitor output on ${IFACE} for ${DURATION}s"
echo "Log: ${OUT}"

trap 'stop_le_scan "${IFACE}"' EXIT

start_le_scan "${IFACE}"
run_btmon_capture "${IFACE}" "${DURATION}" "${OUT}" tee
stop_le_scan "${IFACE}"

warn_if_capture_empty "${OUT}"

echo "Capture complete."
