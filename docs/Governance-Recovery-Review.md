# Governance and recovery hardening

The 3 November 2026 changes add atomic module replacement, governed Sepolia staging and bounded debt-free exits.
The later [contract cleanup](Complexity-Review.md) consolidates duplicate logic. A separate recovery ballot remains
deferred.

## Changes

| Problem | Implemented change | Remaining boundary |
| --- | --- | --- |
| The isolated token/restriction lab cannot exercise governance | A separate full governed Sepolia deployment uses fixed-supply LiberlandMerit, controlled synthetic voter accounts, sealed bootstrap, normal referenda and the timelock | Existing isolated deployments are not retrofitted. Mock USDC, accelerated parameters and the four-subject Congress controller are test-only |
| Separate approved pointer actions can execute in a partial order | One typed bundle action installs all entries in an immutable plan of up to 16 sorted existing non-Core pointers | Migrate records and custody separately. Senate and review replacements keep their own routes and veto rules |
| Replacement code or incumbents may differ from the approved plan | Plans bind the chain, kernel, registry, update entries and evidence. The ballot validates the structure. Queue and execution verify incumbents and runtime hashes | Review the replacement code, compatible storage and migration authority separately |
| A broken future financial policy can prevent an otherwise independent final exit | A debt-free LP withdrawal or repayment closing all global debt uses the already validated accrual interval, preserving interest, reserves, exact receipt and lien closure | Partial repayment, closing only one of several loans and LP withdrawal while debt remains require live policies |
| Recovery procedures and new legal authority were mixed together | The recovery runbook covers synchronization, compatible repair and rollback, custody handoff and reconciliation. RC01–RC07 identify additional decisions | The runbook uses existing authority and grants no new execution powers |

The original `executeActions` convenience batch remains available and its members remain independently executable.
The new `ModuleBundleUpdate` is a distinct single action with no separately executable members. Existing action and
referendum enum values are retained, with new values appended. Existing constructors and public methods remain.
The new bundle methods and read-only helper and manifest fields are additive. This changes fresh-deployment bytecode,
including the immutable core, and cannot patch old deployed core contracts.

`ReferendumApp` creates its own immutable read-only `ReferendumProposalValidator`. The helper shares no writer or
execution authority and cannot be changed by an operator. This keeps deployable app runtime below the normal size
limit while retaining the existing proposal checks and revert selectors.

## Verification

Use the [auditor commands](Auditor-Handoff.md#reproduce-the-checks) on the submitted revision. Examine forward and
preopened reverse plans, stale targets, runtime drift, malformed plans, callback rollback and failed transfers.
Inspect branch coverage and failure flags separately from handler-call counts. Missing Foundry anchors can
under-report execution.

The synthetic genesis fixture uses a USDC test double at the canonical address. Review the issuer's production
implementation and controller powers on a mainnet fork. The [governed Sepolia guide](Sepolia-Governed-Deployment.md)
describes the synthetic controller replacement and rollback through citizen votes.

## Recovery limits and decisions

Use [Recovery Plan](Recovery-Plan.md) before every upgrade and incident. It requires exact dependency inventory,
preserved records/receipts, rehearsal of both directions, a valid execution window and reconciliation of real assets.
Preopened rollback helps only while a suitable authorised finalizer and its dependencies still work. It cannot
repair arbitrary broken governance, replace the permanent core or recover assets an external issuer will not move.

[Recovery Decisions](Recovery-Decisions.md) records the proposed citizen repair route, mutual-veto adjudication,
ongoing-debt exit terms, stalled land proceedings, pending-process migration, lawful role and key succession,
and claims involving immutable core modules or external assets. Production requires the legal inputs, reviewed
genesis data, an independent audit and a release manifest tied to the exact revision.
