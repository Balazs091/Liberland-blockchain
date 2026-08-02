#!/usr/bin/env bash
set -euo pipefail

mapfile -t contracts < scripts/frontend-abi-contracts.txt

mkdir -p frontend-export/abis
for contract in "${contracts[@]}"; do
  contract="${contract%$'\r'}"
  if [[ ! "$contract" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
    echo "Invalid contract name in scripts/frontend-abi-contracts.txt: $contract" >&2
    exit 1
  fi
  abi="$(forge inspect "$contract" abi --json)"
  printf '{"abi":%s}\n' "$abi" > "frontend-export/abis/$contract.json"
done
