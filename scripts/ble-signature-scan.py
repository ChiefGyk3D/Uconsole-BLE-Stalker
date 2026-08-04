#!/usr/bin/env python3
"""Defensive BLE signature scanner for scripted spam/flood patterns.

Detection is rate- and shape-based rather than count-based. The thresholds are
calibrated against a capture taken on the BSidesLV floor at Tuscany Suites,
which is deliberately close to the worst realistic case: a hotel full of
security researchers and their gear. Two findings from that capture drive the
design.

* Ambient traffic at a busy venue is enormous. A 20 second sample measured 32
  advertising events/sec across 159 distinct addresses. Absolute event counts
  are therefore meaningless as evidence on their own, and any rule keyed on
  "lots of events" will fire continuously at a conference.

* Nearly all of that traffic uses random addresses. The same capture measured
  a 0.94 random-address ratio, because modern phones and wearables advertise
  with resolvable private addresses by default. A "mostly random addresses"
  test is satisfied by an empty room and is not evidence of anything.

What does separate spam from ambient is address reuse shape. Ordinary devices
hold an address for minutes and are seen repeatedly (measured unique/event
ratio 0.25, with 66% of addresses seen more than once). Tools that rotate the
address on every advertisement push that ratio toward 1.0 with nearly every
address seen exactly once. That shape is what the rules key on.

A caveat worth stating plainly: at a hacker conference there is no such thing
as a clean ambient baseline, because some of the ambient traffic genuinely is
spam. Calibrating here biases toward fewer false positives at quieter venues,
which is the safer direction to be wrong in.
"""

import argparse
import configparser
import os
import re
import sys
from dataclasses import dataclass
from typing import Dict, List, Set

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ble_parse  # noqa: E402


LURE_NAME_RE = re.compile(
    r"airpods|beats|bose|jbl|pair|tracker|keyboard|mouse|speaker|iphone|galaxy",
    re.IGNORECASE,
)
APPLE_LIKE_RE = re.compile(r"airpods|beats|iphone|ipad|watch|airtag", re.IGNORECASE)
APPLE_VENDOR_RE = re.compile(r"apple|0x004c", re.IGNORECASE)
FAST_PAIR_RE = re.compile(r"fe2c", re.IGNORECASE)

# Fallback window used only when a capture carries no usable timestamps.
ASSUMED_DURATION_SEC = 30.0


DEFAULT_RULES = {
    "conservative": {
        "min_duration_sec": 10,
        "flipper_min_apple_rate": 3.0,
        "flipper_min_unique_addrs": 16,
        "flipper_min_unique_ratio": 0.60,
        "flipper_min_lure_hits": 6,
        "marauder_min_event_rate": 20.0,
        "marauder_min_unique_ratio": 0.70,
        "marauder_min_singleton_ratio": 0.75,
        "marauder_min_unique_addrs": 60,
        "marauder_min_unique_names": 20,
        "marauder_min_vendor_diversity": 6,
        "fastpair_min_rate": 1.5,
        "fastpair_min_unique_addrs": 12,
        "generic_min_event_rate": 25.0,
        "generic_min_unique_ratio": 0.75,
        "random_churn_min_event_rate": 25.0,
        "random_churn_min_unique_ratio": 0.85,
        "random_churn_min_singleton_ratio": 0.85,
        "name_rotation_min_unique_names": 18,
        "name_rotation_min_lure_hits": 12,
        "name_rotation_min_event_rate": 15.0,
        "enable_flipper": True,
        "enable_marauder": True,
        "enable_fastpair": True,
        "enable_generic": True,
        "enable_random_churn": True,
        "enable_name_rotation": True,
    },
    "balanced": {
        "min_duration_sec": 5,
        "flipper_min_apple_rate": 2.0,
        "flipper_min_unique_addrs": 10,
        "flipper_min_unique_ratio": 0.50,
        "flipper_min_lure_hits": 3,
        "marauder_min_event_rate": 12.0,
        "marauder_min_unique_ratio": 0.60,
        "marauder_min_singleton_ratio": 0.65,
        "marauder_min_unique_addrs": 40,
        "marauder_min_unique_names": 15,
        "marauder_min_vendor_diversity": 5,
        "fastpair_min_rate": 0.8,
        "fastpair_min_unique_addrs": 8,
        "generic_min_event_rate": 15.0,
        "generic_min_unique_ratio": 0.60,
        "random_churn_min_event_rate": 15.0,
        "random_churn_min_unique_ratio": 0.75,
        "random_churn_min_singleton_ratio": 0.75,
        "name_rotation_min_unique_names": 12,
        "name_rotation_min_lure_hits": 8,
        "name_rotation_min_event_rate": 10.0,
        "enable_flipper": True,
        "enable_marauder": True,
        "enable_fastpair": True,
        "enable_generic": True,
        "enable_random_churn": True,
        "enable_name_rotation": True,
    },
    "aggressive": {
        "min_duration_sec": 3,
        "flipper_min_apple_rate": 0.8,
        "flipper_min_unique_addrs": 6,
        "flipper_min_unique_ratio": 0.35,
        "flipper_min_lure_hits": 2,
        "marauder_min_event_rate": 5.0,
        "marauder_min_unique_ratio": 0.40,
        "marauder_min_singleton_ratio": 0.45,
        "marauder_min_unique_addrs": 20,
        "marauder_min_unique_names": 8,
        "marauder_min_vendor_diversity": 3,
        "fastpair_min_rate": 0.3,
        "fastpair_min_unique_addrs": 4,
        "generic_min_event_rate": 6.0,
        "generic_min_unique_ratio": 0.40,
        "random_churn_min_event_rate": 6.0,
        "random_churn_min_unique_ratio": 0.50,
        "random_churn_min_singleton_ratio": 0.50,
        "name_rotation_min_unique_names": 6,
        "name_rotation_min_lure_hits": 4,
        "name_rotation_min_event_rate": 4.0,
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
        self.duration = 0.0
        self.duration_estimated = False
        self.unique_addrs: Set[str] = set()
        self.random_addrs: Set[str] = set()
        self.addr_counts: Dict[str, int] = {}
        self.unique_names: Set[str] = set()
        self.lure_name_hits = 0
        self.apple_mfg_events = 0
        self.fast_pair_events = 0
        self.vendor_hits: Dict[str, int] = {}
        self.apple_like_name_hits = 0

    @property
    def event_rate(self) -> float:
        return self.total_events / max(self.duration, 0.001)

    @property
    def unique_ratio(self) -> float:
        return len(self.unique_addrs) / max(1, self.total_events)

    @property
    def random_ratio(self) -> float:
        return len(self.random_addrs) / max(1, len(self.unique_addrs))

    @property
    def singleton_ratio(self) -> float:
        """Fraction of addresses observed exactly once.

        The clearest separator between per-advertisement MAC rotation and
        ordinary devices that hold an address for minutes.
        """
        if not self.addr_counts:
            return 0.0
        singles = sum(1 for count in self.addr_counts.values() if count == 1)
        return singles / len(self.addr_counts)

    @property
    def apple_rate(self) -> float:
        return self.apple_mfg_events / max(self.duration, 0.001)

    @property
    def fast_pair_rate(self) -> float:
        return self.fast_pair_events / max(self.duration, 0.001)


class SignatureConfig:
    def __init__(self, profile: str, rules: Dict[str, object], source: str) -> None:
        self.profile = profile
        self.rules = rules
        self.source = source


def parse_log(path: str) -> Stats:
    stats = Stats()

    try:
        records = ble_parse.parse_records(path)
    except FileNotFoundError:
        print(f"ERROR: input file not found: {path}", file=sys.stderr)
        sys.exit(2)

    stats.total_events = len(records)
    duration = ble_parse.capture_duration(records)
    if duration <= 0:
        stats.duration = ASSUMED_DURATION_SEC
        stats.duration_estimated = True
    else:
        stats.duration = duration

    for record in records:
        stats.unique_addrs.add(record.address)
        stats.addr_counts[record.address] = stats.addr_counts.get(record.address, 0) + 1
        if record.is_random:
            stats.random_addrs.add(record.address)

        if record.name:
            stats.unique_names.add(record.name)
            if LURE_NAME_RE.search(record.name):
                stats.lure_name_hits += 1
            if APPLE_LIKE_RE.search(record.name):
                stats.apple_like_name_hits += 1

        for vendor in record.companies:
            stats.vendor_hits[vendor] = stats.vendor_hits.get(vendor, 0) + 1
            if APPLE_VENDOR_RE.search(vendor):
                stats.apple_mfg_events += 1

        for uuid in record.service_uuids:
            if FAST_PAIR_RE.search(uuid):
                stats.fast_pair_events += 1

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
            if base is None:
                continue
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

    # Very short captures produce unstable rates; a two second sample can look
    # like anything. Require a minimum observation window before judging.
    if stats.duration < get_int(cfg.rules, "min_duration_sec"):
        return matches

    unique_count = len(stats.unique_addrs)
    rate = stats.event_rate
    unique_ratio = stats.unique_ratio
    singleton_ratio = stats.singleton_ratio

    if (
        get_bool(cfg.rules, "enable_flipper")
        and stats.apple_rate >= get_float(cfg.rules, "flipper_min_apple_rate")
        and unique_count >= get_int(cfg.rules, "flipper_min_unique_addrs")
        and unique_ratio >= get_float(cfg.rules, "flipper_min_unique_ratio")
        and stats.lure_name_hits >= get_int(cfg.rules, "flipper_min_lure_hits")
    ):
        score = 45 + int(stats.apple_rate * 2) + int(unique_ratio * 20) + min(stats.lure_name_hits, 15)
        matches.append(
            Match(
                name="Flipper-like Apple popup spam pattern",
                confidence=clamp_confidence(score),
                evidence=(
                    f"apple_rate={stats.apple_rate:.1f}/s, unique_addrs={unique_count}, "
                    f"unique_ratio={unique_ratio:.2f}, lure_name_hits={stats.lure_name_hits}"
                ),
            )
        )

    # Address churn and reuse shape are required here. Vendor diversity alone
    # matched any populated area, since a conference floor already shows half a
    # dozen manufacturers within seconds.
    if (
        get_bool(cfg.rules, "enable_marauder")
        and rate >= get_float(cfg.rules, "marauder_min_event_rate")
        and unique_count >= get_int(cfg.rules, "marauder_min_unique_addrs")
        and unique_ratio >= get_float(cfg.rules, "marauder_min_unique_ratio")
        and singleton_ratio >= get_float(cfg.rules, "marauder_min_singleton_ratio")
        and (
            len(stats.unique_names) >= get_int(cfg.rules, "marauder_min_unique_names")
            or len(stats.vendor_hits) >= get_int(cfg.rules, "marauder_min_vendor_diversity")
        )
    ):
        score = 50 + min(int(rate), 20) + int(singleton_ratio * 15)
        matches.append(
            Match(
                name="Marauder-like rotating beacon flood",
                confidence=clamp_confidence(score),
                evidence=(
                    f"rate={rate:.1f}/s, unique_addrs={unique_count}, "
                    f"unique_ratio={unique_ratio:.2f}, singleton_ratio={singleton_ratio:.2f}, "
                    f"unique_names={len(stats.unique_names)}, vendor_diversity={len(stats.vendor_hits)}"
                ),
            )
        )

    if (
        get_bool(cfg.rules, "enable_fastpair")
        and stats.fast_pair_rate >= get_float(cfg.rules, "fastpair_min_rate")
        and unique_count >= get_int(cfg.rules, "fastpair_min_unique_addrs")
    ):
        score = 55 + min(int(stats.fast_pair_rate * 8), 20)
        matches.append(
            Match(
                name="Fast Pair lure flood pattern",
                confidence=clamp_confidence(score),
                evidence=(
                    f"fast_pair_rate={stats.fast_pair_rate:.2f}/s, "
                    f"fast_pair_events={stats.fast_pair_events}, unique_addrs={unique_count}"
                ),
            )
        )

    if (
        get_bool(cfg.rules, "enable_generic")
        and rate >= get_float(cfg.rules, "generic_min_event_rate")
        and unique_ratio >= get_float(cfg.rules, "generic_min_unique_ratio")
    ):
        score = 35 + min(int(rate), 25) + int(unique_ratio * 20)
        matches.append(
            Match(
                name="Generic BLE spam burst",
                confidence=clamp_confidence(score),
                evidence=(
                    f"rate={rate:.1f}/s, unique_ratio={unique_ratio:.2f}, "
                    f"random_addrs={len(stats.random_addrs)}"
                ),
            )
        )

    # Deliberately keyed on reuse shape, not on the random-address ratio.
    # Ambient traffic measured a 0.94 random ratio, so that test alone is
    # useless; per-advertisement rotation shows up as singletons instead.
    if (
        get_bool(cfg.rules, "enable_random_churn")
        and rate >= get_float(cfg.rules, "random_churn_min_event_rate")
        and unique_ratio >= get_float(cfg.rules, "random_churn_min_unique_ratio")
        and singleton_ratio >= get_float(cfg.rules, "random_churn_min_singleton_ratio")
    ):
        score = 40 + int(unique_ratio * 25) + int(singleton_ratio * 20)
        matches.append(
            Match(
                name="Random-address churn flood",
                confidence=clamp_confidence(score),
                evidence=(
                    f"rate={rate:.1f}/s, unique_ratio={unique_ratio:.2f}, "
                    f"singleton_ratio={singleton_ratio:.2f}, random_ratio={stats.random_ratio:.2f}"
                ),
            )
        )

    if (
        get_bool(cfg.rules, "enable_name_rotation")
        and rate >= get_float(cfg.rules, "name_rotation_min_event_rate")
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
        duration_note = " (estimated: capture had no timestamps)" if stats.duration_estimated else ""
        print(f"duration_sec={stats.duration:.1f}{duration_note}")
        print(f"event_rate_per_sec={stats.event_rate:.1f}")
        print(f"unique_addresses={len(stats.unique_addrs)}")
        print(f"unique_ratio={stats.unique_ratio:.3f}")
        print(f"singleton_ratio={stats.singleton_ratio:.3f}")
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
