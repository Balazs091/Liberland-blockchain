#!/usr/bin/env bash
set -euo pipefail

mapfile -t contracts < scripts/frontend-abi-contracts.txt

mkdir -p frontend-export/abis
for contract in "${contracts[@]}"; do
  abi="$(forge inspect "$contract" abi --json)"
  printf '{"abi":%s}\n' "$abi" > "frontend-export/abis/$contract.json"
done
