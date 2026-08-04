#!/usr/bin/env python3
import argparse
import csv
import math
import os
import sys
from datetime import datetime
from typing import List, Tuple


def parse_timestamp(raw: str) -> float:
    raw = raw.strip()
    if not raw:
        return 0.0
    try:
        return float(raw)
    except ValueError:
        try:
            return datetime.fromisoformat(raw.replace('Z', '+00:00')).timestamp()
        except ValueError:
            return 0.0


def parse_gps_file(path: str) -> List[Tuple[float, float, float]]:
    rows = []
    if not os.path.exists(path):
        raise FileNotFoundError(path)
    with open(path, 'r', encoding='utf-8') as handle:
        first_line = handle.readline().strip()
        handle.seek(0)
        if first_line.startswith('$GPRMC'):
            for line in handle:
                if not line.startswith('$GPRMC'):
                    continue
                parts = line.split(',')
                if len(parts) < 8:
                    continue
                lat = parts[3]
                lon = parts[5]
                try:
                    lat_deg = float(lat[:2]) + float(lat[2:]) / 60.0
                    lon_deg = float(lon[:3]) + float(lon[3:]) / 60.0
                    if parts[4] == 'S':
                        lat_deg = -lat_deg
                    if parts[6] == 'W':
                        lon_deg = -lon_deg
                    rows.append((parse_timestamp(parts[1]), lat_deg, lon_deg))
                except ValueError:
                    continue
            return rows

        reader = csv.DictReader(handle)
        for row in reader:
            lat_key = next((k for k in ('lat', 'latitude', 'lat_deg') if k in row), None)
            lon_key = next((k for k in ('lon', 'longitude', 'lon_deg') if k in row), None)
            ts_key = next((k for k in ('timestamp', 'time', 'ts') if k in row), None)
            if not ts_key or not lat_key or not lon_key:
                continue
            try:
                ts = parse_timestamp(row[ts_key])
                lat = float(row[lat_key])
                lon = float(row[lon_key])
                rows.append((ts, lat, lon))
            except (KeyError, ValueError):
                continue
    return rows


def parse_ble_file(path: str) -> List[Tuple[float, str, float]]:
    rows = []
    if not os.path.exists(path):
        raise FileNotFoundError(path)
    with open(path, 'r', encoding='utf-8') as handle:
        first_line = handle.readline().strip()
        handle.seek(0)
        if first_line and ',' not in first_line:
            for line in handle:
                parts = line.strip().split()
                if len(parts) < 2:
                    continue
                try:
                    rssi = float(parts[-1])
                    mac = parts[0]
                    rows.append((0.0, mac, rssi))
                except ValueError:
                    continue
            return rows

        reader = csv.DictReader(handle)
        for row in reader:
            ts_key = next((k for k in ('timestamp', 'time', 'ts') if k in row), None)
            mac_key = next((k for k in ('mac', 'address', 'device') if k in row), None)
            rssi_key = next((k for k in ('rssi', 'signal') if k in row), None)
            if not ts_key or not mac_key or not rssi_key:
                continue
            try:
                rows.append((parse_timestamp(row[ts_key]), row[mac_key], float(row[rssi_key])))
            except (KeyError, ValueError):
                continue
    return rows


def nearest_gps(ts: float, gps_points: List[Tuple[float, float, float]]) -> Tuple[float, float, float]:
    if not gps_points:
        return (ts, 0.0, 0.0)
    best = gps_points[0]
    best_delta = abs(ts - best[0])
    for point in gps_points[1:]:
        delta = abs(ts - point[0])
        if delta < best_delta:
            best = point
            best_delta = delta
    return best


def write_output(path: str, merged_rows: List[Tuple[float, str, float, float, float]]) -> None:
    with open(path, 'w', encoding='utf-8', newline='') as handle:
        writer = csv.writer(handle)
        writer.writerow(['timestamp', 'mac', 'rssi', 'latitude', 'longitude'])
        writer.writerows(merged_rows)


def main() -> int:
    parser = argparse.ArgumentParser(description='Merge BLE observations with optional GPS coordinates for later plotting')
    parser.add_argument('--gps', default=None, help='Optional GPS input file (CSV or NMEA). If omitted, latitude/longitude will be left blank.')
    parser.add_argument('--ble', required=True, help='BLE input file (CSV or simple text)')
    parser.add_argument('--output', default='logs/ble-gps-plot.csv', help='Output CSV for plotting')
    args = parser.parse_args()

    gps_points = []
    if args.gps:
        gps_points = parse_gps_file(args.gps)
    ble_rows = parse_ble_file(args.ble)
    if not ble_rows:
        print('No BLE rows parsed; ensure the input contains MAC/RSSI data.', file=sys.stderr)
        return 1

    gps_available = bool(args.gps) and bool(gps_points)
    if args.gps and not gps_available:
        print('No GPS points parsed; continuing with blank latitude/longitude values.', file=sys.stderr)

    merged_rows = []
    for ts, mac, rssi in ble_rows:
        if gps_available:
            gps_ts, lat, lon = nearest_gps(ts, gps_points)
        else:
            gps_ts = ts
            lat = ''
            lon = ''
        merged_rows.append((gps_ts, mac, rssi, lat, lon))

    output_path = args.output
    os.makedirs(os.path.dirname(output_path) or '.', exist_ok=True)
    write_output(output_path, merged_rows)
    print(f'Wrote {len(merged_rows)} merged rows to {output_path}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
