# Troubleshooting

This page helps diagnose Bluetooth adapter issues on uConsole and Raspberry Pi OS.

## One-command diagnosis

Run the automated report script:

```bash
cd uconsole-ble-foxhunt-toolkit
chmod +x scripts/troubleshoot-bluetooth.sh
./scripts/troubleshoot-bluetooth.sh
```

The script writes a timestamped report in `logs/` that includes:
- controller inventory
- HCI details
- rfkill state
- USB devices
- kernel module status
- Bluetooth-related kernel log snippets
- quick recommendations

## One-command safe recovery + before/after report

If `hci1` is flaky (for example local-name read errors), run:

```bash
sudo ./scripts/recover-hci.sh
```

Or target a specific interface:

```bash
sudo ./scripts/recover-hci.sh hci1
```

What it does:
- runs `troubleshoot-bluetooth.sh` before changes
- applies safe reset steps (`rfkill`, `hciconfig`, `btmgmt`, bluetooth service restart)
- runs diagnostics again after changes
- writes a recovery summary in `logs/recover-*.txt`

## Common findings and fixes

### 1) Only one HCI controller appears

Symptom:
- `bluetoothctl list` shows only one controller

Cause:
- many AC1200 adapters are Wi-Fi only and do not expose Bluetooth

Fix:
- run in single-adapter mode by setting both `CAPTURE_HCI` and `HUNT_HCI` to the same interface in `config/interfaces.conf`
- or run `./scripts/set-adapter-mode.sh single`

### 2) hci1 local-name read error

Symptom:
- `hciconfig -a` shows local-name read failure or timeout on `hci1`

Recovery steps:

```bash
sudo rfkill unblock all
sudo hciconfig hci1 down || true
sudo hciconfig hci1 reset || true
sudo hciconfig hci1 up
sudo btmgmt -i hci1 power off
sudo btmgmt -i hci1 power on
sudo btmgmt -i hci1 le on
sudo btmgmt -i hci1 bredr off
```

If scan traffic still appears in `btmon -i hci1`, the adapter is often usable for passive monitoring.

Note:
- `Set BR/EDR ... failed with status 0x0b (rejected)` is commonly benign on LE-only or restricted adapters.
- In that case, continue with BLE scanning/monitoring; BR/EDR disable is not required for passive BLE workflows.

### 3) btmon package confusion

Symptom:
- package manager cannot find `btmon`

Fix:
- install `bluez` (btmon is part of bluez, not a standalone package)

```bash
sudo apt update
sudo apt install -y bluez bluez-tools
```

### 4) Adapter blocked by rfkill

Symptom:
- `rfkill list` reports soft or hard block

Fix:

```bash
sudo rfkill unblock all
sudo systemctl restart bluetooth
```

### 5) Driver/firmware issues in dmesg

Symptom:
- `dmesg` shows btusb/btmtk firmware load failures or timeouts

Fix:
- replug USB adapter
- use powered hub if power is marginal
- restart Bluetooth service
- test with a known-good BLE dongle if instability persists

## MediaTek AC1200 specific diagnostics

If you are using the HackerGadgets AC1200 USB-C Wi-Fi card, run:

```bash
./scripts/diagnose-mediatek-ac1200.sh
```

This collects USB inventory, controller visibility, rfkill state, module load info, and relevant Bluetooth/MediaTek dmesg lines into a log file under `logs/`.

## Validation and regression checks

Before heading to the field, run:

```bash
./tests/test-toolkit.sh
```

This exercise checks the toolkit scripts, the expected config files, and writes a validation report into `logs/`.

## Optional GPS merge for later plotting

If you want to start correlating BLE observations with GPS positions, use:

```bash
python3 scripts/ble-gps-merge.py --gps /path/to/gps.csv --ble /path/to/ble.csv --output logs/ble-gps-plot.csv
```

That produces a simple CSV suitable for later plotting or map overlays.

## Shareable debug bundle

You can send this output when asking for help:

```bash
latest=$(ls -1t logs/troubleshoot-*.txt | head -n 1)
echo "$latest"
sed -n '1,220p' "$latest"
```
