#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

SCAN="${ROOT_DIR}/scripts/ble-signature-scan.py"
FIXTURE="${ROOT_DIR}/tests/make-fixture.py"

# Fixtures are generated in real btmon format. An earlier version of this test
# used invented field names, which parsed as zero records, so a completely
# broken parser passed CI.
python3 "${FIXTURE}" --mode ambient  --duration 30 --output "${TMP_DIR}/ambient.log"
python3 "${FIXTURE}" --mode spam     --duration 30 --output "${TMP_DIR}/spam.log"
python3 "${FIXTURE}" --mode fastpair --duration 30 --output "${TMP_DIR}/fastpair.log"

# --- Parser sanity -----------------------------------------------------------
# Guard the specific failure that hid the bug: names must actually be parsed.
python3 - "$ROOT_DIR" "${TMP_DIR}/spam.log" <<'PY'
import sys
sys.path.insert(0, sys.argv[1] + "/scripts")
import ble_parse

records = ble_parse.parse_records(sys.argv[2])
assert records, "parser returned no records from a valid btmon fixture"
assert any(r.name for r in records), "parser found no device names"
assert any(r.rssi is not None for r in records), "parser found no RSSI values"
assert ble_parse.capture_duration(records) > 0, "parser found no timestamps"
print("parser sanity ok: %d records" % len(records))
PY

# --- True positives ----------------------------------------------------------
python3 "${SCAN}" --input "${TMP_DIR}/spam.log" --profile balanced > "${TMP_DIR}/spam.txt"
grep -q 'MATCH Flipper-like Apple popup spam pattern' "${TMP_DIR}/spam.txt"
grep -q 'MATCH Random-address churn flood' "${TMP_DIR}/spam.txt"
grep -q 'MATCH Generic BLE spam burst' "${TMP_DIR}/spam.txt"

python3 "${SCAN}" --input "${TMP_DIR}/fastpair.log" --profile balanced > "${TMP_DIR}/fp.txt"
grep -q 'MATCH Fast Pair lure flood pattern' "${TMP_DIR}/fp.txt"

# --- False positives ---------------------------------------------------------
# Ambient traffic runs at a comparable event rate to the spam fixture, so this
# only passes if detection keys on address reuse shape rather than volume.
for profile in conservative balanced aggressive; do
  python3 "${SCAN}" --input "${TMP_DIR}/ambient.log" --profile "${profile}" \
    > "${TMP_DIR}/ambient-${profile}.txt"
  if grep -q '^MATCH ' "${TMP_DIR}/ambient-${profile}.txt"; then
    echo "FAIL: ambient traffic matched a signature under '${profile}' profile" >&2
    cat "${TMP_DIR}/ambient-${profile}.txt" >&2
    exit 1
  fi
done

# --- Short-capture guard -----------------------------------------------------
# A two second sample is too small to judge; rates are unstable at that size.
python3 "${FIXTURE}" --mode spam --duration 2 --output "${TMP_DIR}/short.log"
python3 "${SCAN}" --input "${TMP_DIR}/short.log" --profile conservative > "${TMP_DIR}/short.txt"
if grep -q '^MATCH ' "${TMP_DIR}/short.txt"; then
  echo "FAIL: conservative profile judged a 2s capture" >&2
  exit 1
fi

echo "BLE signature detection test passed."
