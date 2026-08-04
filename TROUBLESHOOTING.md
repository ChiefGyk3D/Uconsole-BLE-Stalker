# Troubleshooting

This page helps diagnose Bluetooth adapter issues on uConsole and Raspberry Pi OS.

Primary support target:
- uConsole + AIO v2

Secondary support target:
- Other Linux devices on a best-effort basis

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

### About the AC1200 (HackerGadgets)

The **AC1200 USB-C Wi-Fi card** is sourced from [HackerGadgets.com](https://www.hackergadgets.com/) and is a powerful upgrade for uConsole + AIO v2 deployments:

**Key Specifications:**
- **Chipset:** MediaTek MT7921AUN (WiFi 6/6E + Bluetooth 5.2 combo)
- **WiFi:** Passive monitor mode support + active connectivity (802.11 a/b/g/n/ac/ax)
- **Bluetooth 5.2:** Passive scanning (no transmission required for this toolkit)
- **Antennas:** 2× IPEX U.FL connectors each for WiFi and Bluetooth (swappable high-gain options)
- **Interface:** USB 3.2 Gen 1 Type-C

**For this toolkit:** The AC1200 is **fully passive-capable** for BLE monitoring. It scans and listens without transmitting.

### Diagnostics

If you are using the AC1200 USB-C Wi-Fi card, run:

```bash
./scripts/diagnose-mediatek-ac1200.sh
```

This collects USB inventory, controller visibility, rfkill state, module load info, and relevant Bluetooth/MediaTek dmesg lines into a log file under `logs/`.

## Signature scan for common scripted spam

Run against any btmon capture:

```bash
python3 scripts/ble-signature-scan.py --input logs/btmon-hci0-YYYYMMDD-HHMMSS.log
```

Captures also produce a `.btsnoop` trace alongside the text log. It is much
smaller and can be replayed or summarized directly, which makes it the better
file to attach when reporting an issue or sharing evidence with venue staff:

```bash
btmon -r logs/btmon-hci0-YYYYMMDD-HHMMSS.btsnoop
btmon -a logs/btmon-hci0-YYYYMMDD-HHMMSS.btsnoop
```

This scanner is defensive and heuristic-based. It reports likely pattern families (for example Flipper-like, Marauder-like, Fast Pair lure flood, generic burst) with confidence and evidence, but it cannot prove attribution to a specific tool.

### Signature tuning

Copy and tune profile values for your RF environment:

```bash
cp config/signatures.conf.example config/signatures.conf
nano config/signatures.conf
```

You can switch profile directly per run:

```bash
python3 scripts/ble-signature-scan.py --input logs/btmon-hci0-YYYYMMDD-HHMMSS.log --profile aggressive
```

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

GPS is optional. If GPS is missing, stale, or unreliable, you can omit `--gps` and the script will still write the BLE rows with blank latitude/longitude fields for later plotting when a GPS source becomes available.

## Shareable debug bundle

You can send this output when asking for help:

```bash
latest=$(ls -1t logs/troubleshoot-*.txt | head -n 1)
echo "$latest"
sed -n '1,220p' "$latest"
```
