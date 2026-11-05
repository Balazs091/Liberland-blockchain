# Comprehensive code and publication review

Reviewed **5 November 2026**. This is an internal implementation review of the current working source, following
the [toolchain update](Toolchain-Upgrade.md). It does not certify the proposed legal system or approve production.

The candidate is suitable for GitHub publication and external implementation audit once the complete reviewed
tree is captured. A checksummed source archive identifies the unpublished candidate independently of Git. A
commit-based handoff still requires committing all new files and dependency revisions, passing CI for that commit
and running the clean-tree freeze gate. Mainnet deployment remains blocked by the requirements below.

## Findings and changes

### G01 — Unbounded first election duration: low, conditional; fixed

The first permissionless Congress election checked minimum nomination/voting periods and the latest voting start,
but imposed no upper bound on its end. With an unseeded registry already assigned to the election app, a caller
without citizenship could choose `type(uint64).max`. Finalization and the next election would then remain blocked.
An isolated proof reproduced this immediately and ten years later.

The production and demo base deployment sequences (including governed Sepolia) already prevent that exposed state:
their setup authority retains the registry until the initial cycle is seeded. This was a custom-deployment/migration
availability issue, not a demonstrated exploit of the standard mainnet or governed Sepolia launch sequence.

[`CongressElectionApp`](../contracts/apps/CongressElectionApp.sol) now rejects an initial cycle longer than
`policy.cycleDuration()`. It reuses the existing error, introduces no storage or authority, and preserves shorter
valid initial elections. Five [regressions](../test/apps/CongressElections.t.sol) cover the maximum integer, the
duration boundary, normal finalization, recurring cadence and minimum periods. The two excessive-duration tests
fail against the old code; all 39 election tests pass against the fix.

### I01 — Reappointment can revive a land consent: informational; retained and documented

A removed company director cannot authorize a land transfer while removed. Reappointing the same address can make
an unchanged, unexpired signature usable again: the digest binds title/parcel versions and a nonce, but no
appointment epoch. Registrar finalization and valid buyer consent remain required. The isolated test confirmed
that a failed attempt while removed neither transfers title nor consumes the nonce.

This matches current-signer authorization. It is not permanent cancellation of earlier signatures. The
[cadastre guide](Land-Cadastre.md) now states this explicitly and recommends short deadlines and review before
reappointment. If removal must permanently invalidate consent, obtain that exact rule and implement a separately
reviewed epoch/cancellation design.

### I02 — Replacement-policy claims: informational; corrected

Two finance comments overstated runtime guarantees. The pool checks the oracle's asset address, not the correctness
of arbitrary replacement quote units. The risk-policy constructor enforces its own bounds, not those of every
future implementation with the same interface. Both comments now describe those limits accurately. The correction
changes no finance behavior; governed replacement code still needs semantic and economic review.

### V01 — Verification and handoff gaps: corrected

- CI and the freeze script now run the 34 reference-model tests alongside the 20 tooling tests.
- Constitutional-source verification now locates the repository from the script path. It works in an extracted
  archive without `.git`; the pinned PDF and its checksum are unchanged.
- Architecture and deployment guidance distinguish production wiring from synthetic membership staging, and
  identify module replacements as constitutional votes.
- All eight first-party README files received the requested no-ai-slop review. Five were edited and three retained.
  Edits remove repetition, narrow unsupported claims and clarify token/deployment and implemented/proposed scope.

No further new Critical, High or Medium vulnerability was confirmed in the reviewed flows. That finding does not
resolve the existing availability, economic and legal limits below, or establish that every state is safe.

## Review scope

The manual review covered all 65 non-mock implementation, policy, registry and library files. Two separate review
passes traced governance/identity/elections and finance/treasury/property; the coordinating pass covered the
remaining primitives, legislation and candidate policy, deployment boundaries and release tooling. Interfaces and
types were checked through their use sites. Synthetic authorities and their production separation were inspected.
Exact per-file scope and hashes are recorded in the review evidence.

The review challenged authority changes, wallet/person continuity, stale approvals, state transitions, vote
snapshots, signature replay, token receipt, debt/share rounding, original-loan ownership, retired custody,
reentrancy, integer bounds, bounded work, upgrade ordering and stalled processes. It included reproducible probes
for first-election liveness, pool A-to-B-to-A rotation, multi-borrower rounding, director reappointment and expired
encumbrances. The finance probes passed four tests, including 2,048 rounding fuzz cases.

This was not a fresh audit of every upstream OpenZeppelin implementation, a live frontend walkthrough or a real
USDC mainnet-fork test. Dependency pins and deployed profile boundaries were checked. The audit target includes
148 contract files, 60 Solidity test files and eight Solidity script/parameter files; test-instance totals include
inherited cases and are not counts of independent security scenarios.

## Verification evidence

The candidate uses Solidity 0.8.38, Foundry 1.9.0, OpenZeppelin 5.7.0, forge-std 1.17.0, Slither 0.11.6 and
crytic-compile 0.4.2. Exact dependency revisions are in `foundry.lock`; recursive source is included in the archive.
Deployable builds retain Osaka, optimizer 200 and normal deployment-size/transaction-gas limits.

The evidence distinguishes the initial 5 November source from the final election fix and two comment corrections.
The full suite, coverage, static scan, ABI export, build and three local deployment rehearsals were repeated on
the final contract source. The changed Congress invariant campaign was repeated with all three audit seeds.
Other deep campaigns retain their original source identity and documented dependency comparison; they are not
mislabelled as a second full deep run of the final tree.

| Check | Result |
| --- | --- |
| Final full suite | 800 ordinary/fuzz instances plus 24 invariant properties: 824 effective checks, 67 suites; zero failed/skipped |
| Foundry native count | 808 results: the framework groups 24 predicates into eight invariant campaigns |
| Initial deeper invariant campaign | Three seeds, 256 runs at depth 256 across eight campaigns: 1,572,864 reported handler calls; all 24 predicates pass per seed |
| Final changed-election campaign | Congress counting repeated for all three seeds at 256 runs × 256 calls: 196,608 additional handler calls |
| Independent probes | First-election proof and old-code regression control; four finance/property probes including 2,048 fuzz cases |
| Final static analysis | 464 unsuppressed labels: 6 High, 70 Medium, 292 Low, 96 Informational; 459 normalized identities match the reviewed baseline |
| ABI and layout | All 148 contract ABIs, selectors and normalized storage layouts unchanged; 58 exports match compilation |
| Final local rehearsals | Production genesis, isolated foundation and governed Sepolia upgrade/rollback; 220 successful transactions and 14 matching recorded runtime hashes |
| Tooling and reference models | 20 tooling tests and 34 reference-model tests pass |
| Publication checks | Formatting, whitespace, documentation/ABI checks, constitutional-source hash and publishable-file/reachable-history pattern scan pass |
| Final first-party coverage | 62 non-mock files: lines 89.04% (7,012/7,875), functions 94.02% (1,116/1,187), branches 54.27% (819/1,509); zero anchor warnings |

Only CongressElectionApp's deployed instructions changed: 16,600 to 16,732 runtime bytes. The two finance changes
affect compiler metadata only. All contract runtime/initcode sizes remain within their limits. The largest runtime
is CongressCandidateRegistry at 23,904 bytes, leaving 672 bytes of headroom. Layout comparisons include 44 nonempty
layouts and retain slots, offsets, labels and types; matching layouts do not perform a migration.

Coverage retains one documented instrumentation exception: the 1,000-candidate stress instance runs in the full
optimized suite; instrumentation runs the equivalent 100-candidate path. Raw coverage, anchor diagnostics and
function inventory are included in the evidence. The [function inventory](review/FUNCTION-COVERAGE.csv) retains
71 zero-hit instrumented functions. Coverage is finite and does not establish complete branch or
state-machine coverage. Stateful handlers can catch expected rejections; handler-call counts are not counts of
successful user actions. Examine their failure flags and non-vacuity assertions.

Scanner labels are not confirmed vulnerabilities. The final report retains all labels and compares both severity
counts and normalized finding identities. The election fix changed one Low timestamp description; 463 report
instances and 458 distinct identities are unchanged. The updated fingerprint was accepted only after reviewing
that exact delta. No detector was suppressed or severity gate weakened to pass this review.
See [static-analysis triage](Static-Analysis-Triage.md). Compiler/linter warnings are retained with the raw output.

## Material limits for the external auditor

1. **Governance can still become unavailable.** A broken voting, identity, stake, electorate or policy dependency
   can prevent the vote needed to repair it. The permanent kernel/router/timelock cannot replace themselves.
   Senate and constitutional review can cross-block each other's replacement. The separate recovery ballot remains
   deferred; successful upgrade rehearsals do not prove universal recovery.
2. **Replacing a pointer does not migrate records.** Compatible custody handoff, retired loan settlement and payout
   reconciliation have specific guarantees. They do not import arbitrary identity, land, company, debt or pending
   proceedings. Typed bundles atomically change at most 16 eligible existing pointers; ordinary action batches have
   independently executable members. Neither mechanism copies state or authenticates arbitrary replacement code.
3. **Lending still needs economic approval.** A fixed LLM/USDC price is not realizable collateral value. Liquidity,
   liquidation incentives, reserves and limits need assessment. Partial/multi-borrower exits with ongoing debt can
   still need working policies. The existing fallback only covers the stated debt-free/final-global-loan cases.
4. **External assets remain external dependencies.** Local rehearsals use synthetic balances and a USDC test
   double, including at the canonical address. They do not test Circle's live pause/blocklist/proxy behavior or
   certify production asset code. A real-asset fork and controller review remain necessary.
5. **Property and office authority depend on legal operations.** A current director can retain seller authority
   after company suspension/dissolution; removing the last signer can strand property. Accepted disputes and
   encumbrances require explicit resolution/release. Their timestamps do not automatically unlock title.
6. **The proposed Phase A legal workflows are incomplete.** The restriction ledger and synthetic drivers exist.
   Collective admission, discipline, annulment, official writer and full membership-to-eligibility integration do
   not. Mainnet `Deploy` does not install that future membership workflow. Existing identity/civic authority is not
   the complete proposal in the presentation. Exact legal inputs remain in the accepted decision register.
7. **Gas and coverage leave maintenance constraints.** CongressCandidateRegistry is close to the runtime size
   ceiling. Bounded counting handles large admission sets; it does not prove every future configuration fits a
   transaction. The branch coverage gap and inactive/error paths remain explicit external-audit targets.

See [Recovery Plan](Recovery-Plan.md), [Recovery Decisions](Recovery-Decisions.md),
[Phase A legal inputs](phase-a/LEGAL-DECISIONS.md), [Audit Scope](Audit-Scope.md) and
[Release Readiness](Release-Readiness.md) for the detailed rules and retained limitations.

## GitHub and audit handoff

At the 5 November check, local HEAD and GitHub `main` were
`dd0005c15d20754c50a0495cf6d48298b795e1a4`. The latest observed successful
[GitHub CI run](https://github.com/Balazs091/Liberland-blockchain/actions/runs/35234352415) belongs to that September
commit. The reviewed November changes remain unpublished, including new files and updated dependency checkouts.
The clean-tree freeze correctly refuses this working tree. No commit, staging, push or public deployment was made.

The repository is public, main branch protection was off and the root has no LICENSE file, while contracts declare
MIT through SPDX. Before publication, the repository owner should confirm a repository-level license notice and
require review/passing CI for the release branch. No rights holder or licensing decision was invented here.

The new working-tree package is named `Liberland-EVM-Working-Tree-Audit-Snapshot-2026-11-05.zip`. Its provenance,
source/dependency inventory, package checksums and separate archive checksum identify the candidate. It includes
the final source, pinned recursive dependencies, manual reviews, raw test/scanner/coverage records, source
comparisons and local rehearsal receipts. The extraction verification builds and tests those included files without
Git metadata or project credentials. The older 3 November archive remains a different, unchanged historical target.

The workspace evidence directory is `Comprehensive-Review-2026-11-05`, alongside the repository. Portable copies
are under the archive's `evidence/`. Initial and final results retain distinct names; final checks use `final-`.
[`Auditor Handoff`](Auditor-Handoff.md) gives reproduction commands and the required submission scope.

For Git publication, include every reviewed new file and the pinned submodule revisions, create the candidate
commit, run CI and `scripts/audit-freeze-check.sh` on its clean checkout, then record its commit/tree. For mainnet,
also complete external remediation review, real-asset/genesis verification, the dependent legal rules, operational
and signer procedures, and the separately reviewed deployment approval. Those are remaining gates, not results
claimed by this internal audit.
