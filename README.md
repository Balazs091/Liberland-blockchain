# Liberland EVM

Liberland EVM is a constitution-aligned governance protocol in Solidity.

The repository is organized for small, auditable milestones. It is not a generic DAO and it must not rely on hidden super-admin powers, arbitrary execution helpers, or broad emergency backdoors.

## Current status

The repository contains milestone implementations through the demo-ready Milestone 6 surface:

- core governance lifecycle with a bounded action timelock
- identity, citizenship, stake, and voting-power foundations
- referenda, legislation enactment, Senate cancellation, and public veto flows
- Congress election cycles, deterministic recurring cadence, candidacy, weighted signed ballots, finalization, and runner-up succession
- treasury, budget-envelope, office, and payout routing flows
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

- Solidity `0.8.34`
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

The current demo deploy batches bootstrap module registration and stays below 100 broadcast transactions. With treasury prefunding disabled it emits 71 transactions; enabling `TREASURY_PREFUND_WEI` adds one prefund transaction.
