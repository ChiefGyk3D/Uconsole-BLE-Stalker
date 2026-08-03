# uConsole BLE Spam Detector + Foxhunt Toolkit

Defensive BLE monitoring toolkit for conference environments (DEF CON, BSides) using ClockworkPi uConsole.

This toolkit is designed for a dual-adapter setup:
- CM4 built-in Bluetooth (usually `hci0`) for broad monitoring
- External adapter (usually `hci1`) for focused foxhunt tracking

## Legal and Safety

Use only where passive RF monitoring is allowed and authorized by venue/event policy.
This toolkit is passive monitoring only. Do not transmit, jam, deauth, or interfere.

## Features

- Discover available HCI adapters
- Capture raw BLE monitor output via `btmon`
- Summarize top BLE advertisers and flag high-rate senders
- Live target RSSI tracking for hot/cold foxhunt movement
- Optional dual-pane tmux session for monitor + hunt workflow

## Install (Raspberry Pi OS / Debian)

```bash
cd uconsole-ble-foxhunt-toolkit
sudo ./scripts/setup-pi.sh
```

If `btmon` is reported missing, install `bluez`.
`btmon` is a binary provided by the `bluez` package, not a standalone package.

## Configure Interfaces

```bash
cp config/interfaces.conf.example config/interfaces.conf
nano config/interfaces.conf
```

Then discover adapter names:

```bash
./scripts/detect-hci.sh
```

## Typical Mapping

- `hci0`: Pi CM4 internal Bluetooth
- `hci1`: MediaTek USB Bluetooth side

Verify by unplug/replug external adapter and rerun detection.

## Usage

### 1) Detection sweep

```bash
sudo ./scripts/ble-spam-watch.sh hci0 45 60
```

Arguments:
- interface (default from config)
- duration seconds
- alert threshold (ads per address during window)

### 2) Raw capture for later analysis

```bash
sudo ./scripts/capture-btmon.sh hci0 120
```

Creates logs under `logs/`.

### 3) Foxhunt a known sender

```bash
sudo ./scripts/foxhunt-rssi.sh AA:BB:CC:DD:EE:FF hci1
```

Walk slowly and compare median RSSI trend over time.
Rising (less negative) median indicates moving closer.

### 4) Dual-pane session

```bash
sudo ./scripts/start-dual-session.sh
```

Left pane: spam monitor on capture interface.
Right pane: ready for target RSSI tracking command.

## Practical Conference Workflow

1. Run spam watch near suspected area.
2. Note high-rate address candidates.
3. Validate with repeat scans from different locations.
4. Pick target and switch to RSSI tracking on second adapter.
5. Move in short steps and follow median RSSI increase.

## Git Initialization

```bash
git init
git add .
git commit -m "Initial uConsole BLE spam detector and foxhunt toolkit"
```

## Troubleshooting

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for adapter detection, `hci1` local-name errors, package install issues, and single-adapter fallback workflows.

Quick report command:

```bash
./scripts/troubleshoot-bluetooth.sh
```

Auto-recovery command (runs before/after diagnostics):

```bash
sudo ./scripts/recover-hci.sh
```

## Notes

- BLE spammers may rotate MAC addresses quickly.
- Address-only logic can miss rotating identities.
- For stronger fingerprinting, extend parser with manufacturer/service payload signatures from logs.
