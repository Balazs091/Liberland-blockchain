"""Ensure equal severity totals cannot hide a substituted finding."""

import importlib.util
import os
import unittest
from pathlib import Path
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("check_slither", Path(__file__).with_name("check-slither-baseline.py"))
CHECK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECK)


class FindingIdentityTest(unittest.TestCase):
    def test_default_scanner_uses_installed_entrypoint(self):
        with patch.dict(os.environ, {"SLITHER_PYTHON": ""}):
            self.assertEqual(CHECK.slither_command(), ["slither"])

    def test_explicit_interpreter_remains_one_argument(self):
        with patch.dict(os.environ, {"SLITHER_PYTHON": "/tool path/python"}):
            self.assertEqual(CHECK.slither_command(), ["/tool path/python", "-m", "slither"])

    def finding(self, description="App.f() (contracts/App.sol#10-15) calls Registry.write()"):
        return {"check": "calls-loop", "impact": "Low", "confidence": "Medium", "description": description}

    def test_line_movement_does_not_require_retriage(self):
        before = self.finding()
        after = self.finding(before["description"].replace("#10-15", "#90-95"))
        self.assertEqual(CHECK.finding_fingerprints([before]), CHECK.finding_fingerprints([after]))

    def test_same_severity_different_content_is_rejected(self):
        before = self.finding()
        after = self.finding(before["description"].replace("Registry.write", "Treasury.send"))
        self.assertNotEqual(CHECK.finding_fingerprints([before]), CHECK.finding_fingerprints([after]))

    def test_multiplicity_is_preserved(self):
        finding = self.finding()
        self.assertNotEqual(CHECK.finding_fingerprints([finding]), CHECK.finding_fingerprints([finding, finding]))

    def test_detector_and_severity_are_part_of_identity(self):
        before = self.finding()
        self.assertNotEqual(
            CHECK.finding_fingerprints([before]), CHECK.finding_fingerprints([{**before, "impact": "High"}])
        )


if __name__ == "__main__":
    unittest.main()
