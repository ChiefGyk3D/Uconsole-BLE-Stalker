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

timeout "${DURATION}" stdbuf -oL btmon -i "${IFACE}" 2>/dev/null | tee "${OUT}"

echo "Capture complete."
