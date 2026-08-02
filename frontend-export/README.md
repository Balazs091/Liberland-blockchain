# Frontend Export

This folder is the clean handoff package for the frontend.

## Contents

- `sepolia-demo.example.json`
  - schema for deployed contract addresses and seeded identifiers
- `ethereum-mainnet.example.json`
  - schema for the production address manifest and imported Congress continuity fields
- `sepolia-demo.json`
  - generated after a real demo deployment; ignored by Git so stale addresses are not committed
- `FRONTEND-HOWTO.md`
  - page-by-page guidance for the first demo frontend screens
- `FRONTEND-CHANGES.md`
  - migration notes for compiler, manifests, governance, lending, and the breaking cadastre update
- `abis/`
  - generated ABI artifacts for the source contract set; regenerate the whole directory after every contract change
    and do not mix files from different revisions
- `example-config.ts`
  - minimal example of how to wire the addresses into a React + `viem` + `wagmi` app

## Network

- network: `Sepolia`
- chain ID: `11155111`
- explorer: `https://sepolia.etherscan.io`

Production uses Ethereum mainnet (`chainId: 1`) and `deployments/ethereum-mainnet.json`. Reject any configuration whose `chainId` differs from the connected wallet chain.

## Important notes

- Do not use any file under `broadcast/`; it is generated Foundry transaction output
- After running `DeployDemo.s.sol`, copy `deployments/sepolia-demo.json` to `frontend-export/sepolia-demo.json`
- `sepolia-demo.example.json` is only a schema example; it is not a live deployment config
- The demo deployment adds seeded offices, a finance budget, referenda, a Congress election cycle, Senate seats, public veto state, a live `DemoCitizenGateway`, and a demo `LLM` merit token
- `LLMToken.decimals()` is `18` and `cap()` is `70_000_000e18`; multiply user-entered whole LLM by `1e18` for on-chain calls and divide on-chain base-unit balances by `1e18` for display
- The demo uses the production-like 30-day unstake welfare period and a fast 72-hour Congress election cycle
- The seeded demo election and all later demo elections end at `17:00 UTC`; production uses the same fixed endpoint with a 90 day recurring duration
- Late finalization advances the next full cycle to the next `17:00 UTC` boundary, so refresh or preview timestamps instead of deriving them from transaction time
- Finalizing the latest ended Congress election creates the next deterministic cycle automatically in the same transaction; a public transaction is still required because the EVM has no native scheduler
- Congress ballots are cycle-scoped. Recasting replaces the full ballot only in that cycle; no allocation carries forward.
- `stakingVault` is the canonical LLM custody address and `electorateRegistry` provides bounded constitutional snapshot totals
- live referendum/election creation verifies
  `VotingPowerPolicy.electorateRegistry() == ConstitutionKernel.getModule(ELECTORATE_REGISTRY)` and uses
  `ElectorateRegistry.snapshotAtCurrentEpoch(lastCompletedBlock)`; `snapshotAt` is the historical API for an
  already-pinned process
- identity/stake writes use bounded best-effort electorate callbacks and remain usable if the replaceable electorate
  fails; a missed callback or policy rebuild pauses new process creation until catch-up/rebuild has completed and
  one more block has begun
- Timing-only election cadence changes use the dedicated policy referendum; breaking election-policy replacements use the constitutional module path
- Router origins (`ReferendumApp`, `CongressElectionApp`, `SenateApp`, and `OfficeExecutor`) and the
  constitutional-review hook use the constitutional module threshold; only bounded apps without routing/review power
  use the ordinary module threshold
- Coordinated app/authority upgrades use `ActionTimelock.executeActions(actionIds)` so pointer activation is atomic
- the incumbent Senate cannot cancel or hold open the active referendum for its exact `SENATE_APP` replacement or
  cancel the resulting action; its queue hook is skipped only there. Constitutional review is skipped only for its
  own exact pointer replacement; all normal vote and queue checks still apply
- Official contribution rewards are LLM-only Finance-admin payouts from a referendum-approved budget and require a displayed evidence hash/URI; the Treasury never mints LLM
- Senate treasury suspensions and renewals require a published-document hash submitted by a current supporting seat holder; display `DisbursementSuspension.reasonHash` with the active deadline
- `DecisionApp`, `MinistryTreasury`, and lending are deployed by both manifests; production uses external USDC and
  Sepolia uses mock USDC
- elected/executive role authority follows `IdentityRegistry.activeWalletOf(personId)` after migration; historical
  records may still show the wallet used when the record was created
- candidacy is person-bound: keep the original application wallet as the durable ballot target, resolve withdrawal
  through the caller's current active-person link, and use the person's current active wallet for eligibility and
  seat assignment
- `EncumbranceRegistered` includes the external dossier `transactionId`; expired leaseholds cannot be subdivided or
  merged and must use the explicit closure workflow
- expose `recallUnrepresentedSeat(seatIndex)` only when the seated person's `activeWalletOf(personId)` is zero; it is
  a permissionless representation recovery and reverts while the seat remains represented
- For live onboarding demos, set `IDENTITY_ADMIN` to a wallet you control before deploying; that wallet becomes the registrar for `DemoCitizenGateway`
- Sepolia intentionally exports the same address for `identityApp` and `demoCitizenGateway`; the gateway inherits
  the standard `IdentityApp` workflows and is the only standing identity-registry writer
- An older live deployment does not acquire the fixed endpoint, stake snapshots, or wallet-continuity behavior;
  redeploy and replace its generated manifest
- Read `../docs/User-Journeys.md` before building role-gated screens; only Finance has an operational ministry office in v1

## Suggested first screens

- protocol status
  - `ConstitutionKernel`
  - `GovernanceRouter`
  - `ActionTimelock`
- identity and stake reads
  - `IdentityRegistry`
  - `StakeRegistry`
  - `LLMStakingVault`
  - `ElectorateRegistry`
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
  - use `currentPublicVetoSupportCount(measureId)` for pending support; stale ineligible receipts are excluded
- executive and treasury reads
  - `OfficeRegistry`
  - `BudgetEnvelopeRegistry`
  - `DecisionApp`
  - `OfficeExecutor`
  - `PayoutQueue`
  - `TreasuryVault`
  - call `syncPayoutState(requestId)` after timelock execution/cancellation/expiry; do not infer queue state solely
    from the timelock
- land and company reads
  - `LandPartyPolicy`
  - `LandRegistry`
  - `LandRegistryApp`
  - `CompanyRegistry`
  - `CompanyRegistryApp`
- lending reads
  - `USDCLendingPoolApp`
  - `StakeLienRegistry`
  - price / interest policies
  - use `repayFor(personId, amount)` when repayment must survive borrower-wallet revocation
  - use `currentDebtOf(personId)` for current debt; `totalBorrows()` and `borrowIndex()` are stored checkpoints
  - do not expose a protocol-reserve claim action; reserves are locked first-loss capital
  - expose `absorbBadDebt(personId)` only as permissionless loss reconciliation: it rejects while the smallest
    repayment that reduces scaled debt remains liquidatable from surplus stake; protected/retained floor stake is
    not recoverable collateral
  - ministry positions are keyed by office and pool; expose `poolSharesAt`/`withdrawFromPoolAt` for retired pools

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
- `LandPartyPolicy.json`
- `CompanyRegistryApp.json`
- `USDCLendingPoolApp.json`

Use registry and policy ABIs for detailed reads where needed. Do not assume the checked-in ABI directory matches an
unverified local change: run the export script from the exact source revision used by the manifest.

Both manifests expose `DecisionApp`, `MinistryTreasury`, the lending pool, lien registry, lending policy, and
`LandPartyPolicy` addresses.
Still feature-detect addresses and validate `chainId`; an old deployment manifest may predate the current scope.

## Demo flow

The intended public demo flow is:

1. User connects a fresh wallet
2. User calls `registerSelf` on `DemoCitizenGateway`
3. Registrar calls `confirmCitizenship`
4. User calls `mint` on `LLMToken` with base-unit amounts (whole LLM * `1e18`, standard 18 decimals)
5. User approves `DemoCitizenGateway` to spend the same whole-number `LLM` amount
6. User calls `stake` or the discrete `unstake` flow
7. The election screen reads the latest Congress cycle from `CongressCandidateRegistry.latestCycleId()`
8. Eligible citizens can apply during nomination windows, vote during voting windows, and finalize ended cycles
9. After finalization, refresh `latestCycleId()` because the next recurring cycle may already have been created
10. For the ballot UI, read `getBallotReceipt(cycleId, wallet)` and `getBallotAllocationAt(cycleId, wallet, index)`; discard it when moving to another cycle
11. After candidate wallet migration, retain the original application address as the stable ballot target and treat
    a still-linked current active wallet as an alias of that candidate
12. The existing governance screens read the updated citizen status, voting power, and candidate eligibility from the main registries and policies

## Refreshing the handoff package

After changing contracts or deploying a new demo:

On Linux/macOS:

```bash
cp deployments/sepolia-demo.json frontend-export/sepolia-demo.json
bash scripts/export-frontend-abis.sh
```

On Windows PowerShell:

```powershell
Copy-Item deployments/sepolia-demo.json frontend-export/sepolia-demo.json
& scripts/export-frontend-abis.ps1
```

Then validate that the generated manifest has `identityApp == demoCitizenGateway`, reject zero/unexpected addresses,
and smoke-test the write flows before handing the package to another team.

Create a zip only when you need to send the handoff folder outside Git:

```bash
zip -r frontend-export.zip frontend-export
```
