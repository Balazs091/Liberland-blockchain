# Liberland EVM Architecture

Liberland EVM is a modular, constitution-aligned governance system on the EVM. It is not a generic DAO.

## Layers

- `contracts/core`: canonical module registry, origin router, and explicit action timelock
- `contracts/registries`: stable fact and accounting storage
- `contracts/policies`: replaceable rule evaluation over registry facts
- `contracts/apps`: bounded user and government workflows

Registries are the source of truth. Policies define rules. Apps coordinate typed workflows. The router and timelock are the non-repointable execution trust root.

## Implemented systems

- identity, citizenship, one-active-wallet enforcement, delayed wallet migration, and self-renunciation
- canonical LLM staking custody, stake accounting, discrete unstaking, welfare, voting power, and candidate eligibility
- checkpointed electorate aggregates for O(1) constitutional snapshots
- referenda, stake-weighted voting, constitutional double thresholds, adoption delays, and typed enactment
- Congress elections with deterministic cadence, incumbent auto-candidacy, cycle-scoped signed weighted ballots, finalization, and runner-up succession
- Senate queued-action cancellation, referendum veto, sub-legal repeal, documented temporary disbursement suspension, and bounded President-proxy participation
- Senate-elected President and succession, plus Congress/Prime-Minister Cabinet workflows
- treasury vault, referendum-approved budget envelopes, office permissions, and payout routing
- office-mediated land and company fact registries
- bounded Congress and ministry decisions for ERC20 transfers, ministry funding, clerk changes, transfer-and-stake, and office creation
- stake-backed USDC lending and an office-keyed ministry treasury; mock tokens, self-registration, and seeded demo
  state remain Sepolia-only

The full review scope is defined in `docs/Audit-Scope.md`, including mocks and demo-only trust surfaces that the
production script does not deploy.

## Network manifests

Network parameters are intentionally separate:

- `scripts/parameters/EthereumMainnetParameters.sol`: chain ID 1, seven Congress seats, 90-day recurring cycles
- `scripts/parameters/SepoliaDemoParameters.sol`: chain ID 11155111, two Congress seats, 3-day recurring cycles

Both anchor Congress election ends to `17:00 UTC` (18:00 fixed CET, not daylight-saving CEST). Production imports a configurable shortened continuity cycle from the pre-migration system. Later cycles are a full 90 days. Late finalization advances to the next occurrence of the established UTC boundary and therefore cannot permanently drift to the transaction hour.

The production deployment seeds all seven incumbents, Senate seats, the President, offices, identities, and stake before it permanently seals `InitialSetupAuthority` and disables every bootstrap authority. Genesis active stake is pulled from the deployer into `LLMStakingVault` before accounting is credited.

## Stake custody and electorate invariants

`LLMStakingVault` is the sole custody boundary for redeemable active political stake:

- stake increases require an existing identity and exact ERC20 receipt
- setup credits require already funded surplus
- unstaking reduces aggregate active stake before the vault transfers LLM
- `StakeRegistry.totalActiveStake()` must never exceed the vault's LLM balance
- liquidations transfer active stake between person IDs and do not release liquid LLM

`ElectorateRegistry` replaces population-sized snapshot loops:

- every electorate-relevant identity/stake mutation advances both a per-person revision and an aggregate source
  mutation counter
- identity and stake registries attempt a bounded-gas, best-effort synchronization of the affected person; failure
  defers electorate synchronization but never reverts or bricks the canonical identity/stake fact write
- unknown person IDs cannot be injected through permissionless synchronization
- citizen-policy replacement starts a new epoch
- anyone may rebuild a bounded identity-index range
- readiness requires every known identity and every source mutation to be synchronized, so a missed callback is
  visible and permissionless `syncPerson`/bounded `rebuild` can catch it up
- the registry checkpoints readiness, aggregate headcount, aggregate active stake, and each person's civic-roll
  eligibility by block
- `snapshotAt(blockNumber)` returns historical aggregates in O(1) for already-pinned processes and rejects blocks
  whose checkpointed readiness was incomplete
- `snapshotAtCurrentEpoch(blockNumber)` additionally certifies current source-revision synchronization and the
  current policy epoch; new process creation must use this API
- `wasEligibleAt(personId, blockNumber)` and `StakeRegistry.activeStakeAt(...)` provide the matching person-level
  historical inputs
- temporary post-unstake welfare suspends voting but does not remove a person from the constitutional civic roll

`VotingPowerPolicy` immutably pins its identity, stake, citizen-policy, and electorate registries. Live referendum
and election creation requires that policy's electorate to equal the current kernel electorate, then calls
`snapshotAtCurrentEpoch` for the last completed block. A policy rebuild or missed-callback catch-up completed in
block N therefore cannot authorize creation in block N, whose last completed block is N-1; creation resumes in block
N+1 using block N. Historical `snapshotAt`/`wasEligibleAt` reads remain available to already-created processes through
their pinned policy bundle even if the kernel later replaces its voting policy or electorate. Casting still requires
current good standing as well as eligibility and stake at the stored snapshot block. This prevents a later
eligibility or stake change from manufacturing weight while also preventing a currently suspended or otherwise
ineligible wallet from voting on old status.

## Governance and module evolution

Governance uses bounded action types and never unrestricted calldata execution.

- queued actions use deterministic identifiers, pin the target address, have a minimum delay and expiry, and cannot execute twice
- referendum, Congress, Senate, and office origins resolve to the current kernel-approved module and are separately authenticated by the router
- the non-repointable core validates supported typed actions and targets, but does not freeze today's political origin/action matrix
- current Congress and Senate apps expose no positive or unrestricted execution function; the current Senate remains limited to negative powers
- treasury assets leave only through the authorized ERC20 path and an exact active budget commitment
- independently approved actions can execute atomically as a batch, allowing an app pointer and its authority pointers to migrate without an inconsistent intermediate state

`ConstitutionKernel` assigns known IDs a module class:

- `Core`: router and timelock; never repointable
- `State`: registries and value/state-bearing apps; replaceable only through the constitutional double-threshold path and an externally reviewed state/custody migration
- `Policy` and `Authority`: replaceable only through the constitutional double-threshold path
- `Application`: known bounded workflow pointers; ordinary module-governance threshold
- `Undefined`: new extension IDs require the double threshold both to register and to replace later

State evolution requires a separately reviewed migration/deployment; a pointer vote does not copy storage or move custody. Brand-new modules use `ModuleRegistration`; every non-core replacement uses `ModulePointerUpdate`. Both pass through an exact-address referendum, the timelock, and bounded Senate cancellation, while state/policy/authority/extension targets use the constitutional double threshold. Application replacement deliberately relies on voters approving reviewed bytecode and a compatible state/migration plan. The router prevents unsupported or malformed action classes, but it does not assign supported types permanently to political branches. Current branch limits live in the current audited apps. This lets a future constitutional design replace a module without an obsolete core matrix blocking it. Treasury disbursements remain independently constrained by the active budget commitment even if an approved origin module changes.

Optional negative-power hooks are fail-open only when the Senate/review module is absent or interface-incompatible; otherwise active cancellation, suspension, veto, and review records remain enforced. This prevents a breaking-but-approved Senate interface from freezing all future governance. A replacement of `ReferendumApp` itself still requires exceptional care: approving defective bytecode can disable the only current referendum-creation path, and avoiding that absolutely would require another permanent trust root. Production procedure therefore forbids unreviewed upgradeable proxies and requires bytecode, interface, migration, and fork-rehearsal review before an exact address is proposed.

Two exact self-replacement liveness exceptions prevent an incumbent negative-power hook from making itself
irreplaceable:

- the incumbent Senate app cannot cancel or hold open the active referendum that proposes a `SENATE_APP`
  replacement, cannot directly cancel the resulting queued action, and the timelock does not consult that app's
  pending-cancellation hook for that exact action; and
- the constitutional-review pause hook is not consulted for the exact `CONSTITUTIONAL_REVIEW` pointer replacement.

These exceptions do not bypass the referendum threshold, queue delay, pinned target, or any other validation.

New workflows resolve their live policy/app pointers through the kernel. Once a referendum or Congress election is
created, it stores the exact policy bundle and voting-power snapshot block used for that process, so a later module
replacement cannot change an active vote's rules. Immutable references are reserved for stable registries, custody
assets, or the internally consistent dependencies of one immutable policy bundle.

Senate negative-control processes intentionally read the current `SenatePowersPolicy`, so a properly approved policy
replacement has immediate effect on their thresholds and durations. This keeps the negative-control implementation
stateless with respect to policy versions, but replacement proposals and frontends must disclose the impact on open
Senate processes.

Political authority is person-bound where continuity matters. Congress membership, Senate-seat authority, the
President, Prime Minister, ministers, and term-bound ministry-office administration follow the identity registry's
single active wallet after an approved migration. Stored historical records retain their original wallet for audit
provenance; clients resolve `activeWalletOf(personId)` for the current signer. Generic office appointments remain
wallet-bound unless the appointing app explicitly supplies a person ID.

Congress candidacy is also person-bound within a cycle. The original application wallet remains the canonical audit
record and durable ballot target, even if that address is later assigned to another person. A current active wallet
may also be used as a reference while it still resolves to the candidate's person. A migration does not create a
second candidacy; withdrawal follows the caller's current active-person link, finalization checks that person's
current active wallet, and any resulting seat is assigned to it. This separates stable ballot meaning from
active-person authorization.

If an occupied seat's person has no active wallet, anyone may call `recallUnrepresentedSeat(seatIndex)` to vacate it
and attempt ordinary runner-up succession. The call proves the zero-active-wallet condition on-chain and reverts
while the person remains represented; it is not an administrative or discretionary recall power.

Term-bound office authorization expires in read paths without a cleanup transaction. After
`adminAuthorizationEndsAt`, `roleOf`, `isOfficeClerk`, and returned clerk activity all fail closed. President-election
ballots likewise cannot be cast while a President remains in term; a new election begins only after vacancy or term
expiry.

Senate seat assignment, transfer, and succession require the acquiring identity to have current `Citizen` status.
A holder who later renounces can still transfer or vacate the proprietary seat; the current app does not silently
confiscate it or leave it without an exit path.

## Elections and referenda

Congress ballots exist only inside their submitted cycle. Recasting replaces the full cycle ballot; `clearBallot(cycleId)` removes it. No preference or vote total carries into a later cycle. Person-keyed cycle receipts prevent wallet migration from producing a second vote.

Ordinary voting is stake-proportional, without an equal base vote or merit cap. Constitutional amendments and
sensitive module changes require supporting voters to reach at least 50% of the snapshotted electorate and
supporting voting power to reach at least 65% of weighted votes actually cast. Constitutional aggregate electorate
values are snapshotted when the referendum is created. `StakeRegistry` also checkpoints each person's active stake.
Referenda and Congress elections use the last completed block at creation, require current-epoch electorate
certification, and pin the matching voting policy. Stake moved, unstaked, or liquidated after creation therefore
cannot be counted again by another person in the same process. Genesis-only setup uses its current block through its
exclusive setup authority. Deployment is still a multi-transaction operation; its safety comes from unauthorized
callers being unable to write the protected registries. Production keeps the Congress registry under
`InitialSetupAuthority` until both the seed term and continuity cycle exist, then hands authority to
`CongressElectionApp` before readiness checks and sealing. Demo setup overwrites supplied snapshot fields with the
actual setup transaction block. That demo-only shortcut is illustrative: another checkpoint written later in the
same block can change the value returned for that block. Production never deploys `DemoSetupAuthority`; after its
separately documented one-time genesis import, every newly created production process uses the same
last-completed-block/current-epoch checks as Sepolia live creation.

Public-veto support is person-keyed and bounded by the configured threshold. Before repeal, reads count only
currently eligible supporters and the next cast prunes stale receipts, emitting `PublicVetoEligibilityExpired`.
Once repeal executes, the record preserves its final support count and historical receipts.

Congress decisions are bound to the Congress term that prepared them. ERC20 transfer and ministry-funding decisions also require the source to authorize the exact decision ID; an allowance alone is not decision consent.

## Money, offices, and lending

System money is ERC20. LLM is governance/merit collateral; stablecoins are spending and lending assets. Native ETH is gas-only, and protocol contracts do not accept `msg.value`.

LLM has an exact 70,000,000-token hard cap at 18 decimals. Production consumes an external token whose `cap()` and
current supply are checked by the deployment script. Treasury custody has no mint or arbitrary token-call function:
issuance and spending remain separate, and official rewards draw only from LLM already deposited in the vault.

Treasury spending uses an explicit per-asset policy allowlist. Budget approvals are laws. Payouts revalidate current
office permissions and spending policy before routing. At execution, `TreasuryVault` independently matches the
request ID, budget ID, amount, and asset against the stable budget registry commitment and rejects tokens whose
recipient balance delta is not the exact requested amount.

An authorized office may cancel a proposed payout directly. For a routed payout, `OfficeExecutor` first cancels its
timelock action, then `PayoutQueue` records cancellation and releases the budget commitment. Permissionless
`syncPayoutState` can reconcile executed, Senate-canceled, or expired actions. Execution reconciliation verifies the
disbursement against the vault address pinned in the queued action, not a later live vault pointer.

`ContributionReward` is an LLM-only, Finance-admin-only disbursement class for verified donations of time, money, or
other accepted contributions. It requires a nonzero evidence hash and nonempty evidence URI, uses the sensitive queue
delay, and must draw against a referendum-approved contribution-reward budget. Verification standards remain an
operational policy represented by the evidence document rather than an on-chain adjudication system.

Every Senate suspension or renewal of a queued disbursement stores and emits a nonzero hash of its published
reasoned objection. The transaction sender must hold a seat that currently supports that suspension. The hash and
sender supply auditable provenance; the contracts do not interpret the document text or prove its availability.

`MinistryTreasury` keys balances, clerk limits, and daily spend by office ID, and pool shares by both office ID and
pool address. `poolSharesOf` and ordinary supply/withdraw calls use the currently governed pool.
`poolSharesAt`/`withdrawFromPoolAt` preserve access to an office's shares in a retired pool after a reviewed pool
replacement. A ministry cannot spend or redeem another office's accounting.

The lending pool resolves risk, interest, and oracle policies through the kernel. It represents every account's debt
as scaled debt under one RAY-denominated global borrow index, so elapsed interest compounds consistently across
borrowers. The effective borrow rate and reserve factor are checkpointed for each elapsed interval; a cash donation
or policy replacement cannot retroactively reprice time that already passed. `currentDebtOf` previews pending index
growth, while `totalBorrows` and `borrowIndex` expose stored values until `accrueInterest` or another state-changing
pool interaction checkpoints them.

Stake liens raise the required active-stake floor and slashing cannot bypass that floor. The citizenship floor is
snapshotted when a person's lien begins and cleared with the final lien, preventing a later policy increase from
retroactively freezing liquidation. Risk-policy construction also enforces
`liquidationThreshold * (1 + liquidationBonus) <= 100%`. Liquidation transfers active stake to the liquidator.
`absorbBadDebt` rejects a write-off only while the available surplus can liquidate the smallest asset repayment that
actually reduces scaled debt; protected/retained floor stake is deliberately excluded from recoverable collateral.
Eligible residual debt uses the explicit reserve/treasury backstop described in `docs/Lending-And-Treasury.md`. The
fixed launch oracle is intentionally suitable only for the governed launch price model, not as a market-price feed.

Pending companies cannot accumulate directors, share classes, shares, or filings. Those child-state mutations are
limited to `Active` or `ComplianceWarning` companies so rejection/resubmission cannot inherit hidden pre-approval
state.

## Deliberate constraints

- no hidden super-admin or emergency backdoor
- no unrestricted executor
- no sensitive queued action bypass
- no repeated queued-action execution
- no Congress unrestricted technical control
- no operational registry pointer swap without an externally reviewed migration
- no population-sized constitutional snapshot transaction
- no standing Congress ballots across cycles
- no production dependency on demo minting or onboarding powers

Role-by-role behavior and current operational gaps are mapped in `docs/User-Journeys.md`.

Known omissions and external-audit focus areas are listed in `docs/Audit-Scope.md`.
The detailed comparison with the supplied draft constitution is in `docs/Constitution-Alignment.md`.
