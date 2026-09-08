"""Regression tests for the narrow documentation checker, not policy prose validation."""

import importlib.util
import tempfile
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location("check_docs", Path(__file__).with_name("check-docs.py"))
CHECK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECK)


class DocumentationCheckTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="liberland-doc-check-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        (self.root / "docs").mkdir()
        self.document = self.root / "docs" / "README.md"
        self.document.touch()

    def check(self, text):
        return CHECK.check_text(self.document, text, self.root, {"IdentityApp": {"acceptInitialWallet"}})

    def test_missing_relative_target_is_rejected(self):
        self.assertEqual(len(self.check("[Guide](missing.md)")), 1)

    def test_external_and_existing_targets_are_accepted(self):
        self.assertEqual(self.check("[Guide](README.md) [Web](https://example.invalid/no-network)"), [])

    def test_reference_style_and_encoded_targets(self):
        (self.root / "docs" / "A Guide.md").touch()
        self.assertEqual(self.check("[a]: A%20Guide.md\n[b](<A Guide.md>)"), [])
        self.assertEqual(len(self.check("[a]: missing.md")), 1)

    def test_nonportable_local_targets_are_rejected(self):
        self.assertEqual(len(self.check("[Old](../../archive.md)")), 1)

    def test_fenced_examples_are_not_treated_as_live_links(self):
        self.assertEqual(self.check("```md\n[x](missing.md)\n```"), [])

    def test_missing_backticked_document_and_source_are_rejected(self):
        self.assertEqual(len(self.check("`Old-Review.md` `contracts/missing.sol`")), 2)

    def test_unknown_exported_function_is_rejected(self):
        self.assertEqual(len(self.check("`IdentityApp.obsolete()`")), 1)
        self.assertEqual(self.check("`IdentityApp.acceptInitialWallet(personId)`"), [])


if __name__ == "__main__":
    unittest.main()
