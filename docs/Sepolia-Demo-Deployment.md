# Sepolia Demo Deployment

Use `scripts/DeployDemo.s.sol` when you want a Sepolia deployment with seeded read-state plus live demo onboarding and merit staking.

The script is guarded to Sepolia chain ID `11155111` and reads its governance constants from `scripts/parameters/SepoliaDemoParameters.sol`.

The current [governance rules](Governance.md) cover identity consent and recovery,
public repeal, and Congress counting. Election finalization may now require repeated bounded transactions; an
intermediate successful transaction is not a finalized election. Use the regenerated frontend ABIs for a fresh
deployment. Earlier deployed demo addresses do not acquire these changes automatically.

## Civic review and officer readiness

Set `CIVIC_REVIEWER_0` through `CIVIC_REVIEWER_4` before running this script. Both networks require five nonzero,
pairwise-distinct public addresses, each different from the deployer and all four office admins. No reviewer private
key is needed for deployment. Verify disjoint real controllers, conflicts of interest, signing capability, notice
publication and evidence retention off-chain; different addresses alone are not sufficient independence.

The manifest exports `civicAppealReview` and `civicReviewer0` through `civicReviewer4`. Verify the kernel's
`CIVIC_APPEAL_AUTHORITY` pointer, the committee's `identityApp()` binding and all five `reviewerAt(i)` values.
Appoint operational, independently controlled Identity and Finance clerks through the normal authorized workflow
before starting two-officer cases or payments. A Finance clerk may approve or route a sensitive admin proposal;
no officer can provide both approvals. See [Governance](Governance.md) for ruling deadlines and rotation.

## What it seeds

- 4 demo citizens with active wallet links and stake
- 2 enacted laws
- 1 active referendum with votes already recorded
- 1 finalized defeated referendum
- 1 active Congress election cycle with 4 seeded candidates and starter cycle ballots
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
- 1 `LLM` demo merit token with public `mint(address,uint256)`, standard `decimals() == 18`, and the same
  `70_000_000e18` hard cap as production (amounts are base units: 1 whole LLM = `1e18`)
- 1 `DemoCitizenGateway` for:
  - self-registration from the frontend
  - registrar-confirmed citizenship
  - the standard Identity Office lifecycle inherited from `IdentityApp`, including wallet migration and renunciation
  - staking demo merits
  - executing the same discrete unstake and welfare flow as production

## Important property

The seeding path uses an explicit demo-only authority contract during bootstrap, then installs the final module
wiring before bootstrap is disabled. `DemoCitizenGateway` remains the intentional standing identity authority and
inherits `IdentityApp`, so `identityApp` and `demoCitizenGateway` in the output manifest are the same address.
Seeded active stake is fully backed by LLM held in `LLMStakingVault`.

That means the final demo deployment does not keep a hidden mutable demo admin path through the kernel module registry.
It does intentionally keep the documented public demo registration and minting surfaces; neither is deployed by the
production script.

## Deployment rehearsal

`DeployDemo.s.sol` is transaction-heavy. Rehearse it locally with the Sepolia chain ID before relying on a rate-limited public RPC. The script always sends one treasury prefund transaction that mints demo USDC covering the seeded finance budget; `TREASURY_PREFUND_USDC` and `TREASURY_PREFUND_LLM` can add optional prefunding.

Configure the required `COMPANY_REGISTRY_ADMIN` and all five `CIVIC_REVIEWER_*` public addresses first, using
independent test signers for an interactive rehearsal. To re-check the count after changing the deploy script:

```bash
anvil --silent --chain-id 11155111

PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
forge script scripts/DeployDemo.s.sol:DeployDemo \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast --slow --gas-estimate-multiplier 200 \
  -q

jq '.transactions | length' broadcast/DeployDemo.s.sol/11155111/run-latest.json
```

## Fast demo timing

The demo deployment is intentionally faster than the production configuration:

- unstake/welfare period: 30 days (same as production)
- Congress nomination window: 24 hours
- Congress voting window: 48 hours
- total Congress election cycle: 72 hours
- Congress voting start may be scheduled up to 72 hours ahead

The seeded election and every recurring demo election end at exactly `17:00 UTC`. The seed calculation leaves between 24 and 48 hours of active voting time, depending on the deployment hour. Late next-cycle creation advances to the next `17:00 UTC` boundary, so future cycles cannot drift to the transaction time.

The election contracts enforce one unfinalized cycle at a time. Finalization advances only the ended cycle;
after it reaches canonical Finalized status, anyone explicitly calls `createNextElectionCycle()` when the current
policy and certified electorate permit. A failed next-cycle creation cannot undo the completed result.

The EVM cannot call itself at a timestamp, so counting and next-cycle creation require public transactions. If
creation is on the prior boundary, the next cycle uses that `votingEnd` as its anchor. A later creation advances
to the next occurrence of the same UTC time-of-day. Always preview immediately before creation:

- `nominationStart = previousCycle.votingEnd`, or the next matching UTC daily boundary after late next-cycle creation
- `votingStart = nominationStart + minimumNominationDuration()`
- `votingEnd = nominationStart + cycleDuration()`

For the demo policy, this means a cycle ending at 17:00 UTC is followed by a cycle ending 72 hours later, also at 17:00 UTC.

## Office configuration and optional environment variables

`COMPANY_REGISTRY_ADMIN` is required. Sepolia office-admin addresses may be shared, including the deployer;
roles and appointment changes remain scoped to each office. The Finance clerk must differ from the Finance admin,
and all five civic reviewers must still be distinct from each other, the deployer and every office admin. Shared
admins concentrate control and do not bypass two-officer approvals. The following other values remain optional in addition to `SEPOLIA_RPC_URL`,
`PRIVATE_KEY`, and `ETHERSCAN_API_KEY`:

- `FINANCE_ADMIN`
- `IDENTITY_ADMIN`
- `LAND_ADMIN`
- `FINANCE_CLERK`
- `TREASURY_PREFUND_USDC`
- `TREASURY_PREFUND_LLM`

If you do not set them:

- the deployer becomes the finance admin
- `0x...0B0b` becomes the identity office admin
- `0x...cafE` becomes the land registry office admin
- the company registry admin is the explicitly supplied nonzero address
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
5. User stakes or executes a discrete unstake through `DemoCitizenGateway`
6. Existing eligibility-based systems then read the updated identity and stake state

The same deployed gateway also exposes the standard `IdentityApp` office functions. Frontends should use the
`demoCitizenGateway` ABI/address as the write entrypoint and treat the equal `identityApp` field as an explicit
manifest invariant, not as a second authority.

Frontend note: demo `LLM` uses 18 decimals. Convert user-entered whole LLM to base units before mint, approve, or stake calls.

## Congress election demo note

The demo deployment seeds Congress cycle `1` as an active voting cycle:

- nomination starts exactly 72 hours before the seeded 17:00 UTC endpoint
- voting starts exactly 48 hours before that endpoint
- deployment occurs during voting, with between 24 and 48 hours remaining
- voting ends at 17:00 UTC
- the seeded cycle has a 72 hour total window
- 4 seeded citizens are accepted candidates
- starter cycle ballots are recorded so the election page has immediate read-state

For election screens, use `CongressCandidateRegistry.latestCycleId()` as the main cycle pointer. `CongressElectionApp.currentCongressCycleId()` returns the active office term and remains `0` until an election is finalized.

After the seeded cycle ends, anyone advances `CongressElectionApp.finalizeElection(uint256)` with cycle `1` until
the registry reports Finalized. The overload `finalizeElection(uint256,uint256)` accepts a workload of 1..32;
the original selector defaults to 32. Read ranking-store progress, estimate gas and lower the workload if needed.
Next, preview the window and explicitly call `createNextElectionCycle()`; newly active Congress members are
automatically registered for the new cycle unless they withdraw during nomination. Late creation changes the
previewed anchor, so do not assume `cycle1.votingEnd` remains the next nomination start.

New live demo users cannot acquire voting weight in an already-snapshotted election merely by onboarding:

1. User self-registers through `DemoCitizenGateway`
2. Registrar confirms citizenship
3. User mints and stakes enough demo `LLM`
4. Wait for a new election whose completed-block snapshot includes the citizen and their active stake
5. User calls `CongressElectionApp.castBallot(cycleId, candidates, allocations)` during that election's voting window,
   while still in current good standing

`castBallot` stores a ballot only for the supplied cycle. A later call in that cycle replaces the entire ballot, and `clearBallot(cycleId)` removes it. Nothing carries into later cycles. Read `getBallotReceipt(cycleId, wallet)` and `getBallotAllocationAt(cycleId, wallet, index)`.

Candidate applications are person-bound within the cycle. If an accepted candidate migrates wallets, the original
application address remains the canonical registry record and durable ballot target, even if that address is later
reassigned. `getCandidate` resolves from either the canonical address or the person's current active address, and
the person cannot apply again. Withdrawal follows the caller's current active-person link. Ballots may use the
current active address while it still resolves to that person, but they are stored against the canonical candidate;
the contract rejects a ballot containing two references that resolve to the same candidate.

## How to add or change a demo-seeded election cycle

The seeded election is intentionally in demo bootstrap code, not the production election contracts.
`DemoSetupAuthority` replaces any caller-supplied referendum/election snapshot field with the actual setup
transaction's `block.number`. A later checkpoint written in that same block can still change the historical value
returned for the block, so seeded vote state is illustrative rather than a production snapshot guarantee.
Production never deploys `DemoSetupAuthority`; newly created live processes use the last completed block.
After the seeded setup, Sepolia live creation uses the same checks as production: the voting policy must pin the
current kernel electorate and `snapshotAtCurrentEpoch(lastCompletedBlock)` must certify current source-revision
synchronization. A bounded rebuild or missed-callback catch-up completes for creation only in the following block.
Historical `snapshotAt`/`wasEligibleAt` remain for already-pinned processes.

To change it:

1. Edit `_seedCongressElection(...)` in `scripts/DeployDemo.s.sol`
2. Adjust the cycle timestamps, candidates, and starter ballots; the default fast-demo shape is 24 hours nomination plus 48 hours voting
3. Keep `CONGRESS_CANDIDATE_REGISTRY_AUTHORITY` pointed at `DemoSetupAuthority` during `_seedDemoState`
4. Keep `_switchToFinalDemoWiring()` switching `CONGRESS_CANDIDATE_REGISTRY_AUTHORITY` back to `CongressElectionApp`
5. Run `forge fmt`, `forge build`, and `forge test -vvv`
6. Redeploy the demo and copy the new `deployments/sepolia-demo.json` into `frontend-export/sepolia-demo.json`

The production election contracts do not need to change to seed demo state. A new deployment is required because the seeded cycle is written during bootstrap before bootstrap authority is permanently disabled. Deployment JSON files are generated outputs and are intentionally ignored by Git; commit only examples or documentation, not stale live addresses.

## Land and company registry demo note

The demo script deploys and wires `LandRegistry`, `LandPartyPolicy`, `LandRegistryApp`, `CompanyRegistry`, and
`CompanyRegistryApp`, but it does not seed parcel or company records.

The Land Registry clerk may prepare parcel drafts; the office admin/registrar finalizes live parcel/title changes.
Titles reference a registered person, active company, or active office, and a transfer requires current seller and
buyer EIP-712 signatures plus registrar submission. Only a current authorized signer for a registered party may
file a dispute; the registrar then accepts or resolves it. Incorporation submissions remain public through
`CompanyRegistryApp.submitIncorporation(...)`, with approval/rejection handled by the Company Registry Office. See
`docs/Land-Cadastre.md` before constructing demo land data or signatures.

## How to change recurring election cadence

The recurring cadence lives in `CongressElectionPolicy.cycleDuration()`. The demo deploy sets it to 72 hours; the production deploy script sets it to 90 days.

To change it after deployment:

1. Deploy a new `CongressElectionPolicy` with the desired `cycleDuration`
2. Keep the non-timing parameters equal to the current policy: candidate eligibility policy, voting power policy, seat count, runner-up count, max candidate count, and candidate bond requirement
3. Create a policy referendum using `ReferendumApp.createCitizenCongressElectionPolicyReferendum(...)` or `ReferendumApp.createCongressElectionPolicyReferendum(...)`
4. If the referendum passes, `ReferendumApp.finalizeReferendum(...)` queues a bounded `ModulePointerUpdate` for `CONGRESS_ELECTION_POLICY`
5. After the timelock delay and applicable negative-power checks, call `ActionTimelock.executeAction(actionId)`
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

Broadcast and verify once, after reviewing the simulation:

```bash
forge script scripts/DeployDemo.s.sol:DeployDemo \
  --rpc-url "$SEPOLIA_RPC_URL" \
  --broadcast \
  --slow --gas-estimate-multiplier 200 \
  --verify \
  --etherscan-api-key "$ETHERSCAN_API_KEY" \
  -vvvv
```

Do not rerun this non-idempotent deployment merely to verify existing addresses. Use address-specific verification
or the reviewed existing broadcast bundle. For a partial broadcast, inspect confirmed receipts and the exact
Foundry `--resume` bundle before resuming; do not blindly deploy again. The gas-estimate margin and sequential
broadcast account for real separate-block checkpoint allocation, but each transaction still needs target-chain
gas-limit review. Simulation also writes a manifest, which is not evidence of a broadcast.

## Output

The script writes:

- `deployments/sepolia-demo.json`

Use that file for the frontend demo environment by copying it to `frontend-export/sepolia-demo.json`. Do not use `broadcast/` files as frontend config.

Useful fields inside it:

- `demoCitizenGateway`
- `identityApp`, which must equal `demoCitizenGateway` in this deployment
- `decisionApp`
- `llmToken`
- `congressCycleId`
- `congressNominationStart`
- `congressVotingStart`
- `congressVotingEnd`
- `landRegistry`
- `landPartyPolicy`
- `landRegistryApp`
- `companyRegistry`
- `companyRegistryApp`
- office IDs for finance, identity, land, and company registry
- the seeded finance budget ID
- the seeded office admin and finance clerk addresses
- the prefunded treasury amount, if any
- `stakingBackingSurplus`, the LLM vault balance above aggregate active stake (normally zero immediately after seeding)

After every contract change, regenerate the whole ABI directory from the same source revision. After every demo
redeployment, replace the ignored live manifest and smoke-test registration/confirmation, stake, candidacy,
wallet-migration continuity, ballot submission, public-veto counts, payout state synchronization, and lending reads.
The example JSON is a schema only and must never be presented as a live deployment.
