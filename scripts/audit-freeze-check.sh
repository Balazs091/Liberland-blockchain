#!/usr/bin/env bash
set -euo pipefail

repository_root="$(git rev-parse --show-toplevel)"
cd "$repository_root"

python_command=""
for candidate in python3 python; do
  if command -v "$candidate" >/dev/null 2>&1 \
    && "$candidate" -c 'import sys; raise SystemExit(0 if sys.version_info.major == 3 else 1)' >/dev/null 2>&1;
  then
    python_command="$candidate"
    break
  fi
done
if [[ -z "$python_command" ]]; then
  echo "Audit freeze requires a working Python 3 executable named python3 or python." >&2
  exit 1
fi

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
"$python_command" -m unittest discover -s scripts -p 'test_*.py'
"$python_command" scripts/check-docs.py
forge fmt --check
forge build --sizes
forge test -vvv
# The optimized 1,000-candidate stress fixture exceeds coverage instrumentation's test gas budget.
# It remains mandatory above; coverage exercises the same count path with the 100-candidate fixture.
forge coverage --report summary --no-match-test test_Governance_OpenAdmissionFinalizes1000CandidatesInBoundedChunks
FOUNDRY_PROFILE=audit forge test --match-path 'test/invariant/*.t.sol' --fuzz-seed 0x709 -vvv
forge test --match-path 'test/scripts/*.t.sol' -vvv
bash scripts/export-frontend-abis.sh
git diff --exit-code -- frontend-export/abis
"$python_command" scripts/check-docs.py --check-abis
"$python_command" scripts/check-slither-baseline.py

echo "Audit-freeze verification passed for $(git rev-parse HEAD)."
