# Financial and land design for Phase A

This 29 October 2026 design uses baseline `dd0005c`. Feasibility of the Phase D stake-provenance design remains open.
Independent admission and membership work can proceed. The 10 November Justice profile uses voluntary compensation escrow.
[Legal register](LEGAL-DECISIONS.md), [Justice procedures](JUSTICE.md#voting-stake-and-custody)

## Architectural decision

Keep membership discipline separate from financial compensation. Preserve exact token backing, person-bound debt, and the single canonical stake ledger. Do not grant `DisciplineCaseApp` slashing, custody, arbitrary-call, or raw stake-transfer powers.

The target has small typed boundaries:

| Component | Owns | Must not own |
| --- | --- | --- |
| Exposure ledger | Stake provenance, terms acceptance, eligible historical cohorts and their consumption | Adjudication, loan repricing, arbitrary minting |
| Reservation registry | Claim-bound encumbrances, authoritative priority, expiry/stay state and aggregate reserved amounts | Citizenship or membership effects |
| Compensation settlement app | Exact approved financial effects, caps, receipts and beneficiary settlement election | General stake administration or discretionary asset selection |
| Canonical stake writer/vault | Atomic accounting transitions and exact funded custody | Deciding whether an allegation is true |
| Funded restoration pool | Allocated real LLM and restoration receipts | Unbacked restoration or other citizens' backing |
| Land case app | Land-specific procedure and exact adjudicated remedies | General registry write authority |
| Land writer | Owner-consented operations and exact lawful remedies to the stable land registry | Choosing the judgment or substituting effect payloads |

These are responsibilities, not a requirement to deploy seven new contracts. Combine components only when authority, lifecycle, bytecode size and audit scope justify it. Reuse internal hashing, signatures and threshold libraries; do not build a runtime-configurable universal executor. Financial and land effects use distinct issuer/purpose domains. See [proposed interfaces](INTERFACES.md).

## Canonical stake mutation matrix

All successful paths must leave active stake equal to the sum of its provenance buckets and remain exactly backed. Reserved and pledged amounts encumber existing assets; they are not extra active stake.

| Existing mutation and caller/path | Current behaviour | Proposed provenance/reservation work | Protection / open decision |
| --- | --- | --- | --- |
| [`stakeFor`](../../contracts/apps/LLMStakingVault.sol#L104), anyone funds an existing person through current vault | Exact token receipt, then `increaseStake` | Classify deposit under explicit cutover/terms rule; append or update eligible cohort; do not replenish an older cohort | L07: third-party funding is not beneficiary acceptance of exposure |
| [`creditBackedStake`](../../contracts/apps/LLMStakingVault.sol#L116), current setup/general stake authority through vault | Consume already funded backing surplus | Manifest-bound setup classification or explicit funded allocation | Seal import; distinguish genesis, later credits and restoration |
| [`unstake` / `unstakeFor`](../../contracts/apps/LLMStakingVault.sol#L137), active wallet / gateway through vault | Registry releases minimum of policy portion and permitted surplus; sets welfare; vault pays tokens | Consume Legacy/Exposed pro rata under L07; reduce every applicable pre-finality cohort; respect reservations | Full-width `mulDiv`; dust/repeated-call rounding specification; no later-deposit substitution |
| [`setProtectedStakeFloor`](../../contracts/registries/StakeRegistry.sol#L104), general stake authority | Scalar protection, rejected if composed floor exceeds active stake | Derive floor from preserved baseline and independent claim reservations | Do not overwrite another case; preserve captured retained floor and loan rights; L08 defines overlaps |
| [`slashStake`](../../contracts/registries/StakeRegistry.sol#L162), general stake authority | Reduces active/aggregate stake, increases `totalSlashed`; sends no tokens | No disciplinary connection. Any financial reuse requires exact typed settlement and explicit provenance/custody treatment | Not itself a compensation payment; L08 approval required |
| [`recoverStake`](../../contracts/registries/StakeRegistry.sol#L192), canonical vault only | Increases active stake and `totalRecovered` | Consume allocated restoration funding and record restored cohort/classification | Existing vault has no public funded restoration workflow; cannot simply increment accounting |
| [`transferActiveStake`](../../contracts/registries/StakeRegistry.sol#L213), general authority or canonical lien registry | Moves active stake and checkpoints between people; total active unchanged | Transfer/classify source cohorts; update both people; account for beneficiary restrictions | L07/L08 must define classification after transfer; accepting restricted stake must be explicit |
| [`settleLiquidation`](../../contracts/registries/StakeLienRegistry.sol#L94), recorded loan owner through lien registry | Atomically reduces/closes lien then calls `transferActiveStake` **without the vault** | Same provenance consumption as transfer; preserve loan ownership, captured floor and recorded bounds | A vault-only exposure hook misses this path; retired books cannot seize beyond prior lien |
| [`borrow`](../../contracts/apps/USDCLendingPoolApp.sol#L330) / repay / absorb | Debt, liens and loss allocation change; origination checks current eligibility and governed risk | Prevent double encumbrance; release only this loan's encumbrance; do not change provenance just because debt changes | Existing loans' collateral economics and priority cannot be silently rewritten |
| Vault [`handoffBacking`](../../contracts/apps/LLMStakingVault.sol#L54) | Exact transfer to the selected matching-ledger successor | Exposure/case/loan facts remain in their own ledgers | Does not migrate facts, debt or cases; successor inactive until backing and dependencies checked |

The current composed retained amount is `max(protectedFloor, capturedLoanRetainedFloor) + lienedStake` ([source](../../contracts/registries/StakeRegistry.sol#L329)). A reservation implementation must demonstrate its interaction with that exact formula; `sum(reservations)` alone is not a sufficient replacement. Current active loans use all active surplus; only retired books cap collateral at recorded liens ([source](../../contracts/apps/USDCLendingPoolApp.sol#L775)). Preserving a numerical lien is therefore not proof that all original loan rights were preserved.

## Cohort algorithm: alternatives and selection gate

**Unselected. No candidate below is claimed proven or gas-benchmarked.** L07 decides treatment of withdrawals/transfers/terms; L08 decides finality caps and priority. The chosen algorithm must implement those rules, rather than change them to fit a data structure.

| Candidate | Strength | Limitation / acceptance work |
| --- | --- | --- |
| Two aggregate balances, Legacy and Exposed | Constant-sized ordinary classification; straightforward pro-rata arithmetic | Insufficient for arbitrary historical claim cutoffs. Withdraw old 100, deposit new 100 after finality: `min(currentExposed, activeStakeAt(finalBlock))` incorrectly permits using the replacement 100 |
| Ordered per-person deposit cohorts/lots with consumption receipts | Explicit provenance and exact historical exclusion; good reference model | Lot count grows; pro-rata consumption can touch many lots. Need bounded resumable processing and a precise completion rule without letting partial execution reorder rights |
| Checkpointed share/accumulator model plus claim cohort references | Potentially cheaper aggregate transitions | Deposits, pro-rata withdrawals, transfers, reservations and different finality cutoffs interact. Requires derivation, differential testing against the lot reference model and rounding proofs |
| Committed off-chain allocation with on-chain verification | Small on-chain claims when proof rules are appropriate | A root alone proves inclusion, not correctness of provenance or priority. Requires an authorised publication, completeness and challenge model; no silent trusted allocator |

Preferred feasibility approach: use explicit lots as a reference model, then evaluate whether a checkpointed accumulator can preserve the same results at bounded gas. Do not specify a mandatory Merkle root in the public effect interface before this choice. Use a neutral cohort reference. No population-sized or entire-history loop may be required in a voting/staking read or final settlement.

Acceptance examples include repeated dust withdrawals, mixed Legacy conversions, post-finality replacement deposits, two claims with different cutoff blocks, liquidation before/after reservation, recipient transfers, rejected claims, and a stay interrupting a multi-transaction preparation. Bounds and legal operation ordering must be stated explicitly before selecting an implementation.

## Reservations, settlement and restoration

Each reservation has its own order/case ID, issuer, legal version, amount, priority receipt, effective deadline and stay status. Sequence comes from authoritative procedure; a caller cannot pick a favourable priority key. Releasing one order must not release another. Insufficient available eligible stake yields the legally prescribed bounded result; it must not silently seize Legacy or supersede a loan.

Bind the financial determination to exact case/revision, beneficiary, authorised amount, asset/mode, finality cutoff and cohort reference. Distinguish the legal decision's approved maximum from the execution quote's current preconditions. Freezing a global exposure version when the case is proposed would make unrelated legitimate mutations invalidate every later execution. Define when a quote is prepared, which state it binds, and what happens when it goes stale.

L08 must resolve: secured-loan priority; multiple claims and pending maximum holds; pro-rata groups and residue; liquid LLM versus active-stake receipt; beneficiary election; lawful confirmation/stays; restoration funding. Prefer pull payouts from assigned entitlements. Never treat a debt write-off, an accounting slash or an unbacked recovered balance as real compensation. A funded restoration pool may pay only its allocated liquid assets and cannot use other citizens' canonical backing.

## Loan-book migration and run-off stop conditions

The pool immutably binds identity/stake/lien registries ([constructor](../../contracts/apps/USDCLendingPoolApp.sol#L95)). A canonical pointer swap does not update these references. Old debt, LP shares, reserves and cash remain in their original pool. Existing retired-book settlement is a useful compatibility feature, not proof that an arbitrary ledger migration works.

Choose one documented route:

1. **Before genesis:** implement complete canonical mutation coverage and deploy the unified model without live old loans.
2. **Live run-off / consensual refinancing:** retire old origination; retain repayment/liquidation/absorption and old LP withdrawals; enable incompatible changes only after liabilities and collateral obligations are reconciled. This has no guaranteed finish date.
3. **Segregated legacy book / explicit migration:** preserve each existing pool's immutable read and settlement dependencies through an independently reviewed architecture and signed reconciliation. No assumption that a new writer or pool copies old state.

**Stop the financial cutover** if any open loan cannot settle under its original authorised terms; a zero lien is incorrectly treated as a closed book; old and new ledgers disagree; backing is short or still in an operationally retired vault; debt/LP/reserve reconciliation is incomplete; provenance or cohort logic is unproved; L07/L08 are unresolved; or an independently executable governance batch member produces an unsafe intermediate state. Provide separate handling for every retired pool, not just the current kernel pool.

None of these conditions is a reason to leave identity/membership design unfinished. Do not activate Phase D while its feasibility gate is open.

## Land remedy catalog and registry limits

Current authority is the Land Office app, with office-admin permission to accept and resolve disputes ([policy](../../contracts/policies/OfficePermissionPolicy.sol#L45)). Ordinary transfers already require seller and buyer signatures, nonce, deadline, current signers and version checks ([app](../../contracts/apps/LandRegistryApp.sol#L158)); retain them.

| Candidate typed remedy / fact operation | Current registry method | Conditions and implementation limit |
| --- | --- | --- |
| Record filing | [`fileDispute`](../../contracts/registries/LandRegistry.sol#L385) | Creates `Filed`; does **not** lock. Claimant standing/duplicate-abuse rules need L12 |
| Activate this dispute restriction | [`acceptDispute`](../../contracts/registries/LandRegistry.sol#L419) | `Filed` only; sets `Disputed`, increments active dispute counter and parcel version. Proposed automatic seven-day lock is a new legal rule |
| Dismiss/resolve this case, without substantive title change | [`resolveDispute`](../../contracts/registries/LandRegistry.sol#L458) | `Filed` or `Accepted`; only a previously Accepted case decrements counter; last accepted case restores Active. No title transfer |
| Exact holder substitution / transfer | [`transferTitle`](../../contracts/registries/LandRegistry.sol#L205) | Active title, current lease, matching title version/lineage; parcel Active with no disputes or encumbrances. A judgment does not bypass these conditions automatically |
| Exact cadastral correction | [`reviseParcel`](../../contracts/registries/LandRegistry.sol#L145) | Expected revision/lineage and Active status; cannot simply apply during `Disputed` state |
| Close title | [`closeTitle`](../../contracts/registries/LandRegistry.sol#L234) | Active matching title/version; parcel unlocked. Current app permits deterministic expired-lease closure; other closures need consent/lawful effect |
| Subdivide / merge / boundary adjustment | [`subdivideParcel`](../../contracts/registries/LandRegistry.sol#L256), [`mergeParcels`](../../contracts/registries/LandRegistry.sol#L304), [`adjustBoundary`](../../contracts/registries/LandRegistry.sol#L356) | Full bounded affected set, revisions/lineage and existing registry restrictions. All affected owners consent or exact lawful remedy; no generic geometry write |
| Retire parcel | [`retireParcel`](../../contracts/registries/LandRegistry.sol#L164) | No active title; parcel unlocked; matching revision/lineage. Not a route around an existing owner's title |
| Add encumbrance | [`registerEncumbrance`](../../contracts/registries/LandRegistry.sol#L505) | Existing active title; valid type/anchor/beneficiary/expiry; Active and not disputed; increments encumbrance counter |
| Release named encumbrance | [`releaseEncumbrance`](../../contracts/registries/LandRegistry.sol#L554) | Named Active record and correct lineage; decrements its counter only. Need beneficiary consent or exact lawful authority |
| Arbitrary retrospective rewrite, force transfer through other locks, unrestricted judgment calldata | None | Unsupported. Require explicit narrow registry change/migration if legally indispensable; never invent an unlock-all shortcut |

Use one canonical LandWriter authority (possibly `LandRegistryAppV2` itself). Separate `LandDisputeCaseApp` issues land determinations; it does not directly overwrite the registry. A separate `LandExecutor` hop is useful only if size/authority analysis requires it. The stable registry supports one current `LAND_REGISTRY_AUTHORITY`; two apps cannot each be assumed to have independent raw write access.

A remedy binds issuer/purpose/legal version, case/revision, exact parcel/title/encumbrance set, expected owner and versions, exact output parties/anchors, finality and stays. Vote on that payload hash. Execution is permissionless when lawful conditions are met, consumes a decision once, and either performs the complete bounded change or reverts. A changed version requires a fresh compatible execution precondition or renewed determination as the legal rule prescribes, not discretion to substitute a new remedy.

Resolving a case may itself change the parcel version. The execution specification must account for that deterministic version transition; do not sign the pre-lock version and later bypass version validation. With another active dispute or encumbrance, a transfer/correction can remain blocked. Do not clear unrelated locks to execute one award. Prove the exact method sequence against registry preconditions before declaring each remedy supported.

## Land decisions and privacy gates

L12 must define jurisdiction, lawful remedies, standing, service, duplicate filings, screening, urgent/automatic locks, release, appeal/stays and regulation commencement. L05 defines valid service/finality; L11 defines public facts and evidence access; L13 defines court interfaces where needed. Existing public title/parcel links cannot be made confidential merely by encrypting case documents.

The registrar records procedural facts. Separately appointed land bodies adjudicate. Share internal procedure libraries
across separate authorities. Substantive changes, including boundaries, encumbrances, dispute remedies and transfers,
require owner consent or an exact lawful determination.

## Required evidence before implementation approval

- Mutation matrix reconciled to every authoritative caller, including setup and retired paths.
- Selected cohort algorithm, reference model, rounding policy and bounded-work argument.
- L07/L08 decisions, loan-book reconciliation and approved compatibility route.
- Fully funded custody and restoration accounting, exact settlement receipts and replay/stay semantics.
- L12 remedy matrix with executable method sequences, all counter/version interactions and legal authorisation.
- Gas benchmarks at worst permitted cohort/claim/parcel/signature counts; no unmeasured gas-saving claims.
- Tests for later-deposit substitution; double reservation/pledge; concurrent claims; retired settlement; partial handoff; backing shortfall; stale land versions; several disputes; conflicting encumbrances; wrong-purpose decisions; old-admin paths and complete rollback.

Verify deployed addresses and state against the operator evidence. [Deployment inventory](DEPLOYMENT-INVENTORY.csv)
