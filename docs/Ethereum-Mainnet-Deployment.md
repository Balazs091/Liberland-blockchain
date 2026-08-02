# Ethereum Mainnet Deployment

Use `scripts/Deploy.s.sol` for the production Ethereum mainnet deployment. The script is guarded to chain ID `1` and reads its immutable deployment constants from `scripts/parameters/EthereumMainnetParameters.sol`.

The Sepolia demo is a separate deployment path documented in `docs/Sepolia-Demo-Deployment.md`; it must not be used as a source of production parameters.

## Production Congress continuity

Production has seven Congress seats and all seven must be populated at genesis. The recurring Congress cycle is 90 days.

Because this deployment continues an existing Congress term, genesis creates two records:

1. a finalized seed record that installs the seven incumbent office holders; and
2. a live continuity election cycle ending at the imported pre-migration boundary.

Both setup records use the actual genesis setup block for their snapshot fields. The Congress candidate registry is
kept under `InitialSetupAuthority` for this multi-transaction seed window, so permissionless live cycle creation
cannot front-run the continuity record. After seeding, the script switches that registry authority to
`CongressElectionApp`, checks the final wiring, seals setup, and only then disables bootstrap.

Set `GENESIS_CONGRESS_CYCLE_END_TIMESTAMP` to the absolute Unix timestamp at which the remaining imported cycle should end. It must:

- be in the future;
- leave at least the full two-day nomination window and three-day voting window;
- be no more than 90 days after deployment; and
- land exactly at `17:00 UTC`, which is `18:00` in fixed CET (`UTC+1`).

This deliberately means CET, not daylight-saving CEST. Ethereum contracts do not have a reliable civil-time/DST oracle. If the intended requirement is always 18:00 in a European local timezone, seasonal boundary updates need a separately governed design.

After the continuity cycle, each newly created cycle has the full 90-day duration. Timely finalization preserves the prior boundary. Late finalization advances the next cycle start to the next daily `17:00 UTC` boundary, avoiding a permanent drift to an arbitrary transaction hour.

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
- all four office admins, each explicitly set and different from the deployer.

Do not commit secrets or real genesis personal metadata to the repository.

During genesis, the script temporarily approves `LLMStakingVault`, pulls each citizen's configured stake from the deployer, credits the matching person ID, and clears the approval. Deployment reverts if the token transfer is short or aggregate backing would be insufficient.

The deployment also verifies `decimals() == 18`, `cap() == 70_000_000e18`, and `totalSupply() <= cap()` on the
external LLM token. These checks do not make an upgradeable token safe: operators and auditors must verify that the
exact production bytecode cannot replace or bypass its cap. `TreasuryVault` receives only pre-existing LLM through
`receiveTokenDeposit`; it has no mint function or arbitrary token-call path.

## Contribution-reward reserve

Before contribution rewards begin:

1. Transfer the approved institutional LLM reserve into `TreasuryVault` through `receiveTokenDeposit`.
2. Enact an LLM-denominated `ContributionReward` budget envelope by referendum.
3. Publish the operational standard for verifying donated time, money, or other accepted contributions.

Only the active Finance Office admin may propose a `ContributionReward`. Every request must include a nonzero hash
and nonempty URI for its evidence document. Rewards use the sensitive one-day office queue, the normal treasury
timelock, the exact budget commitment, and Senate cancellation/suspension controls. Finance clerks cannot issue this
reward class.

## Dry run and broadcast

Compile and test first:

```bash
forge build
forge test -vvv
```

Before an audit handoff or production broadcast, also refresh the revision-specific coverage, Slither, runtime-size,
and deployment-integration evidence in `docs/Internal-Audit-Report.md`. Do not copy historical counts or size values
from another commit.

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
  --verify \
  --etherscan-api-key "$ETHERSCAN_API_KEY" \
  -vvvv
```

The script writes the address manifest to `deployments/ethereum-mainnet.json`. Treat `deployments/` and `broadcast/` as environment-specific generated output.

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

Debt uses one RAY-scaled global borrow index, and the effective rate/reserve inputs are checkpointed by elapsed
interval. The risk policy rejects a threshold/bonus pair whose full-threshold liquidation could exceed all quoted
collateral. A borrower's citizenship retained-stake floor is fixed when the lien begins and cleared only when the
lien reaches zero.

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

The incumbent Senate cannot cancel or hold open the active referendum proposing its exact `SENATE_APP` replacement,
cannot cancel the resulting queued action, and its pending-cancellation hook is skipped only for that action. The
constitutional-review pause hook is likewise skipped only for the exact `CONSTITUTIONAL_REVIEW` replacement. These
liveness exceptions do not bypass the referendum vote, delay, pinned-target, or execution-window checks; release
review remains mandatory.

Before mainnet use, perform an independent external audit, verify every genesis input out of band, rehearse against a mainnet fork, and archive the compiler settings, deployment transaction bundle, output manifest, and verification evidence.
