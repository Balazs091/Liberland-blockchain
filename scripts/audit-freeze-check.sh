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

if [[ -n "$(git status --porcelain=v1 --untracked-files=all --ignore-submodules=none)" ]]; then
  echo "Audit freeze requires a clean working tree." >&2
  exit 1
fi

forge_version="$(forge --version | sed -n '1s/^forge Version: //p')"
if [[ -n "${SLITHER_PYTHON:-}" ]]; then
  slither_version="$("$SLITHER_PYTHON" -m slither --version 2>&1 | tail -n 1 | tr -d '\r')"
  crytic_version="$("$SLITHER_PYTHON" -c 'from importlib.metadata import version; print(version("crytic-compile"))')"
else
  slither_version="$(slither --version 2>&1 | tail -n 1 | tr -d '\r')"
  crytic_version="$(crytic-compile --version 2>&1 | tail -n 1 | tr -d '\r')"
fi
if [[ "$forge_version" != "1.9.0" ]]; then
  echo "Expected Forge 1.9.0, found $forge_version" >&2
  exit 1
fi
if [[ "$slither_version" != "0.11.6" ]]; then
  echo "Expected Slither 0.11.6, found $slither_version" >&2
  exit 1
fi
if [[ "$crytic_version" != "0.4.2" ]]; then
  echo "Expected crytic-compile 0.4.2, found $crytic_version" >&2
  exit 1
fi
if git submodule status --recursive | grep -Eq '^[-+U]'; then
  echo "Submodule checkout does not match the recorded revisions." >&2
  git submodule status --recursive >&2
  exit 1
fi

echo "Audit target commit: $(git rev-parse HEAD)"
echo "Audit target tree: $(git rev-parse HEAD^{tree})"
"$python_command" scripts/check-repository-hygiene.py --tracked-only --history
bash scripts/verify-constitution-source.sh
"$python_command" -m unittest discover -s scripts -p 'test_*.py'
"$python_command" -m unittest discover -s test/reference -p 'test_*.py'
"$python_command" scripts/check-docs.py
forge fmt --check
forge build --sizes
forge test -vvv
# The optimized 1,000-candidate stress fixture exceeds coverage instrumentation's test gas budget.
# It remains mandatory above; coverage exercises the same count path with the 100-candidate fixture.
forge coverage --report summary --no-match-test test_Governance_OpenAdmissionFinalizes1000CandidatesInBoundedChunks
# Foundry groups predicates per contract; three seeds retain the prior aggregate handler-call budget.
for invariant_seed in 0x709 0x110338 0x381; do
  FOUNDRY_PROFILE=audit forge test --match-path 'test/invariant/*.t.sol' --fuzz-seed "$invariant_seed" -vvv
done
bash scripts/export-frontend-abis.sh
git diff --exit-code -- frontend-export/abis
"$python_command" scripts/check-docs.py --check-abis
"$python_command" scripts/check-slither-baseline.py

if [[ -n "$(git status --porcelain=v1 --untracked-files=all --ignore-submodules=none)" ]]; then
  echo "Audit verification changed the frozen working tree; review generated/source drift." >&2
  exit 1
fi

echo "Audit-freeze verification passed for $(git rev-parse HEAD)."
