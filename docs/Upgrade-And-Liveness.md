# Upgrade and Liveness Boundaries

The kernel permits governed replacement of every non-Core module ID. That is an address-update capability, not a
guarantee that every faulty module, record set or asset position can be recovered. This document is the operational
boundary for the current source. Existing deployments do not acquire these protections from a documentation or ABI
update. See [Governance](Governance.md) and the revision-specific [Internal Review](Internal-Audit-Report.md).

## What can change

| Component | Governed change | Dependency and continuity requirement |
| --- | --- | --- |
| Kernel, router and timelock | The kernel has no replacement mechanism; router/timelock IDs are Core and cannot be repointed | Permanent execution trust root. No administrator or emergency executor can override it |
| Policy modules | Exact-address constitutional-threshold replacement | New immutable policy bundles must reference the matching registries and other policies. Active referenda/elections keep their original policy/snapshot |
| Referendum and Congress apps | Constitutional-threshold authority replacement | Coordinate router-origin and registry-writer IDs. Retain compatible stable registries and account for in-flight votes, ballots and app-local state |
| Senate, office, Cabinet, decision and review authorities | Constitutional-threshold authority replacement | Review every direct/indirect writer, office, case and process dependency. A new pointer neither copies pending approvals nor retires old storage |
| Bounded application pointers | Kernel classification determines the threshold | Application does not mean stateless: land-transfer nonces and app-local workflows need explicit continuity review |
| Payout queue | State-class constitutional-threshold replacement | Requests stay in the original queue; its OfficeExecutor reference is immutable. Existing budget commitments retain their original accounting writer for bounded reconciliation, not new reservation rights |
| Treasury vault | Constitutional-threshold replacement plus `handoffAsset(asset)` on the retired vault | Same-kernel canonical successor only; exact asset receipt, no record rewrite. The retained budget ledger prevents paid-ID reuse; old vault receipts remain for pinned-action reconciliation |
| IdentityApp and civic committee | Identity app is selected through `IDENTITY_REGISTRY_AUTHORITY`; committee through `CIVIC_APPEAL_AUTHORITY` | There is no separate `IDENTITY_APP` ID. Committee immutably binds one app; approved cases pin their committee and retain their timeout |
| Stable fact registries | Constitutional-threshold pointer replacement | Most apps/policies pin registry addresses. Replacing one registry requires its complete dependent bundle and a separately built, reconciled migration; there is no generic import/copy primitive |
| LLM custody vault | Constitutional-threshold replacement plus `handoffBacking()` on the retired vault | Only the exact governed successor with the same kernel, token, identity registry and stake registry may receive backing. This is same-ledger custody handoff, not record migration |
| USDC lending pool | Constitutional-threshold replacement plus settlement of the retired book | Existing debt/LP shares remain in the old pool. Each person's loan owner is retained until explicit closure; new borrowing cannot take over another pool's open position |
| Ministry treasury | State-class constitutional-threshold replacement | Office balances and pool shares remain in the original instance; historical operations still depend on its original office registry and compatible live policy. No generic balance import or sweep is provided |
| New extension ID | Constitutional-threshold registration and subsequent replacement | Registration supplies no migration, arbitrary-call power or exception to existing custody/authority checks |

Read `ConstitutionKernel.moduleClass(moduleId)` from the reviewed release instead of deriving authority from a
contract's name. Multiple IDs can identify one implementation, and immutable references can keep an old address
in use even after its canonical ID changes.

## Governance can still become unavailable

The owner chose to retain the existing political routes after reviewing the following limits. No permanent second
citizen-upgrade ballot or broad exemption from negative powers was added.

- `ReferendumApp` is the only current public route that creates and finalizes module-replacement referenda. Broken
  approved app bytecode can disable that route. Creation and voting also depend on functioning identity, stake,
  citizen/voting/referendum policies and certified electorate state. A broken dependency or an electorate that
  cannot be rebuilt can therefore prevent the vote needed to replace it.
- An ordinary missed electorate callback is recoverable with permissionless synchronization/bounded rebuilding,
  followed by the next block. A defective policy or registry is not equivalent to a missed callback: retries cannot
  repair arbitrary bytecode. Even a citizen-policy pointer update calls the current electorate's rebuild hook.
- Self-replacement exceptions are exact, not general. The incumbent Senate cannot veto/cancel its own `SENATE_APP`
  replacement referendum/action, and constitutional review cannot pause its own `CONSTITUTIONAL_REVIEW`
  replacement action. However, a review module can pause the Senate replacement while Senate blocks the review
  replacement. This cross-hook deadlock remains possible, including with a batch submitted in either order.
- An already approved, unexpired action may provide a narrow way to finish a preplanned transition. There is no
  general retry of expired execution authority and no right to invent a new origin: new proposals still need the
  existing authorized workflows. Loss of quorum, lost controlling keys or external token failure also remain
  operational/architectural availability risks.

These limits must be accepted explicitly by the human auditors and launch decision-makers. The source must not be
described as impossible to freeze. They are not permission to add a recovery administrator or bypass a failed vote.

## Optional negative-power hook safety

The three Senate record probes and the constitutional-review bool probe use `BoundedGovernanceHook`:

- each external probe receives at most 100,000 gas;
- the caller checks enough remaining gas to offer that entire budget, including EIP-150/cold-call headroom;
  deliberately underfunding the call reverts instead of bypassing an active record;
- return buffers have fixed sizes, and exact lengths plus every narrow integer/bool word are validated before
  decoding; successful empty, noncanonical or oversized responses cannot revert the caller's ABI decoder;
- a genuinely reverting, over-budget or malformed optional hook is treated as absent for that read; and
- canonical active veto, cancellation, suspension and review records remain enforced under the existing rules.

Replacement hook implementations must fit this interface and gas budget. The budget is a compatibility condition,
not permission to ignore a valid record by submitting less transaction gas. The core cannot distinguish a
malfunctioning hook from an intentionally incompatible one, so fail-open behavior is a deliberate trust boundary.

## Coordinated activation procedure

1. Inventory every kernel ID, immutable dependency, pending process, signer binding and custody balance affected.
   Deploy exact reviewed bytecode; do not use an independently upgradeable proxy or generic delegatecall executor.
2. Build and rehearse any actual record/process migration before presenting the pointer proposal. There is no
   generic migration action in the timelock. Reconcile record counts, aggregate assets, historical snapshots,
   liens, commitments, nonces and unresolved cases against a production-state fork.
3. Obtain each required typed referendum approval. Before activation, ensure all queued actions pin the expected
   old addresses, their execution windows overlap, and every applicable negative-power check is satisfied.
4. Submit coordinated pointer updates through `ActionTimelock.executeActions(actionIds)` in reviewed dependency
   order. This transaction is atomic, but the actions are not an indivisible stored group: any ready member may
   also be executed individually. Review intermediate states and front-running; operator batching alone is not
   an on-chain dependency lock.
5. Complete the narrowly supported custody/retirement operations below, verify all live getters/writers, and
   publish the new exact-bytecode manifest. Do not infer successful activation from a generated local file.

## LLM same-ledger custody handoff

After the `LLM_STAKING_VAULT` pointer selects the reviewed successor, anyone may call `handoffBacking()` on the old
vault. It checks that the kernel's identity/stake pointers still equal its original ledgers and that the successor
reports the same kernel, token and ledgers. It sends the complete old LLM balance, requires exact receipt and checks
that the successor covers aggregate active stake. The old vault cannot continue ordinary staking/unstaking once
retired. Custody can be temporarily unavailable between pointer activation and handoff; monitor and complete both.

The handoff does not rewrite person balances, stake checkpoints, liens or withdrawal rules, cannot choose another
recipient and cannot support a different token or ledger. Exact successor bytecode still needs independent review:
dependency getters alone cannot prove honest custody logic.

TreasuryVault supports a separate `handoffAsset(asset)` to the exact already-governed same-kernel successor. It
moves the complete specified ERC20 balance with exact receipt, not to a caller-selected address. It neither copies
historical disbursement receipts nor changes budget facts; old receipts remain in the retired vault for existing
payout synchronization. Ordinary disbursement is limited to the current vault and still requires the typed budget
commitment. An accidental deposit into a retired vault may be forwarded with the same handoff. Verify all assets
individually and retain their original receipt addresses in indexers.

`BudgetEnvelopeRegistry.isRequestExecuted(requestId)` is the permanent consumed-ID record across queue/vault
replacements that keep the same budget ledger. The current vault records it atomically with payment, independently
of later `syncPayoutState` bookkeeping; token failure rolls it back. A replacement vault's local receipt does not
replace the original vault's historical receipt. Always synchronize the original queue, which retains settlement
rights for its own old commitments. New reservations remain restricted to the current accounting authority.
Both writers are constrained by execution state: paid commitments cannot be released, and unexecuted commitments
cannot be marked spent. The permanent consumed-ID marker survives completed bookkeeping.
Migrating the budget registry itself must preserve consumed IDs; the helper does not import them automatically.

Drain or explicitly account for proposed/routed payouts before moving the queue/executor/vault bundle. The executor
pins its queue immutably, and old unexecuted actions pin their original vault. Once that vault pointer changes,
those actions need an authorized cancellation or expiry followed by original-queue synchronization; they do not
follow custody to the successor. New queues do not inherit pending proposals or their officer approvals.

## Loan-book retirement

Coordinate `USDC_LENDING_POOL_APP`, `STAKE_LIEN_REGISTRY_AUTHORITY` and `STAKE_LIQUIDATION_AUTHORITY`. Only the pool
selected by all three may add borrowing liens, and its immutable identity/stake/lien registries must equal the
current canonical registries. An obsolete registry cannot originate new liens. `StakeLienRegistry.loanBookOf(personId)` retains the sole owner of
an existing loan, including when liquidation reduces its lien to zero but debt remains. Its captured retained floor
also remains until that owner explicitly closes the position after full repayment or bad-debt absorption.

A retired pool cannot originate/top up loans, and `maxBorrowable` returns zero for retired or foreign-owned books.
It may settle only its own borrowers through the typed lien-registry settlement path. For a retired origin,
`seizedStake + remainingLien <= priorLien`: later unpledged stake cannot enlarge its liquidation rights. Health,
liquidation and bad-debt assessment all cap collateral at the lesser of current surplus and the remaining recorded
lien. Settlement also checks retained/protected floors and performs the corresponding stake transfer atomically. Pools have no
general direct stake-transfer permission. The currently selected compatible pool retains the existing
all-active-surplus collateral model; the numerical retired-book bound does not change active-loan economics. A successor cannot encumber that person until the old book closes.

Old pool share deposits/withdrawals, repayment, liquidation and bad-debt absorption remain available subject to
liquidity, token and live-policy constraints. The supported retirement path keeps the same canonical identity,
stake and lien registries and the same underlying asset. Debt and LP claims do not move to the successor. Ministry users retain
`poolSharesAt`/`withdrawFromPoolAt` access to old positions. A new identity/stake/lien ledger, different underlying asset, incompatible policy change or arbitrary custody/debt
import is outside this retirement mechanism and requires separate design/review. Unencumbered unstaking reads only
the protected floor, not a replaceable citizen policy; existing loan settlement uses its captured floor. New borrowing
still requires current policy/eligibility and matching origin pointers.

## Election progress is separate from future scheduling

`finalizeElection(uint256)` advances only its pinned cycle, with a default workload of 32. The overload
`finalizeElection(uint256,uint256)` accepts 1 through 32 candidates and bounds both score insertion and heap-head
consideration. Each heap operation is O(log N), and selected outcomes still need bounded current-eligibility
revalidation. Open admission does not imply a constant gas cost for an arbitrarily large population.

After canonical status becomes Finalized, anyone explicitly calls `createNextElectionCycle()` when current policy
and certified electorate state permit. It registers incumbents and preserves the configured UTC cadence. Failure
to create the next cycle does not undo the completed election. There is no automatic scheduler or guaranteed keeper.
