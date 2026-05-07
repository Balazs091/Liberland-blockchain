# Frontend Howto

This note is for the React frontend using `viem` and `wagmi`.

## First rule

Do not hardcode constitutional behavior in the UI if the contract already exposes it.

In particular:

- citizenship is decided by `contracts/policies/CitizenEligibilityPolicy.sol`
- voting power is decided by `contracts/policies/VotingPowerPolicy.sol`
- candidate eligibility is decided by `contracts/policies/CandidateEligibilityPolicy.sol`
- Congress election timing is exposed by `contracts/policies/CongressElectionPolicy.sol`
- unstake cooldown is exposed by `contracts/policies/UnstakingPolicy.sol`

## Demo config

Use `frontend-export/sepolia-demo.json` for the live demo environment.

Important:

- `sepolia-demo.json` is generated from a real `DeployDemo.s.sol` broadcast and ignored by Git
- `sepolia-demo.example.json` is only a schema example and contains no usable deployment addresses
- after redeploying, copy `deployments/sepolia-demo.json` into `frontend-export/sepolia-demo.json`

## Page 1: Finances

### User-facing goal

Show the connected wallet's:

- liquid `LLM`
- active staked `LLM`
- pending unstake `LLM`
- welfare / cooldown end time when applicable
- recent `LLM` and stake-related transactions

### Contracts

- `LLMToken`
- `DemoCitizenGateway`
- `IdentityRegistry`
- `StakeRegistry`
- `UnstakingPolicy`
- `CitizenEligibilityPolicy`
- `VotingPowerPolicy`

### Core reads

For the connected wallet `wallet`:

1. `identityRegistry.getWalletLink(wallet)`
2. `identityRegistry.getWalletIdentityRecord(wallet)`
3. `llmToken.balanceOf(wallet)`
4. If `personId != 0x0`:
   - `stakeRegistry.getStakeRecord(personId)`
   - `stakeRegistry.activeStakeOf(personId)`
   - `stakeRegistry.pendingUnstakeOf(personId)`
   - `stakeRegistry.claimableUnstake(personId)`
   - `stakeRegistry.hasActiveUnstakeCooldown(personId)`
   - `unstakingPolicy.cooldownDuration()`
   - `citizenEligibilityPolicy.isCitizenInGoodStanding(wallet)`
   - `votingPowerPolicy.votingPower(wallet)`

### Important UX note

The current demo deploy uses a `24 hour` unstake cooldown. Read it from `unstakingPolicy.cooldownDuration()`.

Changing this is a contract config change and requires a new demo deployment.

### Writes

- register:
  - `demoCitizenGateway.registerSelf(metadataHash, metadataURI)`
- registrar approval:
  - `demoCitizenGateway.confirmCitizenship(wallet, approved, adult)`
- mint demo merits:
  - `llmToken.mint(wallet, amount)`
- approve:
  - `llmToken.approve(demoCitizenGateway, amount)`
- stake:
  - `demoCitizenGateway.stake(amount)`
- start unstake:
  - `demoCitizenGateway.requestUnstake(amount)`
- claim unstake:
  - `demoCitizenGateway.claimUnstake()`

### Suggested balance card

- `Liquid LLM`
- `Staked LLM`
- `Pending Unstake`
- `Voting Power`
- `Citizen In Good Standing`
- `Cooldown Ends At` if cooldown is active

### How to compute cooldown end

Preferred:

- read `stakeRegistry.getStakeRecord(personId)` and use `cooldownEnd`

Fallback:

- if you only know when the unstake tx was submitted, use `unstakingPolicy.previewCooldownEnd(startTimestamp)`

### Transaction history

For v1, build the history from events:

- ERC-20:
  - `Transfer(address,address,uint256)` from `LLMToken`
  - `Approval(address,address,uint256)` if useful
- demo gateway:
  - `DemoRegistrationSubmitted`
  - `DemoCitizenshipConfirmed`
  - `DemoMeritsStaked`
  - `DemoUnstakeRequested`
  - `DemoUnstakeClaimed`
- registry:
  - `StakeIncreased`
  - `UnstakeRequested`
  - `UnstakeClaimed`

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
4. `congressElectionApp.currentCongressCycleId()`
5. `congressCandidateRegistry.getCycleCandidateCount(cycleId)`
6. For each index:
   - `congressCandidateRegistry.getCycleCandidateAt(cycleId, index)`
   - `congressCandidateRegistry.getCandidate(cycleId, candidate)`
7. For connected user:
   - `congressElectionPolicy.isEligibleVoter(wallet)`
   - `congressElectionPolicy.votingWeight(wallet)`
   - `candidateEligibilityPolicy.isEligibleCandidate(wallet)`
   - `votingPowerPolicy.votingPower(wallet)`
   - `congressCandidateRegistry.getBallotReceipt(cycleId, wallet)`
   - `congressCandidateRegistry.getBallotAllocationCount(cycleId, wallet)`
   - `congressCandidateRegistry.getBallotAllocationAt(cycleId, wallet, index)`

Important:

- `latestCycleId()` is the source for scheduled, nomination, voting, and recently finalized election-cycle screens
- `currentCongressCycleId()` returns the active Congress office term only; it stays `0` until an election is finalized and seats are activated
- a newly deployed demo can include a seeded active voting cycle; read its id from `sepolia-demo.json.congressCycleId` as a fallback, but still prefer `latestCycleId()` on-chain
- read the current election policy from `congressElectionApp.congressElectionPolicy()` before policy reads, because future referenda can replace the timing policy module

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

### Cycle creation

Anyone can call `finalizeElection` after a cycle has ended. If the finalized cycle is the latest cycle, that same transaction also creates the next recurring election cycle.

The EVM cannot wake up by itself at a timestamp, so a public transaction is still required. The important contract guarantee is that the next cycle timing is deterministic and cannot drift because of late finalization.

The fast demo policy is a `72 hour` cycle:

- `24 hours` nomination
- `48 hours` voting
- `72 hours` total recurring cycle duration
- voting may be scheduled up to `72 hours` ahead

For recurring cycles after the first one, the contract enforces:

- `nominationStart = previousCycle.votingEnd`
- `votingStart = nominationStart + minimumNominationDuration()`
- `votingEnd = nominationStart + cycleDuration()`

So if a demo cycle ends at 18:00, the next cycle ends 72 hours later at 18:00. In the production deploy script, `cycleDuration()` is 90 days.

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
- a later `castBallot` replaces the previous full ballot
- candidates must have status `Accepted`

Before submission:

- read `congressElectionPolicy.maxPositiveCandidates()`
- read `congressElectionPolicy.maxNegativeAllocation(wallet)`
- read `congressElectionPolicy.votingWeight(wallet)`

Validate in the UI before calling the contract.

### Suggested election page sections

- cycle status
  - nomination window
  - voting window
  - finalized / not finalized
- voter status
  - eligible or not
  - current voting weight
  - current saved ballot summary
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

## Minimal implementation order

1. Wallet connect
2. Demo config load from `sepolia-demo.json`
3. Finances read-only card
4. Register / approve / mint / approve / stake flow
5. Unstake / cooldown / claim flow
6. Election read-only page
7. Cycle preview, finalization, and candidacy actions
8. Ballot builder and `castBallot`
9. Finalize ended cycles and show elected / runner-up results

## Practical notes

- use `citizenEligibilityPolicy.isCitizenInGoodStanding(wallet)` as the source of truth for citizen gating
- use `votingPowerPolicy.votingPower(wallet)` as the source of truth for political weight
- use `candidateEligibilityPolicy.isEligibleCandidate(wallet)` when building candidate-facing actions later
- do not infer person ids in the UI if the wallet is already linked; read them from `IdentityRegistry`
- do not hardcode office or finance rules into these pages
