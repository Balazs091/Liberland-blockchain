# Liberland EVM

Liberland EVM is a constitution-aligned governance protocol in Solidity.

The repository is organized for small, auditable milestones. It is not a generic DAO and it must not rely on hidden super-admin powers, arbitrary execution helpers, or broad emergency backdoors.

## Current status

The repository contains milestone implementations through the Milestone 9 decision surface:

- core governance lifecycle with a bounded action timelock
- identity, citizenship, stake, and voting-power foundations
- referenda, Tier 1/Tier 2 enactment after adoption delay, Senate cancellation, Senate active-referendum veto, Senate sub-legal repeal, President proxy voting for non-voting senators, and public veto flows
- Congress election cycles, deterministic recurring cadence, candidacy, standing weighted signed ballots, finalization, and runner-up succession
- treasury, referendum-approved budget laws, budget-envelope, office, and payout routing flows
- office-authorized land and company registries with stable fact storage for parcels, titles, disputes, encumbrances, companies, directors, filings, and official share ledgers
- stake-backed USDC lending with stake liens, utilization-based interest, treasury reserves, and liquidation into active staked LLM
- bounded Congress and ministry decisions for ERC20 movement, ministry clerk decisions, and LLM transfer-and-stake decisions
- production initial setup authority for genesis citizens, Senate seats, Congress members, and offices, with a readiness check and permanent seal
- Sepolia demo deployment script with seeded read-state and live onboarding helpers

## Required reading

- `AGENTS.md`
- `docs/Milestone-01.md`
- `docs/Architecture.md`
- current milestone document under `docs/`

## Repository layout

```text
contracts/
  apps/
  core/
  interfaces/
  libraries/
  mocks/
  policies/
  registries/
  types/
docs/
frontend-export/
scripts/
test/
```

## Tooling

- Solidity `0.8.35`
- Foundry for build, test, formatting, and scripts
- Anvil for local execution
- Slither for static analysis

Ensure the Foundry binaries are available on your `PATH` before running commands.

After cloning, initialize submodules:

```bash
git submodule update --init --recursive
```

## Commands

```bash
forge fmt
forge build
forge test -vvv
slither .
```

`slither` is optional for local development, but should be run before relying on a production deployment.

## Deployment Outputs

Deployment scripts write generated address files under `deployments/`. Those files are ignored by Git because they are environment-specific and can become stale after contract changes.

For a public demo deployment, run `scripts/DeployDemo.s.sol`, then copy the generated `deployments/sepolia-demo.json` to `frontend-export/sepolia-demo.json` for the frontend handoff package.

For a production-style deployment, `scripts/Deploy.s.sol` registers `InitialSetupAuthority`, seeds deterministic genesis citizens, Senate seats, Congress members, President status, and offices from `.env`, checks readiness, then seals that setup authority before bootstrap is disabled.

The audit scope covers the full contract set under `contracts/`, including the Milestone 8 lending modules and the Milestone 9 `DecisionApp`. Deployment scope is separate and script-dependent: `scripts/Deploy.s.sol` (production) deploys the core governance set — neither lending nor `DecisionApp` — while `scripts/DeployDemo.s.sol` additionally deploys `DecisionApp`.

The current demo deploy batches bootstrap module registration and is designed to stay below common public-RPC free-tier limits. Re-check the exact transaction count after deployment-script changes; the demo always sends one USDC treasury-prefund transaction, and a nonzero `TREASURY_PREFUND_LLM` adds another.
