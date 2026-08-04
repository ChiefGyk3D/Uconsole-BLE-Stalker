#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

need_cmd uname
need_cmd lsusb
need_cmd dmesg
need_cmd grep
need_cmd awk
need_cmd sed
need_cmd mount
need_cmd lsmod
need_cmd rfkill
need_cmd bluetoothctl
need_cmd hciconfig

mkdir -p "${ROOT_DIR}/logs"
REPORT="${ROOT_DIR}/logs/mediatek-ac1200-$(now_stamp).txt"

{
  echo "# MediaTek AC1200 Bluetooth Diagnostic Report"
  echo "generated_at=$(date -Is)"
  echo "hostname=$(hostname)"
  echo "kernel=$(uname -a)"
  echo

  echo "## USB inventory"
  lsusb | grep -Ei 'mediatek|mt76|mt792|wifi|bluetooth|realtek|rtl' || true
  echo

  echo "## Bluetooth controllers"
  bluetoothctl list || true
  echo

  echo "## hciconfig"
  hciconfig -a || true
  echo

  echo "## rfkill"
  rfkill list || true
  echo

  echo "## Loaded kernel modules"
  lsmod | awk 'NR==1 || /btusb|btmtk|btintel|btbcm|mt76|mt792|mt761|cfg80211|mac80211/' || true
  echo

  echo "## dmesg Bluetooth/MediaTek matches"
  dmesg | grep -Ei 'btusb|btmtk|btintel|btbcm|mt76|mt792|mt761|firmware|timeout|hci1|bluetooth|urb|iso' | tail -n 250 || true
  echo

  echo "## USB power / bus hints"
  dmesg | grep -Ei 'usb|firmware|timeout|suspended|resumed|reset' | tail -n 150 || true
  echo

  echo "## Quick interpretation"
  echo "- If you see 'command tx timeout' or 'Failed to apply iso setting', the adapter is failing at the Bluetooth transport layer."
  echo "- If you see 'mt7921u' and firmware/timeouts together, likely driver/firmware/USB interaction rather than pure user-space issue."
  echo "- If the adapter is visible in lsusb but lacks a usable hci controller, it may be Wi-Fi-only or not exposing Bluetooth properly."
} > "${REPORT}"

echo "Wrote report: ${REPORT}"
