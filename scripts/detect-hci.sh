#!/usr/bin/env bash
set -euo pipefail

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing command: $1" >&2
    exit 1
  fi
}

need hciconfig
need bluetoothctl

echo "== hciconfig output =="
hciconfig -a || true

echo
echo "== bluetoothctl controllers =="
bluetoothctl list || true

echo
echo "Hint: built-in CM4 radio is usually hci0; USB dongle usually hci1."
echo "Confirm by unplugging/replugging the USB adapter and rerunning this script."
