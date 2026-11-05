"""Check publishable files/history without printing credential contents.

This deliberately small pattern scan is a publication guard, not proof that every secret format is detected.
Ignored local settings are outside the publishable-file scan; git-tracked files are checked even if ignored.
"""

from __future__ import annotations

import argparse
import re
import subprocess
from pathlib import Path


PUBLIC_ANVIL_KEY = "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
ANVIL_FIXTURE_PATHS = {
    "scripts/rehearse-local-genesis.sh",
    "scripts/rehearse-sepolia-foundation.sh",
    "scripts/rehearse-sepolia-governed.sh",
    "docs/Sepolia-Demo-Deployment.md",
}
SIGNER_ASSIGNMENT = re.compile(
    r"(?i)\b[\w]*(?:private_?key|api_?key|access_?token|client_?secret|password)"
    r"[\w]*[\"']?\s*[:=]\s*[\"']?((?:0x)?[a-f0-9]{64})\b"
)
SECRET_PATTERNS = {
    "private-key-material": re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH |ENCRYPTED )?PRIVATE KEY-----"),
    "provider-token": re.compile(
        r"\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,}|"
        r"(?:AKIA|ASIA)[A-Z0-9]{16}|xox[baprs]-[A-Za-z0-9-]{20,}|"
        r"sk-(?:proj-)?[A-Za-z0-9_-]{32,})\b"
    ),
    "credential-url": re.compile(r"\bhttps?://[^\s/@:'\"]+:[^\s/@'\"]+@"),
    "rpc-provider-token": re.compile(
        r"https://(?:[A-Za-z0-9-]+\.g\.alchemy\.com/v2|[A-Za-z0-9-]+\.infura\.io/v3)/[A-Za-z0-9_-]{20,}"
    ),
    "wallet-recovery-phrase": re.compile(
        r"(?i)\b(?:mnemonic|seed_?phrase|secret_?recovery_?phrase)[\"']?\s*[:=]\s*[\"']"
        r"[a-z]+(?:\s+[a-z]+){11,23}[\"']"
    ),
}
PRIVATE_SUFFIXES = {".key", ".pem", ".p12", ".pfx", ".keystore"}
MAX_GITHUB_FILE_BYTES = 100 * 1024 * 1024


def text_findings(path: str, content: bytes) -> set[tuple[str, int, str]]:
    """Return only location/category; no token, matching fragment or credential is retained."""
    findings = set()
    try:
        lines = content.decode("utf-8").splitlines()
    except UnicodeDecodeError:
        return findings
    for number, line in enumerate(lines, 1):
        for category, pattern in SECRET_PATTERNS.items():
            if pattern.search(line):
                findings.add((path, number, category))
        for match in SIGNER_ASSIGNMENT.finditer(line):
            key = match.group(1).removeprefix("0x").lower()
            if key == PUBLIC_ANVIL_KEY and path in ANVIL_FIXTURE_PATHS:
                continue
            findings.add((path, number, "embedded-signer-or-credential"))
    return findings


def path_findings(path: str, size: int) -> set[tuple[str, int, str]]:
    """Reject tracked settings/signing files and accidental root build output, retaining env examples/PDFs."""
    name = Path(path).name
    first = Path(path).parts[0]
    findings = set()
    if re.search(r"(?:^|\.)env(?:$|\.)", name) and not name.endswith(".example"):
        findings.add((path, 1, "private-environment-file"))
    if Path(path).suffix in PRIVATE_SUFFIXES or name in {"id_rsa", "id_ed25519"}:
        findings.add((path, 1, "private-signing-file"))
    if first in {"out", "cache", "broadcast", "coverage"} or first.startswith(("out-", "cache-")):
        findings.add((path, 1, "generated-build-output"))
    if size > MAX_GITHUB_FILE_BYTES:
        findings.add((path, 1, "github-file-size-limit"))
    return findings


def git(repository: Path, *args: str) -> bytes:
    return subprocess.check_output(["git", "-C", str(repository), *args], stderr=subprocess.PIPE)


def working_files(repository: Path, tracked_only: bool) -> set[str]:
    paths = git(repository, "ls-files", "-z").decode().split("\0")
    if not tracked_only:
        paths += git(repository, "ls-files", "--others", "--exclude-standard", "-z").decode().split("\0")
    return set(paths) - {""}


def scan_history(repository: Path) -> tuple[set[tuple[str, int, str]], int]:
    """Scan every distinct reachable blob; diagnostics identify historical paths without displaying contents."""
    objects = git(repository, "rev-list", "--objects", "--all").decode().splitlines()
    findings = set()
    scanned = 0
    for record in objects:
        object_id, _, path = record.partition(" ")
        if not path or git(repository, "cat-file", "-t", object_id).strip() != b"blob":
            continue
        content = git(repository, "cat-file", "blob", object_id)
        findings |= text_findings(path, content)
        scanned += 1
    return findings, scanned


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tracked-only", action="store_true", help="Check the published checkout without local new files")
    parser.add_argument("--history", action="store_true", help="Also scan all locally reachable history")
    args = parser.parse_args()
    repository = Path(subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip())
    findings = set()
    for path in sorted(working_files(repository, args.tracked_only)):
        file = repository / path
        if not file.is_file():  # Git submodule directories are separately pinned and checked by the freeze run.
            continue
        content = file.read_bytes()
        findings |= path_findings(path, len(content)) | text_findings(path, content)
    if args.history:
        historical, _ = scan_history(repository)
        findings |= historical
    for path, number, category in sorted(findings):
        print(f"{path}:{number}:{category}")
    return 1 if findings else 0


if __name__ == "__main__":
    raise SystemExit(main())
