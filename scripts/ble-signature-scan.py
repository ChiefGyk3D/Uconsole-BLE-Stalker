#!/usr/bin/env python3
import argparse
import re
import sys
from dataclasses import dataclass
from typing import Dict, List, Set


MAC_RE = re.compile(r"([0-9A-F]{2}:){5}[0-9A-F]{2}", re.IGNORECASE)
INT_RE = re.compile(r"-?\d+")
LURE_NAME_RE = re.compile(
    r"airpods|beats|bose|jbl|pair|tracker|keyboard|mouse|speaker|iphone|galaxy",
    re.IGNORECASE,
)


@dataclass
class Match:
    name: str
    confidence: int
    evidence: str


class Stats:
    def __init__(self) -> None:
        self.total_events = 0
        self.unique_addrs: Set[str] = set()
        self.random_addrs: Set[str] = set()
        self.addr_counts: Dict[str, int] = {}
        self.unique_names: Set[str] = set()
        self.lure_name_hits = 0
        self.apple_mfg_events = 0
        self.fast_pair_events = 0
        self.vendor_hits: Dict[str, int] = {}


def parse_log(path: str) -> Stats:
    stats = Stats()
    last_addr = ""
    last_addr_type = ""

    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as handle:
            for raw in handle:
                line = raw.strip()

                if "Address type:" in line:
                    if "Random" in line:
                        last_addr_type = "random"
                    elif "Public" in line:
                        last_addr_type = "public"
                    else:
                        last_addr_type = ""

                if "Address:" in line:
                    mac_match = MAC_RE.search(line)
                    if mac_match:
                        addr = mac_match.group(0).upper()
                        last_addr = addr
                        stats.total_events += 1
                        stats.unique_addrs.add(addr)
                        stats.addr_counts[addr] = stats.addr_counts.get(addr, 0) + 1
                        if last_addr_type == "random":
                            stats.random_addrs.add(addr)

                if "local name:" in line.lower():
                    name = line.split(":", 1)[-1].strip()
                    if name:
                        stats.unique_names.add(name)
                        if LURE_NAME_RE.search(name):
                            stats.lure_name_hits += 1

                if "manufacturer" in line.lower() or "company:" in line.lower():
                    vendor = ""
                    if "(" in line and ")" in line:
                        vendor = line.split("(", 1)[1].split(")", 1)[0].strip()
                    elif ":" in line:
                        vendor = line.split(":", 1)[-1].strip()
                    vendor = vendor.lower()
                    if vendor:
                        stats.vendor_hits[vendor] = stats.vendor_hits.get(vendor, 0) + 1
                    if "apple" in vendor or "0x004c" in vendor or "4c00" in line.lower():
                        stats.apple_mfg_events += 1

                if "fe2c" in line.lower() or "fast pair" in line.lower():
                    stats.fast_pair_events += 1

                if last_addr and "RSSI:" in line:
                    _ = INT_RE.search(line)

    except FileNotFoundError:
        print(f"ERROR: input file not found: {path}", file=sys.stderr)
        sys.exit(2)

    return stats


def clamp_confidence(value: int) -> int:
    return max(1, min(99, value))


def evaluate(stats: Stats) -> List[Match]:
    matches: List[Match] = []

    if stats.total_events == 0:
        return matches

    unique_count = len(stats.unique_addrs)
    random_count = len(stats.random_addrs)
    unique_ratio = unique_count / max(1, stats.total_events)
    random_ratio = random_count / max(1, unique_count)

    if (
        stats.apple_mfg_events >= 20
        and unique_count >= 10
        and random_ratio >= 0.6
        and stats.lure_name_hits >= 3
    ):
        score = 45 + (stats.apple_mfg_events // 4) + int(random_ratio * 15) + min(stats.lure_name_hits, 15)
        matches.append(
            Match(
                name="Flipper-like Apple popup spam pattern",
                confidence=clamp_confidence(score),
                evidence=(
                    f"apple_mfg_events={stats.apple_mfg_events}, unique_addrs={unique_count}, "
                    f"random_ratio={random_ratio:.2f}, lure_name_hits={stats.lure_name_hits}"
                ),
            )
        )

    if stats.total_events >= 80 and unique_count >= 40 and (len(stats.unique_names) >= 15 or len(stats.vendor_hits) >= 5):
        score = 50 + min(stats.total_events // 10, 20) + min(unique_count // 8, 15)
        matches.append(
            Match(
                name="Marauder-like rotating beacon flood",
                confidence=clamp_confidence(score),
                evidence=(
                    f"events={stats.total_events}, unique_addrs={unique_count}, "
                    f"unique_names={len(stats.unique_names)}, vendor_diversity={len(stats.vendor_hits)}"
                ),
            )
        )

    if stats.fast_pair_events >= 10 and unique_count >= 8:
        score = 55 + min(stats.fast_pair_events // 2, 20)
        matches.append(
            Match(
                name="Fast Pair lure flood pattern",
                confidence=clamp_confidence(score),
                evidence=f"fast_pair_events={stats.fast_pair_events}, unique_addrs={unique_count}",
            )
        )

    if stats.total_events >= 60 and unique_ratio >= 0.5:
        score = 35 + min(stats.total_events // 8, 25) + int(unique_ratio * 20)
        matches.append(
            Match(
                name="Generic BLE spam burst",
                confidence=clamp_confidence(score),
                evidence=f"events={stats.total_events}, unique_ratio={unique_ratio:.2f}, random_addrs={random_count}",
            )
        )

    return sorted(matches, key=lambda m: m.confidence, reverse=True)


def print_summary(stats: Stats, matches: List[Match], quiet: bool) -> None:
    if not quiet:
        print("# Signature Scan Summary")
        print(f"events={stats.total_events}")
        print(f"unique_addresses={len(stats.unique_addrs)}")
        print(f"random_addresses={len(stats.random_addrs)}")
        print(f"unique_names={len(stats.unique_names)}")
        print(f"apple_mfg_events={stats.apple_mfg_events}")
        print(f"fast_pair_events={stats.fast_pair_events}")
        print("")

    if not matches:
        print("No high-confidence signatures matched.")
        return

    print("# Matched Signatures")
    for match in matches:
        print(f"MATCH {match.name} confidence={match.confidence}%")
        print(f"  evidence: {match.evidence}")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Defensive BLE signature scanner for common scripted spam/flood patterns"
    )
    parser.add_argument("--input", required=True, help="btmon capture log path")
    parser.add_argument("--quiet", action="store_true", help="Only print match lines")
    args = parser.parse_args()

    stats = parse_log(args.input)
    matches = evaluate(stats)
    print_summary(stats, matches, args.quiet)
    return 0


if __name__ == "__main__":
    sys.exit(main())
