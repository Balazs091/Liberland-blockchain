"""Prepare an unsigned JusticeApp v1 packet from public fields only, without RPC or signing."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import urlsplit


DECISION_FIELDS = (
    ("action", "uint8"), ("decisionId", "bytes32"), ("personId", "bytes32"),
    ("effectHash", "bytes32"), ("reasonHash", "bytes32"), ("recordHash", "bytes32"),
    ("noticeAt", "uint64"), ("deadline", "uint64"), ("stateRevision", "uint256"),
)
DOMAIN_FIELDS = (
    ("name", "string"), ("version", "string"), ("chainId", "uint256"), ("verifyingContract", "address"),
)
CONSENT_FIELDS = (("decisionDigest", "bytes32"),)
EFFECT_FIELDS = {
    "executeIdentity": (
        ("wallet", "address"), ("ageClass", "uint8"), ("route", "uint8"),
        ("presidencyNonce", "uint64"), ("ministerMandateHash", "bytes32"), ("priorDecisionId", "bytes32"),
    ),
    "executeMembership": (("orderId", "bytes32"), ("revision", "uint256"), ("expiresAt", "uint64"), ("rights", "uint16")),
    "executeFinancial": (
        ("referenceId", "bytes32"), ("beneficiary", "bytes32"), ("amount", "uint128"),
        ("cutoffBlock", "uint48"), ("termsHash", "bytes32"),
    ),
}
# Exact ordinal order in JusticeTypes.Action. Existing ABI checks verify every field tuple separately.
ACTIONS = (
    ("Admit", "executeIdentity"), ("Annul", "executeIdentity"), ("Recover", "executeIdentity"),
    ("Restrict", "executeMembership"), ("RemoveMembership", "executeMembership"),
    ("RestoreMembership", "executeMembership"), ("StayOrder", "executeMembership"),
    ("ResumeOrder", "executeMembership"), ("RevokeOrder", "executeMembership"),
    ("Compensate", "executeFinancial"), ("RestoreMerits", "executeFinancial"),
    ("RecognizeAdulthood", "executeIdentity"), ("RestoreCitizenship", "executeIdentity"),
)
DESTINATION_ACTIONS = {"Admit", "Recover", "RecognizeAdulthood"}
MAX_INPUT_BYTES = 16_384


class PacketError(ValueError):
    """Input or local encoding error whose message never includes supplied values."""


def _object(value, keys, label):
    if not isinstance(value, dict) or set(value) != set(keys):
        raise PacketError(f"{label} must contain exactly: {', '.join(sorted(keys))}")
    return value


def _unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise PacketError("JSON object contains a duplicate field")
        result[key] = value
    return result


def _field(value, type_name, label, *, nonzero=False):
    if type_name.startswith("uint"):
        if isinstance(value, str) and re.fullmatch(r"(?:0|[1-9][0-9]{0,77})", value):
            value = int(value)
        if type(value) is not int or not 0 <= value < (1 << int(type_name[4:])):
            raise PacketError(f"{label} must be a {type_name} integer or canonical decimal string")
        if nonzero and value == 0:
            raise PacketError(f"{label} must be nonzero")
        # Retain exact integers in JSON consumed by JavaScript clients.
        return str(value)
    width = 20 if type_name == "address" else 32
    if not isinstance(value, str) or not re.fullmatch(rf"0x[0-9a-fA-F]{{{width * 2}}}", value):
        raise PacketError(f"{label} must be a 0x-prefixed {type_name}")
    if nonzero and int(value, 16) == 0:
        raise PacketError(f"{label} must be nonzero")
    return value.lower()


def _cast(*args):
    try:
        output = subprocess.run(["cast", *args], capture_output=True, text=True, check=True, timeout=15).stdout.strip()
    except FileNotFoundError as exc:
        raise PacketError("Foundry cast must be available on PATH") from exc
    except (subprocess.SubprocessError, OSError) as exc:
        # Do not echo commands, inputs or diagnostics that could contain case data.
        raise PacketError("Foundry cast could not encode the public packet") from exc
    if not re.fullmatch(r"0x(?:[0-9a-fA-F]{2})+", output):
        raise PacketError("Foundry cast returned an unexpected encoding")
    return output.lower()


def _hash_bytes(value):
    return _cast("keccak", "0x" + value.hex())


def _hash_abi(types, values):
    return _cast("keccak", _cast("abi-encode", f"f({','.join(types)})", *values))


def _struct_hash(name, fields, message):
    definition = f"{name}({','.join(f'{kind} {field}' for field, kind in fields)})"
    types = ["bytes32"]
    values = [_hash_bytes(definition.encode())]
    for field, kind in fields:
        types.append("bytes32" if kind == "string" else kind)
        values.append(_hash_bytes(message[field].encode()) if kind == "string" else message[field])
    return _hash_abi(types, values)


def _typed_data(name, fields, domain, message):
    return {
        "types": {
            "EIP712Domain": [{"name": field, "type": kind} for field, kind in DOMAIN_FIELDS],
            name: [{"name": field, "type": kind} for field, kind in fields],
        },
        "primaryType": name,
        "domain": domain,
        "message": message,
    }


def _public_uri(value):
    if not isinstance(value, str) or not value or not value.isprintable() or any(char.isspace() for char in value):
        raise PacketError("publicReasonURI must be a nonempty public ruling URI without whitespace")
    if len(value.encode("utf-8")) > 256:
        raise PacketError("publicReasonURI must fit the contract's 256-byte limit")
    try:
        parts = urlsplit(value)
    except ValueError as exc:
        raise PacketError("publicReasonURI is malformed") from exc
    if (
        parts.scheme not in {"ipfs", "ar", "https"} or not parts.hostname or parts.username is not None
        or "?" in value or "#" in value
    ):
        raise PacketError("publicReasonURI requires ipfs, ar or https with no credentials, query or fragment")
    return value


def prepare(source):
    """Encode the public packet. This validates shape, not legal facts, signatures or chain state."""
    packet = _object(source, {"chainId", "justiceApp", "decision", "effect", "publicReasonURI"}, "packet")
    chain_id = _field(packet["chainId"], "uint256", "chainId", nonzero=True)
    address = _field(packet["justiceApp"], "address", "justiceApp", nonzero=True)
    source_fields = tuple((name, kind) for name, kind in DECISION_FIELDS if name not in {"effectHash", "reasonHash"})
    fields = _object(packet["decision"], {name for name, _ in source_fields}, "decision")
    action = fields["action"]
    if not isinstance(action, str) or action not in {name for name, _ in ACTIONS}:
        raise PacketError("decision.action must name an existing JusticeTypes.Action")
    ordinal, entrypoint = next((i, method) for i, (name, method) in enumerate(ACTIONS) if name == action)
    decision = {"action": str(ordinal)}
    for name, kind in source_fields:
        if name != "action":
            decision[name] = _field(
                fields[name], kind, f"decision.{name}", nonzero=name in {"decisionId", "personId", "recordHash", "deadline"}
            )

    public_uri = _public_uri(packet["publicReasonURI"])
    effect_fields = EFFECT_FIELDS[entrypoint]
    effect_values = _object(packet["effect"], {name for name, _ in effect_fields}, "effect")
    effect = {name: _field(effect_values[name], kind, f"effect.{name}") for name, kind in effect_fields}
    if entrypoint == "executeIdentity" and (int(effect["ageClass"]) > 2 or int(effect["route"]) > 2):
        raise PacketError("effect.ageClass and effect.route must use existing Solidity enum ordinals (0 to 2)")
    decision["effectHash"] = _hash_abi([kind for _, kind in effect_fields], [effect[name] for name, _ in effect_fields])
    decision["reasonHash"] = _hash_bytes(public_uri.encode("utf-8"))
    domain = {"name": "Liberland Justice", "version": "1", "chainId": chain_id, "verifyingContract": address}
    separator = _struct_hash("EIP712Domain", DOMAIN_FIELDS, domain)

    def digest(name, members, message):
        struct_hash = _struct_hash(name, members, message)
        return _cast("keccak", "0x1901" + separator[2:] + struct_hash[2:])

    decision_digest = digest("Decision", DECISION_FIELDS, decision)
    result = {
        "entrypoint": entrypoint,
        "publicReasonURI": public_uri,
        "effect": effect,
        "decisionTuple": "(" + ",".join(decision[name] for name, _ in DECISION_FIELDS) + ")",
        "decisionDigest": decision_digest,
        "authorityTypedData": _typed_data("Decision", DECISION_FIELDS, domain, decision),
    }
    if action in DESTINATION_ACTIONS:
        consent = {"decisionDigest": decision_digest}
        result["destinationConsentDigest"] = digest("DestinationConsent", CONSENT_FIELDS, consent)
        result["destinationTypedData"] = _typed_data("DestinationConsent", CONSENT_FIELDS, domain, consent)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("public_packet", type=Path, help="JSON with public decision fields; never a private case file")
    args = parser.parse_args()
    try:
        with args.public_packet.open("rb") as source:
            data = source.read(MAX_INPUT_BYTES + 1)
        if len(data) > MAX_INPUT_BYTES:
            raise PacketError("public packet exceeds the 16 KiB input limit")
        packet = json.loads(data, object_pairs_hook=_unique_object)
        print(json.dumps(prepare(packet), indent=2))
    except PacketError as exc:
        print(f"justice packet: {exc}", file=sys.stderr)
        return 1
    except (OSError, ValueError, RecursionError):
        print("justice packet: cannot read or parse the public JSON input", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
