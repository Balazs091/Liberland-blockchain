# Liberland EVM

Liberland EVM is a constitution-aligned governance protocol in Solidity.

It is not a generic DAO and it must not rely on hidden super-admin powers, arbitrary execution helpers, or broad emergency backdoors.

## Current status

The implemented contract surface includes:

- core governance lifecycle with a bounded action timelock
- identity, citizenship, stake, and voting-power foundations
- referenda, Tier 1/Tier 2 enactment after adoption delay, Senate cancellation, Senate active-referendum veto, Senate sub-legal repeal, President proxy voting for non-voting senators, and public veto flows
- Congress election cycles, deterministic recurring cadence, person-bound candidacy, cycle-scoped weighted signed ballots, finalization, runner-up succession, and zero-active-wallet seat recovery
- treasury, referendum-approved budget laws, budget-envelope, office, and payout routing flows
- an office-authorized, versioned land cadastre with stable legal-party IDs, dual-consent transfers, atomic parcel
  operations, and a separate company registry with official directors, filings, and share ledgers
- stake-backed USDC lending with stake liens, utilization-based interest, treasury reserves, and liquidation into active staked LLM
- bounded Congress and ministry decisions for ERC20 movement, ministry clerk decisions, and LLM transfer-and-stake decisions
- production initial setup authority for genesis citizens, Senate seats, Congress members, and offices, with a readiness check and permanent seal
- canonical LLM staking custody with aggregate backing checks and checkpointed electorate aggregates and eligibility
- process-pinned governance policies and last-completed-block stake/eligibility snapshots for live referenda and elections
- person-bound elected/executive authority that follows an approved active-wallet migration
- person-bound candidacy that survives wallet migration without duplicate applications or ballot entries
- a 70,000,000 LLM hard-cap requirement and evidence-backed, budgeted contribution rewards with no Treasury mint power
- globally indexed lending debt, lien-start retained-stake floors, and office-and-pool-keyed ministry lending shares
- Sepolia demo deployment script with seeded read-state and live onboarding helpers

## Auditor orientation

- `docs/Architecture.md`
- `docs/Protocol-Parameters.md`
- `docs/Internal-Audit-Report.md`
- `docs/Audit-Scope.md`
- `docs/Constitution-Alignment.md`
- `docs/Land-Cadastre.md`
- `docs/User-Journeys.md`
- the applicable network deployment guide under `docs/`

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

- Solidity `0.8.36`
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

Deployment parameters are network-specific and intentionally kept in separate manifests:

- `scripts/parameters/SepoliaDemoParameters.sol`: Sepolia demo, including 3-day Congress cycles
- `scripts/parameters/EthereumMainnetParameters.sol`: Ethereum mainnet production, including seven Congress seats and 90-day cycles

See `docs/Sepolia-Demo-Deployment.md` and `docs/Ethereum-Mainnet-Deployment.md` for operators. Frontend developers should start with `frontend-export/FRONTEND-CHANGES.md` and `frontend-export/FRONTEND-HOWTO.md`.

For a public demo deployment, run `scripts/DeployDemo.s.sol`, then copy the generated `deployments/sepolia-demo.json` to `frontend-export/sepolia-demo.json` for the frontend handoff package.
In the current demo, `identityApp` and `demoCitizenGateway` intentionally resolve to the same deployed contract:
`DemoCitizenGateway` inherits the standard `IdentityApp` workflows so the demo has one standing identity-registry
writer.

For an Ethereum mainnet deployment, `scripts/Deploy.s.sol` registers `InitialSetupAuthority`, seeds deterministic genesis citizens, all seven Congress seats, Senate seats, President status, and offices from `.env`, imports the remaining pre-migration Congress cycle, checks readiness, then seals that setup authority before bootstrap is disabled. It writes `deployments/ethereum-mainnet.json`.
The Congress candidate registry remains exclusively setup-controlled until the continuity term exists, then the
script hands authority to `CongressElectionApp` before its readiness check and permanent seal.

Both network scripts deploy the bounded `DecisionApp`, `MinistryTreasury`, and lending stack. Production uses an
explicit external six-decimal USDC address and the conservative fixed-price launch parameters; Sepolia uses mock
assets and demo-only onboarding. See `docs/Audit-Scope.md` for the review boundary and
`docs/Protocol-Parameters.md` for the complete boss-review table.

The demo deployment is transaction-heavy and should be rehearsed against a Sepolia-compatible local node or fork before using a rate-limited public RPC.

Repository documentation is audit orientation, not an audit verdict. Revision-specific test, coverage, static
analysis, and runtime-size evidence belongs in `docs/Internal-Audit-Report.md` and must be refreshed before the
external-audit handoff.
