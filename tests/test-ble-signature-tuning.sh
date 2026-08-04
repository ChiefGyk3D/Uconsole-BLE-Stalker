#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

SAMPLE_LOG="${TMP_DIR}/small-btmon.log"
OUT_DEFAULT="${TMP_DIR}/default.txt"
OUT_TUNED="${TMP_DIR}/tuned.txt"
TUNED_CONF="${TMP_DIR}/signatures.conf"

for i in $(seq 1 10); do
  printf 'Address type: Random (0x01)\n' >> "${SAMPLE_LOG}"
  printf 'Address: AA:BB:CC:DD:EE:%02X\n' "$((i % 255))" >> "${SAMPLE_LOG}"
  printf 'Complete local name: AirPods Pro\n' >> "${SAMPLE_LOG}"
  printf 'Manufacturer data (Apple): 4c00deadbeef\n' >> "${SAMPLE_LOG}"
  printf 'RSSI: -55 dBm\n' >> "${SAMPLE_LOG}"
done

cat > "${TUNED_CONF}" <<'EOF'
[general]
profile = aggressive

[aggressive]
flipper_min_apple_mfg_events = 6
flipper_min_unique_addrs = 4
flipper_min_random_ratio = 0.30
flipper_min_lure_hits = 1
enable_flipper = true
EOF

python3 "${ROOT_DIR}/scripts/ble-signature-scan.py" --input "${SAMPLE_LOG}" --profile conservative > "${OUT_DEFAULT}"
python3 "${ROOT_DIR}/scripts/ble-signature-scan.py" --input "${SAMPLE_LOG}" --config "${TUNED_CONF}" > "${OUT_TUNED}"

if grep -q 'MATCH Flipper-like Apple popup spam pattern' "${OUT_DEFAULT}"; then
  echo "Unexpected conservative match for tiny sample; thresholds may be too loose." >&2
  exit 1
fi

grep -q 'MATCH Flipper-like Apple popup spam pattern' "${OUT_TUNED}"

echo "BLE signature tuning test passed."
