#!/usr/bin/env bash
set -euo pipefail

# Regression test for config parsing.
#
# Config files used to be loaded with 'source', which meant anything in them
# ran as root, since most toolkit scripts require sudo. These checks confirm
# config contents are now treated as data: no command execution, unknown keys
# ignored, and non-numeric values that feed 'timeout' rejected.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=../scripts/lib.sh
source "${ROOT_DIR}/scripts/lib.sh"

workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT

canary="${workdir}/canary"

# 1) A config attempting command execution must not run it.
cat > "${workdir}/evil.conf" <<EOF
ADAPTER_MODE="single"
CAPTURE_HCI="\$(touch ${canary})"
HUNT_HCI="\`touch ${canary}.backtick\`"
EVIL_CMD="x"; touch ${canary}.semicolon
EOF

load_conf_file "${workdir}/evil.conf" \
  ADAPTER_MODE PRIMARY_HCI SECONDARY_HCI CAPTURE_HCI HUNT_HCI \
  SCAN_SECONDS ALERT_ADS_PER_ADDR 2>/dev/null

for artifact in "${canary}" "${canary}.backtick" "${canary}.semicolon"; do
  if [[ -e "${artifact}" ]]; then
    echo "FAIL: config parsing executed a command (${artifact} created)." >&2
    exit 1
  fi
done

if [[ "${ADAPTER_MODE}" != "single" ]]; then
  echo "FAIL: expected ADAPTER_MODE=single, got '${ADAPTER_MODE}'." >&2
  exit 1
fi

# The substitution text must be preserved literally, not evaluated.
if [[ "${CAPTURE_HCI}" != "\$(touch ${canary})" ]]; then
  echo "FAIL: CAPTURE_HCI was not treated as literal data: '${CAPTURE_HCI}'." >&2
  exit 1
fi

# 2) Unknown keys must be ignored rather than assigned.
if [[ -n "${EVIL_CMD:-}" ]]; then
  echo "FAIL: unrecognized key EVIL_CMD was assigned." >&2
  exit 1
fi

# 3) Normal values, comments and quoting must still parse correctly.
cat > "${workdir}/good.conf" <<'EOF'
# leading comment
ADAPTER_MODE="dual"
PRIMARY_HCI='hci0'
CAPTURE_HCI=hci0        # trailing comment
SCAN_SECONDS="45"
EOF

unset ADAPTER_MODE PRIMARY_HCI CAPTURE_HCI SCAN_SECONDS
load_conf_file "${workdir}/good.conf" \
  ADAPTER_MODE PRIMARY_HCI CAPTURE_HCI SCAN_SECONDS 2>/dev/null

[[ "${ADAPTER_MODE}" == "dual" ]] || { echo "FAIL: double-quoted value" >&2; exit 1; }
[[ "${PRIMARY_HCI}" == "hci0" ]] || { echo "FAIL: single-quoted value" >&2; exit 1; }
[[ "${CAPTURE_HCI}" == "hci0" ]] || { echo "FAIL: inline comment not stripped: '${CAPTURE_HCI}'" >&2; exit 1; }
[[ "${SCAN_SECONDS}" == "45" ]] || { echo "FAIL: numeric value" >&2; exit 1; }

# 4) Values with spaces (service/interface lists) must survive intact.
cat > "${workdir}/lists.conf" <<'EOF'
GPS_SERVICES="gpsd gpsd.socket"
EOF

unset GPS_SERVICES
load_conf_file "${workdir}/lists.conf" GPS_SERVICES 2>/dev/null
[[ "${GPS_SERVICES}" == "gpsd gpsd.socket" ]] || {
  echo "FAIL: space-separated list mangled: '${GPS_SERVICES}'" >&2
  exit 1
}

# 5) A non-numeric duration must fall back instead of reaching 'timeout'.
SCAN_SECONDS="not-a-number"
_require_positive_int SCAN_SECONDS 30 2>/dev/null
[[ "${SCAN_SECONDS}" == "30" ]] || {
  echo "FAIL: non-numeric SCAN_SECONDS not corrected: '${SCAN_SECONDS}'" >&2
  exit 1
}

echo "Config parsing test passed."
