"""Offline packet vectors, checked against the Solidity digest test and exported ABI."""

import importlib.util
import json
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("prepare-justice-decision.py")
ROOT = SCRIPT.resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("prepare_justice_decision", SCRIPT)
TOOL = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(TOOL)
EXAMPLE = ROOT / "frontend-export" / "justice-decision.example.json"
DECISION_DIGEST = "0x6d600e19242bb5eb93ff6ef6f999eaebed7a0ac000c1234e2b0109e3effcd696"
DESTINATION_DIGEST = "0x9c3f62aa098cca3d8a7828fb8d92dfde3f22f9f3732990f75b0fb855cb6f26c7"


class PrepareJusticeDecisionTest(unittest.TestCase):
    def setUp(self):
        self.packet = json.loads(EXAMPLE.read_text())

    def test_solidity_vector_and_lossless_json_integers(self):
        unsigned = TOOL.prepare(self.packet)
        self.assertEqual(unsigned["entrypoint"], "executeIdentity")
        self.assertEqual(unsigned["decisionDigest"], DECISION_DIGEST)
        self.assertEqual(unsigned["destinationConsentDigest"], DESTINATION_DIGEST)
        self.assertEqual(unsigned["authorityTypedData"]["message"]["stateRevision"], "9007199254740993")
        self.assertEqual(unsigned["destinationTypedData"]["message"], {"decisionDigest": DECISION_DIGEST})
        self.assertEqual(unsigned["authorityTypedData"]["domain"]["verifyingContract"], self.packet["justiceApp"])

    def test_abi_and_action_ordinals_match_source(self):
        abi = json.loads((ROOT / "frontend-export" / "abis" / "JusticeApp.json").read_text())["abi"]
        functions = {item["name"]: item for item in abi if item["type"] == "function"}
        fields = lambda components: tuple((item["name"], item["type"]) for item in components)
        self.assertEqual(fields(functions["decisionDigest"]["inputs"][0]["components"]), TOOL.DECISION_FIELDS)
        for method, effect in TOOL.EFFECT_FIELDS.items():
            self.assertEqual(fields(functions[method]["inputs"][1]["components"]), effect)
        types = (ROOT / "contracts" / "types" / "JusticeTypes.sol").read_text()
        action_body = re.search(r"enum Action\s*\{([^}]+)\}", types).group(1)
        self.assertEqual([name.strip() for name in action_body.split(",")], [name for name, _ in TOOL.ACTIONS])

    def test_membership_and_finance_do_not_request_destination_consent(self):
        zero = "0x" + "00" * 32
        for action, method, effect in (
            ("Restrict", "executeMembership", {"orderId": zero, "revision": "0", "expiresAt": "100", "rights": 1}),
            ("Compensate", "executeFinancial", {
                "referenceId": "0x" + "77" * 32, "beneficiary": "0x" + "88" * 32,
                "amount": "5000000000000000000", "cutoffBlock": "7", "termsHash": "0x" + "99" * 32,
            }),
        ):
            with self.subTest(action=action):
                self.packet["decision"]["action"] = action
                self.packet["effect"] = effect
                unsigned = TOOL.prepare(self.packet)
                self.assertEqual(unsigned["entrypoint"], method)
                self.assertNotIn("destinationTypedData", unsigned)
                self.assertNotIn("destinationConsentDigest", unsigned)

    def test_domain_change_changes_both_signing_digests(self):
        self.packet["chainId"] = 1
        unsigned = TOOL.prepare(self.packet)
        self.assertNotEqual(unsigned["decisionDigest"], DECISION_DIGEST)
        self.assertNotEqual(unsigned["destinationConsentDigest"], DESTINATION_DIGEST)

    def test_rejects_private_fields_and_unsafe_uri_without_echoing_values(self):
        self.packet["privateRecord"] = "sentinel sensitive data"
        with self.assertRaisesRegex(TOOL.PacketError, "packet must contain exactly") as raised:
            TOOL.prepare(self.packet)
        self.assertNotIn("sentinel", str(raised.exception))
        del self.packet["privateRecord"]
        self.packet["publicReasonURI"] = "https://example.test/ruling?token=sentinel"
        with self.assertRaisesRegex(TOOL.PacketError, "no credentials, query or fragment") as raised:
            TOOL.prepare(self.packet)
        self.assertNotIn("sentinel", str(raised.exception))

    def test_rejects_wrong_tuple_and_invalid_integer_widths(self):
        self.packet["decision"]["action"] = "Restrict"
        with self.assertRaisesRegex(TOOL.PacketError, "effect must contain exactly"):
            TOOL.prepare(self.packet)
        self.packet["decision"]["action"] = "Admit"
        for invalid in (-1, True, 2**64, "1e3"):
            with self.subTest(invalid=invalid):
                self.packet["decision"]["deadline"] = invalid
                with self.assertRaisesRegex(TOOL.PacketError, "decision.deadline must be a uint64"):
                    TOOL.prepare(self.packet)
        self.packet["decision"]["deadline"] = "1800000000"
        self.packet["effect"]["route"] = 3
        with self.assertRaisesRegex(TOOL.PacketError, "existing Solidity enum ordinals"):
            TOOL.prepare(self.packet)

    def test_cli_rejects_duplicate_fields_without_publishing_output(self):
        with tempfile.TemporaryDirectory(prefix="liberland-justice-packet-test-") as directory:
            invalid = Path(directory) / "public.json"
            invalid.write_text('{"chainId": 1, "chainId": "sentinel sensitive data"}')
            result = subprocess.run([sys.executable, str(SCRIPT), str(invalid)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertFalse(result.stdout)
        self.assertIn("duplicate field", result.stderr)
        self.assertNotIn("sentinel", result.stderr)


if __name__ == "__main__":
    unittest.main()
