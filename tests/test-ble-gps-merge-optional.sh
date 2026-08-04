#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

BLE_FILE="${TMP_DIR}/ble.csv"
OUTPUT_FILE="${TMP_DIR}/out.csv"

cat > "${BLE_FILE}" <<'EOF'
mac,rssi,timestamp
AA:BB:CC:DD:EE:FF,-65,2026-08-04T11:00:00Z
EOF

python3 "${ROOT_DIR}/scripts/ble-gps-merge.py" --ble "${BLE_FILE}" --output "${OUTPUT_FILE}" >/dev/null

if [[ ! -f "${OUTPUT_FILE}" ]]; then
  echo "Expected output file was not created." >&2
  exit 1
fi

if ! grep -q 'AA:BB:CC:DD:EE:FF' "${OUTPUT_FILE}"; then
  echo "Merged output did not include the BLE row." >&2
  exit 1
fi

if ! grep -q 'latitude,longitude' "${OUTPUT_FILE}"; then
  echo "Output header is missing latitude/longitude columns." >&2
  exit 1
fi

echo "Optional GPS merge test passed."
