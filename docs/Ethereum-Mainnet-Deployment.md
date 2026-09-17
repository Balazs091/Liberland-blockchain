# Ethereum Mainnet Deployment

**Current governance and release requirements:** see `Governance.md`. Require four nonzero,
pairwise-distinct office admins (and independently reviewed disjoint controlling signer sets). Appoint an
independently controlled Identity Office clerk using the normal authorized flow for two-officer recovery/civic
notices. Include `CongressCandidateRegistry.rankingStore()` and its immutable writer boundary in bytecode review.
Existing deployments/ABIs are not updated by this source change; a fresh state/process migration review is mandatory.

Use `scripts/Deploy.s.sol` for the production Ethereum mainnet deployment. The script is guarded to chain ID `1` and reads its immutable deployment constants from `scripts/parameters/EthereumMainnetParameters.sol`.

The Sepolia demo is a separate deployment path documented in `docs/Sepolia-Demo-Deployment.md`; it must not be used as a source of production parameters.

## Civic review and officer readiness

The distinct-office-admin requirement is a production genesis preflight. The registry permits shared admins and
does not enforce continuing cross-office separation after deployment; maintain independent controllers through
appointment policy and monitoring. Two-officer approvals and civic-reviewer exclusions remain enforced.

Set `CIVIC_REVIEWER_0` through `CIVIC_REVIEWER_4` before running this script. Both networks require five nonzero,
pairwise-distinct public addresses, each different from the deployer and all four office admins. No reviewer private
key is needed for deployment. Verify disjoint real controllers, conflicts of interest, signing capability, notice
publication and evidence retention off-chain; different addresses alone are not sufficient independence.

The manifest exports `civicAppealReview` and `civicReviewer0` through `civicReviewer4`. Verify the kernel's
`CIVIC_APPEAL_AUTHORITY` pointer, the committee's `identityApp()` binding and all five `reviewerAt(i)` values.
Appoint operational, independently controlled Identity and Finance clerks through the normal authorized workflow
before starting two-officer cases or payments. A Finance clerk may approve or route a sensitive admin proposal;
no officer can provide both approvals. See [Governance](Governance.md) for ruling deadlines and rotation.

## Production Congress continuity

Production has seven Congress seats and all seven must be populated at genesis. The recurring Congress cycle is 90 days.

Because this deployment continues an existing Congress term, genesis creates two records:

1. a finalized seed record that installs the seven incumbent office holders; and
2. a live continuity election cycle ending at the imported pre-migration boundary.

Deployment now requires two invocations. `run()` prepares contracts and seeds citizens, stake, Senate, President
and offices. It leaves Congress and referendum registry authority parked on `InitialSetupAuthority` and outputs
`genesisComplete: false`. This is **not a live deployment** and bootstrap is intentionally still present.

After preparation transactions are confirmed, `completeGenesis(address)` creates the finalized seed term and live
continuity election using the already-seeded citizen order. The live cycle requires a certified last-completed-block
snapshot; completion must be in a block strictly after the last setup citizen mutation, so the snapshot may be that
mutation block or a later completed block. Same-block completion reverts. Only the already-finalized
seed term retains its setup block (it has no live vote). Completion activates the standing Congress/referendum
writers, checks readiness, seals setup and retires bootstrap. Do not leave preparation unattended or launch a
frontend against it.

Set `GENESIS_CONGRESS_CYCLE_END_TIMESTAMP` to the absolute Unix timestamp at which the remaining imported cycle should end. It must:

- be in the future;
- leave at least the full two-day nomination window and three-day voting window;
- be no more than 90 days after deployment; and
- land exactly at `17:00 UTC`, which is `18:00` in fixed CET (`UTC+1`).

This deliberately means CET, not daylight-saving CEST. Ethereum contracts do not have a reliable civil-time/DST oracle. If the intended requirement is always 18:00 in a European local timezone, seasonal boundary updates need a separately governed design.

After the continuity cycle, each newly created cycle has the full 90-day duration. Finalization completes only the
pinned cycle; anyone separately calls `createNextElectionCycle()` when the current policy/electorate permit. Preview
the window at creation: late creation advances the anchor to the next daily `17:00 UTC` boundary instead of drifting
to an arbitrary transaction hour.

## Required environment

Copy `.env.example` to `.env` and configure:

- `MAINNET_RPC_URL`, `PRIVATE_KEY`, and `ETHERSCAN_API_KEY`;
- the deployed `LLM_TOKEN`, which must use 18 decimals, expose an immutable `cap()` of exactly
  `70_000_000e18`, and be included in the treasury asset allowlist;
- the deployed six-decimal `USDC_TOKEN` used by the launch lending pool;
- all remaining treasury assets and per-payout limits;
- a deployer LLM balance at least equal to the sum of all `GENESIS_CITIZEN_*_ACTIVE_STAKE` values;
- at least seven eligible genesis citizens;
- Senate seat assignments;
- exactly seven to nine ranked Congress candidates, with the first seven becoming incumbents;
- `GENESIS_CONGRESS_CYCLE_END_TIMESTAMP`;
- the genesis President and mandate hash; and
- all four office admins, each explicitly set and different from the deployer; and
- all five independent `CIVIC_REVIEWER_0` through `CIVIC_REVIEWER_4` public addresses.

Do not commit secrets or real genesis personal metadata to the repository.

During genesis, the script temporarily approves `LLMStakingVault`, pulls each citizen's configured stake from the deployer, credits the matching person ID, and clears the approval. Deployment reverts if the token transfer is short or aggregate backing would be insufficient.

The deployment also verifies `decimals() == 18`, `cap() == 70_000_000e18`, and `totalSupply() <= cap()` on the
external LLM token. These checks do not make an upgradeable token safe: operators and auditors must verify that the
exact production bytecode cannot replace or bypass its cap. `TreasuryVault` receives only pre-existing LLM through
`receiveTokenDeposit`; it has no mint function or arbitrary token-call path.

## Contribution-reward reserve

Before contribution rewards begin:

1. Transfer the approved institutional LLM reserve into `TreasuryVault` through `receiveTokenDeposit`.
2. Approve an LLM-denominated `ContributionReward` budget envelope by referendum and execute its queued action.
3. Publish the operational standard for verifying donated time, money, or other accepted contributions.

Only the active Finance Office admin may propose a `ContributionReward`. Every request must include a nonzero hash
and nonempty URI for its evidence document. Rewards use the sensitive one-day office queue, the normal treasury
timelock, the exact budget commitment, and Senate cancellation/suspension controls. A distinct current officer must approve; a permitted clerk may then route this admin-proposed
reward. Revoking an appointment after routing does not cancel the queued action.

Budget approval creates the envelope, not a `LegislationRegistry` enactment. The retained lifecycle does not let
public repeal revoke the envelope; budget validity/accounting and Senate controls over queued payouts are separate.
See [Governance](Governance.md) before representing budget cancellation powers to operators.

## Dry run and broadcast

Compile and test first:

Use the pinned Solidity 0.8.37/Osaka build profile in `foundry.toml`; changing compiler or target settings requires
fresh bytecode, size and verification evidence.

```bash
forge build
forge test -vvv
```

Before an audit handoff or production broadcast, also refresh the revision-specific coverage, Slither, runtime-size,
and deployment-integration evidence in `docs/Release-Readiness.md`. Do not copy historical counts or size values
from another commit.

`bash scripts/rehearse-local-genesis.sh` exercises both stages on localhost with synthetic identities and mock
assets. Its revision-specific result is recorded in [Release Readiness](Release-Readiness.md). A successful local
rehearsal is not a mainnet fork test, real-token verification, production genesis approval or public deployment.

Simulate without broadcasting:

```bash
forge script scripts/Deploy.s.sol:Deploy \
  --rpc-url "$MAINNET_RPC_URL" \
  -vvvv
```

After reviewing the complete simulation output and generated addresses, broadcast and verify:

```bash
forge script scripts/Deploy.s.sol:Deploy \
  --rpc-url "$MAINNET_RPC_URL" \
  --broadcast \
  --slow --gas-estimate-multiplier 200 \
  --verify \
  --etherscan-api-key "$ETHERSCAN_API_KEY" \
  -vvvv
```

The script writes the address manifest to `deployments/ethereum-mainnet.json`. Treat `deployments/` and `broadcast/` as environment-specific generated output.

The command above completes **preparation only**. Confirm its receipts and review the partial manifest, then set
`GENESIS_KERNEL` to that manifest's exact `constitutionKernel`. Keep the same operator and genesis rank inputs.
Simulate the second stage against that prepared chain, review it, and then broadcast:

```bash
forge script scripts/Deploy.s.sol:Deploy \
  --sig 'completeGenesis(address)' "$GENESIS_KERNEL" \
  --rpc-url "$MAINNET_RPC_URL" -vvvv

forge script scripts/Deploy.s.sol:Deploy \
  --sig 'completeGenesis(address)' "$GENESIS_KERNEL" \
  --rpc-url "$MAINNET_RPC_URL" --broadcast --slow --gas-estimate-multiplier 200 -vvvv
```

Completion writes `ethereum-mainnet-activation.json` and, if the matching preparation manifest is present, updates
its Congress fields and `genesisComplete`. Scripts also write files during simulation: **neither file proves a
broadcast occurred**. Before enabling clients, independently verify confirmed receipts, exact module pointers,
seven occupied seats, the continuity snapshot, setup sealing and all bootstrap-authority addresses equal to zero.
Archive both stages' transaction bundles. For a partially broadcast stage use its reviewed Foundry `--resume`
bundle; do not blindly rerun the non-idempotent preparation or reseed an existing continuity cycle.

Use the shown gas-estimate margin and sequential broadcast. Source mutations now reserve a full electorate callback
budget. Foundry's same-block script simulation can underestimate checkpoint allocation across real separate blocks;
the default 130% margin failed a real localhost broadcast of `configureCitizen`, while the 200% rehearsal passed.
Independently check each prepared transaction against the target chain's gas cap; an estimate is not a guarantee.

## Deployment scope

The production script deploys the core governance, identity/stake (including `LLMStakingVault` and
`ElectorateRegistry`), elections, referenda, Senate/public veto, bounded `DecisionApp`, treasury/offices,
`MinistryTreasury`, land/company registries, and the stake-backed USDC lending stack. It does not deploy demo
helpers, mock tokens, demo balances, or seeded demo workflows.

Live referendum and election creation after genesis uses the last completed block. It requires the selected
`VotingPowerPolicy` to pin the current kernel electorate and calls
`ElectorateRegistry.snapshotAtCurrentEpoch` to certify the current policy epoch and live identity/stake mutation
revisions. A citizen-policy rebuild or missed-callback catch-up pauses new process creation through its completion
block; because creation selects the last completed block, it resumes in the next block. Historical
`snapshotAt`/`wasEligibleAt` reads and the policy/electorate already pinned by an active process are not changed by a
later replacement.

The initial lending configuration is fixed at 1 LLM = 2 USDC, 30% maximum LTV, 40% liquidation threshold, 15%
liquidation bonus, 15% reserve factor, 1,000,000 USDC aggregate borrow cap, 100,000 USDC debt cap per person, 5%
base APR, 13% APR at the 80% utilization kink, and 113% APR at full utilization. These are launch parameters, not
immutable constitutional rules: the oracle, risk, and interest policies are governed replaceable modules. The pool
contract and custody state still require an explicit migration plan if the pool app itself is ever replaced.

APR is nominal and compounded per second, not an effective annual yield. The interest policy's combined maximum
nominal rate must be at most 200%; the pool also rejects an incompatible RAY scale or out-of-range rate from a
replacement policy. These are numerical safety bounds, not permission to skip economic review or a guarantee of
perpetual loan-book liveness. The two-day migration and 30-day welfare settings are unchanged; their constructors
reject zero or values above `uint32.max` seconds. Timelock delays and its default execution window have the same
nonzero numerical ceiling. Referendum and action timestamps must remain representable in `uint64`.

Debt uses one RAY-scaled global borrow index, and the effective rate/reserve inputs are checkpointed by elapsed
interval. The risk policy rejects a threshold/bonus pair whose full-threshold liquidation could exceed all quoted
collateral. A borrower's citizenship retained-stake floor is fixed when the lien begins and cleared only when the
loan is explicitly closed after full debt repayment or bad-debt absorption, even if collateral/liquidation already
reduced the lien to zero.
When total scaled debt reaches zero, a pool checkpoint may reset the borrow index to RAY, emitting
`EmptyBookIndexReset`; cash, shares and reserves are unchanged, and outstanding debt cannot be reset this way.

The land deployment includes `LandRegistry`, `LandPartyPolicy`, and `LandRegistryApp`. Production title parties are
stable identity/company/office IDs, while current signers are resolved at execution time. Use a reviewed EIP-1271
multisig as the Land Registry Office administrator where operationally appropriate. Publish the cadastral schema and
canonical hashing rules before importing records, preserve predecessor lineage, and independently reconcile every
parcel, active title, dispute, and encumbrance. Transaction fees, insurance/compensation, and judicial settlement are
not launch placeholders; add them only as reviewed modules once their law is defined. See `docs/Land-Cadastre.md`.

## Module replacement release procedure

Before proposing a replacement address, archive its deployed bytecode and compiler metadata, confirm it is not an independently upgradeable proxy or generic delegatecall executor, review every immutable dependency, and rehearse the migration on a fork with copied production state. A replacement app must preserve the interfaces needed during the transition or be deployed as part of an explicitly reviewed breaking migration. For a state-bearing module, prove how every required record and asset reaches the replacement before activating its canonical pointer; the kernel deliberately cannot infer or perform this migration.

List every kernel pointer that must move. Many workflows have both an app pointer and registry-authority pointers. Each pointer change requires its own approved typed action; once all are ready, execute them in dependency order with `ActionTimelock.executeActions(actionIds)`. Do not activate paired pointers through separate transactions. Confirm every action is executable, targets the expected old address, shares an overlapping execution window, and has no pending Senate cancellation before submitting the batch.

Treat `ReferendumApp` replacement as a special release: it is the only current referendum-creation path. A defective approved replacement cannot be repaired without an already functioning governance origin or a new trust root. Its full create, vote, finalize, enact, veto-integration, and module-routing lifecycle must pass on a production-state fork before the address is proposed.

Optional Senate/review probes have a 100,000-gas budget and require exact canonical ABI responses. A genuine
over-budget/reverting/malformed hook is ignored; deliberate caller underfunding reverts rather than bypassing a
valid record. Replacement bytecode must fit that interface and budget.

The incumbent Senate cannot cancel or hold open the active referendum proposing its exact `SENATE_APP` replacement,
cannot cancel the resulting queued action, and its pending-cancellation hook is skipped only for that action. The
constitutional-review pause hook is likewise skipped only for the exact `CONSTITUTIONAL_REVIEW` replacement. These
liveness exceptions do not bypass the referendum vote, delay, pinned-target, or execution-window checks; release
review remains mandatory.

These are not complete recovery guarantees: the review module may block the Senate replacement while Senate
blocks the review replacement, and broken referendum/policy/electorate dependencies can stop new replacement
votes. The design provides no additional permanent ballot system. An action
batch is atomic when submitted, but individually queued members remain independently executable. Review every
intermediate state, not only the intended batch. See [Upgrade and Liveness](Upgrade-And-Liveness.md) for supported
custody handoff, retired-loan settlement and the limits of arbitrary state migration.

Before mainnet use, perform an independent external audit, verify every genesis input out of band, rehearse against a mainnet fork, and archive the compiler settings, deployment transaction bundle, output manifest, and verification evidence.
