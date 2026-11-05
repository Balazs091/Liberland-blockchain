# Frontend Export

This folder contains frontend ABIs, configuration examples and integration instructions.

The API guidance describes the current source. Before connecting a live client, confirm its deployed revision and
use the matching ABIs. Source or export changes do not upgrade deployed contracts. See
[deployment provenance](../docs/Sepolia-Demo-Deployment.md).

## Contents

- [sepolia-demo.example.json](sepolia-demo.example.json)
  - schema for deployed contract addresses and seeded identifiers
- [ethereum-mainnet.example.json](ethereum-mainnet.example.json)
  - schema for the production address manifest and imported Congress continuity fields
- `sepolia-demo.json`
  - generated after a real demo deployment; ignored by Git so stale addresses are not committed
- [Frontend howto](FRONTEND-HOWTO.md)
  - page-by-page guidance for the first demo frontend screens
- [Integration checklist](INTEGRATION-CHECKLIST.md)
  - current release requirements for configuration, consent, voting, counting, custody and signatures
- [abis/](abis/)
  - generated ABI artifacts for the source contract set; regenerate the whole directory after every contract change
    and do not mix files from different revisions; CI checks exact ABI/source parity
- [example-config.ts](example-config.ts)
  - minimal example of how to wire the addresses into a React + `viem` + `wagmi` app

## Deployment profiles

| Profile | Chain ID | Frontend boundary |
| --- | ---: | --- |
| [Production](../docs/Ethereum-Mainnet-Deployment.md) | `1` | Two-stage genesis; separately deployed fixed-supply Liberland Merit and canonical Ethereum USDC |
| [Original demo](../docs/Sepolia-Demo-Deployment.md) | `11155111` | Full demo with public-mint `LLMToken` and mock USDC |
| [Governed staging](../docs/Sepolia-Governed-Deployment.md) | `11155111` | Full synthetic governance with fixed-supply `LiberlandMerit`, mock USDC and a replaceable restriction controller |
| [Isolated foundation](../docs/Sepolia-Foundation-Deployment.md) | `11155111` | Token and synthetic restriction tests only; no voting, staking or lending |

Use the confirmed manifest for the selected profile. Reject a configuration whose `chainId` differs from the
connected wallet chain. Sepolia transactions can be checked on [Etherscan](https://sepolia.etherscan.io).
Synthetic restriction tests do not install the proposed legal membership procedures or their full rights-policy
integration.

## Integration rules

- Do not use any file under `broadcast/`; it is generated Foundry transaction output
- After running `DeployDemo.s.sol`, copy `deployments/sepolia-demo.json` to `frontend-export/sepolia-demo.json`
- `sepolia-demo.example.json` is only a schema example; it is not a live deployment config
- The demo deployment adds seeded offices, a finance budget, referenda, a Congress election cycle, Senate seats, public veto state, a live `DemoCitizenGateway`, and a demo `LLM` merit token
- `LLMToken.decimals()` is `18` and `cap()` is `70_000_000e18`; multiply user-entered whole LLM by `1e18` for on-chain calls and divide on-chain base-unit balances by `1e18` for display
- The demo uses the production-like 30-day unstake welfare period and a fast 72-hour Congress election cycle
- The seeded demo election and all later demo elections end at `17:00 UTC`; production uses the same fixed endpoint with a 90 day recurring duration
- Late next-cycle creation advances the next full cycle to the next `17:00 UTC` boundary, so refresh or preview timestamps instead of deriving them from transaction time
- Congress counting may need repeated transactions. `finalizeElection(uint256)` defaults to 32;
  `finalizeElection(uint256,uint256)` accepts workloads of 1..32. Final activation completes only its pinned cycle;
  explicitly call `createNextElectionCycle()` afterwards when current policy/electorate readiness permits
- Congress ballots are cycle-scoped. Recasting replaces the full ballot only in that cycle; no allocation carries forward.
- `stakingVault` is the canonical LLM custody address and `electorateRegistry` provides bounded constitutional snapshot totals
- live referendum/election creation verifies
  `VotingPowerPolicy.electorateRegistry() == ConstitutionKernel.getModule(ELECTORATE_REGISTRY)` and uses
  `ElectorateRegistry.snapshotAtCurrentEpoch(lastCompletedBlock)`; `snapshotAt` is the historical API for an
  already-pinned process
- identity/stake writes use bounded best-effort electorate callbacks and remain usable if the replaceable electorate
  fails; a missed callback or policy rebuild pauses new process creation until catch-up/rebuild has completed and
  one more block has begun
- Every election-policy replacement uses the constitutional double threshold, including the dedicated timing-policy route
- Router origins (`ReferendumApp`, `CongressElectionApp`, `SenateApp`, and `OfficeExecutor`) and the
  constitutional-review hook use the constitutional module threshold; only bounded apps without routing/review power
  use the ordinary module threshold
- Where `MODULE_UPGRADE_PLAN_REGISTRY` is installed, coordinated existing-module replacements use a published
  immutable plan and `ReferendumApp.createCitizenModuleBundleReferendum(proposal)` or
  `ReferendumApp.createCongressModuleBundleReferendum(proposal)`. The resulting single action changes all approved
  pointers together. Fresh production and governed staging install that registry.
  `ActionTimelock.executeActions(actionIds)` still groups separate actions whose members remain independently
  executable. See [upgrade and liveness](../docs/Upgrade-And-Liveness.md) for the dependency and migration limits
- the incumbent Senate cannot cancel or hold open the active referendum for its exact `SENATE_APP` replacement or
  cancel the resulting action; its queue hook is skipped only there. Constitutional review is skipped only for its
  own exact pointer replacement; all normal vote and queue checks still apply
- optional negative-power hooks have a 100,000-gas budget and canonical ABI requirement. Underfunded calls revert;
  reverting, over-budget or malformed probes are ignored. Mutual Senate/review blocking and broken referendum
  dependencies remain recovery limits; see [upgrade and liveness](../docs/Upgrade-And-Liveness.md)
- Official contribution rewards are LLM-only Finance-admin-proposed, distinct-officer-approved payouts from a referendum-approved budget and require a displayed evidence hash/URI; the Treasury never mints LLM
- Senate treasury suspensions and renewals require a published-document hash submitted by a current supporting seat holder; display `DisbursementSuspension.reasonHash` with the active deadline
- Two eligible citizens initiate a repeal referendum, not immediate repeal. Ordinary voting has an absolute stake
  quorum and no electorate-headcount quorum: two voters can still pass if their weight suffices and others abstain.
  This rule is the same on mainnet and Sepolia; show the vote and execution stages separately.
- Budget approvals use Law-tier referenda but create budget envelopes, not `LegislationRegistry` law records.
  Public repeal does not revoke an envelope. Do not offer a budget-repeal button; show budget expiry and the
  separate Senate cancellation/suspension controls for queued payouts.
- Production, the original demo and governed staging deploy `DecisionApp`, `MinistryTreasury` and lending.
  Production uses canonical Ethereum USDC; the two full Sepolia profiles use mock USDC
- elected/executive role authority follows `IdentityRegistry.activeWalletOf(personId)` after migration; historical
  records may still show the wallet used when the record was created
- candidacy is person-bound: keep the original application wallet as the durable ballot target, resolve withdrawal
  through the caller's current active-person link, and use the person's current active wallet for eligibility and
  seat assignment
- `EncumbranceRegistered` includes the external dossier `transactionId`; expired leaseholds cannot be subdivided or
  merged and must use the explicit closure workflow
- expose `recallUnrepresentedSeat(seatIndex)` only when the seated person's `activeWalletOf(personId)` is zero; it is
  a permissionless representation recovery and reverts while the seat remains represented
- The original demo reads its registrar from `IDENTITY_ADMIN`; governed staging assigns that role to tester 1.
  Use a wallet the tester controls
- Both full Sepolia profiles export the same address for `identityApp` and `demoCitizenGateway`; the gateway inherits
  the standard `IdentityApp` workflows and is the only standing identity-registry writer
- Read [user journeys](../docs/User-Journeys.md) before building role-gated screens; only Finance has an operational ministry office in v1

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
  - `ModuleUpgradePlanRegistry` and `ReferendumProposalValidator` where installed; verify their manifest bindings
- congress reads
  - `CongressElectionApp`
  - `CongressCandidateRegistry`
  - `CongressElectionPolicy`
  - `CongressRankingStore` (resolve the immutable address with `rankingStore()`)
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
  - call `syncPayoutState(requestId)` on the original queue after execution/cancellation/expiry; do not infer queue
    state solely from the timelock. `BudgetEnvelopeRegistry.isRequestExecuted(requestId)` is the stable paid-ID
    marker across queue/vault replacements, while the original vault receipt remains synchronization evidence
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
  - label rates as nominal APR compounded per second, not APY. `EmptyBookIndexReset` resets the debt unit only when
    no scaled debt remains; it neither forgives an outstanding loan nor changes cash, shares or reserves
  - do not expose a protocol-reserve claim action; reserves are locked first-loss capital
  - expose `absorbBadDebt(personId)` only as permissionless loss reconciliation: it rejects while the smallest
    repayment that reduces scaled debt remains liquidatable. Active pools use surplus stake; retired pools cap
    collateral at their remaining recorded lien. Protected/retained floors are not recoverable collateral
  - ministry positions are keyed by office and pool; expose `poolSharesAt`/`withdrawFromPoolAt` for retired pools
  - show `loanBookOf(personId)` and route existing-loan operations to that originating pool; a replacement cannot
    originate another loan for the same person until explicit closure. Debt/LP shares are not migrated

## ABI guidance

For most frontend work, prefer these as entrypoints:

- [ConstitutionKernel.json](abis/ConstitutionKernel.json)
- [GovernanceRouter.json](abis/GovernanceRouter.json)
- [ActionTimelock.json](abis/ActionTimelock.json)
- [ReferendumApp.json](abis/ReferendumApp.json)
- [CongressElectionApp.json](abis/CongressElectionApp.json)
- [SenateApp.json](abis/SenateApp.json)
- [PublicVetoApp.json](abis/PublicVetoApp.json)
- [PresidentRegistry.json](abis/PresidentRegistry.json)
- [DecisionApp.json](abis/DecisionApp.json)
- [OfficeExecutor.json](abis/OfficeExecutor.json)
- [LandRegistryApp.json](abis/LandRegistryApp.json)
- [LandPartyPolicy.json](abis/LandPartyPolicy.json)
- [CompanyRegistryApp.json](abis/CompanyRegistryApp.json)
- [USDCLendingPoolApp.json](abis/USDCLendingPoolApp.json)

Use registry and policy ABIs for detailed reads where needed. Do not assume the checked-in ABI directory matches an
unverified local change: run the export script from the exact source revision used by the manifest.

The full protocol manifests expose `DecisionApp`, `MinistryTreasury`, the lending pool, lien registry, lending
policies and `LandPartyPolicy`. The isolated foundation manifest covers its five test contracts only.
Validate every required address and `chainId` against the intended deployment; do not silently omit current modules.

## Original demo flow

The original public-mint demo follows these steps. Governed staging uses fixed-supply LLM; give testers an allocation
or transfer tokens to them instead of offering a mint action.

1. User connects a fresh wallet
2. User calls `registerSelf` on `DemoCitizenGateway`
3. Registrar calls `confirmCitizenship`
4. User calls `mint` on `LLMToken` with base-unit amounts (whole LLM * `1e18`, standard 18 decimals)
5. User approves `DemoCitizenGateway` to spend the same LLM amount in base units
6. User calls `stake` or the discrete `unstake` flow
7. The election screen reads the latest Congress cycle from `CongressCandidateRegistry.latestCycleId()`
8. Citizens may apply during nomination; voting also requires eligibility/stake at that cycle's stored snapshot.
   Newly onboarded users cannot vote in an earlier-snapshotted seed cycle merely because they are eligible now
9. Continue bounded finalization until canonical Finalized status, then explicitly create the next cycle once ready
10. For the ballot UI, read `getBallotReceipt(cycleId, wallet)` and `getBallotAllocationAt(cycleId, wallet, index)`; discard it when moving to another cycle
11. After candidate wallet migration, retain the original application address as the stable ballot target and treat
    a still-linked current active wallet as an alias of that candidate
12. The existing governance screens read the updated citizen status, voting power, and candidate eligibility from the main registries and policies

## Refreshing the handoff package

Regenerate ABIs after contract changes. Copy a manifest only after confirming the selected deployment's receipts
and runtime code. The commands below copy the original demo profile:

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

For that profile, validate that the manifest has `identityApp == demoCitizenGateway`, reject zero/unexpected addresses,
and smoke-test the write flows before handing the package to another team.

Create a zip only when you need to send the handoff folder outside Git:

```bash
zip -r frontend-export.zip frontend-export
```
