# Sepolia Demo Deployment

Use `scripts/DeployDemo.s.sol` when you want a Sepolia deployment with seeded read-state plus live demo onboarding and merit staking.

## What it seeds

- 4 demo citizens with active wallet links and stake
- 2 enacted laws
- 1 active referendum with votes already recorded
- 1 finalized defeated referendum
- 1 active Congress election cycle with 4 seeded candidates and starter ballots
- 2 occupied Senate seats
- 1 public veto support record
- 3 offices:
  - `Ministry of Finance`
  - `Identity Office`
  - `Land Registry Office`
- 1 finance clerk
- 1 active Ministry of Finance operations budget envelope
- 1 `LLM` demo merit token with public `mint(address,uint256)`
- 1 `DemoCitizenGateway` for:
  - self-registration from the frontend
  - registrar-confirmed citizenship
  - staking demo merits
  - requesting and claiming unstake after the 24 hour demo cooldown

## Important property

The seeding path uses an explicit demo-only authority contract during bootstrap, then switches the authority slots back to the production-like module wiring before bootstrap is disabled.

That means the final demo deployment does not keep a hidden mutable demo admin path through the kernel module registry.

## Fast demo timing

The demo deployment is intentionally faster than a production-style configuration:

- unstake cooldown: 24 hours
- Congress nomination window: 24 hours
- Congress voting window: 48 hours
- total Congress election cycle: 72 hours
- Congress voting start may be scheduled up to 72 hours ahead

The election contracts enforce one unfinalized cycle at a time. When anyone finalizes the latest ended cycle through `CongressElectionApp.finalizeElection(cycleId)`, the same transaction creates the next deterministic recurring cycle.

The EVM cannot call itself at a timestamp, so a public finalization transaction is still necessary. The next cycle uses the previous cycle's `votingEnd` as its anchor:

- `nominationStart = previousCycle.votingEnd`
- `votingStart = nominationStart + minimumNominationDuration()`
- `votingEnd = nominationStart + cycleDuration()`

For the demo policy, this means a cycle ending at 18:00 is followed by a cycle ending 72 hours later, also at 18:00.

## Optional environment variables

The demo script accepts these optional overrides in addition to the normal `SEPOLIA_RPC_URL`, `PRIVATE_KEY`, and `ETHERSCAN_API_KEY` values:

- `FINANCE_ADMIN`
- `IDENTITY_ADMIN`
- `LAND_ADMIN`
- `FINANCE_CLERK`
- `TREASURY_PREFUND_WEI`

If you do not set them:

- the deployer becomes the finance admin
- `0x...0B0b` becomes the identity office admin
- `0x...cafE` becomes the land registry office admin
- `0x...D00d` becomes the finance clerk
- treasury prefunding is skipped

## Live onboarding demo note

`DemoCitizenGateway` uses `IDENTITY_ADMIN` as the registrar wallet.

If you want to show live onboarding in the frontend, set `IDENTITY_ADMIN` to a wallet you actually control in MetaMask. That wallet will be able to confirm or reject citizenship after users self-register.

The live flow is:

1. User connects wallet and calls `registerSelf(...)`
2. Registrar wallet calls `confirmCitizenship(wallet, approved, adult)`
3. User mints demo `LLM`
4. User approves `DemoCitizenGateway`
5. User stakes or unstakes merits through `DemoCitizenGateway`
6. Existing eligibility-based systems then read the updated identity and stake state

## Congress election demo note

The demo deployment seeds Congress cycle `1` as an active voting cycle:

- nomination started 25 hours before deployment
- voting started 1 hour before deployment
- voting ends 47 hours after deployment
- the seeded cycle has a 72 hour total window
- 4 seeded citizens are accepted candidates
- starter ballots are recorded so the election page has immediate read-state

For election screens, use `CongressCandidateRegistry.latestCycleId()` as the main cycle pointer. `CongressElectionApp.currentCongressCycleId()` returns the active office term and remains `0` until an election is finalized.

After the seeded cycle ends, anyone can call `CongressElectionApp.finalizeElection(1)`. That resolves the Congress seats and creates cycle `2` with:

- `nominationStart = cycle1.votingEnd`
- `votingStart = cycle1.votingEnd + 24 hours`
- `votingEnd = cycle1.votingEnd + 72 hours`

Eligible live demo users can still join the election as voters after onboarding:

1. User self-registers through `DemoCitizenGateway`
2. Registrar confirms citizenship
3. User mints and stakes enough demo `LLM`
4. User calls `CongressElectionApp.castBallot(cycleId, candidates, allocations)` during the voting window

## How to add or change a demo-seeded election cycle

The seeded election is intentionally in demo bootstrap code, not the production election contracts.

To change it:

1. Edit `_seedCongressElection(...)` in `scripts/DeployDemo.s.sol`
2. Adjust the cycle timestamps, candidates, and starter ballots; the default fast-demo shape is 24 hours nomination plus 48 hours voting
3. Keep `CONGRESS_CANDIDATE_REGISTRY_AUTHORITY` pointed at `DemoSetupAuthority` during `_seedDemoState`
4. Keep `_switchToFinalDemoWiring()` switching `CONGRESS_CANDIDATE_REGISTRY_AUTHORITY` back to `CongressElectionApp`
5. Run `forge fmt`, `forge build`, and `forge test -vvv`
6. Redeploy the demo and copy the new `deployments/sepolia-demo.json` into `frontend-export/sepolia-demo.json`

The production election contracts do not need to change to seed demo state. A new deployment is required because the seeded cycle is written during bootstrap before bootstrap authority is permanently disabled.

## How to change recurring election cadence

The recurring cadence lives in `CongressElectionPolicy.cycleDuration()`. The demo deploy sets it to 72 hours; the production deploy script sets it to 90 days.

To change it after deployment:

1. Deploy a new `CongressElectionPolicy` with the desired `cycleDuration`
2. Keep the non-timing parameters equal to the current policy: candidate eligibility policy, voting power policy, seat count, runner-up count, max candidate count, and candidate bond requirement
3. Create a policy referendum using `ReferendumApp.createCitizenCongressElectionPolicyReferendum(...)` or `ReferendumApp.createCongressElectionPolicyReferendum(...)`
4. If the referendum passes, `ReferendumApp.finalizeReferendum(...)` queues a bounded `ModulePointerUpdate` for `CONGRESS_ELECTION_POLICY`
5. After the timelock delay, execute the queued action through `GovernanceRouter`
6. Future election cycles read the new policy from the kernel module pointer

This path changes the election timing policy without giving referenda arbitrary calldata execution.

Set `TREASURY_PREFUND_WEI` if you want live payout execution during the demo. Example:

```bash
export TREASURY_PREFUND_WEI=100000000000000000
```

## Commands

Load your environment:

```bash
set -a
source .env
set +a
```

Dry run:

```bash
forge script scripts/DeployDemo.s.sol:DeployDemo \
  --rpc-url "$SEPOLIA_RPC_URL" \
  -vvvv
```

Broadcast:

```bash
forge script scripts/DeployDemo.s.sol:DeployDemo \
  --rpc-url "$SEPOLIA_RPC_URL" \
  --broadcast \
  -vvvv
```

Verify:

```bash
forge script scripts/DeployDemo.s.sol:DeployDemo \
  --rpc-url "$SEPOLIA_RPC_URL" \
  --broadcast \
  --verify \
  --etherscan-api-key "$ETHERSCAN_API_KEY" \
  -vvvv
```

## Output

The script writes:

- `deployments/sepolia-demo.json`

Use that file for the frontend demo environment.

Useful fields inside it:

- `demoCitizenGateway`
- `llmToken`
- `congressCycleId`
- `congressNominationStart`
- `congressVotingStart`
- `congressVotingEnd`
- office IDs for finance, identity, and land
- the seeded finance budget ID
- the seeded office admin and finance clerk addresses
- the prefunded treasury amount, if any
- the minted gateway reserve backing seeded-user unstake claims
