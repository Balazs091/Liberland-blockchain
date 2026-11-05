#!/usr/bin/env bash
set -euo pipefail

# Localhost only: no checkout .env, public RPC, or real operator key is loaded.
governed_source_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
governed_work="$(mktemp -d -t liberland-sepolia-governed.XXXXXX)"
mkdir -p "$governed_work/source/deployments" "$governed_work/evidence"
tar -C "$governed_source_root" -cf - contracts scripts foundry.toml remappings.txt | tar -C "$governed_work/source" -xf -
ln -s "$governed_source_root/lib" "$governed_work/source/lib"
cd "$governed_work/source"

anvil --host 127.0.0.1 --port 18562 --chain-id 11155111 --hardfork osaka --silent > ../evidence/anvil.log 2>&1 &
governed_anvil_pid=$!
trap 'kill "$governed_anvil_pid" 2>/dev/null || true' EXIT
sleep 1
kill -0 "$governed_anvil_pid"
governed_rpc='http://127.0.0.1:18562'
test "$(cast chain-id --rpc-url "$governed_rpc")" = 11155111
# Public Anvil fixture, only for the disposable local chain above.
export SEPOLIA_GOVERNED_PRIVATE_KEY='0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80'
governed_accounts=$(cast rpc eth_accounts --rpc-url "$governed_rpc")
governed_operator=$(jq -r '.[0]' <<< "$governed_accounts")
export SEPOLIA_GOVERNED_TESTER_1=$(jq -r '.[1]' <<< "$governed_accounts")
export SEPOLIA_GOVERNED_TESTER_2=$(jq -r '.[2]' <<< "$governed_accounts")
export SEPOLIA_GOVERNED_TESTER_3=$(jq -r '.[3]' <<< "$governed_accounts")
for governed_i in 0 1 2 3 4; do
  export "CIVIC_REVIEWER_$governed_i=$(jq -r ".[$((governed_i + 4))]" <<< "$governed_accounts")"
done

forge script scripts/DeploySepoliaGoverned.s.sol:DeploySepoliaGoverned \
  --rpc-url "$governed_rpc" --broadcast --slow --gas-estimate-multiplier 150 -vv \
  > ../evidence/deploy.log 2>&1
governed_manifest='deployments/sepolia-governed.json'
cp "$governed_manifest" ../evidence/sepolia-governed.json
jq -e '.chainId == 11155111 and .deploymentKind == "SEPOLIA_GOVERNED_SYNTHETIC_STAGING" and .syntheticOnly == true and .bootstrapRetired == true and .legalWorkflowsInstalled == false and .governanceInstalled == true' "$governed_manifest" > ../evidence/manifest-check.txt
governed_kernel=$(jq -r .constitutionKernel "$governed_manifest")
governed_token=$(jq -r .llmToken "$governed_manifest")
governed_identity=$(jq -r .identityRegistry "$governed_manifest")
governed_membership=$(jq -r .membershipRegistry "$governed_manifest")
governed_controller=$(jq -r .membershipController "$governed_manifest")
governed_referenda=$(jq -r .referendumApp "$governed_manifest")
governed_votes=$(jq -r .referendumRegistry "$governed_manifest")
governed_queue=$(jq -r .actionTimelock "$governed_manifest")
governed_router=$(jq -r .governanceRouter "$governed_manifest")
governed_office=$(jq -r .officeExecutor "$governed_manifest")
governed_writer_id=$(cast keccak 'authority.identity-writer')
governed_plan_id=$(cast keccak 'registry.module-upgrade-plan')
governed_plans=$(jq -r .moduleUpgradePlanRegistry "$governed_manifest")
governed_person=$(cast to-uint256 1)

for governed_authority in "$governed_kernel" "$governed_router" "$governed_office"; do
  test "$(cast call "$governed_authority" 'bootstrapAuthority()(address)' --rpc-url "$governed_rpc")" = '0x0000000000000000000000000000000000000000'
done
test "$(cast call "$governed_identity" 'totalIdentityCount()(uint256)' --rpc-url "$governed_rpc")" = 4
test "$(cast call "$governed_token" 'totalSupply()(uint256)' --rpc-url "$governed_rpc" | cut -d ' ' -f 1)" = 1000000000000000000000000
test "$(cast call "$governed_controller" 'canSubmit(address)(bool)' "$SEPOLIA_GOVERNED_TESTER_1" --rpc-url "$governed_rpc")" = false
test "$(cast call "$governed_controller" 'canSubmit(address)(bool)' "$SEPOLIA_GOVERNED_TESTER_2" --rpc-url "$governed_rpc")" = true
test "$(cast call "$governed_kernel" 'getModule(bytes32)(address)' "$governed_plan_id" --rpc-url "$governed_rpc")" = "$(jq -r .moduleUpgradePlanRegistry "$governed_manifest")"

: > ../evidence/runtime-hashes.jsonl
for governed_pair in 'llmToken:llmRuntimeHash' 'membershipRegistry:membershipRuntimeHash' 'membershipController:membershipControllerRuntimeHash' 'moduleUpgradePlanRegistry:moduleUpgradePlanRegistryRuntimeHash' 'referendumProposalValidator:referendumProposalValidatorRuntimeHash'; do
  governed_address=$(jq -r ".${governed_pair%%:*}" "$governed_manifest")
  governed_expected=$(jq -r ".${governed_pair##*:}" "$governed_manifest")
  governed_runtime=$(cast code "$governed_address" --rpc-url "$governed_rpc")
  test "$governed_runtime" != '0x'
  governed_observed=$(cast keccak "$governed_runtime")
  test "${governed_observed,,}" = "${governed_expected,,}"
  jq -nc --arg address "$governed_address" --arg expected "$governed_expected" --arg observed "$governed_observed" \
    '{address:$address,expected:$expected,observed:$observed}' >> ../evidence/runtime-hashes.jsonl
done

governed_now=$(cast block latest --rpc-url "$governed_rpc" --json | jq -r '(.data // .).timestamp')
governed_order=$(cast keccak 'governed-rehearsal-indefinite-political')
governed_input="($governed_person,$governed_order,1,$((governed_now)),0,true)"
if cast call "$governed_membership" 'recordOrder((bytes32,bytes32,uint16,uint64,uint64,bool),bytes32)' \
  "$governed_input" "$governed_order" --from "$governed_operator" --rpc-url "$governed_rpc" \
  > ../evidence/direct-registry-write-rejected.log 2>&1; then
  echo 'Unexpected direct membership write success' >&2
  exit 1
fi
cast send "$governed_controller" 'recordRestriction((bytes32,bytes32,uint16,uint64,uint64,bool))' \
  "$governed_input" --from "$SEPOLIA_GOVERNED_TESTER_2" --unlocked --rpc-url "$governed_rpc" --json > ../evidence/order-recorded.json
test "$(cast call "$governed_membership" 'isRestrictedNow(bytes32,uint8)(bool)' "$governed_person" 0 --rpc-url "$governed_rpc")" = true
cast call "$governed_membership" 'orderOf(bytes32,bytes32)' "$governed_person" "$governed_order" --rpc-url "$governed_rpc" > ../evidence/order-before-upgrade.hex

forge create contracts/mocks/SepoliaGovernedMembershipController.sol:SepoliaGovernedMembershipController \
  --private-key "$SEPOLIA_GOVERNED_PRIVATE_KEY" --rpc-url "$governed_rpc" --broadcast --json \
  --constructor-args "$governed_identity" "$governed_membership" > ../evidence/replacement-deployed.json
governed_replacement=$(jq -r '(.data // .).deployedTo' ../evidence/replacement-deployed.json)
test "$governed_replacement" != null
governed_replacement_tx=$(jq -r '(.data // .).transactionHash' ../evidence/replacement-deployed.json)
cast receipt "$governed_replacement_tx" --rpc-url "$governed_rpc" --json > ../evidence/replacement-receipt.json
test "$(jq -r '(.data // .).status' ../evidence/replacement-receipt.json)" = '0x1'
governed_expected=$(jq -r .membershipControllerRuntimeHash "$governed_manifest")
governed_observed=$(cast keccak "$(cast code "$governed_replacement" --rpc-url "$governed_rpc")")
test "${governed_observed,,}" = "${governed_expected,,}"
jq -nc --arg address "$governed_replacement" --arg expected "$governed_expected" --arg observed "$governed_observed" \
  '{address:$address,expected:$expected,observed:$observed}' >> ../evidence/runtime-hashes.jsonl

# Normal public referendum + waiting periods + permissionless execution. Tester accounts vote; operator abstains.
governed_replace() {
  local governed_target="$1" governed_label="$2"
  local governed_start governed_end governed_metadata governed_evidence governed_proposal governed_ref_raw governed_ref governed_result governed_action governed_old governed_hash governed_updates governed_plan_raw governed_plan
  governed_start=$(( $(cast block latest --rpc-url "$governed_rpc" --json | jq -r '(.data // .).timestamp') + 30 ))
  governed_end=$((governed_start + 604800))
  governed_metadata=$(cast keccak "synthetic governed $governed_label metadata")
  governed_evidence=$(cast keccak "synthetic governed $governed_label reviewed runtime and preserved ledger")
  governed_old=$(cast call "$governed_kernel" 'getModule(bytes32)(address)' "$governed_writer_id" --rpc-url "$governed_rpc")
  governed_hash=$(cast keccak "$(cast code "$governed_target" --rpc-url "$governed_rpc")")
  governed_updates="[($governed_writer_id,$governed_old,$governed_target,$governed_hash)]"
  governed_plan_raw=$(cast call "$governed_plans" 'computePlanId((bytes32,address,address,bytes32)[],bytes32)' "$governed_updates" "$governed_evidence" --rpc-url "$governed_rpc")
  governed_plan="0x${governed_plan_raw: -64}"
  cast send "$governed_plans" 'publishPlan((bytes32,address,address,bytes32)[],bytes32)' "$governed_updates" "$governed_evidence" \
    --from "$SEPOLIA_GOVERNED_TESTER_3" --unlocked --rpc-url "$governed_rpc" --json > "../evidence/$governed_label-plan-published.json"
  governed_proposal="($governed_metadata,$governed_plan,$governed_plans,$governed_start,$governed_end,604800)"
  governed_ref_raw=$(cast call "$governed_referenda" 'createCitizenModuleBundleReferendum((bytes32,bytes32,address,uint64,uint64,uint64))' \
    "$governed_proposal" --from "$SEPOLIA_GOVERNED_TESTER_1" --rpc-url "$governed_rpc")
  governed_ref="0x${governed_ref_raw: -64}"
  cast send "$governed_referenda" 'createCitizenModuleBundleReferendum((bytes32,bytes32,address,uint64,uint64,uint64))' \
    "$governed_proposal" --from "$SEPOLIA_GOVERNED_TESTER_1" --unlocked --rpc-url "$governed_rpc" --json > "../evidence/$governed_label-proposal.json"
  cast rpc evm_setNextBlockTimestamp "$governed_start" --rpc-url "$governed_rpc" > /dev/null
  cast rpc evm_mine --rpc-url "$governed_rpc" > /dev/null
  for governed_voter in "$SEPOLIA_GOVERNED_TESTER_1" "$SEPOLIA_GOVERNED_TESTER_2"; do
    cast send "$governed_referenda" 'castVote(bytes32,uint8)' "$governed_ref" 2 --from "$governed_voter" \
      --unlocked --rpc-url "$governed_rpc" --json > "../evidence/$governed_label-vote-$governed_voter.json"
  done
  cast rpc evm_setNextBlockTimestamp "$governed_end" --rpc-url "$governed_rpc" > /dev/null
  cast rpc evm_mine --rpc-url "$governed_rpc" > /dev/null
  cast send "$governed_referenda" 'finalizeReferendum(bytes32)' "$governed_ref" --from "$SEPOLIA_GOVERNED_TESTER_3" \
    --unlocked --rpc-url "$governed_rpc" --json > "../evidence/$governed_label-finalized.json"
  governed_result=$(cast call "$governed_votes" 'getReferendumResult(bytes32)' "$governed_ref" --rpc-url "$governed_rpc")
  governed_action="0x${governed_result: -64}"
  test "$governed_action" != '0x0000000000000000000000000000000000000000000000000000000000000000'
  if cast call "$governed_queue" 'executeAction(bytes32)' "$governed_action" --from "$SEPOLIA_GOVERNED_TESTER_3" \
    --rpc-url "$governed_rpc" > "../evidence/$governed_label-early-execution-rejected.log" 2>&1; then
    echo 'Unexpected early governance execution success' >&2
    exit 1
  fi
  # Vote closing + adoption delay + a small local transaction margin; inside the 7-day execution window.
  cast rpc evm_setNextBlockTimestamp "$((governed_end + 604810))" --rpc-url "$governed_rpc" > /dev/null
  cast rpc evm_mine --rpc-url "$governed_rpc" > /dev/null
  cast send "$governed_queue" 'executeAction(bytes32)' "$governed_action" --from "$SEPOLIA_GOVERNED_TESTER_3" \
    --unlocked --rpc-url "$governed_rpc" --json > "../evidence/$governed_label-executed.json"
  local governed_current
  governed_current=$(cast call "$governed_kernel" 'getModule(bytes32)(address)' "$governed_writer_id" --rpc-url "$governed_rpc")
  test "${governed_current,,}" = "${governed_target,,}"
}

governed_replace "$governed_replacement" upgrade
test "$(cast call "$governed_controller" 'canSubmit(address)(bool)' "$SEPOLIA_GOVERNED_TESTER_2" --rpc-url "$governed_rpc")" = false
test "$(cast call "$governed_replacement" 'canSubmit(address)(bool)' "$SEPOLIA_GOVERNED_TESTER_2" --rpc-url "$governed_rpc")" = true
cast call "$governed_membership" 'orderOf(bytes32,bytes32)' "$governed_person" "$governed_order" --rpc-url "$governed_rpc" > ../evidence/order-after-upgrade.hex
cmp ../evidence/order-before-upgrade.hex ../evidence/order-after-upgrade.hex
cast send "$governed_replacement" 'stayRestriction(bytes32,bytes32,uint256)' "$governed_person" "$governed_order" 1 \
  --from "$SEPOLIA_GOVERNED_TESTER_2" --unlocked --rpc-url "$governed_rpc" --json > ../evidence/replacement-stayed-order.json
test "$(cast call "$governed_membership" 'isRestrictedNow(bytes32,uint8)(bool)' "$governed_person" 0 --rpc-url "$governed_rpc")" = false

# Rollback is a second ordinary public vote. State stays in the same membership ledger throughout.
governed_replace "$governed_controller" rollback
test "$(cast call "$governed_replacement" 'canSubmit(address)(bool)' "$SEPOLIA_GOVERNED_TESTER_2" --rpc-url "$governed_rpc")" = false
cast send "$governed_controller" 'revokeRestriction(bytes32,bytes32,uint256)' "$governed_person" "$governed_order" 2 \
  --from "$SEPOLIA_GOVERNED_TESTER_2" --unlocked --rpc-url "$governed_rpc" --json > ../evidence/restored-controller-revoked-order.json
test "$(cast call "$governed_membership" 'membershipRevisionOf(bytes32)(uint256)' "$governed_person" --rpc-url "$governed_rpc")" = 3
test "$(cast call "$governed_membership" 'isRestrictedNow(bytes32,uint8)(bool)' "$governed_person" 0 --rpc-url "$governed_rpc")" = false
cp broadcast/DeploySepoliaGoverned.s.sol/11155111/run-latest.json ../evidence/local-deployment-receipts.json
echo "Governed Sepolia rehearsal evidence: $governed_work/evidence"
echo 'PASS: fixed LLM, full governance, retired bootstrap, current Congress effect authorization, real citizen-vote controller replacement and rollback, preserved orders, no deployer vote or admin bypass.'
