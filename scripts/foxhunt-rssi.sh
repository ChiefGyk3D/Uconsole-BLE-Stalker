#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

load_config
need_cmd btmon
need_cmd hciconfig
need_root

TARGET_MAC="${1:-}"
IFACE="${2:-}"

if [[ -z "${TARGET_MAC}" ]]; then
  echo "Usage: sudo $0 <TARGET_MAC> [HCI_IFACE]" >&2
  exit 1
fi

if [[ -z "${IFACE}" ]]; then
  IFACE="$(default_hunt_iface)"
else
  ensure_hci "${IFACE}"
fi

echo "Tracking ${TARGET_MAC} on ${IFACE}. Ctrl+C to stop."
echo "Tip: walk slowly and watch the median RSSI trend rise as you approach source."

tmpfile="$(mktemp)"
trap 'rm -f "${tmpfile}"' EXIT

stdbuf -oL btmon -i "${IFACE}" 2>/dev/null | awk -v target="${TARGET_MAC}" '
  BEGIN {
    IGNORECASE=1
  }
  /Address:/ {
    addr=$2
    gsub(",", "", addr)
  }
  /RSSI:/ {
    rssi=$2
    gsub("dBm", "", rssi)
    if (toupper(addr) == toupper(target)) {
      print rssi
      fflush()
    }
  }
' | while read -r rssi; do
  echo "${rssi}" >> "${tmpfile}"
  count=$(wc -l < "${tmpfile}")

  if (( count % 10 == 0 )); then
    med=$(sort -n "${tmpfile}" | awk ' {
      a[NR]=$1
    }
    END {
      if (NR == 0) {
        exit
      }
      if (NR % 2 == 1) {
        print a[(NR+1)/2]
      } else {
        print int((a[NR/2] + a[NR/2 + 1]) / 2)
      }
    }')
    latest=$(tail -n 1 "${tmpfile}")
    echo "samples=${count} latest=${latest}dBm median10=${med}dBm"

    # Keep a sliding window of recent points for responsiveness.
    tail -n 40 "${tmpfile}" > "${tmpfile}.new"
    mv "${tmpfile}.new" "${tmpfile}"
  fi
done
