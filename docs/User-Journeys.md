# User and Government Journeys

This document maps the current user-facing workflows to the contracts that implement them. It describes the
deployed v1 behavior; it is not a constitutional restriction on future audited replacement modules.

## Production onboarding and citizen self-service

Production does not deploy the demo self-registration gateway. Onboarding is an Identity Office workflow:

1. The Identity Office admin creates the person record with `IdentityApp.registerIdentity`.
2. The admin links one active wallet with `IdentityApp.linkWallet` and grants the appropriate status with
   `IdentityApp.setCitizenship`.
3. The person approves LLM to `LLMStakingVault` and calls `stakeFor(personId, amount)`. Eligibility follows the
   live citizen and voting-power policies.
4. The citizen can later call `requestWalletMigration(newWallet)`. An Identity Office admin or clerk approves the
   request, the configured delay elapses, and anyone may finalize it. Stake remains keyed to the person ID. Any
   current Congress, Senate, President, Prime Minister, minister, or term-bound ministry-office authority follows
   the new active wallet; the revoked wallet immediately loses that authority.
5. A citizen may renounce citizenship without office consent. The wallet link remains active so the person can
   continue to manage and unstake their LLM.

Only the Identity Office admin creates identities, links wallets, or changes citizenship in v1. Identity clerks
approve or cancel wallet migrations. This split is intentional current policy, not a kernel limitation; replacing
the identity authority app can change it.

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
- Anyone may finalize after voting closes. The top eligible, non-negatively supported candidates take the bounded
  seats; runner-ups are stored for succession.
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
- Land and Company Registry admins and clerks execute their respective registry workflows through dedicated apps.
- A public company applicant may submit an incorporation request; the Company Registry office handles approval,
  rejection, status, shares, directors, and filings.
- A pending company cannot receive directors, share classes, shares, or filings. Those child-state operations become
  available only in `Active` or `ComplianceWarning` status, preventing rejected/resubmitted applications from
  inheriting hidden pre-approval state.
- Finance payouts require an enacted budget envelope, a policy-permitted request, a queued typed action, the
  timelock, and the Treasury Vault's independent exact-commitment check.
- An authorized office can cancel a proposal. If already routed, `OfficeExecutor.cancelPayout` first cancels the
  timelock action, then records queue cancellation and releases the budget. Anyone may call
  `PayoutQueue.syncPayoutState` after execution, Senate cancellation, or expiry; executed state is verified against
  the vault address pinned in the action.

Evidence: `test/apps/LandAndCompanyRegistries.t.sol` and `test/apps/TreasuryAndOffices.t.sol`.

## Contributors receiving LLM

1. The responsible operational office verifies the donated time, money, or other accepted contribution and publishes
   an evidence document.
2. The Finance Office admin proposes an LLM `ContributionReward` against an active referendum-approved reward budget,
   supplying the evidence hash and URI.
3. After the one-day sensitive office delay, the Finance admin routes the payout into the normal treasury timelock.
4. Senate cancellation and temporary disbursement suspension remain available while the action is pending.
5. Execution transfers existing LLM from `TreasuryVault` to the contributor's wallet. The contributor may stake it
   separately after an identity record exists.

Finance clerks cannot issue contribution rewards. Neither the Finance Office nor `TreasuryVault` can mint LLM; the
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
- A citizen may add or remove person-keyed Public Veto support for active Law-tier legislation. Before repeal,
  support reads count only currently eligible persons; the next cast prunes stale receipts and emits
  `PublicVetoEligibilityExpired`. A completed repeal preserves its final count.
- The current Senate and Congress apps expose no unrestricted execution function. Core routing authenticates the
  currently approved module and typed action, so a future constitutional design can replace those apps without an
  obsolete branch matrix blocking it.

Evidence: `test/apps/SenateAndPublicVeto.t.sol` and `test/apps/HeadOfStateApp.t.sol`.

## Lending users

- Any account may deposit USDC and receive pool shares; share owners may withdraw available liquidity.
- A currently eligible citizen with surplus active LLM may borrow within the live oracle/risk limits. The pool
  records a stake lien and releases it as debt is repaid. The citizenship retained-stake floor is fixed when the
  lien begins and is cleared with the final lien.
- Anyone may repay for a person ID, which preserves recovery if the borrower's wallet is revoked or lost.
- Anyone may liquidate an unhealthy position under the policy limits. Irrecoverable collateral dust follows the
  explicit bad-debt path, with reserves acting as first-loss capital.
- Debt compounds through one RAY-scaled global borrow index. `currentDebtOf` previews pending interest; displayed
  `totalBorrows` and `borrowIndex` are stored checkpoints until someone calls `accrueInterest` or performs another
  state-changing pool operation.
- A minister's pool position is keyed by both office and pool. After governance replaces the live lending pool, the
  admin uses `poolSharesAt` and `withdrawFromPoolAt` to recover that office's shares from the retired pool.

Lending is wired by both deployment scripts. Mainnet uses the external `USDC_TOKEN` and the production parameter
manifest; Sepolia uses `MockUSDC`. Independent economic review and the final mainnet-fork rehearsal remain launch
work.

Evidence: `test/apps/LlmBackedUSDC.t.sol`.

## Upgrade and migration operations

- Core router and timelock pointers are immutable.
- Stable fact/custody modules are canonically replaceable under the constitutional double threshold, but require a
  reviewed migration because changing a pointer does not copy storage or move assets.
- Known apps use the ordinary module threshold; policies and authorities use the constitutional double threshold.
- A new unclassified extension requires the double threshold to register and to replace later. It is no longer
  permanently frozen after registration.
- The dedicated Congress-election-policy referendum remains timing-only. A full breaking replacement, including
  seat-count or eligibility changes, uses the constitutional module-governance path.
- When an app and one or more authority pointers must move together, approve each typed action and call
  `ActionTimelock.executeActions(actionIds)`. The transaction updates all pointers or reverts all of them.
- Optional Senate and constitutional-review hooks cannot permanently freeze the queue merely by being absent or
  interface-incompatible. Active veto/suspension records from the current compatible Senate app remain enforced.
- The incumbent Senate cannot cancel or hold open the active referendum for its exact replacement, cannot cancel the
  resulting `SENATE_APP` action, and its cancellation hook is not consulted for that action. The
  constitutional-review hook cannot pause the exact action replacing `CONSTITUTIONAL_REVIEW`. All other referendum,
  threshold, delay, target, and execution checks still apply.

An approved but defective Referendum app can still disable future referendum creation. Preventing that under all
possible bytecode would require a permanent recovery authority or a second immutable voting system, both of which
would broaden the trust root. The project instead treats exact-address review, non-proxy bytecode verification,
fork rehearsal, interface/migration review, and coordinated atomic pointer activation as mandatory release work.
