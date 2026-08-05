#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root (sudo)." >&2
  exit 1
fi

# Packages the toolkit cannot run without.
#   bluez        btmon, bluetoothctl, btmgmt, hciconfig
#   python3      signature scanner, fingerprinting, capture parsing
#   rfkill       unblocking adapters before a capture
#   tmux         dual-pane capture + hunt session
REQUIRED=(bluez python3 rfkill tmux)

# Useful alongside the toolkit but not called by any script. These are
# installed one at a time and skipped if unavailable, because `apt install`
# fails as a batch: a single missing package aborts the run and installs
# nothing, which would otherwise leave the toolkit with no dependencies at all.
OPTIONAL=(bluez-tools wireless-tools iw tshark)

apt update

echo "Installing required packages: ${REQUIRED[*]}"
apt install -y "${REQUIRED[@]}"

for pkg in "${OPTIONAL[@]}"; do
  if apt install -y "${pkg}"; then
    continue
  fi
  echo "WARNING: optional package '${pkg}' unavailable; continuing." >&2
done

# Confirm the binaries actually landed. Package names and binary names differ,
# and btmon in particular ships inside bluez rather than a package of its own.
missing=()
for bin in btmon bluetoothctl btmgmt hciconfig rfkill python3 tmux awk; do
  command -v "${bin}" >/dev/null 2>&1 || missing+=("${bin}")
done

if (( ${#missing[@]} > 0 )); then
  echo >&2
  echo "ERROR: required commands still missing: ${missing[*]}" >&2
  echo "Install them before running the toolkit." >&2
  exit 1
fi

echo
echo "Dependencies installed and verified."
echo "Next:"
echo "1) cp config/interfaces.conf.example config/interfaces.conf"
echo "2) cp config/signatures.conf.example config/signatures.conf"
echo "3) Edit interface names and optional signature profile"
echo "4) Run scripts/detect-hci.sh"
echo "5) Run ./tests/test-toolkit.sh to confirm the install"
