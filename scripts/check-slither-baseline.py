"""Run Slither unsuppressed and require reviewed counts and normalized finding identities."""

from __future__ import annotations

import collections
import hashlib
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path


# Current manual triage and verification: docs/Release-Readiness.md.
EXPECTED_COUNTS = {
    "High": 6,
    "Medium": 66,
    "Low": 264,
    "Informational": 94,
    "Optimization": 0,
}


def finding_fingerprints(detectors: list[dict]) -> dict[str, int]:
    """Fingerprint finding content, ignoring source-line shifts and whitespace, but retaining multiplicity."""
    fingerprints = collections.Counter()
    for detector in detectors:
        description = re.sub(r"#\d+(?:-\d+)?", "#", detector["description"])
        description = " ".join(description.split())
        identity = [detector["check"], detector["impact"], detector["confidence"], description]
        encoded = json.dumps(identity, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        fingerprints[hashlib.sha256(encoded).hexdigest()] += 1
    return dict(sorted(fingerprints.items()))


def main() -> int:
    """Reject both severity-count drift and different findings that happen to retain the same counts."""
    with tempfile.TemporaryDirectory(prefix="liberland-slither-") as temporary_directory:
        report_path = Path(temporary_directory) / "report.json"
        completed = subprocess.run(
            ["slither", ".", "--json", str(report_path), "--fail-none"],
            check=False,
        )
        if completed.returncode != 0:
            print(f"Slither execution failed with exit code {completed.returncode}.", file=sys.stderr)
            return completed.returncode

        with report_path.open(encoding="utf-8") as report_file:
            report = json.load(report_file)

    detectors = report.get("results", {}).get("detectors", [])
    counted_impacts = collections.Counter(detector.get("impact", "Unknown") for detector in detectors)
    actual_counts = {impact: counted_impacts.get(impact, 0) for impact in EXPECTED_COUNTS}
    unexpected_counts = {
        impact: count for impact, count in counted_impacts.items() if impact not in EXPECTED_COUNTS
    }
    if actual_counts != EXPECTED_COUNTS or unexpected_counts:
        print("Slither finding counts changed; perform and document a fresh manual triage.", file=sys.stderr)
        print(f"Expected: {EXPECTED_COUNTS}", file=sys.stderr)
        print(f"Actual:   {actual_counts}", file=sys.stderr)
        if unexpected_counts:
            print(f"Unexpected impacts: {unexpected_counts}", file=sys.stderr)
        return 1

    baseline_path = Path(__file__).with_name("slither-baseline.json")
    with baseline_path.open(encoding="utf-8") as baseline_file:
        baseline = json.load(baseline_file)
    actual_fingerprints = finding_fingerprints(detectors)
    if baseline.get("schemaVersion") != 1 or actual_fingerprints != baseline.get("findings"):
        print(
            "Slither finding identities changed; manually triage the full report before updating the baseline.",
            file=sys.stderr,
        )
        expected = collections.Counter(baseline.get("findings", {}))
        actual = collections.Counter(actual_fingerprints)
        print(f"Added/changed: {dict(actual - expected)}", file=sys.stderr)
        print(f"Removed/changed: {dict(expected - actual)}", file=sys.stderr)
        return 1

    print(f"Slither baseline verified: {len(detectors)} unsuppressed findings {actual_counts}; identities match")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
