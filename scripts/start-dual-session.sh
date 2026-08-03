#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

load_config
need_cmd tmux

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root (sudo) so btmon access works in both panes." >&2
  exit 1
fi

SESSION="ble-hunt"
tmux new-session -d -s "${SESSION}" -n monitor

tmux send-keys -t "${SESSION}:monitor.0" "cd ${ROOT_DIR} && ./scripts/ble-spam-watch.sh ${CAPTURE_HCI} ${SCAN_SECONDS}" C-m

tmux split-window -h -t "${SESSION}:monitor"
tmux send-keys -t "${SESSION}:monitor.1" "cd ${ROOT_DIR} && echo 'Run: ./scripts/foxhunt-rssi.sh <TARGET_MAC> ${HUNT_HCI}'" C-m

tmux select-pane -t "${SESSION}:monitor.0"
tmux attach-session -t "${SESSION}"
