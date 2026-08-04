#!/usr/bin/env python3
import argparse
import configparser
import os
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
APPLE_LIKE_RE = re.compile(r"airpods|beats|iphone|ipad|watch|airtag", re.IGNORECASE)


DEFAULT_RULES = {
    "conservative": {
        "flipper_min_apple_mfg_events": 30,
        "flipper_min_unique_addrs": 16,
        "flipper_min_random_ratio": 0.70,
        "flipper_min_lure_hits": 6,
        "marauder_min_events": 120,
        "marauder_min_unique_addrs": 60,
        "marauder_min_unique_names": 20,
        "marauder_min_vendor_diversity": 6,
        "fastpair_min_events": 16,
        "fastpair_min_unique_addrs": 12,
        "generic_min_events": 90,
        "generic_min_unique_ratio": 0.70,
        "random_churn_min_events": 120,
        "random_churn_min_unique_ratio": 0.80,
        "random_churn_min_random_ratio": 0.85,
        "name_rotation_min_unique_names": 18,
        "name_rotation_min_lure_hits": 12,
        "name_rotation_min_events": 100,
        "enable_flipper": True,
        "enable_marauder": True,
        "enable_fastpair": True,
        "enable_generic": True,
        "enable_random_churn": True,
        "enable_name_rotation": True,
    },
    "balanced": {
        "flipper_min_apple_mfg_events": 20,
        "flipper_min_unique_addrs": 10,
        "flipper_min_random_ratio": 0.60,
        "flipper_min_lure_hits": 3,
        "marauder_min_events": 80,
        "marauder_min_unique_addrs": 40,
        "marauder_min_unique_names": 15,
        "marauder_min_vendor_diversity": 5,
        "fastpair_min_events": 10,
        "fastpair_min_unique_addrs": 8,
        "generic_min_events": 60,
        "generic_min_unique_ratio": 0.50,
        "random_churn_min_events": 90,
        "random_churn_min_unique_ratio": 0.70,
        "random_churn_min_random_ratio": 0.80,
        "name_rotation_min_unique_names": 12,
        "name_rotation_min_lure_hits": 8,
        "name_rotation_min_events": 75,
        "enable_flipper": True,
        "enable_marauder": True,
        "enable_fastpair": True,
        "enable_generic": True,
        "enable_random_churn": True,
        "enable_name_rotation": True,
    },
    "aggressive": {
        "flipper_min_apple_mfg_events": 12,
        "flipper_min_unique_addrs": 6,
        "flipper_min_random_ratio": 0.50,
        "flipper_min_lure_hits": 2,
        "marauder_min_events": 45,
        "marauder_min_unique_addrs": 20,
        "marauder_min_unique_names": 8,
        "marauder_min_vendor_diversity": 3,
        "fastpair_min_events": 6,
        "fastpair_min_unique_addrs": 4,
        "generic_min_events": 30,
        "generic_min_unique_ratio": 0.40,
        "random_churn_min_events": 45,
        "random_churn_min_unique_ratio": 0.55,
        "random_churn_min_random_ratio": 0.65,
        "name_rotation_min_unique_names": 6,
        "name_rotation_min_lure_hits": 4,
        "name_rotation_min_events": 40,
        "enable_flipper": True,
        "enable_marauder": True,
        "enable_fastpair": True,
        "enable_generic": True,
        "enable_random_churn": True,
        "enable_name_rotation": True,
    },
}


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
        self.apple_like_name_hits = 0


class SignatureConfig:
    def __init__(self, profile: str, rules: Dict[str, object], source: str) -> None:
        self.profile = profile
        self.rules = rules
        self.source = source


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
                        if APPLE_LIKE_RE.search(name):
                            stats.apple_like_name_hits += 1

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


def config_path_default() -> str:
    script_dir = os.path.dirname(os.path.abspath(__file__))
    root_dir = os.path.abspath(os.path.join(script_dir, ".."))
    return os.path.join(root_dir, "config", "signatures.conf")


def get_int(rules: Dict[str, object], key: str) -> int:
    return int(rules[key])


def get_float(rules: Dict[str, object], key: str) -> float:
    return float(rules[key])


def get_bool(rules: Dict[str, object], key: str) -> bool:
    value = rules[key]
    if isinstance(value, bool):
        return value
    return str(value).strip().lower() in ("1", "true", "yes", "on")


def load_config(profile: str, config_path: str) -> SignatureConfig:
    selected_profile = profile.lower() if profile else ""
    if selected_profile and selected_profile not in DEFAULT_RULES:
        selected_profile = "balanced"
    if not selected_profile:
        selected_profile = "balanced"

    rules = dict(DEFAULT_RULES[selected_profile])
    source = f"defaults:{selected_profile}"

    if not config_path or not os.path.exists(config_path):
        return SignatureConfig(selected_profile, rules, source)

    parser = configparser.ConfigParser()
    parser.read(config_path)

    if not profile and parser.has_option("general", "profile"):
        requested = parser.get("general", "profile").strip().lower()
        if requested in DEFAULT_RULES:
            selected_profile = requested
            rules = dict(DEFAULT_RULES[selected_profile])

    if parser.has_section(selected_profile):
        for key, value in parser.items(selected_profile):
            base = rules.get(key)
            if isinstance(base, bool):
                rules[key] = value.strip().lower() in ("1", "true", "yes", "on")
            elif isinstance(base, float):
                try:
                    rules[key] = float(value)
                except ValueError:
                    pass
            elif isinstance(base, int):
                try:
                    rules[key] = int(value)
                except ValueError:
                    pass

    source = f"{config_path}:{selected_profile}"
    return SignatureConfig(selected_profile, rules, source)


def evaluate(stats: Stats, cfg: SignatureConfig) -> List[Match]:
    matches: List[Match] = []

    if stats.total_events == 0:
        return matches

    unique_count = len(stats.unique_addrs)
    random_count = len(stats.random_addrs)
    unique_ratio = unique_count / max(1, stats.total_events)
    random_ratio = random_count / max(1, unique_count)

    if (
        get_bool(cfg.rules, "enable_flipper")
        and stats.apple_mfg_events >= get_int(cfg.rules, "flipper_min_apple_mfg_events")
        and unique_count >= get_int(cfg.rules, "flipper_min_unique_addrs")
        and random_ratio >= get_float(cfg.rules, "flipper_min_random_ratio")
        and stats.lure_name_hits >= get_int(cfg.rules, "flipper_min_lure_hits")
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

    if (
        get_bool(cfg.rules, "enable_marauder")
        and stats.total_events >= get_int(cfg.rules, "marauder_min_events")
        and unique_count >= get_int(cfg.rules, "marauder_min_unique_addrs")
        and (
            len(stats.unique_names) >= get_int(cfg.rules, "marauder_min_unique_names")
            or len(stats.vendor_hits) >= get_int(cfg.rules, "marauder_min_vendor_diversity")
        )
    ):
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

    if (
        get_bool(cfg.rules, "enable_fastpair")
        and stats.fast_pair_events >= get_int(cfg.rules, "fastpair_min_events")
        and unique_count >= get_int(cfg.rules, "fastpair_min_unique_addrs")
    ):
        score = 55 + min(stats.fast_pair_events // 2, 20)
        matches.append(
            Match(
                name="Fast Pair lure flood pattern",
                confidence=clamp_confidence(score),
                evidence=f"fast_pair_events={stats.fast_pair_events}, unique_addrs={unique_count}",
            )
        )

    if (
        get_bool(cfg.rules, "enable_generic")
        and stats.total_events >= get_int(cfg.rules, "generic_min_events")
        and unique_ratio >= get_float(cfg.rules, "generic_min_unique_ratio")
    ):
        score = 35 + min(stats.total_events // 8, 25) + int(unique_ratio * 20)
        matches.append(
            Match(
                name="Generic BLE spam burst",
                confidence=clamp_confidence(score),
                evidence=f"events={stats.total_events}, unique_ratio={unique_ratio:.2f}, random_addrs={random_count}",
            )
        )

    if (
        get_bool(cfg.rules, "enable_random_churn")
        and stats.total_events >= get_int(cfg.rules, "random_churn_min_events")
        and unique_ratio >= get_float(cfg.rules, "random_churn_min_unique_ratio")
        and random_ratio >= get_float(cfg.rules, "random_churn_min_random_ratio")
    ):
        score = 40 + int(unique_ratio * 25) + int(random_ratio * 20)
        matches.append(
            Match(
                name="Random-address churn flood",
                confidence=clamp_confidence(score),
                evidence=(
                    f"events={stats.total_events}, unique_ratio={unique_ratio:.2f}, "
                    f"random_ratio={random_ratio:.2f}"
                ),
            )
        )

    if (
        get_bool(cfg.rules, "enable_name_rotation")
        and stats.total_events >= get_int(cfg.rules, "name_rotation_min_events")
        and len(stats.unique_names) >= get_int(cfg.rules, "name_rotation_min_unique_names")
        and stats.lure_name_hits >= get_int(cfg.rules, "name_rotation_min_lure_hits")
    ):
        score = 45 + min(len(stats.unique_names), 20) + min(stats.lure_name_hits // 2, 15)
        matches.append(
            Match(
                name="Lure-name rotation burst",
                confidence=clamp_confidence(score),
                evidence=(
                    f"unique_names={len(stats.unique_names)}, lure_name_hits={stats.lure_name_hits}, "
                    f"apple_like_name_hits={stats.apple_like_name_hits}"
                ),
            )
        )

    return sorted(matches, key=lambda m: m.confidence, reverse=True)


def print_summary(stats: Stats, matches: List[Match], quiet: bool, cfg: SignatureConfig) -> None:
    if not quiet:
        print("# Signature Scan Summary")
        print(f"profile={cfg.profile}")
        print(f"config_source={cfg.source}")
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
    parser.add_argument(
        "--profile",
        default=None,
        choices=["conservative", "balanced", "aggressive"],
        help="Detection sensitivity profile (overrides config when provided)",
    )
    parser.add_argument(
        "--config",
        default=config_path_default(),
        help="Optional signatures config file path",
    )
    parser.add_argument("--quiet", action="store_true", help="Only print match lines")
    args = parser.parse_args()

    cfg = load_config(args.profile, args.config)
    stats = parse_log(args.input)
    matches = evaluate(stats, cfg)
    print_summary(stats, matches, args.quiet, cfg)
    return 0


if __name__ == "__main__":
    sys.exit(main())
