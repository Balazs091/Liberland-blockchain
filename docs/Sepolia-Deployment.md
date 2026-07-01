# Sepolia Deployment

This repository can be deployed to Sepolia with Foundry using the Solidity script at `scripts/Deploy.s.sol`.

## Prerequisites

- Foundry installed and available on `PATH`
- A Sepolia deployer account funded with Sepolia ETH
- A Sepolia RPC URL
- An Etherscan API key for verification

## Environment variables

Do not commit secrets into the repository.

```bash
cp .env.example .env
```

Populate `.env` with your real values, then load it:

```bash
set -a
source .env
set +a
```

Important:

- `PRIVATE_KEY` must include the `0x` prefix
- the deploy script writes deployed addresses to `deployments/sepolia.json`
- if you do not set `FINANCE_ADMIN`, `IDENTITY_ADMIN`, `LAND_ADMIN`, or `COMPANY_REGISTRY_ADMIN`, the deployer wallet becomes the admin of the corresponding office
- production deployment requires deterministic genesis entries in `.env`; do not use placeholder wallets or metadata for a real launch
- deployment JSON files are generated outputs and are ignored by Git to avoid committing stale addresses

## Genesis seed inputs

`scripts/Deploy.s.sol` seeds genesis state before `InitialSetupAuthority` is sealed. The script requires:

- `GENESIS_CITIZEN_COUNT`
- one `GENESIS_CITIZEN_N_PERSON_ID`, `GENESIS_CITIZEN_N_WALLET`, `GENESIS_CITIZEN_N_ACTIVE_STAKE`, `GENESIS_CITIZEN_N_METADATA_HASH`, and `GENESIS_CITIZEN_N_METADATA_URI` entry for every citizen index from `0` to `GENESIS_CITIZEN_COUNT - 1`
- `GENESIS_SENATE_SEAT_COUNT` and `GENESIS_SENATE_SEAT_N_CITIZEN_INDEX` entries assigning each genesis Senate seat to a citizen index
- `GENESIS_CONGRESS_MEMBER_COUNT` and `GENESIS_CONGRESS_MEMBER_N_CITIZEN_INDEX` entries defining the genesis Congress rank order
- `GENESIS_PRESIDENT_CITIZEN_INDEX` and `GENESIS_PRESIDENT_MANDATE_HASH`

The script validates that each citizen has at least the minimum citizen stake, each genesis Congress member has at least the minimum candidate stake, Senate and Congress citizen indexes are unique within their respective assignments, and the configured Senate seat count meets the current Senate cancellation threshold.

## Dry run

Compile first:

```bash
forge build
```

Then simulate the deployment without broadcasting:

```bash
forge script scripts/Deploy.s.sol:Deploy \
  --rpc-url "$SEPOLIA_RPC_URL" \
  -vvvv
```

## Broadcast deployment

When the dry run succeeds:

```bash
forge script scripts/Deploy.s.sol:Deploy \
  --rpc-url "$SEPOLIA_RPC_URL" \
  --broadcast \
  -vvvv
```

## Verify contracts

After a successful broadcast, run:

```bash
forge script scripts/Deploy.s.sol:Deploy \
  --rpc-url "$SEPOLIA_RPC_URL" \
  --broadcast \
  --verify \
  --etherscan-api-key "$ETHERSCAN_API_KEY" \
  -vvvv
```

If broadcast already happened, verification artifacts will also be available under `broadcast/`. Treat `broadcast/` as generated Foundry transaction output, not application config.

## Current deployment scope

The script deploys and wires the production-style governance stack through the land/company registry surface:

- core: `ConstitutionKernel`, `ActionTimelock`, `GovernanceRouter`
- registries: identity, stake, legislation, referendum, congress candidate, senate seat, land, company, budget envelope, office
- policies: citizen eligibility, unstaking, voting power, candidate eligibility, congress election, referendum, senate powers, office permission, treasury spending
- apps: congress election, referendum, senate, public veto, land registry, company registry, payout queue, office executor, initial setup authority
- treasury: `TreasuryVault`
- genesis-created offices:
  - `Ministry of Finance`
  - `Identity Office`
  - `Land Registry Office`
  - `Company Registry Office`

The production-style deploy script also batches bootstrap module-pointer writes and stays designed for small public-RPC deployments. Re-check the exact transaction count after deployment-script changes with a local Anvil broadcast:

```bash
anvil --silent

forge script scripts/Deploy.s.sol:Deploy \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast \
  -q

jq '.transactions | length' broadcast/Deploy.s.sol/31337/run-latest.json
```

The production Congress election policy uses a 90 day recurring cycle duration. Finalizing the latest ended Congress election creates the next deterministic cycle in the same transaction, automatically registers the newly active Congress members as next-cycle candidates, and future cadence changes can be routed through a bounded `CongressElectionPolicy` referendum.

The deployment registers `InitialSetupAuthority` before bootstrap is disabled. This authority is intentionally narrow: it adds genesis citizens/stake, assigns Senate seats, seeds a finalized Congress term, and creates initial offices from the deterministic `.env` entries. It cannot execute arbitrary calldata or update kernel modules. The production script calls its readiness check and then permanently seals the setup authority before disabling bootstrap.

## Important limitation

This deploy script creates the production governance baseline only. It does not seed legislation, referenda, land/company data, treasury budgets, or demo balances. Use `scripts/DeployDemo.s.sol` instead when you want a public demo deployment with realistic data already loaded.

`DecisionApp` and the Milestone 8 lending contracts are intentionally not deployed by this production-style script (the demo `scripts/DeployDemo.s.sol` deploys `DecisionApp`). They remain part of the repository's audit scope even though this script does not deploy them.
