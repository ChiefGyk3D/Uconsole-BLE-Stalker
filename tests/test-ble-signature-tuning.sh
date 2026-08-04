#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

SCAN="${ROOT_DIR}/scripts/ble-signature-scan.py"
FIXTURE="${ROOT_DIR}/tests/make-fixture.py"

# A low-volume Apple lure burst. The rate is deliberately placed between the
# shipped conservative threshold (3.0/s) and the tuned one below (2.0/s), so
# this test measures the config override and nothing else.
python3 "${FIXTURE}" --mode spam --duration 20 --rate 2.5 --output "${TMP_DIR}/weak.log"

python3 "${SCAN}" --input "${TMP_DIR}/weak.log" --profile conservative > "${TMP_DIR}/default.txt"
if grep -q 'MATCH Flipper-like Apple popup spam pattern' "${TMP_DIR}/default.txt"; then
  echo "FAIL: conservative profile matched a low-volume burst; thresholds too loose." >&2
  cat "${TMP_DIR}/default.txt" >&2
  exit 1
fi

# Same capture, operator-lowered thresholds, should now match.
cat > "${TMP_DIR}/signatures.conf" <<'EOF'
[general]
profile = aggressive

[aggressive]
min_duration_sec = 5
flipper_min_apple_rate = 2.0
flipper_min_unique_addrs = 8
flipper_min_unique_ratio = 0.60
flipper_min_lure_hits = 4
enable_flipper = true
EOF

python3 "${SCAN}" --input "${TMP_DIR}/weak.log" --config "${TMP_DIR}/signatures.conf" \
  > "${TMP_DIR}/tuned.txt"

if ! grep -q 'MATCH Flipper-like Apple popup spam pattern' "${TMP_DIR}/tuned.txt"; then
  echo "FAIL: tuned config did not lower thresholds as expected." >&2
  cat "${TMP_DIR}/tuned.txt" >&2
  exit 1
fi

# The summary must report where its thresholds came from, otherwise a silently
# ignored config file looks identical to a working one.
grep -q "config_source=${TMP_DIR}/signatures.conf" "${TMP_DIR}/tuned.txt"

# Disabling a rule must actually disable it.
cat > "${TMP_DIR}/disabled.conf" <<'EOF'
[general]
profile = aggressive

[aggressive]
min_duration_sec = 5
flipper_min_apple_rate = 2.0
flipper_min_unique_addrs = 8
flipper_min_unique_ratio = 0.60
flipper_min_lure_hits = 4
enable_flipper = false
EOF

python3 "${SCAN}" --input "${TMP_DIR}/weak.log" --config "${TMP_DIR}/disabled.conf" \
  > "${TMP_DIR}/disabled.txt"
if grep -q 'MATCH Flipper-like Apple popup spam pattern' "${TMP_DIR}/disabled.txt"; then
  echo "FAIL: enable_flipper=false did not disable the rule." >&2
  exit 1
fi

echo "BLE signature tuning test passed."
