#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

load_config
need_cmd btmon
need_cmd timeout
need_cmd awk
need_cmd sort
need_cmd head
need_cmd tee
need_cmd wc
need_root

IFACE="${1:-}"
DURATION="${2:-300}"
ALERT_THRESHOLD="${3:-${ALERT_ADS_PER_ADDR}}"

if [[ -z "${IFACE}" ]]; then
  IFACE="$(default_capture_iface)"
else
  ensure_hci "${IFACE}"
fi
mkdir -p "${ROOT_DIR}/logs"

STAMP="$(now_stamp)"
CAPTURE_LOG="${ROOT_DIR}/logs/btmon-${IFACE}-${STAMP}.log"
SUMMARY_FILE="${ROOT_DIR}/logs/summary-${IFACE}-${STAMP}.txt"

echo "Starting BLE field run on ${IFACE} for ${DURATION}s"
echo "Capture log: ${CAPTURE_LOG}"
echo "Summary file: ${SUMMARY_FILE}"

timeout "${DURATION}" stdbuf -oL btmon -i "${IFACE}" 2>/dev/null | tee "${CAPTURE_LOG}" >/dev/null

{
  echo "# BLE Field Summary"
  echo "generated_at=$(date -Is)"
  echo "interface=${IFACE}"
  echo "duration_seconds=${DURATION}"
  echo "alert_threshold=${ALERT_THRESHOLD}"
  echo "capture_log=${CAPTURE_LOG}"
  echo

  total_lines=$(wc -l < "${CAPTURE_LOG}" | tr -d ' ')
  echo "capture_lines=${total_lines}"
  echo

  echo "## Top advertisers by count"
  awk '
    /Address:/ {
      addr=$2
      gsub(",", "", addr)
      if (addr ~ /([0-9A-F]{2}:){5}[0-9A-F]{2}/) {
        count[addr]++
      }
    }
    END {
      for (a in count) {
        printf "%s %d\n", a, count[a]
      }
    }
  ' "${CAPTURE_LOG}" | sort -k2,2nr | head -n 25

  echo
  echo "## Potential spam senders"
  awk -v t="${ALERT_THRESHOLD}" '
    /Address:/ {
      addr=$2
      gsub(",", "", addr)
      if (addr ~ /([0-9A-F]{2}:){5}[0-9A-F]{2}/) {
        count[addr]++
      }
    }
    END {
      for (a in count) {
        if (count[a] >= t) {
          printf "ALERT %s %d\n", a, count[a]
        }
      }
    }
  ' "${CAPTURE_LOG}" | sort -k3,3nr

  echo
  echo "## Top average RSSI by sender (min 5 RSSI samples)"
  awk '
    /Address:/ {
      addr=$2
      gsub(",", "", addr)
      valid=(addr ~ /([0-9A-F]{2}:){5}[0-9A-F]{2}/)
    }
    /RSSI:/ {
      if (valid) {
        rssi=$2
        gsub("dBm", "", rssi)
        if (rssi ~ /^-?[0-9]+$/) {
          sum[addr]+=rssi
          n[addr]++
        }
      }
    }
    END {
      for (a in n) {
        if (n[a] >= 5) {
          avg=sum[a]/n[a]
          printf "%s %.2f %d\n", a, avg, n[a]
        }
      }
    }
  ' "${CAPTURE_LOG}" | sort -k2,2nr | head -n 20
} > "${SUMMARY_FILE}"

echo
echo "Field run complete."
echo "Open summary: ${SUMMARY_FILE}"
