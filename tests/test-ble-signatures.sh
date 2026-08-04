#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

SAMPLE_LOG="${TMP_DIR}/sample-btmon.log"
OUT_FILE="${TMP_DIR}/signatures.txt"

names=("AirPods Pro" "Beats Studio" "Galaxy Buds" "JBL Flip" "Bose QC" "Tracker Tag" "Keyboard Pro" "Mouse Pro")
vendors=("Apple" "Apple" "Apple" "Samsung" "Google" "Sony" "Anker" "JBL")

for i in $(seq 1 100); do
  name_idx=$((i % ${#names[@]}))
  vendor_idx=$((i % ${#vendors[@]}))
  printf 'Address type: Random (0x01)\n' >> "${SAMPLE_LOG}"
  printf 'Address: AA:BB:CC:DD:EE:%02X\n' "$((i % 255))" >> "${SAMPLE_LOG}"
  printf 'Complete local name: %s\n' "${names[$name_idx]}" >> "${SAMPLE_LOG}"
  printf 'Manufacturer data (%s): 4c00deadbeef\n' "${vendors[$vendor_idx]}" >> "${SAMPLE_LOG}"
  printf 'Service Data (UUID 0xFE2C): 001122\n' >> "${SAMPLE_LOG}"
  printf 'RSSI: -60 dBm\n' >> "${SAMPLE_LOG}"
done

python3 "${ROOT_DIR}/scripts/ble-signature-scan.py" --input "${SAMPLE_LOG}" --profile aggressive > "${OUT_FILE}"

grep -q 'MATCH Flipper-like Apple popup spam pattern' "${OUT_FILE}"
grep -q 'MATCH Marauder-like rotating beacon flood' "${OUT_FILE}"
grep -q 'MATCH Fast Pair lure flood pattern' "${OUT_FILE}"
grep -q 'MATCH Generic BLE spam burst' "${OUT_FILE}"
grep -q 'MATCH Random-address churn flood' "${OUT_FILE}"
grep -q 'MATCH Lure-name rotation burst' "${OUT_FILE}"

echo "BLE signature detection test passed."
