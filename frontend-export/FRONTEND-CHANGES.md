# Frontend Changes

This handoff covers the Solidity `0.8.36`, network-manifest, staking/electorate, identity continuity, governance
liveness, treasury, lending, Congress-ballot, and land-cadastre changes.

## Required integration changes

1. Select configuration by connected chain:
   - Sepolia `11155111`: generated `sepolia-demo.json`
   - Ethereum mainnet `1`: generated `ethereum-mainnet.json`
2. Refuse writes when the wallet chain differs from the manifest `chainId`.
3. Add `stakingVault` and `electorateRegistry` to both address schemas.
4. Remove all standing-ballot calls and cached cross-cycle ballot preferences.
5. Replace request/claim unstake UX with the current discrete `unstake()` plus welfare-status UX.
6. Refresh `latestCycleId()` after finalization; the same transaction normally creates the next cycle.
7. Render returned Unix timestamps and never derive election endpoints from transaction time.
8. Replace the lending ABI: use `repayFor(personId, amount)` for third-party/revoked-wallet repayment and remove every `claimProtocolReserves` control.
9. Remove handling for `GovernanceRouter.UnauthorizedActionOrigin`; the router now authenticates the live origin module without freezing a political origin/action matrix.
10. Add `ActionTimelock.executeActions(actionIds)` for atomic execution of coordinated app and authority pointer changes.
11. Update Senate disbursement calls to `suspendDisbursement(actionId, supportingSeatIndex, reasonHash)` and `renewDisbursementSuspension(actionId, supportingSeatIndex, reasonHash)`; the caller must hold that currently supporting seat and both calls reject a zero hash.
12. Restrict Senate seat recipient and nominated-successor selectors to identities whose current `citizenshipStatus` is `Citizen`; surface `SenateSeatRecipientNotCitizen` before asking the holder to submit.
13. Add treasury `DisbursementType.ContributionReward` (numeric value `7`). It is LLM-only and Finance-admin-only; require both `noteHash` and `noteURI`, display the evidence document, and handle `ContributionRewardEvidenceRequired`. Read the canonical asset from `TreasurySpendingPolicy.llmAsset()`.
14. Add `IdentityRegistry.activeWalletOf(personId)`. Resolve the current signer through it for Congress, Senate,
    President, Prime Minister, minister, and term-bound ministry-office records; a stored record wallet is historical.
15. Read `votingPowerSnapshotBlock` and the pinned policy address from every Congress cycle and referendum. Display
    those rules for an active process instead of substituting the latest kernel policy. Senate negative-control
    processes are the exception: refresh threshold/deadline displays from the current `SenatePowersPolicy` because
    an approved policy replacement takes immediate effect there.
16. Update structs: `CongressSeatRecord.holderPersonId`; `OfficeRecord.adminPersonId` and
    `adminAuthorizationEndsAt`; referendum/cycle snapshot-policy fields. Replace the full generated ABI package.
17. Treat `UnexpectedDisbursementAmount`/`UnexpectedAssetAmount` as a terminal unsupported-token error: outbound
    transfers require the recipient to receive the exact requested amount.
18. Add the production `usdcToken`, `decisionApp`, `stakeLienRegistry`, lending policy/pool, and
    `ministryTreasury` manifest fields.
19. In Sepolia, require `identityApp == demoCitizenGateway`. Replace the gateway ABI: it now inherits the full
    `IdentityApp` surface and its constructor has nine arguments.
20. Add `VotingPowerPolicy.electorateRegistry()` and `ElectorateRegistry.snapshotAtCurrentEpoch(blockNumber)`.
    New process creation requires that immutable electorate pointer to match the current kernel electorate and
    current source revisions to be synchronized. Keep `snapshotAt`/`wasEligibleAt` for already-pinned historical
    processes. After rebuild/catch-up completion, wait until the next block before retrying creation.
21. Make candidacy person-bound in UI state. Preserve the original application wallet as the durable ballot target
    even if reassigned; withdrawal follows the caller's current active-person link, while eligibility/seat
    assignment follow that person's current active wallet. Prevent two references to the canonical candidate from
    appearing in one ballot. Add permissionless `recallUnrepresentedSeat(seatIndex)` only for an occupied seat whose
    person has no active wallet; it reverts while the person remains represented.
22. Add `PublicVetoApp.currentPublicVetoSupportCount(measureId)` and handle
    `PublicVetoEligibilityExpired`. Pending records exclude ineligible supporters; repealed records retain the final
    stored count.
23. Add `MinistryTreasury.poolSharesAt(officeId, pool)` and
    `withdrawFromPoolAt(officeId, pool, amount)`. Pool events/errors now include the pool address.
24. Add `OfficeExecutor.cancelPayout(officeId, requestId)` and `PayoutQueue.syncPayoutState(requestId)`. A queued
    payout is canceled at the timelock first; queue state can lag until sync, and executed sync uses the action's
    pinned vault address.
25. Treat `OfficeRegistry.roleOf`, `isOfficeClerk`, and returned clerk `active` as immediately expired when
    `adminAuthorizationEndsAt` passes; no cleanup transaction is required.
26. Disable presidential voting while `PresidentRegistry.isPresidentInTerm()` is true and handle
    `PresidentAlreadyInTerm`.
27. Disable company director/share/filing writes unless company status is `Active` or `ComplianceWarning`.
28. Replace the lending ABI: the pool constructor has six arguments, debt is globally index-scaled,
    `currentDebtOf` previews pending interest, and `totalBorrows`/`borrowIndex` remain stored until accrual.

29. Replace the complete land ABI and add the `landPartyPolicy` manifest field. Titles now use
    `PartyRef(namespace,id)`, transfers use dual EIP-712/EIP-1271 authorization and a title nonce, record writes use
    versioned `RecordAnchor` lineage, and subdivision/merge/boundary operations are atomic. The old wallet-holder and
    direct parcel/title mutation interfaces are incompatible.
30. Do not reuse old numeric `OfficeActionClass` values. The new land split is `PrepareLandRecords = 7`,
    `FinalizeLandRecords = 8`, and `ResolveLandDisputes = 9`; `ManageCompanyRegistry`, `ManageOfficeMetadata`, and
    `SetOfficeActive` are now `10`, `11`, and `12`. Prefer app capability checks over passing these policy enums from
    ordinary user screens.

## Cadastre migration

- Treat this as a breaking land redeployment, not an ABI-only frontend update.
- Read `LandPartyPolicy.personNamespace()`, `companyNamespace()`, and `officeNamespace()` instead of hardcoding
  namespace hashes in business logic.
- Use `LandRegistry` for records/events and `LandRegistryApp` for every write.
- Only clerks may prepare/update drafts; only the Land Registry admin/registrar may finalize live records,
  structural operations, encumbrances, and dispute status.
- Build transfers from `getTitle(titleId).versionHash`, `titleTransferNonce(titleId)`, a new anchor whose
  `lineageHash` is that version, a unique `transactionId`, and a deadline. Ask both sides to sign the digest returned
  by `hashTitleTransferAuthorization(request)`, then let the registrar submit both signatures.
- Resolve current authorized signers through the live land-party policy immediately before submission. A wallet
  migration, director change, or office-administrator change can invalidate an earlier signature by design.
- Do not calculate legal geometry validity, document authenticity, fees, insurance, or compensation in the browser.
  Display and verify the external canonical records whose hashes are committed on-chain.

The complete data and signature contract is in `../docs/Land-Cadastre.md`.

## Congress timing

| Network | Seats | Recurring cycle | Fixed endpoint |
| --- | ---: | ---: | --- |
| Sepolia demo | 2 | 3 days | 17:00 UTC |
| Ethereum mainnet | 7 | 90 days | 17:00 UTC |

Production cycle 1 is the finalized seed term and the imported live continuity cycle is normally cycle 2. The continuity end is an operator-supplied absolute timestamp. Later cycles are a full 90 days.

Late finalization moves the next nomination start to the next daily occurrence of the established UTC boundary, then applies the full cycle duration. This can create a short gap but cannot permanently drift.

Canonical reads:

- `CongressCandidateRegistry.latestCycleId()`
- `CongressCandidateRegistry.getCycle(cycleId)`
- `CongressCandidateRegistry.getCurrentOfficeTerm()`
- `CongressCandidateRegistry.currentCongressMembers()`
- `CongressElectionApp.previewNextElectionWindow()`
- `CongressElectionApp.congressElectionPolicy()`

## Ballot ABI and behavior

Ballots are now cycle-scoped:

- `castBallot(cycleId, candidates, allocations)` replaces the full ballot for that cycle
- `clearBallot(cycleId)` clears only that cycle
- read `getBallotReceipt(cycleId, wallet)`, `getBallotAllocationCount(cycleId, wallet)`, and `getBallotAllocationAt(cycleId, wallet, index)`
- no ballot or vote total carries into a later cycle
- wallet migration cannot create a second cycle ballot because the registry binds the receipt to the person ID

Candidacy is also person-bound. The original application address remains canonical storage and an exact durable
ballot target even if that address is later reassigned. `getCandidate(cycleId, address)` also resolves a person's
current active wallet while it remains linked. Migration does not permit a second application; withdrawal follows
the caller's current active-person link, finalization checks that person's active wallet, and ballot aliases resolve
to the canonical candidate. A ballot containing two references to that candidate reverts as a duplicate.

Removed ABI:

- `getStandingBallotReceipt`
- `getStandingBallotAllocationCount`
- `getStandingBallotAllocationAt`
- `purgeIneligibleStandingBallots`

## Staking and electorate

`LLMStakingVault` is now the custody contract for active stake. The manifest's `stakingVault` balance should be at least `StakeRegistry.totalActiveStake()`.

Demo write flow:

1. mint demo LLM
2. approve `DemoCitizenGateway`
3. call `stake(amount)`
4. call `unstake()` when eligible; it releases the policy-defined discrete portion immediately and starts welfare

There is no pending request/claim balance.

`ElectorateRegistry.snapshot()` returns constitutional headcount and voting power in O(1). Every relevant
identity/stake mutation advances per-person and aggregate source revisions. The source then makes a bounded
best-effort callback, so a broken/replaced electorate cannot revert the canonical fact write; a missed callback is
instead visible as `isReady() == false`. Show maintenance state and allow keepers/operators to call permissionless
`syncPerson(personId)` or bounded `rebuild(startIndex, maxCount)`.

For new live processes, the voting policy's immutable `electorateRegistry()` must equal the current kernel
electorate and `snapshotAtCurrentEpoch(lastCompletedBlock)` must certify the current policy epoch and source-revision
synchronization. A rebuild/catch-up completed in block N becomes creation-eligible in block N+1 because the
completion block must first become the last completed block. `snapshotAt(blockNumber)` and
`wasEligibleAt(personId, blockNumber)` remain historical APIs for processes that already pinned that
policy/electorate. `DemoSetupAuthority` instead overwrites seeded snapshot input with its current transaction block;
a later same-block checkpoint can still change that read, so the seed is illustrative and this authority is never
deployed in production. Voting still requires current good standing, so historical eligibility alone never enables
a suspended wallet.

## Dynamic module reads

New workflow creation resolves the live kernel pointer. Do not retain a deployment-time policy address as permanent
UI state. Refresh module addresses after module governance, but keep using the policy stored in an already-created
referendum or Congress cycle for that process's display and simulation.

State-bearing modules, policies, and authorities require the constitutional threshold. A state-bearing replacement additionally requires a reviewed storage/custody migration because the pointer action does not migrate state. Known bounded workflow apps use the ordinary module-governance threshold. Unclassified newly registered IDs require the constitutional threshold and can be repointed later; they are no longer permanently frozen. A replacement app is an exact-address, reviewed-bytecode governance decision; after execution, refresh every live app pointer.

The router authenticates the current kernel-approved module for each origin and validates supported typed actions and targets. It no longer hardcodes today's branch/action matrix. Current Congress and Senate apps still expose no positive or unrestricted execution method, and the current Senate routes cancellation only. A future audited replacement app can therefore change the constitutional workflow without replacing the core.

Some app replacements also require one or more authority-pointer actions. Once every separately approved action is ready, submit their IDs in dependency order to `actionTimelock.executeActions(actionIds)`. If any action is stale, vetoed, expired, or otherwise invalid, the entire transaction reverts and no pointer is partially activated. `isActionExecutable(actionId)` now also returns false when the queued target pointer has changed.

For liveness, the incumbent Senate cannot cancel or hold open the active referendum for its exact `SENATE_APP`
replacement, cannot cancel the resulting queued action, and the timelock does not query its pending-cancellation hook
for that one action. The constitutional-review pause hook is similarly skipped only for its exact own replacement.
Do not generalize these exceptions to other actions in the UI.

State-bearing module pointers are no longer permanently frozen. They require the constitutional double threshold and an audited migration; changing the pointer does not copy records or move assets. Upgrade UIs should label these proposals as migrations and display the reviewed migration manifest alongside the exact replacement address.

`TreasuryVault.executeDisbursement` now rejects any payload that does not exactly match an active `BudgetEnvelopeRegistry.getBudgetCommitment(requestId)` record. Frontends should surface an uncommitted/mismatched payout as invalid rather than retrying execution.

`currentCongressMembers()` returns each seated person's current active wallet. A migrated member's ballot under the
old wallet no longer counts in Cabinet/Decision tallies until the active wallet casts it. `isActiveCongressMember`
also follows the active wallet. For Senate/President/Executive records, resolve the stored person ID with
`activeWalletOf`; do not authorize from the record's historical wallet field alone.

`SenateTypes.DisbursementSuspension` now includes `reasonHash`. Resolve that hash to the published objection or renewal document and show it beside `suspendedUntil` and `renewalCount`. The chain verifies that the hash is nonzero and its publisher currently holds an actively supporting seat; document availability and content verification remain client/operational responsibilities.

## Congress decision source consent

Congress ERC20-transfer and ministry-funding decisions require the source to authorize the exact decision ID. An allowance alone is insufficient.

- show source authorization state with `isCongressDecisionSourceAuthorized(decisionId)`
- source calls `authorizeCongressDecisionSource(decisionId)` before execution
- source may call `revokeCongressDecisionSource(decisionId)` before execution
- refresh the decision after either transaction

## Lending ABI and behavior

- `borrow(amount)` requires the connected wallet to be a citizen in good standing at call time
- `repay(amount)` remains the active borrower's convenience path
- `repayFor(personId, amount)` lets any payer repay canonical person-keyed debt, including after wallet revocation
- `currentDebtOf(personId)` previews the compounded global borrow index at the current timestamp
- `totalBorrows()` and `borrowIndex()` expose stored checkpoints until `accrueInterest()` or another mutating pool
  operation updates them
- the effective rate and reserve factor are checkpointed by interval; a policy swap or cash donation does not
  retroactively reprice elapsed time
- `StakeLienRegistry.retainedStakeFloorOf(personId)` returns the citizenship floor captured when the current lien
  began; it resets to the live policy floor after the lien reaches zero
- risk-policy deployment must satisfy `liquidationThreshold * (1 + liquidationBonus) <= 100%`
- protocol reserves remain first-loss capital; `claimProtocolReserves` and `ProtocolReservesClaimed` no longer exist
- `absorbBadDebt(personId)` rejects only while surplus stake can fund the rounded seizure for the smallest repayment
  that actually reduces scaled debt. Protected/retained floor stake is not recoverable collateral; eligible
  residual debt is absorbed through reserves first and then supplier share value
- both current manifest schemas include lending; feature-detect nonzero addresses so old deployments fail closed

## Treasury, veto, and lifecycle reads

- A routed payout cancellation must use `OfficeExecutor.cancelPayout`; direct queue cancellation is not a frontend
  path. Refresh both timelock and queue state, then call permissionless `syncPayoutState` when necessary.
- Key ministry lending positions by both `officeId` and pool. `poolSharesOf` covers only the live governed pool;
  retired positions remain available through `poolSharesAt` and `withdrawFromPoolAt`.
- Pending Public Veto support is dynamic. Use `currentPublicVetoSupportCount`; the next cast removes stale eligibility
  receipts and emits `PublicVetoEligibilityExpired`.
- Office term expiry is effective in view functions immediately. Do not keep a cached clerk/admin role after the
  timestamp passes.
- Disable presidential vote submission while `PresidentRegistry.isPresidentInTerm()` is true.
- Pending companies cannot acquire directors, share classes, shares, or filings. Enable those writes only for
  `Active` or `ComplianceWarning`.

## Generated artifacts

See `../docs/User-Journeys.md` for the role matrix. In particular, only Finance has a wired operational ministry office in v1; the other three ministers are political roles until reviewed domain apps/offices are added.

ABIs are compiled from Solidity `0.8.36`. Replace the whole ABI package after contract changes; do not merge
individual old ABI files. A prior deployment does not acquire these behaviors—redeploy and replace its manifest.
Before handoff, confirm the generated ABI revision matches the deployment source and smoke-test the changed calls;
this document is not evidence that generation or deployment verification has already completed.
