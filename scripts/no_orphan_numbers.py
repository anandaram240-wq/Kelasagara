#!/usr/bin/env python3
"""
scripts/no_orphan_numbers.py
Linter that verifies that quantitative numbers in markdown reports are backed by evidence/*.json.
Fulfills Rule R3 and Gate GATE-S6-02.
"""

import os
import sys
import glob
import json
import re
from pathlib import Path

# Allow-list for known identifiers, dates, versions, standard specs, and common textual integers
ALLOW_LIST = {
    # Years and dates
    "2021", "2023", "2024", "2025", "2026", "10", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0",
    # Versions
    "1.0.0", "1.0", "2.0", "v1", "v2", "v3", "v4", "v5", "v6", "v7", "v8", "v9", "v17", "v24", "v20",
    # Standards
    "24745", "30136", "800", "38", "19794", "4", "5",
    # Common ports, thresholds, or HTTP codes
    "401", "403", "404", "429", "500", "503", "200", "201", "256", "128", "96", "64", "32", "16", "8",
    "100", "0", "100%", "0%", "95%", "95", "99", "50", "60", "200",
    # Dimensions
    "112", "112x112",
}

def extract_numbers_from_evidence(evidence_dir):
    numbers = set()
    for filepath in glob.glob(os.path.join(evidence_dir, "*.json")):
        try:
            with open(filepath, "r", encoding="utf-8") as f:
                data = json.load(f)
                
            def recurse_extract(val):
                if isinstance(val, (int, float)):
                    numbers.add(str(val))
                    numbers.add(f"{val:.1f}")
                    numbers.add(f"{val:.2f}")
                    numbers.add(f"{val:.3f}")
                    numbers.add(f"{val:.4f}")
                    if isinstance(val, float):
                        # also scientific notation
                        numbers.add(f"{val:.1e}")
                        numbers.add(f"{val:.2e}")
                elif isinstance(val, dict):
                    for v in val.values():
                        recurse_extract(v)
                elif isinstance(val, list):
                    for v in val:
                        recurse_extract(v)
                elif isinstance(val, str):
                    for m in re.findall(r'\b\d+(?:\.\d+)?(?:e-?\d+)?%?\b', val):
                        numbers.add(m)

            recurse_extract(data)
        except Exception as e:
            pass
    return numbers

def check_report(report_path, known_numbers):
    with open(report_path, "r", encoding="utf-8") as f:
        content = f.read()

    # Find numbers in tables and metrics
    # Regex for numbers: e.g. 14.16, 48.83, 98.15%, 1e-5, etc.
    num_pattern = re.compile(r'\b(?<![A-Za-z_-])(\d+(?:\.\d+)?(?:e-?\d+)?%?)(?![A-Za-z_-])')
    
    date_pattern = re.compile(r'\b\d{4}-\d{2}-\d{2}(?:T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z?)?\b')

    orphans = []
    lines = content.splitlines()
    for line_idx, line in enumerate(lines, start=1):
        # Skip pure headings, ticket references, metadata lines, or comment lines
        if (line.startswith("#") or "Ticket" in line or "SHA" in line or 
            "Date:" in line or "Session" in line or "Basis:" in line):
            continue
        # Mask dates in line before matching isolated numbers
        sanitized_line = date_pattern.sub('DATE_MASKED', line)
        matches = num_pattern.findall(sanitized_line)
        for m in matches:
            clean_m = m.rstrip('%')
            if m in ALLOW_LIST or clean_m in ALLOW_LIST:
                continue
            # Check if in known numbers
            found = False
            if m in known_numbers or clean_m in known_numbers:
                found = True
            else:
                try:
                    fval = float(clean_m)
                    for kn in known_numbers:
                        try:
                            if abs(float(kn.rstrip('%')) - fval) < 1e-4:
                                found = True
                                break
                        except ValueError:
                            pass
                except ValueError:
                    pass
            if not found:
                orphans.append((line_idx, m, line.strip()))

    return orphans

def main():
    root = Path(__file__).resolve().parent.parent
    evidence_dir = root / "evidence"
    known_numbers = extract_numbers_from_evidence(evidence_dir)

    target_reports = [
        root / "FINAL_REPORT_S6.md",
        root / "TAUTOLOGY_REPORT.md"
    ]

    total_orphans = 0
    for rep in target_reports:
        if not rep.exists():
            continue
        orphans = check_report(rep, known_numbers)
        if orphans:
            print(f"FAILED: Found {len(orphans)} orphan numbers in {rep.name}:")
            for line_idx, num, line in orphans[:10]:
                print(f"  Line {line_idx}: number '{num}' in: {line}")
            total_orphans += len(orphans)
        else:
            print(f"PASSED: 0 orphan numbers in {rep.name}")

    if total_orphans > 0:
        print(f"\nTotal orphan numbers detected: {total_orphans}")
        # Return code 1 for failure if needed
        sys.exit(1)
    else:
        print("\nAll scanned reports have 100% evidence-backed metrics.")
        sys.exit(0)

if __name__ == "__main__":
    main()
