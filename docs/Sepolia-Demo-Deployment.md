# Sepolia Demo Deployment

Use `scripts/DeployDemo.s.sol` when you want a Sepolia deployment with seeded read-state plus live demo onboarding and merit staking.

## What it seeds

- 4 demo citizens with active wallet links and stake
- 2 enacted laws
- 1 active referendum with votes already recorded
- 1 finalized defeated referendum
- 1 active Congress election cycle with 4 seeded candidates and starter standing ballots
- 2 occupied Senate seats
- 1 public veto support record
- 4 offices seeded at genesis:
  - `Ministry of Finance`
  - `Identity Office`
  - `Land Registry Office`
  - `Company Registry Office`
- 1 finance clerk
- 1 active Ministry of Finance operations budget envelope
- deployed land and company registries plus their office-authorized app workflows
- deployed `DecisionApp` for Congress and ministry ERC20 decisions, clerk decisions, LLM transfer-and-stake decisions, and Congress-approved creation of new offices and ministries

> **Adding offices after genesis.** The four offices above are seeded at bootstrap, but the office set is not frozen. A Congress majority can create additional offices at any time through `DecisionApp.createCongressRegisterOfficeDecision(...)` — the `OfficeRegistry` accepts `DecisionApp` (the kernel `DECISION_APP` pointer) as a registry authority, so no redeploy or bootstrap re-enable is needed. The new office is created with a chosen kind, name, and admin once the decision reaches Congress majority support and is executed.
- 1 `LLM` demo merit token with public `mint(address,uint256)` and the standard `decimals() == 18` (amounts are base units: 1 whole LLM = `1e18`)
- 1 `DemoCitizenGateway` for:
  - self-registration from the frontend
  - registrar-confirmed citizenship
  - staking demo merits
  - requesting and claiming unstake after the 24 hour demo cooldown

## Important property

The seeding path uses an explicit demo-only authority contract during bootstrap, then switches the authority slots back to the production-like module wiring before bootstrap is disabled.

That means the final demo deployment does not keep a hidden mutable demo admin path through the kernel module registry.

## Deployment transaction count

`DeployDemo.s.sol` batches bootstrap module-pointer writes through `ConstitutionKernel.bootstrapSetModules(...)` and is designed to stay below common public RPC free-tier limits around 100 submitted transactions. The script always sends one treasury prefund transaction that mints demo USDC covering the seeded finance budget; `TREASURY_PREFUND_USDC` / `TREASURY_PREFUND_LLM` add optional extra amounts (one more transaction when the LLM top-up is nonzero).

To re-check the count after changing the deploy script:

```bash
anvil --silent

PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
forge script scripts/DeployDemo.s.sol:DeployDemo \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast \
  -q

jq '.transactions | length' broadcast/DeployDemo.s.sol/31337/run-latest.json
```

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
- `COMPANY_REGISTRY_ADMIN`
- `FINANCE_CLERK`
- `TREASURY_PREFUND_USDC`
- `TREASURY_PREFUND_LLM`

If you do not set them:

- the deployer becomes the finance admin
- `0x...0B0b` becomes the identity office admin
- `0x...cafE` becomes the land registry office admin
- the deployer becomes the company registry office admin
- `0x...D00d` becomes the finance clerk
- the treasury is prefunded with exactly the seeded demo budget amount of mock USDC and no extra LLM

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

Frontend note: all demo `LLM` amounts are whole-number merit units. Do not multiply by `1e18`.

## Congress election demo note

The demo deployment seeds Congress cycle `1` as an active voting cycle:

- nomination started 25 hours before deployment
- voting started 1 hour before deployment
- voting ends 47 hours after deployment
- the seeded cycle has a 72 hour total window
- 4 seeded citizens are accepted candidates
- starter standing ballots are recorded so the election page has immediate read-state

For election screens, use `CongressCandidateRegistry.latestCycleId()` as the main cycle pointer. `CongressElectionApp.currentCongressCycleId()` returns the active office term and remains `0` until an election is finalized.

After the seeded cycle ends, anyone can call `CongressElectionApp.finalizeElection(1)`. That resolves the Congress seats and creates cycle `2` with:

- `nominationStart = cycle1.votingEnd`
- `votingStart = cycle1.votingEnd + 24 hours`
- `votingEnd = cycle1.votingEnd + 72 hours`
- the newly active Congress members automatically registered as cycle `2` candidates unless they withdraw during nomination

Eligible live demo users can still join the election as voters after onboarding:

1. User self-registers through `DemoCitizenGateway`
2. Registrar confirms citizenship
3. User mints and stakes enough demo `LLM`
4. User calls `CongressElectionApp.castBallot(cycleId, candidates, allocations)` during the voting window

`castBallot` stores the citizen's standing ballot. It remains in force across future cycles for candidates that register again, until the citizen replaces it with another `castBallot` call or clears it with `clearBallot`. For the saved-preference UI, read `getStandingBallotReceipt(...)` and `getStandingBallotAllocationAt(...)`; use cycle-specific ballot reads only for the current cycle receipt.

## How to add or change a demo-seeded election cycle

The seeded election is intentionally in demo bootstrap code, not the production election contracts.

To change it:

1. Edit `_seedCongressElection(...)` in `scripts/DeployDemo.s.sol`
2. Adjust the cycle timestamps, candidates, and starter ballots; the default fast-demo shape is 24 hours nomination plus 48 hours voting
3. Keep `CONGRESS_CANDIDATE_REGISTRY_AUTHORITY` pointed at `DemoSetupAuthority` during `_seedDemoState`
4. Keep `_switchToFinalDemoWiring()` switching `CONGRESS_CANDIDATE_REGISTRY_AUTHORITY` back to `CongressElectionApp`
5. Run `forge fmt`, `forge build`, and `forge test -vvv`
6. Redeploy the demo and copy the new `deployments/sepolia-demo.json` into `frontend-export/sepolia-demo.json`

The production election contracts do not need to change to seed demo state. A new deployment is required because the seeded cycle is written during bootstrap before bootstrap authority is permanently disabled. Deployment JSON files are generated outputs and are intentionally ignored by Git; commit only examples or documentation, not stale live addresses.

## Land and company registry demo note

The demo script deploys and wires `LandRegistry`, `LandRegistryApp`, `CompanyRegistry`, and `CompanyRegistryApp`, but it does not seed parcel or company records.

Use the configured land and company registry office admin wallets to create live demo records after deployment. Land disputes can be filed by any wallet through `LandRegistryApp.fileDispute(...)`, then accepted or resolved by the Land Registry Office. Incorporation submissions can be made by any wallet through `CompanyRegistryApp.submitIncorporation(...)`, then approved or rejected by the Company Registry Office.

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

The treasury is always prefunded with enough mock USDC to execute the seeded demo budget. Set `TREASURY_PREFUND_USDC` (6-decimal base units) or `TREASURY_PREFUND_LLM` (18-decimal base units) for extra demo money. Example:

```bash
export TREASURY_PREFUND_USDC=5000000000
export TREASURY_PREFUND_LLM=1000000000000000000000
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

Use that file for the frontend demo environment by copying it to `frontend-export/sepolia-demo.json`. Do not use `broadcast/` files as frontend config.

Useful fields inside it:

- `demoCitizenGateway`
- `decisionApp`
- `llmToken`
- `congressCycleId`
- `congressNominationStart`
- `congressVotingStart`
- `congressVotingEnd`
- `landRegistry`
- `landRegistryApp`
- `companyRegistry`
- `companyRegistryApp`
- office IDs for finance, identity, land, and company registry
- the seeded finance budget ID
- the seeded office admin and finance clerk addresses
- the prefunded treasury amount, if any
- the minted gateway reserve backing seeded-user unstake claims
