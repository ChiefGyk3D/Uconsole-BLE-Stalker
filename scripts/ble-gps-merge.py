#!/usr/bin/env python3
import argparse
import csv
import math
import os
import sys
from datetime import datetime
from typing import List, Tuple


EARTH_RADIUS_M = 6371000.0


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


def parse_ble_file(path: str) -> List[dict]:
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
                    rows.append({
                        'timestamp': 0.0,
                        'mac': parts[0],
                        'rssi': float(parts[-1]),
                        'fingerprint': ' '.join(parts[1:-1]) if len(parts) > 2 else '',
                        'heading': '',
                    })
                except ValueError:
                    continue
            return rows

        reader = csv.DictReader(handle)
        for row in reader:
            ts_key = next((k for k in ('timestamp', 'time', 'ts') if k in row), None)
            mac_key = next((k for k in ('mac', 'address', 'device') if k in row), None)
            rssi_key = next((k for k in ('rssi', 'signal') if k in row), None)
            fingerprint_key = next((k for k in ('fingerprint', 'label', 'name', 'device_name') if k in row), None)
            heading_key = 'heading' if 'heading' in row else None
            if not ts_key or not mac_key or not rssi_key:
                continue
            try:
                rows.append({
                    'timestamp': parse_timestamp(row[ts_key]),
                    'mac': row[mac_key],
                    'rssi': float(row[rssi_key]),
                    'fingerprint': row[fingerprint_key] if fingerprint_key else '',
                    'heading': row[heading_key] if heading_key else '',
                })
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


def calculate_bearing(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    lat1_rad = math.radians(lat1)
    lon1_rad = math.radians(lon1)
    lat2_rad = math.radians(lat2)
    lon2_rad = math.radians(lon2)

    dlon = lon2_rad - lon1_rad
    y = math.sin(dlon) * math.cos(lat2_rad)
    x = math.cos(lat1_rad) * math.sin(lat2_rad) - math.sin(lat1_rad) * math.cos(lat2_rad) * math.cos(dlon)
    bearing = math.degrees(math.atan2(y, x))
    return (bearing + 360.0) % 360.0


def calculate_distance_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    lat1_rad = math.radians(lat1)
    lon1_rad = math.radians(lon1)
    lat2_rad = math.radians(lat2)
    lon2_rad = math.radians(lon2)

    dlat = lat2_rad - lat1_rad
    dlon = lon2_rad - lon1_rad
    a = math.sin(dlat / 2.0) ** 2 + math.cos(lat1_rad) * math.cos(lat2_rad) * math.sin(dlon / 2.0) ** 2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return EARTH_RADIUS_M * c


def write_output(path: str, merged_rows: List[Tuple[float, str, float, str, str, str, str, str, str]]) -> None:
    with open(path, 'w', encoding='utf-8', newline='') as handle:
        writer = csv.writer(handle)
        writer.writerow(['timestamp', 'mac', 'rssi', 'latitude', 'longitude', 'fingerprint', 'heading', 'bearing_to_target', 'distance_m'])
        writer.writerows(merged_rows)


def main() -> int:
    parser = argparse.ArgumentParser(description='Merge BLE observations with optional GPS coordinates for later plotting')
    parser.add_argument('--gps', default=None, help='Optional GPS input file (CSV or NMEA). If omitted, latitude/longitude will be left blank.')
    parser.add_argument('--ble', required=True, help='BLE input file (CSV or simple text)')
    parser.add_argument('--output', default='logs/ble-gps-plot.csv', help='Output CSV for plotting')
    parser.add_argument('--target-lat', type=float, default=None, help='Optional target latitude for bearing/distance calculations')
    parser.add_argument('--target-lon', type=float, default=None, help='Optional target longitude for bearing/distance calculations')
    parser.add_argument('--heading', type=float, default=None, help='Optional heading value to include in the output (degrees)')
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

    if (args.target_lat is None) != (args.target_lon is None):
        print('Both --target-lat and --target-lon must be provided together.', file=sys.stderr)
        return 1

    merged_rows = []
    for row in ble_rows:
        ts = row['timestamp']
        if gps_available:
            gps_ts, lat, lon = nearest_gps(ts, gps_points)
            lat_value = lat
            lon_value = lon
        else:
            gps_ts = ts
            lat_value = ''
            lon_value = ''

        fingerprint_value = row.get('fingerprint', '')
        heading_value = row.get('heading', '')
        if heading_value == '' and args.heading is not None:
            heading_value = args.heading

        bearing_value = ''
        distance_value = ''
        if lat_value != '' and lon_value != '' and args.target_lat is not None and args.target_lon is not None:
            bearing_value = f"{calculate_bearing(float(lat_value), float(lon_value), args.target_lat, args.target_lon):.1f}"
            distance_value = f"{calculate_distance_m(float(lat_value), float(lon_value), args.target_lat, args.target_lon):.0f}"

        merged_rows.append((
            gps_ts,
            row['mac'],
            row['rssi'],
            lat_value,
            lon_value,
            fingerprint_value,
            heading_value,
            bearing_value,
            distance_value,
        ))

    output_path = args.output
    os.makedirs(os.path.dirname(output_path) or '.', exist_ok=True)
    write_output(output_path, merged_rows)
    print(f'Wrote {len(merged_rows)} merged rows to {output_path}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
