# GPS-assisted BLE plotting notes

This repo now includes an optional bridge from BLE capture data to GPS coordinates so the workflow can mature into a plotted map over time.

## Current workflow

1. Capture BLE observations with the existing toolkit scripts.
2. Record GPS points in either CSV form or NMEA sentences.
3. Merge the two sources with:

```bash
python3 scripts/ble-gps-merge.py --gps /path/to/gps.csv --ble /path/to/ble.csv --output logs/ble-gps-plot.csv
```

If GPS is unavailable, omit `--gps` and the output will still contain the BLE rows with blank latitude/longitude values.

4. Plot the resulting CSV in a spreadsheet, Python notebook, or GIS tool.

## Expected CSV output

The merge script writes rows with:
- `timestamp`
- `mac`
- `rssi`
- `latitude`
- `longitude`

That structure is intentionally simple so it can be consumed by later plotting tools without extra transformation.

## Future direction

As the workflow matures, the next upgrade can add:
- live GPS logging during field runs
- automatic map overlays for strong BLE transmitters
- heatmap or RSSI gradient plotting by location
