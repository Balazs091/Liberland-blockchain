# Upgrade and stuck-state recovery plan

Prepared 3 November 2026. This plan separates ordinary governed repair from powers that still need a legal and
governance decision. It introduces no administrator, unrestricted executor, asset sweep or automatic veto override.
The [accepted implementation direction](phase-a/IMPLEMENTATION-DECISIONS.md) remains in force.

The current simplification direction keeps recovery bounded and auditable. A separate recovery ballot is deferred
by user instruction. Use the existing governed paths below; [Complexity Review](Complexity-Review.md) records the
internal cleanup without new recovery authority.

## Recovery scope

The current source includes a governance-capable Sepolia environment and safer coordinated module changes.
[Governance and Recovery Review](Governance-Recovery-Review.md) records real proposals, votes, delays, execution
and rollback on disposable local chains. Public deployment still needs its own observed receipts and read-backs. The earlier isolated five-contract fixture remains a component test; it cannot gain
governance after its bootstrap has been retired.

The governed staging profile uses the full governance setup and actual fixed-supply LiberlandMerit. Current
Congress members exercise the explicitly synthetic restriction controller. Controller replacement keeps the same
MembershipRegistry and its orders; it does not reseed identities or grant a permanent deployment operator. Public
testers must supply their own controlled test addresses before public deployment; synthetic local actors are not
evidence of independent production control.

The ordinary repair path is: approve exact compatible replacement code through the existing authorised governance
route, wait through the queue, execute the approved transition, reconcile state and custody, and verify the result.
Neither an operator nor an incident declaration receives new authority. An exact rollback already approved under
working rules may help; it is not a universal substitute for a functioning governance system.

The kernel, router and timelock remain the permanent execution trust root. No contract can force an external token
issuer to release frozen assets or create liquidity already lent to borrowers. [Recovery decisions](Recovery-Decisions.md)
identifies the additional rules needed if those limits are unacceptable.

## Before every upgrade

1. **Record the exact change.** Identify the network, kernel, source revision/build, old and new module addresses,
   runtime hashes, constructor arguments, proposed rule version and the complete dependency bundle. For every slot,
   state the expected incumbent and the approved successor. Check actual bytecode and controllers; matching getters
   alone do not establish honest code.
2. **Classify what must survive.** List balances and backing, debt and LP shares, liens, budgets and consumed payout
   IDs, identity links and nonces, membership orders and their revisions, pending cases/appeals, votes and consent
   signatures. Record whether each item stays in its original ledger, finishes before cutover, or needs a specific
   reviewed migration. A source-data export is evidence, not an importer or a legal decision to cancel a case.
3. **Retain stable ledgers where possible.** Replacing a policy or controller while preserving its ledger is the
   preferred small change. In particular, replace the synthetic membership controller against the existing
   MembershipRegistry when testing authority changes. Replacing that registry requires a separate order/history
   importer and reconciliation; an empty replacement is not a recovery.
4. **Rehearse both directions.** On a disposable fork or synthetic staging deployment, exercise the real voting
   route and timelock, an already-open process, representative users, token failure, state/custody handoff and the
   intended rollback. Include any temporary or irreversible steps. A successful address update is insufficient.
5. **Prepare the rollback before the risky cutover.** For compatible policy changes, an original-address rollback
   ballot can be opened while that address is still current. Cast its required votes under its pinned rules and
   retain it in a legally executable state. Finalize it **after** the cutover when needed, so its queued action
   captures the actual new incumbent. Finalizing it early can leave a stale target after cutover. This technique
   depends on a still-functioning authorised finalizer, its writer, pinned rules and all applicable negative powers.
6. **Review the execution window.** Record voting/adoption ends, queue readiness and expiry, consent deadlines,
   custody handoff timing, and the time needed for public observation and execution. Assign a primary operator and
   an independent observer; permissionless transactions may be submitted by another person if the primary is absent.
   A keeper has no discretion to alter the approved effect.
7. **Check indivisibility.** The new transition design records an immutable, content-addressed plan in
   ModuleUpgradePlanRegistry: at most 16 sorted, unique, already-registered non-core updates, each with its expected
   incumbent, exact successor and runtime hash, plus an evidence commitment and chain/kernel/registry domain. The
   existing referendum route approves the complete plan at the constitutional threshold. One timelock action
   applies all pointer updates or none; there are no separately executable members. Verify that implementation in
   the selected fresh deployment. The older `executeActions` convenience call still does not make its separately
   queued members indivisible. Atomic pointer changes do not themselves migrate state or custody.
8. **Publish the reviewed manifest.** Include the exact authorised effects, preserved processes, rehearsed failure
   cases and rollback conditions. Keep private case evidence outside public manifests according to the approved
   disclosure rules. Do not publish keys or real identity documents as recovery evidence.

The bundle path excludes the permanent core and both `SENATE_APP` and `CONSTITUTIONAL_REVIEW`. Those two hooks keep
their existing exact single-module replacement paths; bundling cannot borrow a self-replacement exception to
bypass another check. This deliberately does not settle the cross-veto problem in RC02. A stored plan is not
approval, code honesty or migration proof. Expected incumbents must be checked at execution; rehearse rollback
plans whose expected incumbents become current only after the forward cutover.

Keep the plan registry stable during routine upgrades. Its address is part of each plan's domain, so copying the
same entries into another registry does not preserve their IDs or authorise already-open ballots/actions. Drain or
explicitly preserve that registry's pending plans before replacing it, including any pre-opened rollback plan.

## Incident procedure

### Establish what actually failed

Record a confirmed block/hash, the failed transaction or read, revert data, current pointers, relevant authority
records, deadline and asset balances. Repeat important reads through an independent source when available. Separate
a bad interface/display, stale electorate synchronisation, insufficient gas, expired approval, missing consent,
political veto, absent authorised signer, invalid policy code and external token failure.

Stop submitting optional operator-originated actions that would enlarge the affected exposure while diagnosis is
under way. This is an operational instruction, not an on-chain global pause. Continue correctly authorised exits,
repayments and protective deadlines when their preconditions remain valid. Do not change official records merely
to make an eligibility or readiness check pass.

### Select a supported route

| Observed condition | Supported action | Boundary |
| --- | --- | --- |
| Missed electorate callback or unfinished rebuild | Permissionless `syncPerson` or bounded `rebuild`; verify every source/epoch and wait for a certified completed block | Do not fabricate a historical snapshot or advance counters manually. Retry cannot repair arbitrary bad policy code |
| Compatible bad policy, ordinary governance still works | Submit the exact reviewed replacement, or use a suitable pre-opened rollback; keep ordinary thresholds, delays and negative controls | Preserve the dependencies needed to approve and execute the repair |
| Individual queued action has a stale target or expired window | Use its authorised cancellation/expiry and any required original-queue reconciliation; obtain fresh approval where required | Its payload and target cannot be edited, its ID cannot be replayed, and expiry does not create new execution authority |
| Coupled application/writer update | Execute the approved indivisible transition, or complete the already-authorised compatible remaining action only if the old separate-action path was used and remains valid | Do not improvise a writer change or assume app-local approvals transferred |
| Staking/Treasury pointer changed, backing still in the old vault | Use the existing exact-successor `handoffBacking`/`handoffAsset` methods and reconcile actual token receipt | Same-ledger and same-asset constraints apply. These methods are not arbitrary recipient transfers |
| Old loan or LP position after pool replacement | Use the original pool; repay/close the old loan book and recover old shares subject to liquidity. Ministry users use their explicit old-pool methods | Debt and shares do not move automatically. New borrowing cannot take over an open foreign book |
| Live financial policy is unusable | A debt-free pool can return available cash to share owners. The final borrower can repay the entire global loan book using its already validated accrual interval; exact receipt, reserves and lien closure still apply. For remaining debt, restore a compatible approved policy through working governance | Closing one of several loans or paying part of the final loan still requires valid live rules. New exposure remains blocked. RC03 is required for any ongoing-debt fallback |
| Land consent or case pending during app replacement | Retain canonical records/locks; finish the old process lawfully or obtain new domain-bound consent under the approved transition | A new app address does not make an old signature valid or erase a dispute lock |
| Finite membership restriction expires | Read the current rights summary; expiry takes effect without cleanup | Source mutation counters do not change merely because time passed. They are not historical electorate certificates |
| Indefinite restriction or protected-office consequence | Obtain the competent body's exact lawful relief through its approved route | Neither an operator nor a deployment script can remove the order or bypass an office-specific procedure |

### Do not cross the unavailable-authority boundary

If a faulty ReferendumApp or required dependency prevents all suitable proposal/finalisation paths, no suitable
pre-opened repair exists, or Senate/review powers form a cross-lock, this ordinary runbook cannot authorise an
override. The same applies when required keys/quorum are unavailable or the immutable core is defective. Preserve
evidence and claims, identify the exact unavailable authority and use the decision process in
[Recovery decisions](Recovery-Decisions.md). Announcing an emergency, changing a UI or possessing the deployment key
does not restore retired bootstrap authority.

## State and asset reconciliation

For a controller-only upgrade, compare the same ledger's order IDs, original references, status/revision, scoped
rights and source counters before and after. New synthetic controller references use their own domain; they do not
reissue real legal approvals or permit a duplicate order. For a future official issuer, consumed receipts and open
case finality/stays must be preserved explicitly.

For payouts, retain the original queue and the vault address captured by the action. A paid request must retain its
permanent consumed-ID marker in the budget ledger. After cancellation/expiry or execution, synchronise the original
queue and verify the commitment was released or spent once. An unexecuted action pinned to a retired vault does
not follow funds to the new vault; settle its authorised cancellation/expiry before preparing a fresh request.

For lending, reconcile cash, reserves, total/scaled debt, borrow index, retained floors, liens, loan owners and LP
claims. Preserve the captured old-book rights and its collateral bound; later unpledged deposits cannot expand a
retired lender's rights. Replacing the Ministry Treasury does not move its balances or shares. Its old exits resolve
the current OfficeRegistry, so preserve the office IDs and valid role facts before changing that registry.

For a ledger migration, require a module-specific importer, exact source/target roots and tested accounting rather
than a spreadsheet-to-admin write process. Specify how ongoing mutations are stopped or incorporated, prevent
duplicate claims and retain original evidence. Required legal choices about active cases and settlement priority
remain decisions, not technical defaults.

## Close the incident

Verify code and every affected pointer, sole writer, immutable dependency, source epoch and receipt counter.
Reconcile each asset and liability, retry the affected user journeys, and test the retained rollback route. Record
which effects are irreversible and which original instances must remain accessible. Publish the confirmed block,
transaction receipts and bounded result. Resume optional operations only after their applicable checks pass.

An event log or a simulation manifest is not proof of successful public deployment, state preservation or lawful
recovery. Governance-capable Sepolia is a place to rehearse these paths with synthetic data; it does not supply the
missing legal powers or guarantee recovery from every future fault.
