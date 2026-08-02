"""Run Slither unsuppressed and require the reviewed severity-count baseline."""

from __future__ import annotations

import collections
import json
import subprocess
import sys
import tempfile
from pathlib import Path


EXPECTED_COUNTS = {
    "High": 6,
    "Medium": 49,
    "Low": 218,
    "Informational": 91,
    "Optimization": 2,
}


def main() -> int:
    """Return success only when Slither runs and its full finding counts match the reviewed baseline."""
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
    actual_counts = dict(collections.Counter(detector.get("impact", "Unknown") for detector in detectors))
    if actual_counts != EXPECTED_COUNTS:
        print("Slither finding counts changed; perform and document a fresh manual triage.", file=sys.stderr)
        print(f"Expected: {EXPECTED_COUNTS}", file=sys.stderr)
        print(f"Actual:   {actual_counts}", file=sys.stderr)
        return 1

    print(f"Slither baseline verified: {len(detectors)} unsuppressed findings {actual_counts}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
