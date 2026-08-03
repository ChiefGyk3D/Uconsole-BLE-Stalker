#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root (sudo)." >&2
  exit 1
fi

apt update
apt install -y bluez bluez-tools wireless-tools iw kismet tshark

echo "Dependencies installed."
echo "Next:"
echo "1) cp config/interfaces.conf.example config/interfaces.conf"
echo "2) Edit interface names"
echo "3) Run scripts/detect-hci.sh"
