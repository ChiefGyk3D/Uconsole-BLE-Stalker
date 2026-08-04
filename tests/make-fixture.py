#!/usr/bin/env python3
"""Generate synthetic btmon-format captures for detector testing.

Fixtures are emitted in the exact text format btmon produces, including the
'> HCI Event' block header and timestamp column. Hand-written fixtures using
invented field names (for example 'Complete local name:') silently parse as
empty, which previously let a completely broken parser pass CI.
"""

import argparse
import random
import sys


def rand_mac(rng: random.Random) -> str:
    return ":".join(f"{rng.randint(0, 255):02X}" for _ in range(6))


def emit(handle, timestamp: float, addr: str, addr_type: str, rssi: int,
         name: str = "", company: str = "", company_id: int = 0,
         service_uuid: str = "", addr_class: str = "Resolvable") -> None:
    handle.write(f"> HCI Event: LE Meta Event (0x3e) plen 43 {' ' * 20}#1 {timestamp:.6f}\n")
    handle.write("      LE Extended Advertising Report (0x0d)\n")
    handle.write("        Num reports: 1\n")
    handle.write("        Entry 0\n")
    handle.write("          Event type: 0x0013\n")
    handle.write("          Legacy PDU Type: ADV_IND (0x0013)\n")
    handle.write(f"          Address type: {addr_type} (0x01)\n")
    handle.write(f"          Address: {addr} ({addr_class})\n")
    handle.write("          Primary PHY: LE 1M\n")
    handle.write("          TX power: 127 dBm\n")
    handle.write(f"          RSSI: {rssi} dBm (0xa3)\n")
    handle.write("          Data length: 24\n")
    handle.write("          Flags: 0x1a\n")
    if name:
        handle.write(f"          Name (complete): {name}\n")
    if company:
        handle.write(f"          Company: {company} ({company_id})\n")
    if service_uuid:
        handle.write(f"          Service Data: {service_uuid}\n")


def gen_ambient(handle, duration: float, rng: random.Random,
                rate: float = 30.0) -> None:
    """Ordinary venue traffic: devices hold an address and repeat."""
    devices = []
    for i in range(60):
        devices.append({
            "addr": rand_mac(rng),
            "type": "Random" if i % 20 else "Public",
            "name": f"Device-{i}" if i % 12 == 0 else "",
            "company": rng.choice(["Apple, Inc.", "Samsung Electronics Co. Ltd.",
                                   "Microsoft", "LG Electronics"]) if i % 3 == 0 else "",
        })
    count = max(1, int(duration * rate))
    for n in range(count):
        dev = devices[rng.randrange(len(devices))]
        emit(handle, n * (duration / count), dev["addr"], dev["type"],
             rng.randint(-95, -45), dev["name"], dev["company"], 76)


def gen_spam(handle, duration: float, rng: random.Random,
             rate: float = 45.0) -> None:
    """MAC-rotating Apple popup spam: new address nearly every advertisement."""
    lures = ["AirPods Pro", "Beats Studio", "AirPods Max", "Apple TV",
             "AirTag", "Bose QC", "JBL Flip", "Galaxy Buds"]
    count = max(1, int(duration * rate))
    for n in range(count):
        emit(handle, n * (duration / count), rand_mac(rng), "Random",
             rng.randint(-80, -40), rng.choice(lures), "Apple, Inc.", 76,
             "Service Data: Google (0xfe2c)" if n % 4 == 0 else "")


def gen_fastpair(handle, duration: float, rng: random.Random,
                 rate: float = 20.0) -> None:
    """Fast Pair lure flood."""
    count = max(1, int(duration * rate))
    for n in range(count):
        emit(handle, n * (duration / count), rand_mac(rng), "Random",
             rng.randint(-75, -45), "Pair Now", "Google", 224,
             "Service Data: Google (0xfe2c)")


def gen_identity(handle, duration: float, rng: random.Random,
                 rate: float = 4.0) -> None:
    """One device of each address class, for identity-tier testing.

    Includes a device that advertises its name only intermittently, which is
    what splits a single physical device across two identity keys unless the
    tool coalesces them.
    """
    tick = 1.0 / rate
    n = 0

    def step():
        nonlocal n
        n += 1
        return n * tick

    for _ in range(6):
        # Public address: btmon annotates these with an OUI or vendor name.
        emit(handle, step(), "40:ED:98:18:DE:AB", "Public", -55,
             "FIIO BTR11", "Guangzhou FiiO", 1234, addr_class="OUI 40-ED-98")
    for _ in range(6):
        # Random static: stable until the device reboots.
        emit(handle, step(), "E7:D3:B0:3F:95:E5", "Random", -58,
             "Speaker", "Microsoft", 6, addr_class="Static")
    for _ in range(6):
        # Resolvable private: rotates, so each sighting looks like a new device.
        emit(handle, step(), rand_mac(rng), "Random", -70,
             "", "Apple, Inc.", 76, addr_class="Resolvable")
    for _ in range(6):
        # Non-resolvable private also rotates, despite the name containing
        # 'Resolvable' as a substring.
        emit(handle, step(), rand_mac(rng), "Random", -72,
             "", "LG Electronics", 96, addr_class="Non-Resolvable")
    for i in range(8):
        # Serial-bearing device that omits its name on every other advert.
        emit(handle, step(), "DA:AB:97:C5:53:68", "Random", -66,
             "WHOOP 5AM0191117" if i % 2 == 0 else "", "", 0,
             addr_class="Static")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", required=True,
                        choices=["ambient", "spam", "fastpair", "identity"])
    parser.add_argument("--duration", type=float, default=30.0)
    parser.add_argument("--rate", type=float, default=None,
                        help="advertisements per second (default: mode-specific)")
    parser.add_argument("--seed", type=int, default=1337)
    parser.add_argument("--output", default="-")
    args = parser.parse_args()

    rng = random.Random(args.seed)
    handle = sys.stdout if args.output == "-" else open(args.output, "w", encoding="utf-8")
    generator = {"ambient": gen_ambient, "spam": gen_spam,
                 "fastpair": gen_fastpair, "identity": gen_identity}[args.mode]
    extra = {} if args.rate is None else {"rate": args.rate}
    try:
        generator(handle, args.duration, rng, **extra)
    finally:
        if handle is not sys.stdout:
            handle.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
