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

**Operator Qualifications & Compliance:**
- This toolkit is operated under a **General Class Amateur Radio license** in compliance with US FCC regulations and all applicable US federal, state, and local laws.
- Amateur Radio licensing demonstrates intentional training in RF safety, interference prevention, and responsible spectrum use.
- This toolkit is **passive monitoring only**. Do not transmit, jam, deauth, or interfere.

**Critical Warning: BLE Spamming is Harmful and Often Illegal**

This toolkit is designed to **detect and analyze** BLE spam—**not to generate it**. Running BLE spam attacks in uncontrolled, public environments is:

- **Illegal** in most jurisdictions under FCC regulations and computer fraud/interference statutes
- **Dangerous**: BLE spam floods can interfere with emergency services (e.g., disrupting 911 call connectivity or emergency alert systems)
- **Deeply harmful to accessibility**: Hearing-impaired and disabled individuals rely on Bluetooth audio devices for communication, safety, and independence. BLE spam disrupts cochlear implants, hearing aids, and medical alert devices.
- **Unethical**: Subjecting non-consenting users to interference violates their autonomy and safety.

**There is a time and place.** Research involving intentional BLE spam belongs in controlled laboratory environments or isolated locations without public presence or cell coverage—never in public venues where people depend on reliable connectivity.

**Venue Authorization:**
- Use this toolkit only where passive RF monitoring is allowed and authorized by venue/event policy.
- This work has been reviewed and approved by BSidesLV 2026 SOC/NOC staff.
- Initial concerns about extensive antenna equipment were addressed through transparent explanation of the research goals and methodology.
- Multiple BSidesLV staff members have expressed full support and have offered to vouch for this work if needed.

**Community Context:**
- Cybersecurity conferences have historically faced scrutiny and displacement due to security concerns and regulatory paranoia. DEFCON 32 was nearly cancelled when Caesar's Palace withdrew venue support mid-event, leading to the last-minute relocation to Las Vegas Convention Center and the iconic "DEFCON Un-Cancelled" t-shirt.
- This toolkit is built with deep care for the infosec community and its future. Ethical, legal, responsible research strengthens trust in our field and helps venues welcome and protect the conferences we love.
- Responsible boundaries are essential: more aggressive or invasive experiments are conducted in controlled home environments or isolated locations without cell coverage, never at public venues.

**Thank You:**
- Deep gratitude to BSidesLV 2026 SOC/NOC staff for engaging openly, understanding the research mission, and championing ethical experimental work that improves conference security posture and protects community trust.

## Features

- Discover available HCI adapters
- Capture raw BLE monitor output via `btmon`
- Summarize top BLE advertisers and flag high-rate senders
- Match defensive signatures for common scripted BLE spam/flood behaviors
- Live target RSSI tracking for hot/cold foxhunt movement
- Optional dual-pane tmux session for monitor + hunt workflow
- One-command capture plus summary report for field sessions
- Reversible AIO feature profiles to reduce noise and power draw during BLE operations

## Hardware

This toolkit is optimized for uConsole with AIO v2. Optional USB-C expansion adapters sourced from [HackerGadgets.com](https://www.hackergadgets.com/):

- **AC1200 USB-C Wi-Fi Card** (MediaTek MT7921AUN): Dual Bluetooth adapter for parallel capture/hunt workflows; passive BLE 5.2 monitoring + active WiFi 6E connectivity; swappable IPEX antennas.
- **Dual-adapter mode** leverages hci0 (internal) for continuous capture and hci1 (AC1200 external) for live target tracking, or fallback to single-adapter on compatible hardware.

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

Config files are parsed as plain `KEY=value` data, not executed as shell.
Only recognized settings are applied; anything else is reported and ignored.

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

Instantaneous RSSI is far too noisy to navigate by, so the median over a
sliding window is what you steer on. The tool prints a `waiting:` line when the
target has not been heard for a few seconds; many devices advertise only every
few seconds, so silence usually means "not yet" rather than "broken".

### 3a) Identify and track devices across captures

```bash
./scripts/ble-fingerprint.py --input logs/btmon-hci0-YYYYMMDD-HHMMSS.log
```

This records every advertiser in `logs/sightings.json`, so devices seen in an
earlier capture are flagged with `*` when they turn up again.

Tracking a device is not simply tracking its MAC. Most modern devices advertise
with addresses that rotate every few minutes. In a 25 second sample taken on a
conference floor, 63% of addresses were rotating, 33% were random static, and
only 4% were public. Each device therefore gets an identity tier, and the tier
is the part worth reading:

| Tier | Meaning | Reliable for |
|---|---|---|
| `strong` | public address, or a serial number in the advertised name | identifying an individual unit |
| `session` | random static address | one unit until it reboots |
| `model` | rotating address; only the advertisement's structure persists | identifying a product, not a unit |
| `ambiguous` | too little distinguishing content to attribute at all | nothing |

`model` and `ambiguous` hits are leads, not identifications. Several people
carrying the same earbuds produce one `model` fingerprint. In one real capture
three different devices all advertised the name `AC695X_1`, a chipset used by
many cheap earbud vendors.

Keep a list of devices worth flagging:

```bash
cp config/watchlist.conf.example config/watchlist.conf
./scripts/ble-fingerprint.py --input logs/capture.log --watchlist config/watchlist.conf
```

### 3b) Hunt a device whose address rotates

Resolve a target by name, vendor, serial or fingerprint, then track every
address it is currently using:

```bash
sudo ./scripts/foxhunt-rssi.sh --hunt "flipper" --from-capture logs/capture.log
```

Read the tier warning it prints. If the target resolved at `model` or
`ambiguous` tier the address set may span several different devices, and the
RSSI trend will jump between them as you walk.

To supply targets yourself:

```bash
./scripts/ble-fingerprint.py --input logs/capture.log --hunt "whoop" > targets.txt
sudo ./scripts/foxhunt-rssi.sh --targets targets.txt
```

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

This checks shell syntax for the toolkit scripts, runs `shellcheck` when it is installed, confirms the example config files exist, exercises the signature and GPS-merge regression tests, verifies the capture pipeline survives its own timeout, and writes a timestamped report under `logs/`.

The same suite runs in CI on every push and pull request. To match CI locally, install `shellcheck`:

```bash
sudo apt install -y shellcheck
```

## How scanning works

`btmon` is a passive observer of the local HCI channel. It does not start a scan
itself, and a Bluetooth controller only emits `LE Advertising Report` events
while an LE scan is active. A capture taken on an otherwise idle adapter will
therefore be nearly empty.

The capture scripts handle this for you: they enable LE scanning on the target
interface for the duration of the run and stop it again on exit, including when
you interrupt with Ctrl+C. If `btmgmt` is unavailable the scripts warn and
continue, and you can start a scan yourself in another shell:

```bash
bluetoothctl scan on
```

If a capture completes with no advertising reports, the scripts say so rather
than letting an empty result look like a quiet RF environment.

### Capture artifacts

Captures produce both a human-readable text log and a compact `.btsnoop`
binary trace:

```bash
btmon -r logs/btmon-hci0-<timestamp>.btsnoop   # replay the capture
btmon -a logs/btmon-hci0-<timestamp>.btsnoop   # summarize the capture
```

The `.btsnoop` file is far smaller than the text log and is the better artifact
to share with venue SOC/NOC staff or attach to a bug report.

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

## Contributing

Testing on additional hardware is especially welcome. When reporting an issue,
include the output of:

```bash
./scripts/troubleshoot-bluetooth.sh
./tests/test-toolkit.sh
```

Please run `shellcheck -S warning -x scripts/*.sh tests/*.sh` before opening a
pull request; CI enforces the same check.

## License

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE).

Apache-2.0 was chosen so the toolkit stays usable in both open source and
corporate environments, and because it includes an explicit patent grant.
