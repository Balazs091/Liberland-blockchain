#!/usr/bin/env bash
set -euo pipefail
# Disposable localhost chain ONLY. This publicly known Anvil key must never hold real assets.
audit_source_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
audit_work="$(mktemp -d -t liberland-genesis-rehearsal.XXXXXX)"
mkdir -p "$audit_work/source" "$audit_work/evidence"
tar -C "$audit_source_root" -cf - contracts scripts foundry.toml remappings.txt | tar -C "$audit_work/source" -xf -
ln -s "$audit_source_root/lib" "$audit_work/source/lib"
cd "$audit_work/source"
# Never load the source checkout's .env or connect to a public RPC.
anvil --host 127.0.0.1 --port 18560 --chain-id 1 --hardfork osaka --silent > ../evidence/anvil.log 2>&1 &
audit_anvil_pid=$!
trap 'kill "$audit_anvil_pid" 2>/dev/null || true' EXIT
sleep 1
kill -0 "$audit_anvil_pid"
audit_rpc='http://127.0.0.1:18560'
export PRIVATE_KEY='0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80'
audit_deployer=$(cast wallet address --private-key "$PRIVATE_KEY")
forge create contracts/mocks/LLMToken.sol:LLMToken --rpc-url "$audit_rpc" --private-key "$PRIVATE_KEY" --broadcast --json > ../evidence/rehearsal-llm.json
forge create contracts/mocks/MockUSDC.sol:MockUSDC --rpc-url "$audit_rpc" --private-key "$PRIVATE_KEY" --broadcast --json > ../evidence/rehearsal-usdc.json
export LLM_TOKEN=$(jq -r .deployedTo ../evidence/rehearsal-llm.json)
export USDC_TOKEN=$(jq -r .deployedTo ../evidence/rehearsal-usdc.json)
cast send "$LLM_TOKEN" 'mint(address,uint256)' "$audit_deployer" 100000000000000000000000 --rpc-url "$audit_rpc" --private-key "$PRIVATE_KEY" > ../evidence/rehearsal-mint.log
export FINANCE_ADMIN=$(printf '0x%040x' 4097)
export IDENTITY_ADMIN=$(printf '0x%040x' 4098)
export LAND_ADMIN=$(printf '0x%040x' 4099)
export COMPANY_REGISTRY_ADMIN=$(printf '0x%040x' 4100)
for audit_index in {0..4}; do
  export "CIVIC_REVIEWER_${audit_index}=$(printf '0x%040x' "$((12288+audit_index))")"
done
export TREASURY_ASSET_COUNT=2
export TREASURY_ASSET_0_ADDRESS="$LLM_TOKEN"
export TREASURY_ASSET_0_CLERK_OPERATIONS_LIMIT=3000000000000000000000
export TREASURY_ASSET_0_CLERK_SALARY_LIMIT=2000000000000000000000
export TREASURY_ASSET_1_ADDRESS="$USDC_TOKEN"
export TREASURY_ASSET_1_CLERK_OPERATIONS_LIMIT=3000000000
export TREASURY_ASSET_1_CLERK_SALARY_LIMIT=2000000000
export GENESIS_CITIZEN_COUNT=7
for audit_index in {0..6}; do
  export "GENESIS_CITIZEN_${audit_index}_PERSON_ID=$(printf '0x%064x' "$((audit_index+1))")"
  export "GENESIS_CITIZEN_${audit_index}_WALLET=$(printf '0x%040x' "$((8192+audit_index))")"
  export "GENESIS_CITIZEN_${audit_index}_ACTIVE_STAKE=10000000000000000000000"
  export "GENESIS_CITIZEN_${audit_index}_METADATA_HASH=$(printf '0x%064x' "$((audit_index+100))")"
  export "GENESIS_CITIZEN_${audit_index}_METADATA_URI=ipfs://synthetic-audit-citizen-$audit_index"
  export "GENESIS_CONGRESS_MEMBER_${audit_index}_CITIZEN_INDEX=$audit_index"
done
export GENESIS_CONGRESS_MEMBER_COUNT=7
export GENESIS_SENATE_SEAT_COUNT=2
export GENESIS_SENATE_SEAT_0_CITIZEN_INDEX=0
export GENESIS_SENATE_SEAT_1_CITIZEN_INDEX=1
export GENESIS_PRESIDENT_CITIZEN_INDEX=0
export GENESIS_PRESIDENT_MANDATE_HASH=$(printf '0x%064x' 456)
audit_timestamp=$(cast block latest --rpc-url "$audit_rpc" --json | jq -r .timestamp)
export GENESIS_CONGRESS_CYCLE_END_TIMESTAMP=$(( (audit_timestamp / 86400 + 30) * 86400 + 61200 ))
forge script scripts/Deploy.s.sol:Deploy --sig 'run()' --rpc-url "$audit_rpc" --broadcast --slow --gas-estimate-multiplier 200 -vv > ../evidence/rehearsal-prepare.log 2>&1
audit_kernel=$(jq -r .constitutionKernel deployments/ethereum-mainnet.json)
jq -e '.genesisComplete == false and .genesisCongressSeatCount == 0' deployments/ethereum-mainnet.json
cast call "$audit_kernel" 'bootstrapAuthority()(address)' --rpc-url "$audit_rpc" > ../evidence/rehearsal-bootstrap-before.log
cast rpc evm_mine --rpc-url "$audit_rpc" > /dev/null
forge script scripts/Deploy.s.sol:Deploy --sig 'completeGenesis(address)' "$audit_kernel" --rpc-url "$audit_rpc" --broadcast --slow --gas-estimate-multiplier 200 -vv > ../evidence/rehearsal-complete.log 2>&1
jq -e '.genesisComplete == true and .genesisCongressSeatCount == 7 and .genesisCongressContinuityCycleId == 2' deployments/ethereum-mainnet.json
audit_bootstrap=$(cast call "$audit_kernel" 'bootstrapAuthority()(address)' --rpc-url "$audit_rpc")
test "$audit_bootstrap" = '0x0000000000000000000000000000000000000000'
audit_router=$(jq -r .governanceRouter deployments/ethereum-mainnet.json)
test "$(cast call "$audit_router" 'bootstrapAuthority()(address)' --rpc-url "$audit_rpc")" = '0x0000000000000000000000000000000000000000'
audit_setup=$(jq -r .initialSetupAuthority deployments/ethereum-mainnet.json)
test "$(cast call "$audit_setup" 'isSealed()(bool)' --rpc-url "$audit_rpc")" = true
audit_candidates=$(jq -r .congressCandidateRegistry deployments/ethereum-mainnet.json)
audit_ranking=$(cast call "$audit_candidates" 'rankingStore()(address)' --rpc-url "$audit_rpc")
test "$(cast call "$audit_ranking" 'registry()(address)' --rpc-url "$audit_rpc")" = "$audit_candidates"
cast call "$audit_candidates" 'getCurrentOfficeTerm()((uint256,uint32,uint32,uint32,uint32,uint64,uint64))' --rpc-url "$audit_rpc" > ../evidence/rehearsal-congress-term.log
cast code "$audit_candidates" --rpc-url "$audit_rpc" > ../evidence/rehearsal-candidate-runtime.hex
audit_committee=$(jq -r .civicAppealReview deployments/ethereum-mainnet.json)
audit_identity=$(jq -r .identityApp deployments/ethereum-mainnet.json)
test "$(cast call "$audit_committee" 'identityApp()(address)' --rpc-url "$audit_rpc")" = "$audit_identity"
for audit_index in {0..4}; do
  audit_expected=$(jq -r ".civicReviewer$audit_index" deployments/ethereum-mainnet.json)
  test "$(cast call "$audit_committee" 'reviewerAt(uint256)(address)' "$audit_index" --rpc-url "$audit_rpc")" = "$audit_expected"
done
audit_office_executor=$(jq -r .officeExecutor deployments/ethereum-mainnet.json)
test "$(cast call "$audit_office_executor" 'bootstrapAuthority()(address)' --rpc-url "$audit_rpc")" = '0x0000000000000000000000000000000000000000'
echo "Synthetic rehearsal evidence: $audit_work/evidence"
echo 'PASS: local two-stage deployment, seven seats in manifest, setup sealed, kernel/router bootstrap retired; Osaka transaction gas cap enforced.'
