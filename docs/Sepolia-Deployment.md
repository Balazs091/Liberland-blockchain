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
- if you do not set `FINANCE_ADMIN`, `IDENTITY_ADMIN`, or `LAND_ADMIN`, the deployer wallet becomes the admin of all three Milestone 6 offices

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

If broadcast already happened, verification artifacts will also be available under `broadcast/`.

## Current deployment scope

The script now deploys and wires the Milestone 06 stack:

- core: `ConstitutionKernel`, `ActionTimelock`, `GovernanceRouter`
- registries: identity, stake, legislation, referendum, congress candidate, senate seat, budget envelope, office
- policies: citizen eligibility, unstaking, voting power, candidate eligibility, congress election, referendum, senate powers, office permission, treasury spending
- apps: congress election, referendum, senate, public veto, payout queue, office executor
- treasury: `TreasuryVault`
- bootstrap-created offices:
  - `Ministry of Finance`
  - `Identity Office`
  - `Land Registry Office`

The production Congress election policy uses a 90 day recurring cycle duration. Finalizing the latest ended Congress election creates the next deterministic cycle in the same transaction, and future cadence changes can be routed through a bounded `CongressElectionPolicy` referendum.

## Important limitation

This deploy script creates an empty Sepolia environment. It does not seed identities, stake, legislation, referenda, Senate seats, or demo budgets.

Use `scripts/DeployDemo.s.sol` instead when you want a public demo deployment with realistic data already loaded.
