# Frontend Export

This folder is the clean handoff package for the frontend.

## Contents

- `sepolia-demo.json`
  - deployed contract addresses and seeded identifiers for the demo Sepolia environment
- `FRONTEND-HOWTO.md`
  - page-by-page guidance for the first demo frontend screens
- `abis/`
  - ABI artifacts for the currently deployed contract set
- `example-config.ts`
  - minimal example of how to wire the addresses into a React + `viem` + `wagmi` app

## Network

- network: `Sepolia`
- chain ID: `11155111`
- explorer: `https://sepolia.etherscan.io`

## Important notes

- Use `frontend-export/sepolia-demo.json`, not any file under `broadcast/.../dry-run/`
- `sepolia-demo.json` is the seeded Milestone 6 demo deployment once you copy it here after running `DeployDemo.s.sol`
- `sepolia-demo.json` in this folder currently mirrors the latest local deployment artifact
- The demo deployment adds seeded offices, a finance budget, referenda, a Congress election cycle, Senate seats, public veto state, a live `DemoCitizenGateway`, and a demo `LLM` merit token
- The fast demo timing uses a 24 hour unstake cooldown and a 72 hour Congress election cycle by policy
- Finalizing the latest ended Congress election creates the next deterministic cycle automatically in the same transaction; a public transaction is still required because the EVM has no native scheduler
- Future election cadence changes go through a bounded `CongressElectionPolicy` referendum and timelock update
- For live onboarding demos, set `IDENTITY_ADMIN` to a wallet you control before deploying; that wallet becomes the registrar for `DemoCitizenGateway`

## Suggested first screens

- protocol status
  - `ConstitutionKernel`
  - `GovernanceRouter`
  - `ActionTimelock`
- identity and stake reads
  - `IdentityRegistry`
  - `StakeRegistry`
  - `CitizenEligibilityPolicy`
  - `VotingPowerPolicy`
- live demo onboarding and staking
  - `DemoCitizenGateway`
  - `LLMToken`
- referendum reads
  - `ReferendumApp`
  - `ReferendumRegistry`
  - `ReferendumPolicy`
  - `LegislationRegistry`
- congress reads
  - `CongressElectionApp`
  - `CongressCandidateRegistry`
  - `CongressElectionPolicy`
- senate and veto reads
  - `SenateApp`
  - `SenateSeatRegistry`
  - `SenatePowersPolicy`
  - `PublicVetoApp`
- executive and treasury reads
  - `OfficeRegistry`
  - `BudgetEnvelopeRegistry`
  - `OfficeExecutor`
  - `PayoutQueue`
  - `TreasuryVault`

## ABI guidance

For most frontend work, prefer these as entrypoints:

- `ConstitutionKernel.json`
- `GovernanceRouter.json`
- `ActionTimelock.json`
- `ReferendumApp.json`
- `CongressElectionApp.json`
- `SenateApp.json`
- `PublicVetoApp.json`

Use registry and policy ABIs for detailed reads where needed.

## Demo flow

The intended public demo flow is:

1. User connects a fresh wallet
2. User calls `registerSelf` on `DemoCitizenGateway`
3. Registrar calls `confirmCitizenship`
4. User calls `mint` on `LLMToken`
5. User approves `DemoCitizenGateway` to spend `LLM`
6. User calls `stake`, `requestUnstake`, and `claimUnstake`
7. The election screen reads the latest Congress cycle from `CongressCandidateRegistry.latestCycleId()`
8. Eligible citizens can apply during nomination windows, vote during voting windows, and finalize ended cycles
9. After finalization, refresh `latestCycleId()` because the next recurring cycle may already have been created
10. The existing governance screens read the updated citizen status, voting power, and candidate eligibility from the main registries and policies
