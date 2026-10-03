#!/usr/bin/env python3
"""Summarize ScanSuite results for a person: a --summary-json file or a report archive.

    python3 summarize.py scan.json        # written by scansuite-ci --summary-json
    python3 summarize.py report.zip       # from: api.sh -o report.zip GET /scans/<id>/report

For a summary file: the scan, the gate, findings by severity and the most
severe of them, and how many secrets (never their values). For a report
archive: what it contains and what can be read from it — open ports per host
(nmap), subdomains (OSINT), raw Nuclei results by severity and template
(including the Low/Info ones the server does not store as findings), web
technologies (httpx).
"""
import collections
import io
import json
import re
import sys
import zipfile

ORDER = {"critical": 0, "high": 1, "medium": 2, "low": 3, "info": 4}


def rank(severity):
    return ORDER.get(str(severity).lower(), 9)


def summary_file(path):
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
    scan = data.get("scan") or {}
    print("Scan %s (#%s): %s %s, product %s" % (scan.get("scan_id"), scan.get("id"), scan.get("scan_type"),
                                              scan.get("status"), scan.get("product_name")))
    if scan.get("failed_scanners"):
        print("Scanners that did not complete: %s" % ", ".join(scan["failed_scanners"]))
    gate = data.get("gate") or {}
    if gate:
        print("Gate: %s" % ("passed" if gate.get("passed") else "FAILED"))
    findings = data.get("findings") or []
    counts = collections.Counter(f.get("severity", "?") for f in findings)
    print("Findings: %d %s" % (len(findings), dict(sorted(counts.items(), key=lambda item: rank(item[0])))))
    for finding in sorted(findings, key=lambda f: rank(f.get("severity")))[:40]:
        print("  %-8s %-60s %-12s %s" % (finding.get("severity"), str(finding.get("title"))[:60],
                                        str(finding.get("validation_status") or "")[:12],
                                        str(finding.get("target"))[:70]))
    if len(findings) > 40:
        print("  ... %d more" % (len(findings) - 40))
    secrets = data.get("secrets") or []
    print("Secrets: %d (values are never included)" % len(secrets))
    if not findings:
        print("No stored findings. Low/Info results may be in the report archive only: summarize it too.")


def nmap(text):
    hosts = []
    for line in text.splitlines():
        match = re.match(r"Host: (\S+) \(([^)]*)\)\s+Ports: (.*?)(\t|$)", line)
        if not match:
            continue
        ports = []
        for item in match.group(3).split(", "):
            parts = item.split("/")
            if len(parts) > 6 and parts[1] == "open":
                ports.append("%s/%s %s %s" % (parts[0], parts[2], parts[4], parts[6]))
        hosts.append((match.group(1), match.group(2), ports))
    return hosts


def nuclei(text):
    results = []
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("{"):
            try:
                results.append(json.loads(line))
            except ValueError:
                pass
    return results


def report_archive(path):
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        print("Report archive: %d files" % len(names))
        for name in names:
            print("  %s" % name)

        def read(name):
            return io.TextIOWrapper(archive.open(name), encoding="utf-8", errors="replace").read()

        for name in names:
            if name.endswith(".gnmap"):
                print("\nOpen ports per host (%s):" % name)
                for address, hostname, ports in nmap(read(name)):
                    print("  %s%s" % (address, " (%s)" % hostname if hostname else ""))
                    for port in ports:
                        print("    %s" % port.strip())
            if name.endswith("subdomains-report.txt"):
                subdomains = [line.strip() for line in read(name).splitlines() if line.strip()]
                print("\nSubdomains found (%d) — %s:" % (len(subdomains), name))
                for subdomain in subdomains:
                    print("  %s" % subdomain)
            if name.endswith("dnstwist-report.txt"):
                print("\nLookalike domains (dnstwist; other people's, do not scan):")
                for line in read(name).splitlines():
                    if line.strip() and not line.startswith("*original"):
                        print("  %s" % line.strip())
            if name.endswith("nuclei-report.json"):
                results = nuclei(read(name))
                counts = collections.Counter(r.get("info", {}).get("severity", "?") for r in results)
                print("\nNuclei results: %d %s" % (len(results), dict(sorted(counts.items(), key=lambda item: rank(item[0])))))
                grouped = collections.defaultdict(set)
                for result in results:
                    info = result.get("info", {})
                    key = (info.get("severity", "?"), result.get("template-id", "?"), str(info.get("name", ""))[:50])
                    grouped[key].add("%s:%s" % (result.get("host", ""), result.get("port", "")))
                for (severity, template, title), hosts in sorted(grouped.items(), key=lambda item: (rank(item[0][0]), item[0][1])):
                    print("  %-8s %-32s %-50s %s" % (severity, template[:32], title, ", ".join(sorted(hosts))[:100]))
            if name.endswith("httpx-tech-report.txt"):
                print("\nWeb technologies (httpx):")
                for line in read(name).splitlines():
                    if line.strip():
                        print("  %s" % line.strip()[:160])


def main():
    if len(sys.argv) != 2:
        print(__doc__.strip())
        return 2
    path = sys.argv[1]
    if zipfile.is_zipfile(path):
        report_archive(path)
    else:
        summary_file(path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
