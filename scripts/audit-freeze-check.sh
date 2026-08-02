#!/usr/bin/env bash
set -euo pipefail

repository_root="$(git rev-parse --show-toplevel)"
cd "$repository_root"

if [[ -n "$(git status --porcelain=v1)" ]]; then
  echo "Audit freeze requires a clean working tree." >&2
  exit 1
fi

forge_version="$(forge --version | sed -n '1s/^forge Version: //p')"
slither_version="$(slither --version 2>&1 | tail -n 1 | tr -d '\r')"
if [[ "$forge_version" != "1.7.1" ]]; then
  echo "Expected Forge 1.7.1, found $forge_version" >&2
  exit 1
fi
if [[ "$slither_version" != "0.11.5" ]]; then
  echo "Expected Slither 0.11.5, found $slither_version" >&2
  exit 1
fi
if git submodule status --recursive | grep -Eq '^[-+U]'; then
  echo "Submodule checkout does not match the recorded revisions." >&2
  git submodule status --recursive >&2
  exit 1
fi

echo "Audit target commit: $(git rev-parse HEAD)"
bash scripts/verify-constitution-source.sh
forge fmt --check
forge build --sizes
forge test -vvv
forge coverage --report summary
FOUNDRY_PROFILE=audit forge test --match-path 'test/invariant/*.t.sol' -vvv
forge test --match-path 'test/scripts/*.t.sol' -vvv
bash scripts/export-frontend-abis.sh
git diff --exit-code -- frontend-export/abis
python3 scripts/check-slither-baseline.py

echo "Audit-freeze verification passed for $(git rev-parse HEAD)."
