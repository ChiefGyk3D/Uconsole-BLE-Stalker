#!/usr/bin/env bash
set -euo pipefail

# Regression test for the capture pipeline.
#
# btmon runs until 'timeout' stops it, which makes timeout exit 124. Under
# 'set -o pipefail' plus 'set -e' that status used to abort the calling script
# before any analysis stage ran, so summaries and signature scans silently
# never executed. This test stubs btmon and asserts that execution continues
# past the capture and that the captured data is still written.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=../scripts/lib.sh
source "${ROOT_DIR}/scripts/lib.sh"

workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT

# Stub btmon with a process that never exits on its own, so timeout must kill it.
mkdir -p "${workdir}/bin"
cat > "${workdir}/bin/btmon" <<'STUB'
#!/usr/bin/env bash
while :; do
  echo "        Address: AA:BB:CC:DD:EE:FF (Resolvable)"
  echo "        RSSI: -60 dBm (0xc4)"
  sleep 0.1
done
STUB
chmod +x "${workdir}/bin/btmon"

PATH="${workdir}/bin:${PATH}"
export PATH

capture_log="${workdir}/capture.log"
reached_analysis=0

run_btmon_capture "hci0" 2 "${capture_log}" quiet
reached_analysis=1

if (( reached_analysis != 1 )); then
  echo "FAIL: execution did not continue past the capture stage." >&2
  exit 1
fi

if [[ ! -s "${capture_log}" ]]; then
  echo "FAIL: capture log is empty; capture output was not written." >&2
  exit 1
fi

if ! grep -q "Address:" "${capture_log}"; then
  echo "FAIL: capture log is missing expected advertising data." >&2
  exit 1
fi

# The tee variant must survive the same timeout status.
tee_log="${workdir}/capture-tee.log"
run_btmon_capture "hci0" 2 "${tee_log}" tee >/dev/null
if [[ ! -s "${tee_log}" ]]; then
  echo "FAIL: tee-mode capture log is empty." >&2
  exit 1
fi

# An empty capture should be reported rather than passing silently.
empty_log="${workdir}/empty.log"
: > "${empty_log}"
if ! warn_if_capture_empty "${empty_log}" 2>&1 | grep -q "warn:"; then
  echo "FAIL: empty capture did not produce a warning." >&2
  exit 1
fi

echo "Capture resilience test passed."
