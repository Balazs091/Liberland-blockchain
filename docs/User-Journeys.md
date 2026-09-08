# User and Government Journeys

This document maps the current user-facing workflows to the contracts that implement them. It describes the
current local source; it is not proof of deployment or a restriction on future audited replacement modules.

## Production onboarding and citizen self-service

Production does not deploy the demo self-registration gateway. Onboarding is an Identity Office workflow:

1. The Identity Office admin onboards a new non-citizen with `IdentityApp.registerIdentity`; existing records cannot
   be overwritten. Metadata-only corrections use `correctMetadata`.
2. The admin proposes the first wallet with `IdentityApp.linkWallet`; that wallet calls `acceptInitialWallet`.
   `setCitizenship` only grants citizenship to a verified adult non-citizen without final suspension.
3. The person approves LLM to `LLMStakingVault` and calls `stakeFor(personId, amount)`. Eligibility follows the
   live citizen and voting-power policies.
4. The citizen can later call `requestWalletMigration(newWallet)`. The destination accepts the exact
   `walletMigrationId(personId)`; an officer approves that same nonce-bound ID, two days elapse, and anyone may
   finalize. Lost-key recovery instead needs an admin proposal, nonzero evidence hash, destination consent, a
   distinct officer and seven days; the old wallet can cancel and is not needed to finalize. Stake stays person-keyed. Any
   current Congress, Senate, President, Prime Minister, minister, or term-bound ministry-office authority follows
   the new active wallet; the revoked wallet immediately loses that authority.
5. A citizen may renounce citizenship without office consent. The wallet link remains active so the person can
   continue to manage and unstake their LLM.

Adverse civic changes and reversals of final suspension use `proposeCivicChange`, distinct-officer
 `approveCivicChange`, seven-day notice and `finalizeCivicChange`. The affected active wallet may file one
evidence-backed `appealCivicChange` during notice. Three of five independent reviewers resolve the exact case;
upholding preserves notice and adds a two-day post-ruling delay. An unanswered appeal is dismissed after 30 days.
Officers can withdraw cases except their own; subjects cannot delete an upheld case. Renunciation remains immediate,
but re-enrollment uses the civic procedure. See [Governance](Governance.md).

Sepolia instead uses one combined `DemoCitizenGateway`: it inherits the standard `IdentityApp` office, migration,
and renunciation workflows and adds public self-registration, registrar confirmation/rejection, and demo staking.
The manifest intentionally has `identityApp == demoCitizenGateway`, leaving only one standing identity-registry
writer. The gateway's public onboarding and demo-token minting assumptions are not production authorities.

Evidence: `test/apps/IdentityApp.t.sol`, `test/apps/DemoCitizenGateway.t.sol`, and
`test/policies/IdentityStakePolicies.t.sol`.

## Congress member and voter journey

- Anyone may create the next election cycle once the schedule permits.
- An eligible citizen applies during nomination. Incumbents are automatically entered and may withdraw.
- Candidacy is person-bound for the cycle. After wallet migration the original application remains the canonical
  record and durable ballot target, even if that address is later reassigned. The person cannot reapply. Withdrawal
  follows the caller's current active-person link; reads and a still-linked current active wallet can resolve to the
  same canonical candidate.
- An eligible voter submits one person-keyed signed-allocation ballot for that cycle. Recasting replaces the whole
  ballot and wallet migration cannot create a second ballot.
- There is no first-come candidate cap. Anyone may repeatedly call `finalizeElection` after voting closes;
  intermediate successful calls are progress, not finality. `finalizeElection(uint256)` defaults to 32 candidates;
  `finalizeElection(uint256,uint256)` accepts 1..32 for both insertion and heap-head consideration. Heap operations
  remain O(log N), and selected outcomes still require bounded revalidation before activation.
  Current eligibility is checked on selection and again before activation. Disqualified candidates do not re-enter
  that count; losing eligibility while counting can forfeit candidacy. Stake is not separately locked.
- After canonical Finalized status, anyone explicitly calls `createNextElectionCycle()` when the current policy and
  certified electorate permit. Failure to create a future cycle does not undo the completed election.
- A member may resign. Anyone may recall a member who has lost candidate eligibility, after which the next eligible
  runner-up fills the vacancy.
- If a seated person's identity has no active wallet, anyone may call
  `recallUnrepresentedSeat(seatIndex)`. It reverts while that person has an active wallet and is therefore a narrow
  permissionless representation-liveness recovery, not an administrative recall. Ordinary eligible runner-up
  succession is attempted after the seat is vacated.
- Congress members can propose eligible referenda, appoint or remove the Prime Minister, dismiss ministers, and use
  the bounded `DecisionApp` deployed by both network manifests.

Election endpoints remain anchored to 17:00 UTC in both manifests. Production uses seven seats and 90-day cycles;
Sepolia uses two seats and 3-day cycles.

Evidence: `test/apps/CongressElections.t.sol`, `test/apps/CabinetApp.t.sol`, `test/apps/Decisions.t.sol`, and
`test/scripts/DeployDemoTiming.t.sol`.

## Prime Minister, ministers, and clerks

- A strict majority of the current occupied Congress seats appoints the Prime Minister. The recorded winning tally
  is the later removal threshold.
- The Prime Minister appoints the four political ministers. The Prime Minister cannot dismiss them; Congress can,
  and a minister can resign.
- The Finance ministry is the only ministry currently wired to an operational office. Appointing the Finance
  Minister transfers that office's admin role to the minister and activates it. Dismissal or resignation
  deactivates it.
- The Finance Minister can appoint/revoke office clerks, operate ministry funds, configure each clerk's per-asset
  daily limit, and supply to or withdraw from the lending pool.
- Finance clerks can prepare and route policy-permitted treasury payouts and spend ministry balances only within
  the minister-set daily limit. A clerk may prepare a ministry decision, but only the current minister/admin can
  execute it.
- Foreign Affairs, Interior, and Justice appointments work politically, but v1 does not wire operational offices or
  domain applications for those ministries. Their future powers should be added through reviewed offices/apps and a
  replacement Cabinet app; the core does not prevent that extension.
- Ministry-office admin authority expires at the minister's term end even if nobody submits the cleanup transaction.
  Dismissal, resignation, expiry retirement, or replacement revokes the old admin and invalidates every clerk from
  that administration in O(1), so a successor cannot silently inherit old staff.

Evidence: `test/apps/CabinetApp.t.sol`, `test/apps/MinistryTreasury.t.sol`,
`test/apps/TreasuryAndOffices.t.sol`, and `test/apps/Decisions.t.sol`.

## Other office workflows

- An office admin controls clerks, admin transfer, metadata, and active status according to the live office policy.
  The Finance Ministry admin cannot self-transfer that political office; Cabinet succession controls it.
- A Land Registry clerk prepares and revises parcel drafts. Only the Land Registry admin/registrar can make a parcel
  live, revise/retire it, register a title, close an expired lease, finalize a signed transfer, perform a
  subdivision/merge/boundary
  adjustment, manage encumbrances, or accept/resolve a dispute.
- Structural parcel operations reject expired leaseholds. `EncumbranceRegistered` emits the supplied transaction ID
  so auditors and indexers can bind the compact on-chain fact to its external dossier.
- Title holders are stable person/company/office IDs rather than wallets. A transfer requires current seller and
  buyer EIP-712/EIP-1271 signatures, the current title version and nonce, a deadline, and registrar finalization.
  A currently authorized party signer may file a dispute; an accepted dispute or active encumbrance locks transfer
  and structural parcel changes. See `docs/Land-Cadastre.md` for the full frontend/legal data contract.
- Company Registry admins and clerks execute their workflows through the dedicated company app.
- A public company applicant may submit an incorporation request; the Company Registry office handles approval,
  rejection, status, shares, directors, and filings.
- A pending company cannot receive directors, share classes, shares, or filings. Those child-state operations become
  available only in `Active` or `ComplianceWarning` status, preventing rejected/resubmitted applications from
  inheriting hidden pre-approval state.
- Finance payouts require an enacted budget envelope, a policy-permitted request, a distinct current officer's approval, a queued typed action, the
  timelock, and the Treasury Vault's independent exact-commitment check.
- An authorized office can cancel a proposal. If already routed, `OfficeExecutor.cancelPayout` first cancels the
  timelock action, then records queue cancellation and releases the budget. Anyone may call
  `PayoutQueue.syncPayoutState` after execution, Senate cancellation, or expiry; executed state is verified against
  the vault address pinned in the action. Call synchronization on the original queue, not a replacement that has
  no request record. The budget ledger's permanent `isRequestExecuted(requestId)` marker prevents paid-ID replay
  across queue/vault replacements; it may already be true while queue state still awaits synchronization.

Evidence: `test/apps/LandRegistry.t.sol`, `test/apps/CompanyRegistry.t.sol`, and
`test/apps/TreasuryAndOffices.t.sol`.

## Contributors receiving LLM

1. The responsible operational office verifies the donated time, money, or other accepted contribution and publishes
   an evidence document.
2. The Finance Office admin proposes an LLM `ContributionReward` against an active referendum-approved reward budget,
   supplying the evidence hash and URI.
3. A distinct current Finance officer approves the exact proposal. After the one-day sensitive office delay from
   proposal, a permitted officer routes it into the normal treasury timelock; both appointments and the proposer's
   spending policy must still be valid.
4. Senate cancellation and temporary disbursement suspension remain available while the action is pending.
5. Execution transfers existing LLM from `TreasuryVault` to the contributor's wallet. The contributor may stake it
   separately after an identity record exists.

Finance clerks cannot propose contribution rewards; they may provide the second approval or route an approved admin proposal. Neither the Finance Office nor `TreasuryVault` can mint LLM; the
vault must first receive a pre-existing institutional reserve. The contracts preserve evidence provenance but do not
decide whether a contribution is genuine or what amount it merits.

Evidence: `test/apps/TreasuryAndOffices.t.sol`.

## Senate and Head of State

- Senate seat holders manage transfer, vacancy, and nominated succession through `SenateApp`. Every recipient or
  successor must be a current citizen; a holder who later renounces can still transfer or vacate the seat.
- The Senate's current app implements negative powers: queued-action cancellation, eligible referendum veto,
  sub-legal repeal, and temporary treasury-disbursement suspension. Creating or renewing a suspension requires its
  publisher to hold a currently supporting seat and supply the hash of a published reasoned objection; clients should
  display the referenced document with the deadline.
- Senators elect the President. The President appoints two Vice Presidents from eligible Senate seat holders;
  resignation follows the recorded succession order. A Senate seat cannot cast a new presidential ballot while the
  incumbent remains in term; voting starts only after vacancy or term expiry.
- A citizen may add or remove person-keyed Public Veto support for active Law-tier legislation. Before submission,
  support reads count only currently eligible persons; the next cast prunes stale receipts and emits
  `PublicVetoEligibilityExpired`. Two signatures initiate a typed ordinary repeal referendum; they do not cast
  referendum votes or repeal the law. After passage and the normal delay, execute the queued repeal. Failed or
  canceled rounds can be reset for fresh petition signatures.
- The current Senate and Congress apps expose no unrestricted execution function. Core routing authenticates the
  currently approved module and typed action, so a future constitutional design can replace those apps without an
  obsolete branch matrix blocking it.

Evidence: `test/apps/SenateAndPublicVeto.t.sol` and `test/apps/HeadOfStateApp.t.sol`.

## Lending users

- Any account may deposit USDC and receive pool shares; share owners may withdraw available liquidity.
- A currently eligible citizen with surplus active LLM may borrow within the live oracle/risk limits. The pool
  records a stake lien and releases it when debt is fully repaid (not proportionally on partial repayment). The citizenship retained-stake floor is fixed when the
  loan begins and persists until that owning pool explicitly closes the loan after full repayment or bad-debt
  absorption; a zero lien alone does not prove that the debt is closed.
- Anyone may repay for a person ID, which preserves recovery if the borrower's wallet is revoked or lost.
- Anyone may liquidate an unhealthy position under the policy limits. Irrecoverable collateral dust follows the
  explicit bad-debt path, with reserves acting as first-loss capital.
- Debt compounds through one RAY-scaled global borrow index. `currentDebtOf` previews pending interest; displayed
  `totalBorrows` and `borrowIndex` are stored checkpoints until someone calls `accrueInterest` or performs another
  state-changing pool operation.
- Read `StakeLienRegistry.loanBookOf(personId)` before switching pool UI. Existing debt remains with its originating
  pool until closure. Retired pools cannot add borrowing, and their health/liquidation/bad-debt collateral is capped
  at the remaining recorded lien as well as current surplus; newly unpledged stake does not increase old rights.
  They settle only their own borrowers through the lien registry, with seized plus remaining collateral bounded
  by the prior lien. The successor cannot take over that open position; no debt or LP-share import occurs.
- A minister's pool position is keyed by both office and pool. After governance replaces the live lending pool, the
  admin uses `poolSharesAt` and `withdrawFromPoolAt` to recover that office's shares from the retired pool.

Lending is wired by both deployment scripts. Mainnet uses the external `USDC_TOKEN` and the production parameter
manifest; Sepolia uses `MockUSDC`. Independent economic review and the final mainnet-fork rehearsal remain launch
work.

Evidence: `test/apps/LlmBackedUSDC.t.sol`.

## Upgrade and migration operations

- Core router and timelock pointers are immutable; the kernel has no replacement mechanism.
- Stable fact/custody modules are canonically replaceable under the constitutional double threshold, but require a
  reviewed migration because changing a pointer does not copy storage or move assets.
- Router origins (`ReferendumApp`, `CongressElectionApp`, `SenateApp`, and `OfficeExecutor`) and the
  constitutional-review hook are authorities and use the constitutional double threshold. Only bounded apps without
  routing or review power use the ordinary module threshold; policies and other authorities also use the double
  threshold.
- A new unclassified extension requires the double threshold to register and to replace later. It is no longer
  permanently frozen after registration.
- The dedicated Congress-election-policy referendum checks matching metadata but also requires the constitutional
  threshold. A full breaking replacement uses constitutional module governance; neither route has weaker approval.
- When an app and one or more authority pointers must move together, approve each typed action and call
  `ActionTimelock.executeActions(actionIds)`. The transaction updates all pointers or reverts all of them.
- Optional Senate and constitutional-review probes use a 100,000-gas cap and canonical exact-length ABI validation.
  Absent, reverting, over-budget or malformed hooks fail open, but caller underfunding reverts. Valid active records
  remain enforced. This technical protection does not eliminate governance deadlocks.
- The incumbent Senate cannot cancel or hold open the active referendum for its exact replacement, cannot cancel the
  resulting `SENATE_APP` action, and its cancellation hook is not consulted for that action. The
  constitutional-review hook cannot pause the exact action replacing `CONSTITUTIONAL_REVIEW`. All other referendum,
  threshold, delay, target, and execution checks still apply.

A review module can pause the Senate replacement while Senate blocks review replacement. An approved but defective
Referendum app, voting/policy dependency or unrecoverable electorate can disable future module-replacement voting. Preventing that under all
possible bytecode would require a permanent recovery authority or a second immutable voting system, both of which
would broaden the trust root. The project instead treats exact-address review, non-proxy bytecode verification,
fork rehearsal, interface/migration review, and coordinated atomic pointer activation as mandatory release work.
These routes provide no permanent second ballot. Batch members can still be executed
individually, so review intermediate states. Same-ledger LLM backing handoff, exact-successor Treasury handoff,
original-writer budget reconciliation, stable paid-request markers and retired-loan settlement have narrow continuity
checks; they do not copy
arbitrary storage. See [Upgrade and Liveness](Upgrade-And-Liveness.md).
