#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

load_config
need_cmd btmon
need_cmd hciconfig
need_cmd timeout
need_root

IFACE="${1:-${CAPTURE_HCI}}"
DURATION="${2:-${SCAN_SECONDS}}"
THRESHOLD="${3:-${ALERT_ADS_PER_ADDR}}"

ensure_hci "${IFACE}"

echo "Monitoring ${IFACE} for ${DURATION}s. Alert threshold=${THRESHOLD} ads/address"

tmpfile="$(mktemp)"
trap 'rm -f "${tmpfile}"' EXIT

timeout "${DURATION}" stdbuf -oL btmon -i "${IFACE}" 2>/dev/null | awk '
  /Address:/ {
    addr=$2
    gsub(",", "", addr)
    if (addr ~ /([0-9A-F]{2}:){5}[0-9A-F]{2}/) {
      counts[addr]++
    }
  }
  END {
    for (a in counts) {
      printf "%s %d\n", a, counts[a]
    }
  }
' | sort -k2,2nr > "${tmpfile}"

echo
echo "Top advertisers:"
head -n 20 "${tmpfile}" | awk '{printf "%-20s %s\n", $1, $2}'

echo
echo "Potential spam senders (>=${THRESHOLD}):"
awk -v t="${THRESHOLD}" '$2 >= t {printf "ALERT %-20s %s ads\n", $1, $2}' "${tmpfile}" || true
