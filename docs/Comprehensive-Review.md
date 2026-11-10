# Comprehensive code and publication review

This record covers the 5 November 2026 source snapshot after the [toolchain update](Toolchain-Upgrade.md).
See [Auditor Handoff](Auditor-Handoff.md) for the current submission procedure.

## Findings and changes

### G01. Unbounded first election duration (low, fixed)

The first permissionless Congress election checked minimum nomination/voting periods and the latest voting start,
but imposed no upper bound on its end. With an unseeded registry already assigned to the election app, a caller
without citizenship could choose `type(uint64).max`. Finalization and the next election would then remain blocked.

The production and demo base deployment sequences (including governed Sepolia) already prevent that exposed state:
their setup authority retains the registry until it seeds the initial cycle. The exposed sequence concerns
custom deployment and migration.

[`CongressElectionApp`](../contracts/apps/CongressElectionApp.sol) now rejects an initial cycle longer than
`policy.cycleDuration()`. It reuses the existing error, introduces no storage or authority, and preserves shorter
valid initial elections. [Regression cases](../test/apps/CongressElections.t.sol) cover the maximum integer, the
duration boundary, normal finalization, recurring cadence and minimum periods.

### I01. Reappointment can revive land consent (informational)

A removed company director cannot authorize a land transfer while removed. Reappointing the same address can make
an unchanged, unexpired signature usable again: the digest binds title/parcel versions and a nonce, but no
appointment epoch. Registrar finalization and valid buyer consent remain required. A failed attempt while the
director is removed leaves title and nonce unchanged.

The [cadastre guide](Land-Cadastre.md) describes short deadlines and review before reappointment. Permanent
invalidation on removal would require an appointment epoch or a cancellation rule.

### I02. Replacement policy guarantees (informational)

The pool checks the oracle's asset address. Review a replacement's quote units separately. The risk-policy
constructor enforces its own bounds. A replacement using the same interface still needs economic review.

### V01. Verification and handoff changes

- CI and the freeze script include the reference-model and tooling tests.
- Constitutional-source verification locates the repository from the script path, including in an extracted
  archive without `.git`. The pinned PDF and its checksum are unchanged.
- Architecture and deployment guidance distinguish production wiring from synthetic membership staging and
  identify module replacements as constitutional votes.

## Review scope

The snapshot includes contract implementations, interfaces, policies, registries, libraries, tests and deployment
scripts. Use [Audit Scope](Audit-Scope.md) to identify the current scope, including pinned dependencies, replacement
paths and the separation between synthetic authorities and production roles.

## Verification evidence

The snapshot uses Solidity 0.8.38, Foundry 1.9.0, OpenZeppelin 5.7.0, forge-std 1.17.0, Slither 0.11.6 and
crytic-compile 0.4.2. Exact dependency revisions are in `foundry.lock`. The archive includes recursive source.
Deployable builds retain Osaka, optimizer 200 and normal deployment-size/transaction-gas limits.

Only CongressElectionApp's deployed instructions changed: 16,600 to 16,732 runtime bytes. The two finance changes
affect compiler metadata only. All contract runtime/initcode sizes remain within their limits. The largest runtime
is CongressCandidateRegistry at 23,904 bytes, leaving 672 bytes of headroom. The election and finance changes
preserve selectors and normalized storage layouts.

The optimized suite includes the 1,000-candidate stress case. The coverage profile instruments the equivalent
100-candidate path. Inspect uncovered branches and failure paths on the submitted source. The election fix changes
one Low timestamp finding in the [Slither baseline](Static-Analysis-Triage.md).

## Material limits for the external auditor

1. **Governance can still become unavailable.** A broken voting, identity, stake, electorate or policy dependency
   can prevent the vote needed to repair it. The permanent kernel/router/timelock cannot replace themselves.
   Senate and constitutional review can cross-block each other's replacement. The separate recovery ballot remains
   deferred.
2. **Replacing a pointer does not migrate records.** Compatible custody handoff, retired loan settlement and payout
   reconciliation have specific guarantees. They do not import arbitrary identity, land, company, debt or pending
   proceedings. Typed bundles atomically change at most 16 eligible existing pointers. Ordinary action batches have
   independently executable members. Both mechanisms require separate state migration and bytecode review.
3. **Lending still needs economic approval.** A fixed LLM/USDC price is not realizable collateral value. Liquidity,
   liquidation incentives, reserves and limits need assessment. Partial/multi-borrower exits with ongoing debt can
   still need working policies. The existing fallback only covers the stated debt-free/final-global-loan cases.
4. **USDC controller behavior requires review.** Synthetic profiles use a USDC test double. Use a mainnet fork
   to examine the production proxy, pause and blocklist controls.
5. **Property and office authority depend on legal operations.** In this snapshot, removing a company's last signer
   can strand property. The [current cadastre guide](Land-Cadastre.md) describes subsequent safeguards. Accepted
   disputes and encumbrances require explicit resolution or release.
6. **The snapshot predates the optional Justice profile.** See [Justice procedures](phase-a/JUSTICE.md) for the
   current admission, discipline, annulment and eligibility rules and the off-chain responsibilities.
7. **Gas and coverage leave maintenance constraints.** CongressCandidateRegistry is close to the runtime size
   ceiling. Verify the transaction gas bound for the chosen election configuration. Review uncovered branches,
   inactive states and error paths.

See [Recovery Plan](Recovery-Plan.md), [Recovery Decisions](Recovery-Decisions.md),
[Phase A legal inputs](phase-a/LEGAL-DECISIONS.md), [Audit Scope](Audit-Scope.md) and
[Release Readiness](Release-Readiness.md) for the detailed rules and retained limitations.

## GitHub and audit handoff

The historical archive is `Liberland-EVM-Working-Tree-Audit-Snapshot-2026-11-05.zip`. Its provenance, file inventory
and checksums identify an unpublished source snapshot based on `dd0005c15d20754c50a0495cf6d48298b795e1a4`.
[GitHub CI for that base commit](https://github.com/Balazs091/Liberland-blockchain/actions/runs/35234352415) covers
the September source. For the current submission and production requirements, use
[Auditor Handoff](Auditor-Handoff.md) and [Release Readiness](Release-Readiness.md).
