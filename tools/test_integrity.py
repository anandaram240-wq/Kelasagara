#!/usr/bin/env python3
"""
tools/test_integrity.py
Audits test suites across backend (TypeScript) and client (Dart) for test-smells,
tautologies, zero-assertion tests, skipped tests, .only, swallowed exceptions, and mock-on-unit.
Implements Rule R4 and Ticket Z-02 of Stage S6.
"""

import os
import sys
import re
import json
import glob
from pathlib import Path

def analyze_ts_test_file(filepath):
    with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
        content = f.read()
        lines = content.splitlines()

    test_pattern = re.compile(r'\b(?:it|test)\s*\(\s*([\'"`].*?[\'"`])', re.MULTILINE)
    skip_pattern = re.compile(r'\b(?:it\.skip|test\.skip|xit|xtest)\s*\(')
    only_pattern = re.compile(r'\b(?:it\.only|test\.only|fit)\s*\(')
    assertion_pattern = re.compile(r'\b(?:assert|expect)\b')
    tautology_patterns = [
        re.compile(r'assert(?:\.[a-zA-Z]+)?\s*\(\s*([a-zA-Z0-9_]+)\s*,\s*\1\s*\)'),
        re.compile(r'assert\s*\(\s*true\s*\)'),
        re.compile(r'expect\s*\(\s*true\s*\)\.to(?:Be|Equal)\s*\(\s*true\s*\)'),
        re.compile(r'expect\s*\(\s*([a-zA-Z0-9_]+)\s*\)\.to(?:Be|Equal)\s*\(\s*\1\s*\)'),
        re.compile(r'expect\s*\(\s*([a-zA-Z0-9_]+)\s*===?\s*\1\s*\)')
    ]
    or_true_pattern = re.compile(r'\|\|\s*true\b')
    swallowed_err_pattern = re.compile(r'catch\s*\([^)]*\)\s*\{\s*(?:\/\/.*|\/\*.*?\*\/|\s*console\.log\([^)]*\);?\s*)*\}', re.MULTILINE)

    tests = list(test_pattern.finditer(content))
    total_tests = len(tests)
    skipped_tests = len(skip_pattern.findall(content))
    only_tests = len(only_pattern.findall(content))
    total_assertions = len(assertion_pattern.findall(content))
    tautologies = []
    for pat in tautology_patterns:
        for m in pat.finditer(content):
            tautologies.append(m.group(0))
    or_trues = list(or_true_pattern.finditer(content))
    swallowed_exceptions = list(swallowed_err_pattern.finditer(content))

    # Split into individual test blocks to detect zero-assertion tests
    zero_assertion_tests = []
    for match in tests:
        test_name = match.group(1)
        start_pos = match.start()
        brace_pos = content.find('{', start_pos)
        if brace_pos != -1:
            depth = 1
            idx = brace_pos + 1
            while idx < len(content) and depth > 0:
                if content[idx] == '{':
                    depth += 1
                elif content[idx] == '}':
                    depth -= 1
                idx += 1
            test_body = content[brace_pos:idx]
            if not assertion_pattern.search(test_body):
                zero_assertion_tests.append(test_name)

    mock_on_unit = []
    base_name = Path(filepath).stem.replace('.test', '')
    if 'mock' in content.lower():
        if re.search(rf'mock(?:ResolvedValue|ReturnValue|Implementation)?.*{base_name}', content, re.IGNORECASE):
            mock_on_unit.append(f"Potential mock on unit {base_name}")

    return {
        "file": str(filepath),
        "language": "typescript",
        "test_count": total_tests,
        "assertion_count": total_assertions,
        "skipped_tests": skipped_tests,
        "only_tests": only_tests,
        "zero_assertion_tests": zero_assertion_tests,
        "tautological_assertions": tautologies,
        "or_true_count": len(or_trues),
        "swallowed_exceptions": len(swallowed_exceptions),
        "mock_on_unit": mock_on_unit
    }

def analyze_dart_test_file(filepath):
    with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
        content = f.read()

    test_pattern = re.compile(r'\b(?:test|testWidgets)\s*\(\s*([\'"].*?[\'"])')
    skip_pattern = re.compile(r'\bskip\s*:\s*(?:true|[\'"].*?[\'"])')
    only_pattern = re.compile(r'\bsolo\s*:\s*true')
    assertion_pattern = re.compile(r'\b(?:expect|assert)\s*\(')
    tautology_patterns = [
        re.compile(r'expect\s*\(\s*([a-zA-Z0-9_]+)\s*,\s*equals\s*\(\s*\1\s*\)\s*\)'),
        re.compile(r'expect\s*\(\s*([a-zA-Z0-9_]+)\s*,\s*\1\s*\)'),
        re.compile(r'expect\s*\(\s*true\s*,\s*isTrue\s*\)')
    ]
    or_true_pattern = re.compile(r'\|\|\s*true\b')
    swallowed_err_pattern = re.compile(r'catch\s*\([^)]*\)\s*\{\s*(?:\/\/.*|\/\*.*?\*\/|\s*print\([^)]*\);?\s*)*\}', re.MULTILINE)

    tests = list(test_pattern.finditer(content))
    total_tests = len(tests)
    skipped_tests = len(skip_pattern.findall(content))
    only_tests = len(only_pattern.findall(content))
    total_assertions = len(assertion_pattern.findall(content))
    tautologies = []
    for pat in tautology_patterns:
        for m in pat.finditer(content):
            tautologies.append(m.group(0))
    or_trues = list(or_true_pattern.finditer(content))
    swallowed_exceptions = list(swallowed_err_pattern.finditer(content))

    zero_assertion_tests = []
    for match in tests:
        test_name = match.group(1)
        start_pos = match.start()
        brace_pos = content.find('{', start_pos)
        if brace_pos != -1:
            depth = 1
            idx = brace_pos + 1
            while idx < len(content) and depth > 0:
                if content[idx] == '{':
                    depth += 1
                elif content[idx] == '}':
                    depth -= 1
                idx += 1
            test_body = content[brace_pos:idx]
            if not assertion_pattern.search(test_body):
                zero_assertion_tests.append(test_name)

    return {
        "file": str(filepath),
        "language": "dart",
        "test_count": total_tests,
        "assertion_count": total_assertions,
        "skipped_tests": skipped_tests,
        "only_tests": only_tests,
        "zero_assertion_tests": zero_assertion_tests,
        "tautological_assertions": [t.group(0) for t in tautologies],
        "or_true_count": len(or_trues),
        "swallowed_exceptions": len(swallowed_exceptions),
        "mock_on_unit": []
    }

def main():
    root = Path(__file__).resolve().parent.parent
    backend_tests = sorted(glob.glob(str(root / "backend" / "src" / "tests" / "*.test.ts")))
    dart_tests = sorted(glob.glob(str(root / "test" / "*_test.dart")))

    results = []
    total_tests = 0
    total_assertions = 0
    total_skipped = 0
    total_only = 0
    total_zero_assert = 0
    total_tautologies = 0
    total_or_true = 0
    total_swallowed = 0
    total_mock_unit = 0

    for tf in backend_tests:
        r = analyze_ts_test_file(tf)
        results.append(r)
        total_tests += r["test_count"]
        total_assertions += r["assertion_count"]
        total_skipped += r["skipped_tests"]
        total_only += r["only_tests"]
        total_zero_assert += len(r["zero_assertion_tests"])
        total_tautologies += len(r["tautological_assertions"])
        total_or_true += r["or_true_count"]
        total_swallowed += r["swallowed_exceptions"]
        total_mock_unit += len(r["mock_on_unit"])

    for tf in dart_tests:
        r = analyze_dart_test_file(tf)
        results.append(r)
        total_tests += r["test_count"]
        total_assertions += r["assertion_count"]
        total_skipped += r["skipped_tests"]
        total_only += r["only_tests"]
        total_zero_assert += len(r["zero_assertion_tests"])
        total_tautologies += len(r["tautological_assertions"])
        total_or_true += r["or_true_count"]
        total_swallowed += r["swallowed_exceptions"]
        total_mock_unit += len(r["mock_on_unit"])

    evidence_data = {
        "ticket": "Z-02",
        "description": "Test-Integrity Baseline Scan across backend (TypeScript) and client (Dart)",
        "summary": {
            "total_files_scanned": len(results),
            "backend_test_files": len(backend_tests),
            "dart_test_files": len(dart_tests),
            "total_tests": total_tests,
            "total_assertions": total_assertions,
            "assertions_per_test": round(total_assertions / max(1, total_tests), 2),
            "skipped_tests": total_skipped,
            "only_tests": total_only,
            "zero_assertion_tests": total_zero_assert,
            "tautological_assertions": total_tautologies,
            "or_true_occurrences": total_or_true,
            "swallowed_exceptions": total_swallowed,
            "mock_on_unit_occurrences": total_mock_unit,
            "hypothesis_h1_confirmed": bool(total_tautologies > 0 or total_zero_assert > 0 or total_swallowed > 0)
        },
        "files": results
    }

    os.makedirs(root / "evidence", exist_ok=True)
    evidence_path = root / "evidence" / "z02_test_integrity.json"
    with open(evidence_path, "w", encoding="utf-8") as f:
        json.dump(evidence_data, f, indent=2)

    # Render TAUTOLOGY_REPORT.md
    report_lines = [
        "# KELASAGARA BIOMATCH · TEST-INTEGRITY BASELINE AUDIT (TAUTOLOGY_REPORT.md)",
        f"**Audit Date:** 2026-10-10",
        f"**Files Scanned:** {len(results)} ({len(backend_tests)} TS backend, {len(dart_tests)} Dart client)",
        f"**Hypothesis $H_1$ Status:** {'CONFIRMED (Defects cataloged below)' if evidence_data['summary']['hypothesis_h1_confirmed'] else 'REFUTED (Zero smells found)'}",
        "",
        "## 1. Summary Metrics",
        "",
        "| Metric | Count | Acceptable Limit | Status |",
        "| :--- | :---: | :---: | :---: |",
        f"| Total Test Files Scanned | {len(results)} | N/A | OBSERVED |",
        f"| Total Defined Tests | {total_tests} | >= 100 | {'PASS' if total_tests >= 100 else 'FAIL'} |",
        f"| Total Assertions | {total_assertions} | >= total tests | {'PASS' if total_assertions >= total_tests else 'FAIL'} |",
        f"| Mean Assertions per Test | {evidence_data['summary']['assertions_per_test']} | >= 1.0 | {'PASS' if evidence_data['summary']['assertions_per_test'] >= 1.0 else 'FAIL'} |",
        f"| Skipped Tests (`.skip`, `skip: true`) | {total_skipped} | 0 | {'PASS' if total_skipped == 0 else 'WARNING'} |",
        f"| Focused Tests (`.only`, `solo: true`) | {total_only} | 0 | {'PASS' if total_only == 0 else 'FAIL'} |",
        f"| Zero-Assertion Tests | {total_zero_assert} | 0 | {'PASS' if total_zero_assert == 0 else 'INVESTIGATE'} |",
        f"| Tautological Assertions (`assert(x, x)`) | {total_tautologies} | 0 | {'PASS' if total_tautologies == 0 else 'INVESTIGATE'} |",
        f"| Condition Flaws (`|| true`) | {total_or_true} | 0 | {'PASS' if total_or_true == 0 else 'FAIL'} |",
        f"| Swallowed Exceptions (`catch {{}}`) | {total_swallowed} | 0 | {'PASS' if total_swallowed == 0 else 'INVESTIGATE'} |",
        f"| Mock-on-Unit Occurrences | {total_mock_unit} | 0 | {'PASS' if total_mock_unit == 0 else 'INVESTIGATE'} |",
        "",
        "## 2. Identified Smells and Tautologies Detail",
        ""
    ]

    smells_found = False
    for r in results:
        issues = []
        if r["skipped_tests"] > 0:
            issues.append(f"Skipped tests: {r['skipped_tests']}")
        if r["only_tests"] > 0:
            issues.append(f"Focused (.only) tests: {r['only_tests']}")
        if r["zero_assertion_tests"]:
            issues.append(f"Zero-assertion tests: {r['zero_assertion_tests']}")
        if r["tautological_assertions"]:
            issues.append(f"Tautological assertions: {r['tautological_assertions']}")
        if r["or_true_count"] > 0:
            issues.append(f"`|| true` conditions: {r['or_true_count']}")
        if r["swallowed_exceptions"] > 0:
            issues.append(f"Swallowed exception blocks: {r['swallowed_exceptions']}")
        if r["mock_on_unit"]:
            issues.append(f"Mock on unit: {r['mock_on_unit']}")

        if issues:
            smells_found = True
            rel_path = os.path.relpath(r["file"], root)
            report_lines.append(f"### `{rel_path}`")
            for iss in issues:
                report_lines.append(f"- {iss}")
            report_lines.append("")

    if not smells_found:
        report_lines.append("Zero test smells, zero tautologies, and zero swallowed exceptions detected across all suites.")
        report_lines.append("")

    report_lines.extend([
        "## 3. Enforcement Policy",
        "- CI check `test_integrity.py` runs on every pull request and pre-commit hook.",
        "- Any increase in skipped tests, zero-assertion tests, tautologies, or swallowed exceptions blocks merge.",
        "- Any golden value modification must be accompanied by an errata entry explaining the empirical reason.",
        ""
    ])

    report_path = root / "TAUTOLOGY_REPORT.md"
    with open(report_path, "w", encoding="utf-8") as f:
        f.write("\n".join(report_lines))

    print(f"Test-Integrity scan complete.")
    print(f"Scanned {len(results)} files: {total_tests} tests, {total_assertions} assertions.")
    print(f"Smells: skipped={total_skipped}, only={total_only}, zero_assert={total_zero_assert}, tautologies={total_tautologies}, or_true={total_or_true}, swallowed={total_swallowed}")
    print(f"Wrote {evidence_path} and {report_path}")

if __name__ == "__main__":
    main()
