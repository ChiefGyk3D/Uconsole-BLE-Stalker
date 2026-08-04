#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONF_FILE="${ROOT_DIR}/config/interfaces.conf"

# Settings accepted from config/interfaces.conf. Anything else is ignored.
INTERFACES_CONF_KEYS=(
  ADAPTER_MODE
  PRIMARY_HCI
  SECONDARY_HCI
  CAPTURE_HCI
  HUNT_HCI
  SCAN_SECONDS
  ALERT_ADS_PER_ADDR
)

_assign_conf_value() {
  local key="$1"
  local value="$2"

  # Take the contents of a quoted value and discard any trailing comment.
  # Unquoted values are truncated at the first '#'.
  if [[ "${value}" =~ ^\"([^\"]*)\" ]]; then
    value="${BASH_REMATCH[1]}"
  elif [[ "${value}" =~ ^\'([^\']*)\' ]]; then
    value="${BASH_REMATCH[1]}"
  else
    value="${value%%#*}"
    value="${value%"${value##*[![:space:]]}"}"
  fi

  printf -v "${key}" '%s' "${value}"
}

# Read a KEY=value config file without evaluating it.
#
# Using 'source' here would let anything in a config file run as root, since
# most of these scripts require sudo. This parser only assigns values for
# keys that are explicitly allowed, so config contents are treated as data.
#
# Usage: load_conf_file <file> <allowed_key>...
load_conf_file() {
  local file="$1"
  shift
  local allowed_keys=("$@")

  local lineno=0
  local line key value candidate matched

  while IFS= read -r line || [[ -n "${line}" ]]; do
    lineno=$((lineno + 1))

    line="${line%$'\r'}"
    line="${line#"${line%%[![:space:]]*}"}"

    [[ -z "${line}" || "${line}" == \#* ]] && continue

    if [[ ! "${line}" =~ ^([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=(.*)$ ]]; then
      echo "warn: ${file}:${lineno}: ignoring unparsable line." >&2
      continue
    fi

    key="${BASH_REMATCH[1]}"
    value="${BASH_REMATCH[2]}"

    matched=0
    for candidate in "${allowed_keys[@]}"; do
      if [[ "${key}" == "${candidate}" ]]; then
        matched=1
        break
      fi
    done

    if (( matched == 0 )); then
      echo "warn: ${file}:${lineno}: ignoring unrecognized setting '${key}'." >&2
      continue
    fi

    _assign_conf_value "${key}" "${value}"
  done < "${file}"
}

# Fall back to a default when a setting that feeds timeout/awk is not numeric.
_require_positive_int() {
  local key="$1"
  local fallback="$2"
  local current="${!key:-}"

  if [[ ! "${current}" =~ ^[0-9]+$ ]] || (( current == 0 )); then
    echo "warn: ${key}='${current}' is not a positive integer; using ${fallback}." >&2
    printf -v "${key}" '%s' "${fallback}"
  fi
}

load_config() {
  if [[ ! -f "${CONF_FILE}" ]]; then
    echo "Missing ${CONF_FILE}. Copy interfaces.conf.example first." >&2
    exit 1
  fi

  load_conf_file "${CONF_FILE}" "${INTERFACES_CONF_KEYS[@]}"

  SCAN_SECONDS="${SCAN_SECONDS:-30}"
  ALERT_ADS_PER_ADDR="${ALERT_ADS_PER_ADDR:-40}"

  _require_positive_int SCAN_SECONDS 30
  _require_positive_int ALERT_ADS_PER_ADDR 40
}

need_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Missing required command: ${cmd}" >&2
    exit 1
  fi
}

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Run as root (sudo)." >&2
    exit 1
  fi
}

hci_exists() {
  local iface="$1"
  hciconfig "${iface}" >/dev/null 2>&1
}

adapter_mode() {
  local mode="${ADAPTER_MODE:-dual}"
  case "${mode}" in
    dual|single|auto)
      printf "%s\n" "${mode}"
      ;;
    *)
      echo "Unknown ADAPTER_MODE='${mode}'. Supported: dual, single, auto. Falling back to dual." >&2
      printf "%s\n" "dual"
      ;;
  esac
}

ensure_hci() {
  local iface="$1"
  if ! hci_exists "${iface}"; then
    echo "Bluetooth interface ${iface} not found." >&2
    echo "Run scripts/detect-hci.sh to discover adapter names." >&2
    exit 1
  fi
}

pick_runtime_iface() {
  local preferred="$1"
  local fallback="$2"
  local context="$3"

  if [[ -n "${preferred}" ]] && hci_exists "${preferred}"; then
    printf "%s\n" "${preferred}"
    return 0
  fi

  if [[ -n "${fallback}" ]] && hci_exists "${fallback}"; then
    echo "${context}: preferred interface ${preferred} not available; falling back to ${fallback}." >&2
    printf "%s\n" "${fallback}"
    return 0
  fi

  echo "${context}: no usable Bluetooth interface found (preferred=${preferred}, fallback=${fallback})." >&2
  echo "Run scripts/detect-hci.sh and update config/interfaces.conf." >&2
  exit 1
}

default_capture_iface() {
  local preferred="${CAPTURE_HCI:-hci0}"
  local fallback="${PRIMARY_HCI:-hci0}"
  pick_runtime_iface "${preferred}" "${fallback}" "capture"
}

default_hunt_iface() {
  local mode
  mode="$(adapter_mode)"

  local preferred
  local fallback

  case "${mode}" in
    single)
      preferred="${HUNT_HCI:-${CAPTURE_HCI:-${PRIMARY_HCI:-hci0}}}"
      fallback="${CAPTURE_HCI:-${PRIMARY_HCI:-hci0}}"
      ;;
    auto)
      if hci_exists "${SECONDARY_HCI:-hci1}"; then
        preferred="${HUNT_HCI:-${SECONDARY_HCI:-hci1}}"
      else
        preferred="${HUNT_HCI:-${CAPTURE_HCI:-${PRIMARY_HCI:-hci0}}}"
      fi
      fallback="${CAPTURE_HCI:-${PRIMARY_HCI:-hci0}}"
      ;;
    dual|*)
      preferred="${HUNT_HCI:-${SECONDARY_HCI:-hci1}}"
      fallback="${CAPTURE_HCI:-${PRIMARY_HCI:-hci0}}"
      ;;
  esac

  pick_runtime_iface "${preferred}" "${fallback}" "hunt"
}

now_stamp() {
  date +"%Y%m%d-%H%M%S"
}

# btmon is a passive observer of the HCI channel. The controller only emits
# LE Advertising Report events while an LE scan is active, so captures taken
# on an idle adapter are almost empty. These helpers turn scanning on for the
# duration of a capture and reliably tear it down afterwards.
LE_SCAN_PGID=""

start_le_scan() {
  local iface="$1"

  if ! command -v btmgmt >/dev/null 2>&1; then
    echo "warn: btmgmt not found; cannot enable LE scan automatically." >&2
    echo "warn: install bluez-tools, or run 'bluetoothctl scan on' in another shell." >&2
    return 0
  fi

  btmgmt -i "${iface}" power on >/dev/null 2>&1 || true
  btmgmt -i "${iface}" le on >/dev/null 2>&1 || true

  # 'btmgmt find' completes after one discovery window, so loop it to keep the
  # scan running. setsid puts the loop in its own process group, which lets us
  # kill the loop and any in-flight btmgmt child together.
  if command -v setsid >/dev/null 2>&1; then
    setsid bash -c 'while :; do btmgmt -i "$1" find -l >/dev/null 2>&1 || true; sleep 1; done' _ "${iface}" >/dev/null 2>&1 &
    LE_SCAN_PGID=$!
  else
    bash -c 'while :; do btmgmt -i "$1" find -l >/dev/null 2>&1 || true; sleep 1; done' _ "${iface}" >/dev/null 2>&1 &
    LE_SCAN_PGID=$!
  fi

  # Give the controller a moment to actually start scanning before capturing.
  sleep 1
}

stop_le_scan() {
  local iface="${1:-}"

  if [[ -n "${LE_SCAN_PGID}" ]]; then
    kill -- -"${LE_SCAN_PGID}" 2>/dev/null || kill "${LE_SCAN_PGID}" 2>/dev/null || true
    wait "${LE_SCAN_PGID}" 2>/dev/null || true
    LE_SCAN_PGID=""
  fi

  if [[ -n "${iface}" ]] && command -v btmgmt >/dev/null 2>&1; then
    btmgmt -i "${iface}" stop-find >/dev/null 2>&1 || true
  fi
}

# Capture btmon output for a bounded duration.
#
# 'timeout' exits 124 when it stops the command, and under 'set -o pipefail'
# plus 'set -e' that status would abort the calling script before any analysis
# stage could run. Absorb the expected statuses here so callers keep going.
#
# When a btsnoop path is given, btmon also writes a compact binary trace that
# can be replayed with 'btmon -r <file>' or summarized with 'btmon -a <file>'.
# That format is much smaller than the text log and is the better artifact to
# hand to venue SOC/NOC staff.
#
# Usage: run_btmon_capture <iface> <duration> <outfile> [quiet|tee] [btsnoop]
run_btmon_capture() {
  local iface="$1"
  local duration="$2"
  local outfile="$3"
  local mode="${4:-quiet}"
  local btsnoop="${5:-}"
  local rc=0

  local btmon_args=(-i "${iface}")
  if [[ -n "${btsnoop}" ]]; then
    btmon_args+=(-w "${btsnoop}")
  fi

  if [[ "${mode}" == "tee" ]]; then
    timeout "${duration}" stdbuf -oL btmon "${btmon_args[@]}" 2>/dev/null | tee "${outfile}" || rc=$?
  else
    timeout "${duration}" stdbuf -oL btmon "${btmon_args[@]}" >"${outfile}" 2>/dev/null || rc=$?
  fi

  case "${rc}" in
    0|124|143)
      # 0 = clean exit, 124 = timeout reached (expected), 143 = SIGTERM.
      :
      ;;
    *)
      echo "warn: btmon capture on ${iface} exited with status ${rc}." >&2
      echo "warn: results may be incomplete. See TROUBLESHOOTING.md." >&2
      ;;
  esac

  return 0
}

# Warn when a capture produced no usable advertising data, so an empty result
# is reported as a problem instead of looking like a quiet RF environment.
warn_if_capture_empty() {
  local logfile="$1"

  if [[ ! -s "${logfile}" ]]; then
    echo "warn: capture file is empty. The adapter may not be scanning." >&2
    return 0
  fi

  if ! grep -q "Address:" "${logfile}" 2>/dev/null; then
    echo "warn: capture contains no advertising reports." >&2
    echo "warn: check that LE scan is enabled and the adapter is up (see TROUBLESHOOTING.md)." >&2
  fi
}
