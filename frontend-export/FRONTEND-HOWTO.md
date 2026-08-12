# Frontend Howto

This note is for the React frontend using `viem` and `wagmi`.

## First rule

Do not hardcode constitutional behavior in the UI if the contract already exposes it.

In particular:

- citizenship is decided by `contracts/policies/CitizenEligibilityPolicy.sol`
- voting power is decided by `contracts/policies/VotingPowerPolicy.sol`
- candidate eligibility is decided by `contracts/policies/CandidateEligibilityPolicy.sol`
- Congress election timing is exposed by `contracts/policies/CongressElectionPolicy.sol`
- unstake portion and welfare period are exposed by `contracts/policies/UnstakingPolicy.sol`
- land-party existence, acquisition eligibility, and current signers are decided by
  `contracts/policies/LandPartyPolicy.sol`

## Network and audit-build config

Use `frontend-export/sepolia-demo.json` for the live demo environment.

Important:

- `sepolia-demo.json` is generated from a real `DeployDemo.s.sol` broadcast and ignored by Git
- `sepolia-demo.example.json` is only a schema example and contains no usable deployment addresses
- after redeploying, copy `deployments/sepolia-demo.json` into `frontend-export/sepolia-demo.json`
- validate `config.chainId === walletChainId` before enabling writes
- parse `treasuryPrefundUsdc`, `treasuryPrefundLlm`, and `stakingBackingSurplus` with `BigInt(...)`; these token
  base-unit amounts are decimal strings so JSON parsing cannot silently lose precision
- require `config.identityApp === config.demoCitizenGateway` for the current Sepolia deployment. The gateway inherits
  `IdentityApp` and is the one standing identity-registry authority, not a second onboarding-only writer
- the client/audit UI must use the office-mediated `IdentityApp` lifecycle even when the Sepolia address also exposes
  demo-only `registerSelf` and `confirmCitizenship` selectors. Do not render those demo-only selectors in the audit
  build
- an older deployment does not gain the fixed boundary, historical vote weight, or person-bound role continuity;
  redeploy and replace its config

For production, use `deployments/ethereum-mainnet.json`; its schema is shown in `ethereum-mainnet.example.json`. `genesisCongressSeatCount` is `7`, while `genesisCongressContinuityCycleId` and `genesisCongressContinuityEnd` identify the imported live cycle and its absolute Unix endpoint. These are deployment metadata. Prefer on-chain registry reads for current state.

### Network-specific onboarding

The audit/client build has no public on-chain citizenship application transaction. The application and evidence
submission stay off-chain. The connected citizen wallet may display an application-status/pending-office-review
screen, but it must not manufacture a local `personId` or submit `registerSelf`.

On both the production deployment and the Sepolia audit UI, the Identity Office admin performs the on-chain writes:

1. Resolve `identityOfficeId()` from `IdentityApp`, then read the current admin from
   `officeRegistry.getOfficeRecord(identityOfficeId)`; do not hardcode the admin wallet.
2. The admin calls `identityApp.registerIdentity(personId, input)`, where `input` contains `metadataHash`,
   `metadataURI`, `verificationStatus`, `citizenshipStatus`, `ageClass`, `correctionFlag`, and `finalSuspension`.
3. The admin calls `identityApp.linkWallet(personId, wallet, WalletLinkStatus.Active)`.
4. Later citizenship-only changes use `identityApp.setCitizenship(personId, status)`.

Only the Identity Office admin may register identities, link wallets, or set citizenship. Identity Office clerks may
approve/cancel wallet migrations, but they cannot onboard a person. The public UI should poll
`identityRegistry.getWalletLink(wallet)` and `getWalletIdentityRecord(wallet)` after the off-chain application is
submitted.

Sepolia deployment metadata may expose `identityApp == demoCitizenGateway`. That is one contract inheriting the
standard office workflow, so call the inherited `IdentityApp` methods at `identityApp`. The extra self-registration
selectors are test/demo conveniences and are outside the client/audit UI contract.

Wallet migration is the citizen-facing on-chain identity flow:

- old active wallet: `requestWalletMigration(newWallet)`
- Identity Office admin or clerk: `approveWalletMigration(personId)`
- anyone after `migrationDelay()`: `finalizeWalletMigration(personId)`
- old wallet or Identity Office officer: `cancelWalletMigration(personId)`
- status read: `getWalletMigration(personId)`

The new wallet must be unlinked, and the person's stake remains attached to `personId` throughout migration.

### Deployment-only demo authority

`demoAuthority` is the address of a `DemoSetupAuthority` contract, not a wallet with its own private key. Its
immutable `owner()` is the Sepolia deployment wallet from `PRIVATE_KEY` (the current manifest's
`0x6319d5531045fdA2E91fe43f363eE80b8BCD7DDc`). The repository does not identify a human custodian beyond that
wallet; the deployment operator must document custody off-chain.

This contract was authorized only while seeded demo state was being written. Final deployment wiring replaces all
of its registry-authority module pointers, and the kernel, router, and office bootstrap authorities are zero. It
therefore gates no live frontend action and cannot seed more state on this deployment even if its owner signs. Do
not expose it as an admin or recovery control.

## Governance timing rule

Do not hardcode timelock delays in the UI.

- read `actionTimelock.minimumDelay(actionType)` for the currently deployed delay
- read `actionTimelock.getAction(actionId)` for `earliestExecutionTime`, `expiresAt`, `targetModuleAddress`, and final state
- use `actionTimelock.isActionExecutable(actionId)` for the execution button; it also detects a stale pinned target
- queued actions pin the target module address; if a module is replaced before execution, the queued action reverts instead of silently executing against the new module
- when a reviewed migration has separately approved app and authority-pointer actions, execute them atomically with `actionTimelock.executeActions(actionIds)` after every action reports executable
- treat a `State` module pointer update as a migration, not a software-only upgrade: require the reviewed record/asset migration manifest in the proposal UI and do not imply that the pointer action itself copies state
- the incumbent Senate cannot cancel or hold open the active referendum that replaces `SENATE_APP`, cannot cancel
  the resulting action, and the timelock skips that app's pending-cancellation hook only for the same action
- the constitutional-review pause hook is skipped only for the exact `CONSTITUTIONAL_REVIEW` replacement

## Page 1: Finances

### User-facing goal

Show the connected wallet's:

- liquid `LLM`
- active staked `LLM`
- welfare end time when applicable
- recent `LLM` and stake-related transactions

### Contracts

- `LLMToken`
- `IdentityApp`
- `DemoCitizenGateway`
- `IdentityRegistry`
- `StakeRegistry`
- `LLMStakingVault`
- `UnstakingPolicy`
- `CitizenEligibilityPolicy`
- `VotingPowerPolicy`

### Core reads

For the connected wallet `wallet`:

1. `identityRegistry.getWalletLink(wallet)`
2. `identityRegistry.getWalletIdentityRecord(wallet)`
3. `llmToken.decimals()`
4. `llmToken.balanceOf(wallet)`
5. If `personId != 0x0`:
   - `stakeRegistry.getStakeRecord(personId)`
   - `stakeRegistry.activeStakeOf(personId)`
   - `stakeRegistry.welfareUntilOf(personId)`
   - `stakeRegistry.isInWelfare(personId)`
   - `unstakingPolicy.unstakePortion(activeStake)`
   - `unstakingPolicy.welfarePeriod()`
   - `citizenEligibilityPolicy.isCitizenInGoodStanding(wallet)`
   - `votingPowerPolicy.votingPower(wallet)`

### Important UX note

The demo uses the same 30-day welfare policy as production. `unstake()` immediately releases one policy-defined discrete portion, reduces active stake, and starts welfare; there is no pending request/claim balance.

`LLMToken.decimals()` is `18` (standard ERC-20) and `cap()` is `70_000_000e18`. Multiply user-entered whole LLM by `1e18` before every on-chain call (mint, approve, stake) and divide base-unit balances by `1e18` for display. Stake thresholds, bonds, and quorums are likewise in base units (e.g. the 5000 LLM minimum stake is `5000e18`). Demo minting remains public but reverts at the hard cap.

### Writes

- office-mediated onboarding for the audit/client build:
  - `identityApp.registerIdentity(personId, input)` from the Identity Office admin
  - `identityApp.linkWallet(personId, wallet, WalletLinkStatus.Active)` from the Identity Office admin
  - `identityApp.setCitizenship(personId, status)` for later status-only changes
- citizen wallet migration:
  - `identityApp.requestWalletMigration(newWallet)`
  - `identityApp.approveWalletMigration(personId)` from an Identity Office admin or clerk
  - `identityApp.finalizeWalletMigration(personId)` after `migrationDelay()`
  - `identityApp.cancelWalletMigration(personId)` from the old wallet or an Identity Office officer
- mint demo merits:
  - `llmToken.mint(wallet, amount)`
- approve:
  - `llmToken.approve(demoCitizenGateway, amount)`
- stake:
  - `demoCitizenGateway.stake(amount)`
- unstake the policy-defined portion:
  - `demoCitizenGateway.unstake()`

The same Sepolia address may also expose demo-only `registerSelf` and `confirmCitizenship` functions. They are not
part of the audit/client onboarding flow. Do not treat the equal `identityApp` and `demoCitizenGateway` manifest
fields as separate contracts.

### Suggested balance card

- `Liquid LLM`
- `Staked LLM`
- `Voting Power`
- `Citizen In Good Standing`
- `Welfare Ends At` if welfare is active

### How to read welfare end

Read `stakeRegistry.welfareUntilOf(personId)`. Treat the citizen as in welfare while `block.timestamp < welfareUntil`.

### Transaction history

For v1, build the history from events:

- ERC-20:
  - `Transfer(address,address,uint256)` from `LLMToken`
  - `Approval(address,address,uint256)` if useful
- identity app/registry:
  - `WalletMigrationRequested`
  - `WalletMigrationApproved`
  - `WalletMigrationFinalized`
  - `IdentityRecordUpdated`
  - `WalletLinkUpdated`
- demo gateway, only for a separate explicit sandbox UI:
  - `DemoRegistrationSubmitted`
  - `DemoCitizenshipConfirmed`
  - `DemoMeritsStaked`
  - `DemoUnstakeExecuted`
- registry:
  - `StakeIncreased`
  - `UnstakeExecuted`

If you want a simple first pass, show token transfers and gateway events only.

## Page 2: Election

### User-facing goal

Allow eligible citizens to view the latest Congress election cycle, inspect candidates, and submit or replace a weighted prioritized ballot.

### Contracts

- `CongressElectionApp`
- `CongressCandidateRegistry`
- `CongressElectionPolicy`
- `CandidateEligibilityPolicy`
- `VotingPowerPolicy`
- `CitizenEligibilityPolicy`
- `IdentityRegistry`

### Core reads

1. `congressCandidateRegistry.latestCycleId()`
2. `congressCandidateRegistry.getCycle(cycleId)`
3. `congressCandidateRegistry.getCurrentOfficeTerm()`
4. `congressCandidateRegistry.currentCongressMembers()`
5. `congressElectionApp.currentCongressCycleId()`
6. `congressCandidateRegistry.getCycleCandidateCount(cycleId)`
7. For each index:
   - `congressCandidateRegistry.getCycleCandidateAt(cycleId, index)`
   - `congressCandidateRegistry.getCandidate(cycleId, candidate)`
8. For connected user:
   - `cycle.policy -> CongressElectionPolicy.isEligibleVoter(wallet)`
   - `CongressElectionPolicy.votingWeightAt(wallet, cycle.votingPowerSnapshotBlock)`
   - `candidateEligibilityPolicy.isEligibleCandidate(wallet)`
   - `votingPowerPolicy.votingPower(wallet)`
   - `congressCandidateRegistry.getBallotReceipt(cycleId, wallet)`
   - `congressCandidateRegistry.getBallotAllocationCount(cycleId, wallet)`
   - `congressCandidateRegistry.getBallotAllocationAt(cycleId, wallet, index)`

Important:

- `latestCycleId()` is the source for scheduled, nomination, voting, and recently finalized election-cycle screens
- `currentCongressCycleId()` returns the active Congress office term only; it stays `0` until an election is finalized and seats are activated
- a newly deployed demo can include a seeded active voting cycle; read its id from `sepolia-demo.json.congressCycleId` as a fallback, but still prefer `latestCycleId()` on-chain
- read the current election policy from `congressElectionApp.congressElectionPolicy()` when previewing a new cycle;
  for an existing cycle use its stored `policy` and `votingPowerSnapshotBlock`
- `currentCongressMembers()` is the preferred direct getter for the active Congress directory and resolves migrated
  members to their current active wallets
- live cycle creation uses the last completed block, requires the selected voting policy's
  `electorateRegistry()` to match the current kernel electorate, and calls
  `electorateRegistry.snapshotAtCurrentEpoch(votingPowerSnapshotBlock)`. If a citizen-policy rebuild or missed source
  callback makes the electorate unready, show maintenance state. Catch-up/rebuild completion in block N permits
  creation starting in block N+1; do not loop retries in the completion block
- `snapshotAt(blockNumber)` and `wasEligibleAt(...)` remain historical reads for a process that already pinned its
  policy/electorate; do not use `snapshotAt` as readiness certification for a new process
- an active voter needs current good standing, `electorateRegistry.wasEligibleAt(personId, snapshotBlock)`, and
  historical stake at that block; current stake alone is not the ballot weight
- demo-seeded processes are illustrative: `DemoSetupAuthority` pins them to its current transaction block, and a
  later checkpoint in that same block can change the historical read. Do not generalize this to live creation;
  production never deploys that authority and new live processes use the last completed block

### Calls and write actions

- preview the deterministic next cycle:
  - `congressElectionApp.previewNextElectionWindow()`
- create the deterministic next cycle when there is no unfinalized cycle:
  - `congressElectionApp.createNextElectionCycle()`
- create an explicit cycle window:
  - `congressElectionApp.createElectionCycle(nominationStart, votingStart, votingEnd)`
- apply as candidate:
  - `congressElectionApp.applyAsCandidate(cycleId, applicationHash, applicationURI)`
- withdraw candidacy:
  - `congressElectionApp.withdrawCandidacy(cycleId)`
- cast or replace ballot:
  - `congressElectionApp.castBallot(cycleId, candidates, allocations)`
- clear ballot:
  - `congressElectionApp.clearBallot(cycleId)`
- finalize an ended cycle:
  - `congressElectionApp.finalizeElection(cycleId)`
- resign an active Congress seat:
  - `congressElectionApp.resignSeat()`
- recover a seat whose person has no active wallet:
  - `congressElectionApp.recallUnrepresentedSeat(seatIndex)`

`recallUnrepresentedSeat` is permissionless but not discretionary. Show it only when the occupied seat has a nonzero
`holderPersonId` and `identityRegistry.activeWalletOf(holderPersonId) == address(0)`. The call reverts with
`CongressSeatStillRepresented` while an active wallet exists and otherwise uses the normal runner-up succession path.

### Cycle creation

Anyone can call `finalizeElection` after a cycle has ended. If the finalized cycle is the latest cycle, that same transaction also creates the next recurring election cycle.

The EVM cannot wake up by itself at a timestamp, so a public transaction is still required. The important contract guarantee is that the next cycle timing is deterministic and cannot drift because of late finalization.

The fast demo policy is a `72 hour` cycle:

- `24 hours` nomination
- `48 hours` voting
- `72 hours` total recurring cycle duration
- voting may be scheduled up to `72 hours` ahead
- all seeded and recurring voting endpoints are anchored to `17:00 UTC`

For recurring cycles after the first one, the contract enforces a full policy duration. Exact-boundary finalization uses the previous endpoint; late finalization advances to the next occurrence of the same UTC time-of-day:

- `nominationStart = previousCycle.votingEnd`, or the next matching daily UTC boundary after late finalization
- `votingStart = nominationStart + minimumNominationDuration()`
- `votingEnd = nominationStart + cycleDuration()`

Both network manifests currently anchor endpoints to `17:00 UTC`: demo cycles recur every 3 days and production cycles every 90 days. Do not calculate the next timestamps from the finalization transaction time. Use `previewNextElectionWindow()` or read the cycle created by `finalizeElection(...)`.

Use `previewNextElectionWindow()` to show these exact timestamps. Use `createNextElectionCycle()` for the initial/catch-up path when the latest cycle is finalized but finalization did not create a new one. Use `createElectionCycle(...)` only when the UI intentionally supplies the exact window; after a previous cycle exists, any non-matching recurring window reverts.

Before showing the create-cycle form, read:

- `congressCandidateRegistry.latestCycleId()`
- `congressCandidateRegistry.getCycle(latestCycleId)`
- `congressElectionPolicy.minimumNominationDuration()`
- `congressElectionPolicy.minimumVotingDuration()`
- `congressElectionPolicy.cycleDuration()`
- `congressElectionPolicy.maxScheduleLeadTime()`
- `congressElectionPolicy.seatCount()`
- `congressElectionPolicy.runnerUpCount()`
- `congressElectionPolicy.maxCandidateCount()`

Hide or disable create-cycle when the latest cycle exists and is not `Finalized`. Show finalization when `now >= votingEnd` and the cycle is not finalized; after a successful finalization, refresh `latestCycleId()` because the next cycle may already exist.

If no eligible candidates remain at finalization, the cycle still finalizes and the next cycle is scheduled when applicable. In that case active Congress can have zero occupied seats until a later cycle elects eligible members. This is intentional to avoid a permanent election deadlock.

For the first explicit cycle only, use timestamps where:

- `nominationStart >= now`
- `votingStart - nominationStart >= minimumNominationDuration`
- `votingEnd - votingStart >= minimumVotingDuration`
- `votingStart <= now + maxScheduleLeadTime`

For the default fast-demo button, use:

- `nominationStart = now`
- `votingStart = now + minimumNominationDuration`
- `votingEnd = votingStart + minimumVotingDuration`

### Changing election cadence by referendum

The recurring election cadence is changeable without redeploying `CongressElectionApp`.

1. Deploy a new `CongressElectionPolicy` with the desired timing values, such as `cycleDuration = 3 days` for demo or `90 days` for production.
2. Keep the non-timing parameters the same as the current policy: candidate eligibility policy, voting power policy, seat count, runner-up count, max candidate count, and candidate bond requirement.
3. Create a policy referendum with `createCitizenCongressElectionPolicyReferendum(...)` or `createCongressElectionPolicyReferendum(...)`.
4. If the referendum passes, finalization queues a bounded `ModulePointerUpdate` for `CONGRESS_ELECTION_POLICY`.
5. After the timelock executes, `congressElectionApp.congressElectionPolicy()` points at the new policy, and future cycles use the new `cycleDuration()`.

That dedicated route is intentionally timing-only and uses the ordinary policy vote. For a breaking replacement that changes seat count, eligibility, ballot rules, or other non-timing fields, use `createCitizenModuleGovernanceReferendum(...)` or `createCongressModuleGovernanceReferendum(...)` with target `CONGRESS_ELECTION_POLICY`; it uses the constitutional double threshold.

### Candidacy

Show candidacy actions only during the nomination window:

- `now >= cycle.nominationStart`
- `now < cycle.votingStart`
- `candidateEligibilityPolicy.isEligibleCandidate(wallet) == true`

`applicationHash` should be a stable hash of the off-chain application content. `applicationURI` should point to the same content.

### Ballot model

The current election system is not a simple single-choice vote.

- the frontend must collect an ordered / weighted ballot
- `candidates[]` and `allocations[]` are parallel arrays
- `castBallot` stores a ballot only for the supplied cycle; a later call replaces the previous full ballot in that cycle
- no allocation or vote total carries into a later cycle
- `clearBallot(cycleId)` clears only that cycle
- candidates must have status `Accepted`

Before submission:

- instantiate the policy stored in the cycle
- read `maxPositiveCandidates()`
- read `maxNegativeAllocationAt(wallet, cycle.votingPowerSnapshotBlock)`
- read `votingWeightAt(wallet, cycle.votingPowerSnapshotBlock)`

Validate in the UI before calling the contract.

Candidate registration is person-bound within a cycle:

- the original application wallet remains the canonical stored `CongressCandidateRecord.candidate` and a durable
  ballot target even if that address is later reassigned
- `getCandidate(cycleId, address)` resolves the same record from either that original address or the person's current
  active wallet
- wallet migration does not permit a second application
- withdrawal follows the caller's current active-person link, so a reassigned historical address cannot withdraw the
  former holder's candidacy
- finalization checks eligibility at the current active wallet and assigns any seat to that wallet
- a current active wallet can be a ballot alias while it still resolves to the candidate's person; store and display
  the canonical application address and reject a UI ballot containing two references to that candidate

For display:

- use `getBallotReceipt(cycleId, wallet)`, `getBallotAllocationCount(cycleId, wallet)`, and `getBallotAllocationAt(cycleId, wallet, index)`
- after `castBallot` or `clearBallot`, refresh the cycle receipt and candidate totals

### Suggested election page sections

- cycle status
  - nomination window
  - voting window
  - finalized / not finalized
- voter status
  - eligible or not
  - current voting weight
   - current cycle ballot summary
- candidate list
  - candidate wallet
  - person id
  - application hash / URI
  - current vote total
  - candidate status
- cycle actions
  - preview / create deterministic next cycle when the latest cycle is finalized
  - apply / withdraw during nomination
  - finalize after voting end, which also creates the next cycle for the latest election
- ballot builder
  - select candidates
  - assign signed allocations
  - preview total positive and negative allocation
  - submit / replace / clear

## Page 3: Offices, treasury, land, and company registry

### User-facing goal

Show office records, budget envelopes, payout requests, and the office-mediated land/company registries.

### Contracts

- `OfficeRegistry`
- `DecisionApp` (deployed by both manifests and the path for creating new offices/ministries after bootstrap)
- `OfficeExecutor`
- `BudgetEnvelopeRegistry`
- `PayoutQueue`
- `TreasuryVault`
- `LandRegistry`
- `LandPartyPolicy`
- `LandRegistryApp`
- `CompanyRegistry`
- `CompanyRegistryApp`

### Office reads

- `officeRegistry.getOfficeRecord(officeId)`
- `officeRegistry.roleOf(officeId, wallet)`
- `identityRegistry.activeWalletOf(officeRecord.adminPersonId)` for a term-bound political office; `admin` remains
  the appointment-time wallet and `adminAuthorizationEndsAt` is the hard authority expiry
- `officeExecutor.computeBudgetId(officeId, sequence)`

### Office admin writes

Call these on `OfficeExecutor`, not directly on `OfficeRegistry`:

- `officeExecutor.assignClerk(officeId, clerk)`
- `officeExecutor.revokeClerk(officeId, clerk)`
- `officeExecutor.transferOfficeAdmin(officeId, newAdmin)`
- `officeExecutor.renameOffice(officeId, newName)`
- `officeExecutor.setOfficeActive(officeId, active)`

`OfficeRecord.active` is mutable. Hide operational actions when an office is inactive or the term authorization has
expired. A new ministry administration invalidates prior clerks, so always re-read `roleOf` before signing.

### Decision notes

Both current deployment scripts wire `DecisionApp`; feature-detect the address so older manifests fail closed.

Use `DecisionApp` for bounded Congress and ministry decisions:

- Congress ERC20 transfer:
  - `createCongressTokenTransferDecision(...)`
  - source checks `isCongressDecisionSourceAuthorized(decisionId)` and calls `authorizeCongressDecisionSource(decisionId)` when needed
  - `supportCongressDecision(decisionId)`
  - `revokeCongressDecisionSupport(decisionId)`
  - `executeCongressDecision(decisionId)`
- Congress ministry funding:
  - `createCongressFundMinistryDecision(...)`
  - source authorizes the exact decision ID and approves `MinistryTreasury` for the token amount
  - Congress support/execute uses the same functions above
- Ministry ERC20 transfer:
  - `prepareMinistryTokenTransferDecision(...)`
  - `executeMinistryDecision(decisionId)`
- Ministry LLM transfer-and-stake:
  - `prepareMinistryLlmStakeDecision(...)`
  - `executeMinistryDecision(decisionId)`
- Ministry clerk add/remove:
  - `prepareMinistryClerkDecision(...)`
  - `executeMinistryDecision(decisionId)`

For Congress token transfers, the source approves `DecisionApp`. For Congress ministry funding, the source approves
`MinistryTreasury`. In both cases the source must also authorize the exact decision ID; a generic ERC20 allowance is
not decision consent. Creation auto-authorizes the source only when `source == msg.sender`, meaning the active
Congress member creating the decision is also the recorded source wallet. Every other source must call
`authorizeCongressDecisionSource(decisionId)` itself and may revoke with
`revokeCongressDecisionSource(decisionId)` before execution. For ministry decisions, the current contract model
treats the office admin wallet as the ministry signer/source wallet.

### Budget-approval referendum form

The canonical creation path is
`referendumApp.createCongressBudgetApprovalReferendum(proposal)`. Only a current Congress member can submit it.
`officeExecutor.requestBudgetApproval(...)` is a compatibility stub that always reverts with
`BudgetApprovalRequiresReferendum`; never build a form around it.

The `BudgetApprovalProposal` form fields are:

- `proposalMetadataHash`: commitment to the proposal metadata/evidence document
- `budgetId`: nonzero and not already registered; `officeExecutor.computeBudgetId(officeId, sequence)` is the
  deterministic helper
- `budgetLawTextHash`: nonzero commitment to the budget-law text
- `budget.officeId`: nonzero target office ID
- `budget.disbursementType`: nonzero `DisbursementType` (`Operations=1`, `Salary=2`, `Grant=3`, `Refund=4`,
  `CourtOrder=5`, `CapitalExpenditure=6`, `ContributionReward=7`)
- `budget.asset`: deployed ERC-20 contract currently allowed by `TreasurySpendingPolicy`; read the policy instead of
  hardcoding the token list
- `budget.allocatedAmount`: positive amount in the asset's smallest units
- `budget.startsAt` and `budget.endsAt`: budget validity interval, with `endsAt > startsAt`
- `startTime` and `endTime`: referendum voting interval; require `startTime >= latestBlock.timestamp` and
  `endTime - startTime >= referendumPolicy.minimumVotingDuration()`
- `adoptionDelay`: post-vote review delay
- `emergency`: Congress-only shortcut flag

For a normal budget referendum, default `adoptionDelay` from `referendumPolicy.standardAdoptionDelay()` (currently
7 days). The contract permits a Congress proposal up to `maximumAdoptionDelay()` (currently 7 days). For
`emergency=true`, the voting interval must be at least `emergencyVotingDuration()` (currently 3 days) and
`adoptionDelay` must be zero. Emergency does not skip the treasury action timelock: after a passing vote is
finalized, `TreasuryBudgetApproval` still observes `actionTimelock.minimumDelay(...)` (currently 1 day on Sepolia).

After creation, read `referendumRegistry.getBudgetApprovalDetails(referendumId)`. After the voting window, anyone
may call `finalizeReferendum(referendumId)`. If it passes, follow
`getReferendumResult(referendumId).enactmentActionId`, wait until the timelock reports it executable, and call
`actionTimelock.executeAction(actionId)`. Only that execution creates the budget envelope.

### Treasury notes

- budget approvals are referendum/timelock actions, not office-only actions
- contribution rewards use `DisbursementType.ContributionReward` (`7`) and must reference an active LLM-denominated budget
- only the Finance Office admin may propose or route a contribution reward; clerks cannot use this class
- require a nonzero `noteHash` and nonempty `noteURI`, and display the referenced contribution evidence before signing
- read the required token from `treasurySpendingPolicy.llmAsset()`; the reward source is existing `TreasuryVault` LLM, never a mint
- Senate suspension and renewal forms must hash the published reason document and call `suspendDisbursement(actionId, supportingSeatIndex, reasonHash)` or `renewDisbursementSuspension(actionId, supportingSeatIndex, reasonHash)` from the holder of that currently supporting seat; display the stored `reasonHash` with the suspension deadline
- Senate transfer and successor forms must resolve the recipient identity and require current `Citizen` status; a non-citizen recipient reverts with `SenateSeatRecipientNotCitizen`
- use `computeBudgetId(officeId, sequence)` for deterministic budget ids when the frontend proposes a new budget id
- payout routing revalidates the current office role and treasury spending policy at route time, so a stale proposed payout can fail if permissions or policy changed
- vault execution revalidates the exact active budget commitment; read `budgetEnvelopeRegistry.getBudgetCommitment(requestId)` when diagnosing a failed execution
- `officeExecutor.cancelPayout(officeId, requestId)` also cancels a routed timelock action before queue cancellation
  releases the budget; do not try to cancel only the queue record
- call permissionless `payoutQueue.syncPayoutState(requestId)` after the action executes, is Senate-canceled, or
  expires. Queue state may legitimately lag timelock state until synchronization
- synchronization verifies execution on `getAction(actionId).targetModuleAddress`, the pinned Treasury Vault, not a
  later live kernel pointer
- vault and ministry transfers also require the recipient to receive the exact amount; treat
  `UnexpectedDisbursementAmount`/`UnexpectedAssetAmount` as an unsupported-token failure
- use `actionTimelock.getAction(actionId)` to show when queued payouts become executable

### Land and company notes

- use the app contracts for writes because they enforce the relevant office role checks
- use the registries for read pages and event indexing
- land titles use `PartyRef(namespace,id)`, not wallet holders; show the stable party and resolve current signers from
  `LandPartyPolicy`
- clerks can call only `submitParcelDraft` and `updateParcelDraft`; registrar/admin controls all live record changes
- title transfer is a registrar-submitted dual-consent EIP-712 flow. Fetch the current title version and nonce, build
  an anchor whose lineage is that version, call `hashTitleTransferAuthorization`, collect both signatures, and
  submit them before the deadline
- refresh authorization immediately before submission because a person-wallet migration, company-director change,
  or office-administrator change invalidates the previous signer authority
- block/warn before removing a company's final director or finalizing dissolution while it still owns land; the
  current policy deliberately does not invent a receiver for a terminal signer-less company
- index `ParcelVersionRecorded` and `TitleVersionRecorded`; resolve their content/source hashes through the
  canonical off-chain schema. Do not treat an arbitrary JSON encoding or URI as the hashed legal record
- subdivision/merge accept at most `MAX_PARCELS_PER_OPERATION()` parcels and are atomic; boundary adjustment updates
  exactly two parcels atomically
- filed disputes do not lock a parcel until accepted; accepted disputes and active encumbrances block transfers and
  structural operations
- rejected company applications release their name / registration-number reservation, so a corrected application can reuse the identifiers
- pending, suspended, dissolving, dissolved, and rejected companies cannot mutate directors, share classes, shares,
  or filings; these child-state writes are limited to `Active` and `ComplianceWarning`
- leasehold land titles must have a future `leaseExpiresAt`, and expired leaseholds cannot be transferred,
  subdivided, or merged
- index the `transactionId` emitted by `EncumbranceRegistered` as the external dossier provenance for that fact
- the current app exposes `closeExpiredLease`, not general title closure; freehold and other non-lease titles cannot
  be administratively closed and reassigned around the dual-consent transfer workflow

Read `../docs/Land-Cadastre.md` before implementing cadastral writes. Fees, insurance/compensation, court orders,
co-ownership shares, and geometry validation are intentionally absent until reviewed modules and underlying rules
exist; do not simulate them as if the current contracts enforced them.

### Ministry pool replacement

- `ministryTreasury.poolSharesOf(officeId)` is only the office's balance in the current governed lending pool
- use `poolSharesAt(officeId, pool)` to enumerate a known retired-pool balance
- a current office admin may call `withdrawFromPoolAt(officeId, retiredPool, amount)` to recover it
- events and errors now include the pool address; key indexed state by `(officeId, pool)`, not by office alone

## Page 4: Senate, Public Veto, President, and lending deltas

For Public Veto screens, use `currentPublicVetoSupportCount(measureId)` and
`remainingRepealSupport(measureId)` while the measure is pending. `getPublicVetoRecord` returns a dynamically filtered
support count before repeal. The next `castPublicVeto` prunes ineligible receipts and emits
`PublicVetoEligibilityExpired`; after repeal, the stored final count is historical.

Disable `HeadOfStateApp.voteForPresident` while `PresidentRegistry.isPresidentInTerm()` is true. The contract rejects
early ballots rather than keeping a successor election open during an incumbent term.

For lending:

- client-demo scope: slides/read-only tier, not a live borrow/supply storyline. The current Sepolia pool has no
  liquidity, LP shares, borrows, or reserves, so a transactional screen would demonstrate setup rather than a real
  position. A compact read-only page may show the live parameters and zero state
- the deployed fixed oracle returns `2_000_000` USDC base units per whole LLM: `1 LLM = 2 USDC`
- current risk parameters are 30% max LTV, 40% liquidation threshold, 15% liquidation bonus, 15% reserve factor,
  1,000,000 USDC total borrow cap, and no per-person cap on the Sepolia demo
- `currentDebtOf(personId)` previews the current compounded debt
- `totalBorrows()` and `borrowIndex()` return stored checkpoints; refresh them after `accrueInterest()` or another
  mutating pool transaction and do not expect a time-only block to change them
- interest uses global RAY-scaled debt and the effective rate/reserve configuration for the elapsed interval
- display `StakeLienRegistry.retainedStakeFloorOf(personId)`; a nonzero lien keeps the floor captured when it began
- reject a risk-policy form unless `liquidationThreshold * (1 + liquidationBonus) <= 100%`
- `absorbBadDebt(personId)` is permissionless but rejects while surplus stake can cover the rounded seizure for the
  smallest repayment that actually reduces scaled debt. Protected/retained floor stake is not recoverable
  collateral; do not label such floor stake as liquidation capacity

## Minimal implementation order

1. Wallet connect
2. Demo config load from `sepolia-demo.json`
3. Finances read-only card
4. Off-chain application status plus Identity Office `registerIdentity` / `linkWallet` panel
5. Mint / approve / stake and discrete unstake / welfare flows
6. Wallet migration request / approve / finalize flow
7. Election read-only page
8. Cycle preview, finalization, and candidacy actions
9. Ballot builder and `castBallot`
10. Finalize ended cycles and show elected / runner-up results
11. Show zero-active-wallet seat recovery when its on-chain condition is met
12. Office and treasury read-only pages
13. Budget-approval referendum form and pass / timelock / execute status
14. Decision read/write pages for office admins, clerks, and Congress members
15. Land/company registry read-only pages
16. Public Veto and President election-state pages
17. Lending parameter/state page in the slides/read-only tier

## Practical notes

- use `citizenEligibilityPolicy.isCitizenInGoodStanding(wallet)` as the source of truth for citizen gating
- use `votingPowerPolicy.votingPower(wallet)` as the source of truth for political weight
- use `candidateEligibilityPolicy.isEligibleCandidate(wallet)` when building candidate-facing actions later
- do not infer person ids in the UI if the wallet is already linked; read them from `IdentityRegistry`
- for a stored process, use its pinned snapshot block and policy rather than current stake or the latest policy
- treat the canonical candidacy address and current active wallet as aliases of one person within a cycle
- do not hardcode office or finance rules into these pages
