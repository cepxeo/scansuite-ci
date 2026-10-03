#!/usr/bin/env python3
"""Resolve host names (for example subdomains an OSINT scan found) to addresses.

    python3 resolve_targets.py names.txt            # one name per line
    python3 resolve_targets.py a.example.com b.example.com
    python3 resolve_targets.py report_dir/subdomains-report.txt --csv

Prints each name with its IPv4 addresses (or "no address"), then the unique
addresses with the names behind them, and a comma-separated target list for
--target. Uses the system resolver. Deciding which addresses belong to the user
is yours: leave out shared hosting, other people's cloud addresses and lookalike
domains before scanning.
"""
import ipaddress
import socket
import sys
from collections import OrderedDict


def read_names(arguments):
    names = []
    for argument in arguments:
        try:
            with open(argument, encoding="utf-8") as handle:
                lines = handle.read().split()
        except OSError:
            lines = [argument]
        for line in lines:
            name = line.strip().strip(".").lower()
            if name and not name.startswith("#") and name not in names:
                names.append(name)
    return names


def resolve(name):
    try:
        ipaddress.ip_address(name)
        return [name]
    except ValueError:
        pass
    try:
        infos = socket.getaddrinfo(name, None, socket.AF_INET, socket.SOCK_STREAM)
    except socket.gaierror:
        return []
    addresses = []
    for info in infos:
        address = info[4][0]
        if address not in addresses:
            addresses.append(address)
    return addresses


def main():
    arguments = [a for a in sys.argv[1:] if a != "--csv"]
    if not arguments:
        print(__doc__.strip())
        return 2
    by_address = OrderedDict()
    width = max(len(n) for n in read_names(arguments) or ["x"])
    for name in read_names(arguments):
        addresses = resolve(name)
        print("%-*s  %s" % (width, name, ", ".join(addresses) if addresses else "no address"))
        for address in addresses:
            by_address.setdefault(address, []).append(name)
    print()
    print("Unique addresses (%d):" % len(by_address))
    for address, names in by_address.items():
        private = ipaddress.ip_address(address).is_private
        print("  %-15s %s%s" % (address, ", ".join(names), "  [private]" if private else ""))
    print()
    print("--target " + ",".join(by_address))
    return 0


if __name__ == "__main__":
    sys.exit(main())
