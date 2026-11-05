#!/usr/bin/env bash
set -euo pipefail

# Disposable localhost chain ONLY. Never load the checkout's .env or use its public RPC/operator settings.
foundation_source_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
foundation_work="$(mktemp -d -t liberland-sepolia-foundation.XXXXXX)"
mkdir -p "$foundation_work/source" "$foundation_work/evidence"
tar -C "$foundation_source_root" -cf - contracts scripts foundry.toml remappings.txt | tar -C "$foundation_work/source" -xf -
ln -s "$foundation_source_root/lib" "$foundation_work/source/lib"
cd "$foundation_work/source"

anvil --host 127.0.0.1 --port 18561 --chain-id 11155111 --hardfork osaka --silent > ../evidence/anvil.log 2>&1 &
foundation_anvil_pid=$!
trap 'kill "$foundation_anvil_pid" 2>/dev/null || true' EXIT
sleep 1
kill -0 "$foundation_anvil_pid"
foundation_rpc='http://127.0.0.1:18561'
# Publicly known local fixture key. No real operator credential is read or copied.
export SEPOLIA_FOUNDATION_PRIVATE_KEY='0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80'
foundation_operator=$(cast wallet address --private-key "$SEPOLIA_FOUNDATION_PRIVATE_KEY")
test "$(cast chain-id --rpc-url "$foundation_rpc")" = 11155111

forge script scripts/DeploySepoliaFoundation.s.sol:DeploySepoliaFoundation \
  --rpc-url "$foundation_rpc" --broadcast --slow --gas-estimate-multiplier 150 -vv \
  > ../evidence/deploy.log 2>&1
cp deployments/sepolia-foundation.json ../evidence/sepolia-foundation.json
foundation_manifest='deployments/sepolia-foundation.json'
jq -e '.chainId == 11155111 and .syntheticOnly == true and .bootstrapRetired == true and .legalWorkflowsInstalled == false and .governanceInstalled == false' "$foundation_manifest" > ../evidence/manifest-check.txt
foundation_kernel=$(jq -r .constitutionKernel "$foundation_manifest")
foundation_token=$(jq -r .llmToken "$foundation_manifest")
foundation_identity=$(jq -r .identityRegistry "$foundation_manifest")
foundation_membership=$(jq -r .membershipRegistry "$foundation_manifest")
foundation_controller=$(jq -r .membershipController "$foundation_manifest")
foundation_person=$(jq -r .personId0 "$foundation_manifest")
foundation_other_person=$(jq -r .personId1 "$foundation_manifest")
test "$(cast call "$foundation_kernel" 'bootstrapAuthority()(address)' --rpc-url "$foundation_rpc")" = '0x0000000000000000000000000000000000000000'
test "$(cast call "$foundation_controller" 'fixturesSeeded()(bool)' --rpc-url "$foundation_rpc")" = true
test "$(cast call "$foundation_identity" 'totalIdentityCount()(uint256)' --rpc-url "$foundation_rpc")" = 3

# Verify every recorded runtime hash against code actually mined on this local chain.
: > ../evidence/runtime-hashes.jsonl
for foundation_pair in \
  'constitutionKernel:kernelRuntimeHash' 'llmToken:llmRuntimeHash' \
  'identityRegistry:identityRuntimeHash' 'membershipRegistry:membershipRuntimeHash' \
  'membershipController:controllerRuntimeHash'; do
  foundation_address=$(jq -r ".${foundation_pair%%:*}" "$foundation_manifest")
  foundation_expected=$(jq -r ".${foundation_pair##*:}" "$foundation_manifest")
  foundation_runtime=$(cast code "$foundation_address" --rpc-url "$foundation_rpc")
  test "$foundation_runtime" != '0x'
  foundation_observed=$(cast keccak "$foundation_runtime")
  test "${foundation_observed,,}" = "${foundation_expected,,}"
  jq -nc --arg address "$foundation_address" --arg expected "$foundation_expected" --arg observed "$foundation_observed" \
    '{address:$address,expected:$expected,observed:$observed}' >> ../evidence/runtime-hashes.jsonl
done

forge script scripts/DeploySepoliaFoundation.s.sol:DeploySepoliaFoundation \
  --sig 'verify(address,address)' "$foundation_kernel" "$foundation_token" \
  --rpc-url "$foundation_rpc" -vv > ../evidence/read-back.log 2>&1

foundation_now=$(cast block latest --rpc-url "$foundation_rpc" --json | jq -r '(.data // .).timestamp')
foundation_start=$((foundation_now))
foundation_short_end=$((foundation_start + 600))
foundation_long_end=$((foundation_start + 1200))
foundation_order_a=$(cast keccak 'sepolia-rehearsal-short-political')
foundation_order_b=$(cast keccak 'sepolia-rehearsal-independent-political-community')
foundation_order_c=$(cast keccak 'sepolia-rehearsal-indefinite-appointment')
foundation_input_a="($foundation_person,$foundation_order_a,1,$foundation_start,$foundation_short_end,false)"
foundation_input_b="($foundation_person,$foundation_order_b,3,$foundation_start,$foundation_long_end,false)"
foundation_other_operator=$(cast rpc eth_accounts --rpc-url "$foundation_rpc" | jq -r '.[1]')

# Read-only negative probes must revert, including the deployer attempting to bypass the test controller.
if cast call "$foundation_controller" 'recordRestriction((bytes32,bytes32,uint16,uint64,uint64,bool))' \
  "$foundation_input_a" --from "$foundation_other_operator" --rpc-url "$foundation_rpc" \
  > ../evidence/unauthorized-controller.log 2>&1; then
  echo 'Unexpected unauthorized controller success' >&2
  exit 1
fi
if cast call "$foundation_membership" 'recordOrder((bytes32,bytes32,uint16,uint64,uint64,bool),bytes32)' \
  "$foundation_input_a" "$foundation_order_a" --from "$foundation_operator" --rpc-url "$foundation_rpc" \
  > ../evidence/unauthorized-registry.log 2>&1; then
  echo 'Unexpected direct registry write success' >&2
  exit 1
fi
if cast call "$foundation_controller" 'seedSyntheticIdentities()' \
  --from "$foundation_operator" --rpc-url "$foundation_rpc" > ../evidence/reseed.log 2>&1; then
  echo 'Unexpected reseed success after bootstrap retirement' >&2
  exit 1
fi

cast send "$foundation_controller" 'recordRestriction((bytes32,bytes32,uint16,uint64,uint64,bool))' \
  "$foundation_input_a" --from "$foundation_operator" --unlocked --rpc-url "$foundation_rpc" --json > ../evidence/record-a.json
cast send "$foundation_controller" 'recordRestriction((bytes32,bytes32,uint16,uint64,uint64,bool))' \
  "$foundation_input_b" --from "$foundation_operator" --unlocked --rpc-url "$foundation_rpc" --json > ../evidence/record-b.json
test "$(cast call "$foundation_membership" 'isRestrictedNow(bytes32,uint8)(bool)' "$foundation_person" 1 --rpc-url "$foundation_rpc")" = true
cast send "$foundation_controller" 'stayRestriction(bytes32,bytes32,uint256)' \
  "$foundation_person" "$foundation_order_b" 1 --from "$foundation_operator" --unlocked --rpc-url "$foundation_rpc" --json > ../evidence/stay-b.json
test "$(cast call "$foundation_membership" 'isRestrictedNow(bytes32,uint8)(bool)' "$foundation_person" 0 --rpc-url "$foundation_rpc")" = true
test "$(cast call "$foundation_membership" 'isRestrictedNow(bytes32,uint8)(bool)' "$foundation_person" 1 --rpc-url "$foundation_rpc")" = false
cast send "$foundation_controller" 'resumeRestriction(bytes32,bytes32,uint256)' \
  "$foundation_person" "$foundation_order_b" 2 --from "$foundation_operator" --unlocked --rpc-url "$foundation_rpc" --json > ../evidence/resume-b.json
test "$(cast call "$foundation_membership" 'isRestrictedNow(bytes32,uint8)(bool)' "$foundation_person" 1 --rpc-url "$foundation_rpc")" = true
cast send "$foundation_controller" 'revokeRestriction(bytes32,bytes32,uint256)' \
  "$foundation_person" "$foundation_order_b" 3 --from "$foundation_operator" --unlocked --rpc-url "$foundation_rpc" --json > ../evidence/revoke-b.json
test "$(cast call "$foundation_membership" 'isRestrictedNow(bytes32,uint8)(bool)' "$foundation_person" 0 --rpc-url "$foundation_rpc")" = true
foundation_mutations=$(cast call "$foundation_membership" 'electorateMutationCount()(uint256)' --rpc-url "$foundation_rpc")
test "$foundation_mutations" = 5

# Expiry is checked at its exact boundary without a cleanup transaction or a forged source-counter update.
cast rpc evm_setNextBlockTimestamp "$foundation_short_end" --rpc-url "$foundation_rpc" > /dev/null
cast rpc evm_mine --rpc-url "$foundation_rpc" > /dev/null
test "$(cast call "$foundation_membership" 'isRestrictedNow(bytes32,uint8)(bool)' "$foundation_person" 0 --rpc-url "$foundation_rpc")" = false
test "$(cast call "$foundation_membership" 'electorateMutationCount()(uint256)' --rpc-url "$foundation_rpc")" = "$foundation_mutations"

foundation_input_c="($foundation_other_person,$foundation_order_c,16,$foundation_start,0,true)"
cast send "$foundation_controller" 'recordRestriction((bytes32,bytes32,uint16,uint64,uint64,bool))' \
  "$foundation_input_c" --from "$foundation_operator" --unlocked --rpc-url "$foundation_rpc" --json > ../evidence/record-c.json
test "$(cast call "$foundation_membership" 'isRestrictedNow(bytes32,uint8)(bool)' "$foundation_other_person" 4 --rpc-url "$foundation_rpc")" = true
cast send "$foundation_controller" 'revokeRestriction(bytes32,bytes32,uint256)' \
  "$foundation_other_person" "$foundation_order_c" 1 --from "$foundation_operator" --unlocked --rpc-url "$foundation_rpc" --json > ../evidence/revoke-c.json
test "$(cast call "$foundation_membership" 'isRestrictedNow(bytes32,uint8)(bool)' "$foundation_other_person" 4 --rpc-url "$foundation_rpc")" = false
test "$(cast call "$foundation_controller" 'nextReceiptNonce()(uint256)' --rpc-url "$foundation_rpc")" = 7
test "$(cast call "$foundation_token" 'totalSupply()(uint256)' --rpc-url "$foundation_rpc" | cut -d ' ' -f 1)" = 1000000000000000000000000

# Copy only public local receipts; do not package Foundry's cache/private credential files.
cp broadcast/DeploySepoliaFoundation.s.sol/11155111/run-latest.json ../evidence/local-deployment-receipts.json
echo "Synthetic Sepolia rehearsal evidence: $foundation_work/evidence"
echo 'PASS: five contracts, fixed synthetic allocation, runtime/read-back checks, retired bootstrap, authorization probes, scoped relief and cleanup-free expiry.'
