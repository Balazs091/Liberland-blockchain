"""Publication guards preserve examples/fixtures and report locations without exposing credentials."""

import importlib.util
import subprocess
import tempfile
import unittest
from pathlib import Path


SPEC = importlib.util.spec_from_file_location("repository_hygiene", Path(__file__).with_name("check-repository-hygiene.py"))
CHECK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECK)
REPOSITORY_ROOT = Path(__file__).resolve().parents[1]


class CredentialDiagnosticsTest(unittest.TestCase):
    def test_signer_diagnostic_contains_only_location_and_category(self):
        value = "0x" + "b7" * 32
        findings = CHECK.text_findings("settings.txt", ("header\nPRIVATE_KEY=" + value).encode())
        self.assertEqual(findings, {("settings.txt", 2, "embedded-signer-or-credential")})
        self.assertNotIn(value, repr(findings))

    def test_public_anvil_key_is_allowed_only_in_named_fixture_paths(self):
        text = ("PRIVATE_KEY=0x" + CHECK.PUBLIC_ANVIL_KEY).encode()
        self.assertFalse(CHECK.text_findings("scripts/rehearse-local-genesis.sh", text))
        self.assertTrue(CHECK.text_findings("settings.txt", text))

    def test_provider_pem_url_and_phrase_formats_are_detected(self):
        cases = {
            "provider-token": "ghp_" + "A" * 36,
            "private-key-material": "-----BEGIN " + "PRIVATE KEY-----",
            "credential-url": "https://" + "person:password@example.test",
            "wallet-recovery-phrase": 'mnemonic="' + "word " * 11 + 'last"',
        }
        for category, content in cases.items():
            with self.subTest(category=category):
                self.assertEqual(CHECK.text_findings("settings.txt", content.encode()), {("settings.txt", 1, category)})

    def test_hashes_and_short_test_keys_are_not_signing_credentials(self):
        content = "bytes32 hash = 0x" + "b7" * 32 + ";\nuint256 privateKey = 0xA11CE;"
        self.assertFalse(CHECK.text_findings("test/Fixture.sol", content.encode()))

    def test_tracked_private_files_and_generated_output_are_rejected(self):
        for path in (".env.production", "sepolia.env", "wallet.key", "out/App.sol/App.json"):
            with self.subTest(path=path):
                self.assertTrue(CHECK.path_findings(path, 10))
        for path in (".env.example", "sepolia.env.example", "docs/constitutional-sources/2024-09-24 Constitution.pdf"):
            with self.subTest(path=path):
                self.assertFalse(CHECK.path_findings(path, 10))


class IgnoreAndInventoryTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="liberland-hygiene-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        (self.root / ".gitignore").write_text((REPOSITORY_ROOT / ".gitignore").read_text())

    def ignored(self, path):
        result = subprocess.run(["git", "-C", str(self.root), "check-ignore", "--no-index", "--quiet", path])
        return result.returncode == 0

    def test_secret_settings_ignored_and_reviewable_sources_preserved(self):
        for path in (".env", ".env.production", "sepolia-governed.env", "wallet.pem", "keystores/account.json", "coverage.lcov"):
            with self.subTest(path=path):
                self.assertTrue(self.ignored(path))
        for path in (".env.example", ".env.sepolia.example", "sepolia-governed.env.example", "frontend-export/abis/ReferendumApp.json", "scripts/slither-baseline.json", "docs/constitutional-sources/2024-09-24 Constitution.pdf"):
            with self.subTest(path=path):
                self.assertFalse(self.ignored(path))

    def test_tracked_secret_cannot_hide_behind_new_ignore_rules(self):
        (self.root / ".env").write_text("PRIVATE_KEY=\n")
        (self.root / "new-source.sol").write_text("// new source\n")
        (self.root / ".env.production").write_text("PRIVATE_KEY=\n")
        subprocess.run(["git", "-C", str(self.root), "add", "--force", ".env"], check=True)
        tracked = CHECK.working_files(self.root, tracked_only=True)
        all_publishable = CHECK.working_files(self.root, tracked_only=False)
        self.assertIn(".env", tracked)
        self.assertNotIn("new-source.sol", tracked)
        self.assertIn("new-source.sol", all_publishable)
        self.assertNotIn(".env.production", all_publishable)


if __name__ == "__main__":
    unittest.main()
