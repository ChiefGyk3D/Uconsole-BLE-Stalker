# uConsole BLE Spam Detector + Foxhunt Toolkit

Defensive BLE monitoring toolkit for conference environments (DEF CON, BSides) using ClockworkPi uConsole.

Primary configuration target:
- uConsole with AIO v2

Secondary configuration target:
- Other Linux devices (laptops, mini PCs, SBCs) on a best-effort basis

This toolkit is designed for a dual-adapter setup:
- CM4 built-in Bluetooth (usually `hci0`) for broad monitoring
- External adapter (usually `hci1`) for focused foxhunt tracking

Out-of-box defaults are single-adapter safe:
- default mode is `dual` for stock uConsole + AIO v2 assumptions
- scripts auto-fallback to `hci0` if `hci1` is missing or unstable
- one-command mode switch is available for `dual`, `single`, and `auto`

## Legal and Safety

Use only where passive RF monitoring is allowed and authorized by venue/event policy.
This toolkit is passive monitoring only. Do not transmit, jam, deauth, or interfere.

## Features

- Discover available HCI adapters
- Capture raw BLE monitor output via `btmon`
- Summarize top BLE advertisers and flag high-rate senders
- Match defensive signatures for common scripted BLE spam/flood behaviors
- Live target RSSI tracking for hot/cold foxhunt movement
- Optional dual-pane tmux session for monitor + hunt workflow
- One-command capture plus summary report for field sessions
- Reversible AIO feature profiles to reduce noise and power draw during BLE operations

## Install (Raspberry Pi OS / Debian)

Primary path (uConsole + AIO v2):

```bash
cd uconsole-ble-foxhunt-toolkit
sudo ./scripts/setup-pi.sh
```

Secondary path (other apt-based Linux devices):

```bash
cd uconsole-ble-foxhunt-toolkit
sudo ./scripts/setup-linux.sh
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

Switch adapter mode quickly:

```bash
./scripts/set-adapter-mode.sh status
./scripts/set-adapter-mode.sh dual
./scripts/set-adapter-mode.sh single
./scripts/set-adapter-mode.sh auto
```

## Typical Mapping

- `hci0`: Pi CM4 internal Bluetooth
- `hci1`: external USB Bluetooth (if present)

Note: some AC1200 adapters are Wi-Fi-only and do not expose Bluetooth.

Verify by unplug/replug external adapter and rerun detection.

Mode behavior:
- `dual`: capture prefers `hci0`, hunt prefers `hci1`
- `single`: capture and hunt use one adapter
- `auto`: uses dual when `hci1` exists, otherwise single-like fallback

## Usage

### 1) Detection sweep

```bash
sudo ./scripts/ble-spam-watch.sh
```

At the end of each sweep, the script also runs a defensive signature scan and reports likely matches such as:
- Flipper-like Apple popup spam pattern
- Marauder-like rotating beacon flood
- Fast Pair lure flood pattern
- Generic BLE spam burst
- Random-address churn flood
- Lure-name rotation burst

Arguments:
- interface (default from config)
- duration seconds
- alert threshold (ads per address during window)

Signature tuning options:
- sensitivity profile: conservative, balanced, aggressive
- optional local overrides via config/signatures.conf

Example:

```bash
python3 scripts/ble-signature-scan.py --input logs/btmon-hci0-YYYYMMDD-HHMMSS.log --profile conservative
```

### 2) Raw capture for later analysis

```bash
sudo ./scripts/capture-btmon.sh
```

Creates logs under `logs/`.

### 3) Foxhunt a known sender

```bash
sudo ./scripts/foxhunt-rssi.sh AA:BB:CC:DD:EE:FF
```

Walk slowly and compare median RSSI trend over time.
Rising (less negative) median indicates moving closer.

### 4) Dual-pane session

```bash
sudo ./scripts/start-dual-session.sh
```

Left pane: spam monitor on capture interface.
Right pane: ready for target RSSI tracking command.

### 5) One-command field run (capture + summary)

```bash
sudo ./scripts/ble-field-run.sh
```

Outputs:
- `logs/btmon-<iface>-<timestamp>.log`
- `logs/summary-<iface>-<timestamp>.txt`

The summary now includes a signature scan section based on the captured `btmon` log.

### 6) AIO feature profile modes (disable unused subsystems)

Default profile script behavior is conservative and reversible.

```bash
sudo ./scripts/aio-feature-profile.sh ble-only
sudo ./scripts/aio-feature-profile.sh ble-gps
sudo ./scripts/aio-feature-profile.sh ble-gps-lora
sudo ./scripts/aio-feature-profile.sh restore
```

Customize target interfaces/services:

```bash
cp config/aio-features.conf.example config/aio-features.conf
nano config/aio-features.conf
```

The script writes and uses `logs/aio-state-latest.state` to restore previous interface and service states.

## Validation suite

Run the full local validation suite before a field session:

```bash
./tests/test-toolkit.sh
```

This checks shell syntax for the toolkit scripts, confirms the core config files exist, and writes a timestamped report under `logs/`.

## Optional GPS-assisted plotting

For future mapping work, you can merge BLE observations with GPS coordinates into a CSV that is easy to plot. GPS is optional, so the workflow still works if the GPS source is unavailable or unreliable:

```bash
python3 scripts/ble-gps-merge.py --gps /path/to/gps.csv --ble /path/to/ble.csv --output logs/ble-gps-plot.csv
```

If you omit `--gps`, the script still writes the BLE rows and leaves the latitude/longitude fields blank.

See `docs/gps-plotting-notes.md` for the intended workflow and output schema.

## Practical Conference Workflow

1. Run spam watch near suspected area.
2. Note high-rate address candidates.
3. Validate with repeat scans from different locations.
4. Pick target and switch to RSSI tracking on second adapter.
5. Move in short steps and follow median RSSI increase.

## Field Operation Checklist

Use this sequence when you are actively operating in the field.

1. Pull latest changes:

```bash
git pull
```

2. Enter BLE-focused mode (pick one):

```bash
sudo ./scripts/aio-feature-profile.sh ble-only
sudo ./scripts/aio-feature-profile.sh ble-gps
sudo ./scripts/aio-feature-profile.sh ble-gps-lora
```

3. Run health check:

```bash
./scripts/troubleshoot-bluetooth.sh
```

4. If second adapter is unstable, run recovery:

```bash
sudo ./scripts/recover-hci.sh hci1
```

5. Capture and summarize in one run:

```bash
sudo ./scripts/ble-field-run.sh
```

6. Read the newest summary and select hunt targets:

```bash
latest=$(ls -1t logs/summary-*.txt | head -n 1)
sed -n '1,220p' "$latest"
```

7. Foxhunt a selected target:

```bash
sudo ./scripts/foxhunt-rssi.sh AA:BB:CC:DD:EE:FF hci0
```

8. Restore normal system profile after operation:

```bash
sudo ./scripts/aio-feature-profile.sh restore
```

9. Archive logs before moving locations:

```bash
mkdir -p ~/field-archives
tar -czf ~/field-archives/ble-$(date +%Y%m%d-%H%M%S).tgz logs/
```

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

MediaTek AC1200-specific diagnostic report:

```bash
./scripts/diagnose-mediatek-ac1200.sh
```

## Notes

- BLE spammers may rotate MAC addresses quickly.
- Address-only logic can miss rotating identities.
- Signature matches are heuristic and defensive, not attribution-grade proof of a specific tool.
- Coverage is strong for common scripted BLE spam patterns but not exhaustive for every custom payload seen during Hacker Summer Camp.
