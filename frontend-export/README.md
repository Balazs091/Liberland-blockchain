# Frontend Export

This folder is the clean handoff package for the frontend.

## Contents

- `sepolia-demo.example.json`
  - schema for deployed contract addresses and seeded identifiers
- `sepolia-demo.json`
  - generated after a real demo deployment; ignored by Git so stale addresses are not committed
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

- Do not use any file under `broadcast/`; it is generated Foundry transaction output
- After running `DeployDemo.s.sol`, copy `deployments/sepolia-demo.json` to `frontend-export/sepolia-demo.json`
- `sepolia-demo.example.json` is only a schema example; it is not a live deployment config
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

## Refreshing the handoff package

After deploying a new demo:

```bash
cp deployments/sepolia-demo.json frontend-export/sepolia-demo.json
cp out/CongressElectionApp.sol/CongressElectionApp.json frontend-export/abis/
cp out/CongressElectionPolicy.sol/CongressElectionPolicy.json frontend-export/abis/
cp out/ReferendumApp.sol/ReferendumApp.json frontend-export/abis/
cp out/ReferendumRegistry.sol/ReferendumRegistry.json frontend-export/abis/
```

Create a zip only when you need to send the handoff folder outside Git:

```bash
zip -r frontend-export.zip frontend-export
```
