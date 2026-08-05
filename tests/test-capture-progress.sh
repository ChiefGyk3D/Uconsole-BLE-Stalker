#!/usr/bin/env bash
set -euo pipefail

# Regression test for operator feedback during a capture.
#
# A field run defaults to 300 seconds. It used to print a header and then show
# nothing at all until it finished, and it wrote its entire summary to a file
# rather than the screen. In the field that is indistinguishable from a hung
# tool, and it also hid the case where the adapter was recording nothing.
#
# This test asserts that a running capture reports progress, that the progress
# counter ignores MGMT echo lines, and that the field run still prints its
# summary to stdout instead of only to a file.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=../scripts/lib.sh
source "${ROOT_DIR}/scripts/lib.sh"

workdir="$(mktemp -d)"
trap 'stop_capture_progress; rm -rf "${workdir}"' EXIT

logfile="${workdir}/capture.log"
: > "${logfile}"

# Simulate btmon appending advertising reports while the capture runs. Each
# advert is written twice: once as a real HCI event and once as the MGMT echo
# of the same advert, which must not be counted.
(
  for i in 1 2 3 4 5 6; do
    printf '> HCI Event: LE Meta Event (0x3e)\n        Address: AA:BB:CC:00:00:%02X (Random)\n' "${i}" >> "${logfile}"
    printf '@ MGMT Event: Device Found (0x0012)\n        Address: AA:BB:CC:00:00:%02X (Random)\n' "${i}" >> "${logfile}"
    sleep 1
  done
) &
writer=$!

progress_out="${workdir}/progress.txt"
start_capture_progress "${logfile}" 4 2 > "${progress_out}" 2>&1
sleep 5
stop_capture_progress
wait "${writer}" 2>/dev/null || true

if ! grep -q "capturing" "${progress_out}"; then
  echo "FAIL: capture produced no progress output at all." >&2
  cat "${progress_out}" >&2
  exit 1
fi

lines="$(grep -c "capturing" "${progress_out}")"
if (( lines < 2 )); then
  echo "FAIL: expected repeated progress lines, got ${lines}." >&2
  cat "${progress_out}" >&2
  exit 1
fi

# The counter must show movement, otherwise it is not proving liveness.
if ! grep -qE "events=[1-9][0-9]*" "${progress_out}"; then
  echo "FAIL: progress never reported a non-zero event count." >&2
  cat "${progress_out}" >&2
  exit 1
fi

# MGMT echoes duplicate every advert. If they were counted the totals would be
# double the number of real events written.
written_events="$(grep -c '^> ' "${logfile}")"
reported="$(grep -oE "events=[0-9]+" "${progress_out}" | tail -1 | cut -d= -f2)"
if (( reported > written_events )); then
  echo "FAIL: progress counted ${reported} events but only ${written_events} were written." >&2
  echo "MGMT echo lines are probably being counted as events." >&2
  exit 1
fi

# A capture that records nothing must say so rather than looking healthy.
empty_log="${workdir}/empty.log"
: > "${empty_log}"
silent_out="${workdir}/silent.txt"
start_capture_progress "${empty_log}" 4 2 > "${silent_out}" 2>&1
sleep 5
stop_capture_progress

if ! grep -q "nothing captured yet" "${silent_out}"; then
  echo "FAIL: a capture recording nothing did not warn the operator." >&2
  cat "${silent_out}" >&2
  exit 1
fi

# The field run must print its summary, not just save it.
if grep -qE '^\} > "\$\{SUMMARY_FILE\}"' "${ROOT_DIR}/scripts/ble-field-run.sh"; then
  echo "FAIL: ble-field-run.sh redirects its summary to a file only." >&2
  echo "The operator would see a blank screen and a path to go and read." >&2
  exit 1
fi

if ! grep -q 'tee "${SUMMARY_FILE}"' "${ROOT_DIR}/scripts/ble-field-run.sh"; then
  echo "FAIL: ble-field-run.sh no longer tees its summary to stdout." >&2
  exit 1
fi

# Both long-running captures must show activity.
for script in ble-field-run.sh ble-spam-watch.sh; do
  if ! grep -q "start_capture_progress" "${ROOT_DIR}/scripts/${script}"; then
    echo "FAIL: ${script} runs a quiet capture with no progress output." >&2
    exit 1
  fi
done

echo "Capture progress test passed."
