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
- `LLMToken.decimals()` is `18` (standard ERC-20); multiply user-entered whole LLM by `1e18` for on-chain calls and divide on-chain base-unit balances by `1e18` for display
- The fast demo timing uses a 24 hour unstake cooldown and a 72 hour Congress election cycle by policy
- Finalizing the latest ended Congress election creates the next deterministic cycle automatically in the same transaction; a public transaction is still required because the EVM has no native scheduler
- Congress ballots are standing preferences. A citizen's last ballot remains in force across future cycles for candidates that register again, until the citizen casts a replacement ballot or clears it.
- Future election cadence changes go through a bounded `CongressElectionPolicy` referendum and timelock update
- `DecisionApp` is included for the Sepolia demo decision screens, but it is outside the first production audit/deployment scope unless explicitly added
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
  - use `currentCongressMembers()` for the active member list
- senate and veto reads
  - `SenateApp`
  - `SenateSeatRegistry`
  - `SenatePowersPolicy`
  - `PresidentRegistry`
  - `PublicVetoApp`
- executive and treasury reads
  - `OfficeRegistry`
  - `BudgetEnvelopeRegistry`
  - `DecisionApp`
  - `OfficeExecutor`
  - `PayoutQueue`
  - `TreasuryVault`
- land and company reads
  - `LandRegistry`
  - `LandRegistryApp`
  - `CompanyRegistry`
  - `CompanyRegistryApp`
- lending reads, when a deployment wires Milestone 8 modules
  - `USDCLendingPoolApp`
  - `StakeLienRegistry`
  - price / interest policies

## ABI guidance

For most frontend work, prefer these as entrypoints:

- `ConstitutionKernel.json`
- `GovernanceRouter.json`
- `ActionTimelock.json`
- `ReferendumApp.json`
- `CongressElectionApp.json`
- `SenateApp.json`
- `PublicVetoApp.json`
- `PresidentRegistry.json`
- `DecisionApp.json`
- `OfficeExecutor.json`
- `LandRegistryApp.json`
- `CompanyRegistryApp.json`
- `USDCLendingPoolApp.json`

Use registry and policy ABIs for detailed reads where needed.

The current Sepolia demo config includes `DecisionApp`. Lending ABIs are included so the handoff package stays aligned with the repository code surface, but the current demo config does not include lending-pool addresses. Neither `DecisionApp` nor lending are part of the first production audit scope by default.

## Demo flow

The intended public demo flow is:

1. User connects a fresh wallet
2. User calls `registerSelf` on `DemoCitizenGateway`
3. Registrar calls `confirmCitizenship`
4. User calls `mint` on `LLMToken` with base-unit amounts (whole LLM * `1e18`, standard 18 decimals)
5. User approves `DemoCitizenGateway` to spend the same whole-number `LLM` amount
6. User calls `stake`, `requestUnstake`, and `claimUnstake`
7. The election screen reads the latest Congress cycle from `CongressCandidateRegistry.latestCycleId()`
8. Eligible citizens can apply during nomination windows, vote during voting windows, and finalize ended cycles
9. After finalization, refresh `latestCycleId()` because the next recurring cycle may already have been created
10. For the saved ballot UI, read `getStandingBallotReceipt` and `getStandingBallotAllocationAt`; this is the preference that carries into later cycles
11. The existing governance screens read the updated citizen status, voting power, and candidate eligibility from the main registries and policies

## Refreshing the handoff package

After deploying a new demo:

```bash
cp deployments/sepolia-demo.json frontend-export/sepolia-demo.json
for artifact in \
  ActionTimelock BudgetEnvelopeRegistry CandidateEligibilityPolicy CitizenEligibilityPolicy \
  CompanyRegistry CompanyRegistryApp CongressCandidateRegistry CongressElectionApp CongressElectionPolicy \
  ConstitutionKernel DecisionApp DemoCitizenGateway GovernanceRouter IdentityRegistry InitialSetupAuthority \
  FixedLlmUsdcPriceOraclePolicy KinkedInterestRatePolicy LandRegistry LandRegistryApp \
  LegislationRegistry LLMToken MockUSDC OfficeExecutor OfficeRegistry \
  PayoutQueue PresidentRegistry PublicVetoApp ReferendumApp ReferendumPolicy ReferendumRegistry SenateApp \
  SenatePowersPolicy SenateSeatRegistry StakeLienRegistry StakeRegistry TreasuryVault \
  USDCLendingPoolApp UnstakingPolicy VotingPowerPolicy
do
  cp "out/${artifact}.sol/${artifact}.json" frontend-export/abis/
done
```

Create a zip only when you need to send the handoff folder outside Git:

```bash
zip -r frontend-export.zip frontend-export
```
