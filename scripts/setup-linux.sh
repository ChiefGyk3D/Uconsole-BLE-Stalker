#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root (sudo)." >&2
  exit 1
fi

if ! command -v apt >/dev/null 2>&1; then
  echo "This installer currently supports apt-based Debian/Ubuntu systems." >&2
  echo "Install equivalents manually: bluez bluez-tools wireless-tools iw kismet tshark tmux" >&2
  exit 1
fi

apt update
apt install -y bluez bluez-tools wireless-tools iw kismet tshark tmux

echo "Dependencies installed for secondary Linux/laptop use."
echo "Primary support target remains uConsole + AIO v2; non-uConsole usage is best-effort."
echo "Next:"
echo "1) cp config/interfaces.conf.example config/interfaces.conf"
echo "2) cp config/signatures.conf.example config/signatures.conf"
echo "3) Edit interface names and optional signature profile"
echo "4) Run scripts/detect-hci.sh"
