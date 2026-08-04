#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

load_config
need_cmd rfkill
need_cmd awk
need_cmd sed
need_cmd grep
need_cmd ip
need_cmd hciconfig
need_root

AIO_CONF="${ROOT_DIR}/config/aio-features.conf"
STATE_FILE="${ROOT_DIR}/logs/aio-state-latest.state"

WIFI_INTERFACES="wlan0 wlan1"
SDR_INTERFACES=""
LORA_INTERFACES="lora0"
GPS_SERVICES="gpsd gpsd.socket"
LORA_SERVICES=""
SDR_SERVICES=""
EXTRA_DISABLE_SERVICES=""

if [[ -f "${AIO_CONF}" ]]; then
  # shellcheck disable=SC1090
  source "${AIO_CONF}"
fi

split_words() {
  local input="$1"
  read -r -a out <<< "${input}"
  printf "%s\n" "${out[@]:-}"
}

iface_exists() {
  local iface="$1"
  ip link show "${iface}" >/dev/null 2>&1
}

iface_state() {
  local iface="$1"
  if ! iface_exists "${iface}"; then
    echo "missing"
    return
  fi

  if ip link show "${iface}" | grep -q ' state UP '; then
    echo "up"
  else
    echo "down"
  fi
}

service_exists() {
  local svc="$1"
  if ! command -v systemctl >/dev/null 2>&1; then
    return 1
  fi
  systemctl list-unit-files --no-legend --no-pager "${svc}" 2>/dev/null | grep -q "${svc}"
}

service_state() {
  local svc="$1"
  if ! service_exists "${svc}"; then
    echo "missing"
    return
  fi

  if systemctl is-active --quiet "${svc}"; then
    echo "active"
  else
    echo "inactive"
  fi
}

stop_service() {
  local svc="$1"
  if service_exists "${svc}"; then
    systemctl stop "${svc}" || true
  fi
}

start_service_if_was_active() {
  local svc="$1"
  local prior_state="$2"
  if [[ "${prior_state}" == "active" ]] && service_exists "${svc}"; then
    systemctl start "${svc}" || true
  fi
}

snapshot_state() {
  local mode="$1"
  mkdir -p "${ROOT_DIR}/logs"
  {
    echo "# AIO feature state snapshot"
    echo "generated_at=$(date -Is)"
    echo "mode=${mode}"
    echo "rfkill_wifi=$(rfkill list wifi 2>/dev/null | awk '/Soft blocked:/{print $3; exit}' || true)"
    echo "rfkill_bluetooth=$(rfkill list bluetooth 2>/dev/null | awk '/Soft blocked:/{print $3; exit}' || true)"

    for iface in $(split_words "${WIFI_INTERFACES}") $(split_words "${SDR_INTERFACES}") $(split_words "${LORA_INTERFACES}"); do
      [[ -z "${iface}" ]] && continue
      echo "IFACE|${iface}|$(iface_state "${iface}")"
    done

    for svc in $(split_words "${GPS_SERVICES}") $(split_words "${LORA_SERVICES}") $(split_words "${SDR_SERVICES}") $(split_words "${EXTRA_DISABLE_SERVICES}"); do
      [[ -z "${svc}" ]] && continue
      echo "SERVICE|${svc}|$(service_state "${svc}")"
    done
  } > "${STATE_FILE}"
}

ensure_bluetooth_target_up() {
  if hci_exists "${CAPTURE_HCI}"; then
    hciconfig "${CAPTURE_HCI}" up || true
  fi
  if hci_exists "${HUNT_HCI}"; then
    hciconfig "${HUNT_HCI}" up || true
  fi
}

set_iface_down_group() {
  local ifaces="$1"
  for iface in $(split_words "${ifaces}"); do
    [[ -z "${iface}" ]] && continue
    if iface_exists "${iface}"; then
      ip link set "${iface}" down || true
    fi
  done
}

stop_service_group() {
  local services="$1"
  for svc in $(split_words "${services}"); do
    [[ -z "${svc}" ]] && continue
    stop_service "${svc}"
  done
}

apply_mode() {
  local mode="$1"
  local keep_gps=0
  local keep_lora=0

  case "${mode}" in
    ble-only)
      keep_gps=0
      keep_lora=0
      ;;
    ble-gps)
      keep_gps=1
      keep_lora=0
      ;;
    ble-gps-lora)
      keep_gps=1
      keep_lora=1
      ;;
    *)
      echo "Unsupported mode: ${mode}" >&2
      exit 1
      ;;
  esac

  snapshot_state "${mode}"
  rfkill unblock bluetooth || true
  rfkill block wifi || true

  set_iface_down_group "${WIFI_INTERFACES}"
  set_iface_down_group "${SDR_INTERFACES}"

  if [[ "${keep_lora}" -eq 0 ]]; then
    set_iface_down_group "${LORA_INTERFACES}"
    stop_service_group "${LORA_SERVICES}"
  fi

  if [[ "${keep_gps}" -eq 0 ]]; then
    stop_service_group "${GPS_SERVICES}"
  fi

  stop_service_group "${SDR_SERVICES}"
  stop_service_group "${EXTRA_DISABLE_SERVICES}"
  ensure_bluetooth_target_up

  echo "Applied mode ${mode}."
  echo "State snapshot: ${STATE_FILE}"
}

restore_mode() {
  if [[ ! -f "${STATE_FILE}" ]]; then
    echo "No state file found: ${STATE_FILE}" >&2
    echo "Apply a profile first before restore." >&2
    exit 1
  fi

  rfkill unblock wifi || true
  rfkill unblock bluetooth || true

  while IFS='|' read -r kind name state; do
    [[ -z "${kind}" ]] && continue
    [[ "${kind}" =~ ^# ]] && continue

    if [[ "${kind}" == "IFACE" ]]; then
      if [[ "${state}" == "up" ]] && iface_exists "${name}"; then
        ip link set "${name}" up || true
      fi
      continue
    fi

    if [[ "${kind}" == "SERVICE" ]]; then
      start_service_if_was_active "${name}" "${state}"
      continue
    fi
  done < "${STATE_FILE}"

  ensure_bluetooth_target_up
  echo "Restored from state ${STATE_FILE}."
}

usage() {
  cat <<'EOF'
Usage:
  sudo ./scripts/aio-feature-profile.sh ble-only
  sudo ./scripts/aio-feature-profile.sh ble-gps
  sudo ./scripts/aio-feature-profile.sh ble-gps-lora
  sudo ./scripts/aio-feature-profile.sh restore

Modes:
  ble-only      Keep BLE on, disable Wi-Fi/SDR/LoRa/GPS configured features.
  ble-gps       Keep BLE and GPS, disable Wi-Fi/SDR/LoRa configured features.
  ble-gps-lora  Keep BLE, GPS, LoRa; disable Wi-Fi/SDR configured features.
  restore       Restore interface and service states from latest snapshot.

Config file:
  config/aio-features.conf
EOF
}

MODE="${1:-}"
if [[ -z "${MODE}" ]]; then
  usage
  exit 1
fi

case "${MODE}" in
  restore)
    restore_mode
    ;;
  ble-only|ble-gps|ble-gps-lora)
    apply_mode "${MODE}"
    ;;
  *)
    usage
    exit 1
    ;;
esac
