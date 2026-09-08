"""Check current first-party documentation targets and optionally exact generated ABI parity.

This deliberately is not a full Markdown parser or a semantic validator of policy prose.
It checks inline/reference link targets, exact backticked source paths and named ABI functions.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
from pathlib import Path
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[1]
SOURCE_PREFIXES = ("contracts/", "scripts/", "test/", "docs/", "frontend-export/")


def abi_contracts(root: Path) -> list[str]:
    """Read the single ABI export manifest, rejecting duplicates or unsafe contract names."""
    names = (root / "scripts/frontend-abi-contracts.txt").read_text(encoding="utf-8").splitlines()
    if not names or len(names) != len(set(names)) or any(not re.fullmatch(r"[A-Za-z_]\w*", n) for n in names):
        raise ValueError("Invalid or duplicate ABI export contract names")
    return names


def markdown_files(root: Path) -> list[Path]:
    """Enumerate maintained docs only; dependencies and generated output are excluded."""
    files = list(root.glob("*.md"))
    for directory in ("docs", "frontend-export", "deployments"):
        files.extend((root / directory).rglob("*.md"))
    return sorted(files)


def check_text(path: Path, text: str, root: Path, functions: dict[str, set[str]]) -> list[str]:
    """Return actionable target/function errors without interpreting external content."""
    problems = []
    # Fenced snippets can illustrate paths that are created later; do not interpret them as live links.
    prose = re.sub(r"^```[^\n]*\n.*?^```[^\n]*$", "", text, flags=re.MULTILINE | re.DOTALL)
    links = re.findall(r"\[[^\]\n]+\]\((<[^>]+>|[^)\s]+)(?:\s+\"[^\"]*\")?\)", prose)
    links += re.findall(r"^\s*\[[^\]]+\]:\s*(<[^>]+>|\S+)", prose, flags=re.MULTILINE)
    for link in links:
        target = link.strip("<>")
        url = urlsplit(target)
        if url.scheme or url.netloc or not url.path:
            continue
        file_path = unquote(url.path)
        resolved = (path.parent / file_path).resolve()
        if not resolved.is_relative_to(root):
            problems.append(f"{path.relative_to(root)}: nonportable local link {target}")
        elif not resolved.exists():
            problems.append(f"{path.relative_to(root)}: missing link target {target}")

    for code in re.findall(r"`([^`\n]+)`", prose):
        if code.startswith(SOURCE_PREFIXES) and not any(c in code for c in "*<> (){}"):
            # Only concrete source/docs files, not generated live address manifests or function examples.
            if code.endswith((".sol", ".md", ".py", ".sh", ".ps1", ".txt")) and not (root / code).is_file():
                problems.append(f"{path.relative_to(root)}: missing source reference {code}")
        if re.fullmatch(r"[A-Za-z][A-Za-z0-9_-]*\.md", code):
            if not (path.parent / code).is_file() and not (root / code).is_file():
                problems.append(f"{path.relative_to(root)}: missing document reference {code}")
        for contract, function in re.findall(r"\b([A-Z]\w*)\.([a-z]\w*)\(", code):
            if contract in functions and function not in functions[contract]:
                problems.append(f"{path.relative_to(root)}: {contract}.{function} is absent from its ABI")
    return problems


def main() -> int:
    """Check documentation and report every mismatch; never regenerate or accept artifacts."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check-abis", action="store_true", help="Compare every exported ABI with forge inspect")
    args = parser.parse_args()
    names = abi_contracts(ROOT)
    problems = []
    functions: dict[str, set[str]] = {}
    expected_paths = {f"{name}.json" for name in names}
    actual_paths = {p.name for p in (ROOT / "frontend-export/abis").glob("*.json")}
    if actual_paths != expected_paths:
        problems.append(
            f"ABI inventory mismatch: missing={sorted(expected_paths - actual_paths)}, "
            f"extra={sorted(actual_paths - expected_paths)}"
        )
    for name in names:
        path = ROOT / "frontend-export/abis" / f"{name}.json"
        if not path.is_file():
            continue
        try:
            abi = json.loads(path.read_text(encoding="utf-8"))["abi"]
            functions[name] = {item["name"] for item in abi if item.get("type") == "function"}
            if args.check_abis:
                result = subprocess.run(
                    ["forge", "inspect", name, "abi", "--json"],
                    cwd=ROOT, capture_output=True, text=True, check=True,
                )
                if abi != json.loads(result.stdout):
                    problems.append(f"Stale ABI: {path.relative_to(ROOT)}; regenerate the complete ABI package")
        except (ValueError, KeyError, TypeError, subprocess.CalledProcessError) as error:
            problems.append(f"{name}: ABI validation failed: {error}")
    documents = markdown_files(ROOT)
    for path in documents:
        if re.search(r"\d{4}-\d{2}-\d{2}", path.name):
            problems.append(f"Superseded-style dated code document in current set: {path.relative_to(ROOT)}")
        problems.extend(check_text(path, path.read_text(encoding="utf-8"), ROOT, functions))
    for problem in problems:
        print(problem)
    if problems:
        return 1
    print(
        f"Current documentation verified: {len(documents)} Markdown files, {len(names)} ABI exports"
        + (" with exact source parity" if args.check_abis else "")
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
