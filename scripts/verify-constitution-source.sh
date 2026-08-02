#!/usr/bin/env bash
set -euo pipefail

repository_root="$(git rev-parse --show-toplevel)"
source_path="$repository_root/docs/constitutional-sources/2024-09-24 Constitution.pdf"
expected_sha256="a24e56a4077d3513d3467091bdd81ea445208d4f5d1cde207ba87effe076bee6"

if [[ ! -f "$source_path" ]]; then
  echo "Missing reviewed constitution source: $source_path" >&2
  echo "Required SHA-256: $expected_sha256" >&2
  exit 1
fi

actual_sha256="$(sha256sum "$source_path" | awk '{print $1}')"
if [[ "$actual_sha256" != "$expected_sha256" ]]; then
  echo "Constitution source hash mismatch." >&2
  echo "Expected: $expected_sha256" >&2
  echo "Actual:   $actual_sha256" >&2
  exit 1
fi

echo "Constitution source verified: $actual_sha256"
