# Internal Audit: Upgrade Safety and Release Readiness

Review date: September 8, 2026. Baseline: `8b6798f9f4a92d171c15560c090ef53f9f82c645`.
This report describes the subsequent local remediation candidate. Its exact commit, tree and dependency revisions
are recorded in the package's `PROVENANCE.json`; baseline findings must not be mistaken for unfixed findings in that candidate.

**Disposition: candidate for independent human-led audit, not mainnet approval or an “unfreezable” certification.**
The owner explicitly chose to retain existing governance routes after considering an additional permanent citizen
upgrade ballot. No such ballot, administrator, generic executor or broad negative-power exemption was added.

This is AI-assisted internal engineering, including parallel source review and cross-review, executable regression
tests, stateful fuzzing, unsuppressed static analysis, gas measurements and documentation checks. It is not an
independent audit. Neither writing style nor automated detection can establish who wrote another firm's report;
this review makes no unsupported authorship claim.

## Findings against the baseline and remediation

Severity below is contextual impact, not an assertion that an arbitrary outsider can trigger every fault.

| ID | Baseline finding and precondition | Disposition and executable evidence |
| --- | --- | --- |
| U-01 — High, conditional liveness | An approved optional Senate/review hook can return successfully with malformed ABI data or consume nearly all forwarded gas. Ordinary `try/catch` does not protect the caller's return decoder, and repeated gas-burning hooks could stop otherwise executable actions. | Fixed with one bounded fixed-buffer reader, exact response length, canonical integer/bool validation and a 100,000-gas allowance. Callers must supply the full allowance; underfunding reverts. `UpgradeLivenessAudit.t.sol` checks empty/invalid/oversized returns, gas exhaustion, direct referendum finalization and valid negative powers. |
| U-02 — High, lending accounting | Rotating lending writer/liquidator authorities can make old debt impossible to fully repay/liquidate. A successor can lend against collateral backing outstanding old debt; an old pool can top up without touching its revoked lien writer if its computed lien is unchanged. | Fixed with one stable owning loan book per person and all-three-pointer authorization for new debt. Ownership and the captured floor persist until explicit debt closure, even with zero remaining lien. Historical repayment/typed liquidation continue without granting old pools general transfer authority. `WorkflowLivenessAudit.t.sol` and strengthened `LendingInvariant.t.sol`. |
| U-03 — High, custody activation | Repointing a vault does not move ERC20 custody. The staking successor can inherit withdrawal authority over a shared ledger without receiving backing; a retired treasury has no ordinary way to move its entire reserve into its successor. | Narrow permissionless `handoffBacking()` and `handoffAsset(asset)` transfer only to the already-governed compatible successor, require exact receipt and preserve existing ledgers/receipts. Retired staking operations and Treasury disbursement are blocked; Treasury deposits remain handoff-recoverable. These helpers do not migrate arbitrary state. `StakingVaultUpgrade.t.sol`, `TreasuryUpgrade.t.sol`. |
| U-04 — Medium, election completion | Finalizing the old election also creates the next using live policy/electorate state. Failure of that unrelated future process rolls back the completed old result. | Finalization and `createNextElectionCycle()` are explicit separate operations. Existing cadence and incumbent registration remain in next-cycle creation. A 1–32 workload overload and simpler counting paths reduce cost without changing election rules. `EfficiencyAudit.t.sol`, Congress unit/invariant suites. |
| U-05 — Medium, payout accounting | Replacing a payout queue/accounting writer can strand the original queue's outstanding commitment even after its pinned action executes, expires or is canceled. The queue itself stores requests but was classified Application. | Commitments retain their original writer for settlement only; retired writers cannot reserve new amounts or reconcile another writer's new commitment. Queue is now State-class under the existing constitutional threshold. Historical execution remains checked against the original vault. `TreasuryAndOffices.t.sol`, `TreasuryUpgrade.t.sol`. |
| U-06 — Medium, successor consistency | Senate tally loops use live policy seat count, although canonical occupancy is a fixed registry fact. A successor policy reporting a different count can omit real votes or make tallying unbounded. | Tally uses the registry's fixed total seats. Regression policies reporting zero, one and the maximum uint32 leave legitimate direct-seat support intact. `SenateAndPublicVeto.t.sol`. |
| U-07 — Medium, upgrade replay continuity | A fresh queue, executor and vault can reuse a paid request ID after old commitment settlement. Fresh officer approvals remain necessary, but request-ID deduplication is lost. | Stable one-shot execution receipts bind consumed IDs in the retained budget registry, independently of the current queue or vault. Current-vault-only recording is atomic with token transfer; historical queue reconciliation remains separate. Different IDs for the same invoice still require off-chain checks; registry replacement requires receipt migration. `TreasuryUpgrade.t.sol`. |
| U-08 — Documentation | Current-facing guides included stale deployment assertions, wrong Finance call arguments/execution target, misleading seed-voter instructions, double-broadcast verification guidance and overbroad upgrade continuity statements. | Every maintained first-party Markdown document was reviewed. Stale passages were removed or corrected, current ABI contracts are regenerated, and a dedicated dependency/recovery guide was added. The pinned constitutional source is retained as provenance, not rewritten as current protocol law. |
| U-09 — High, conditional ledger mismatch | A partial registry replacement can leave a pool writing liens into its pinned old ledger while canonical unstaking consults a fresh ledger. New debt can therefore lack the encumbrance observed by withdrawals. | New origination requires matching canonical identity, stake and lien registries; detached lien registries cannot originate liens. This blocks new mismatched lending, not loss of preexisting records through a bad migration. `LoanRetirementIndependentAudit.t.sol`. |

Cross-review also tightened the newly introduced retirement mechanism before freeze: retired health, liquidation
and bad-debt calculations use the smaller of active surplus and recorded lien, and every retired settlement requires
`seizedStake + remainingLien <= priorLien`. A reproduced intermediate implementation could seize 14,375 LLM after
new staking despite an old 5,000 LLM lien; the final regression prevents that extension of historical authority.
Current-pool all-active-surplus economics remain unchanged. Repayment/closure and additional unpledged stake are
tested together; a zero numerical lien cannot lock a retired bad-debt position forever.

The malformed-return behavior is documented by [Solidity's exception rules](https://docs.soliditylang.org/en/latest/control-structures.html#try-catch).
The caller-gas check accounts for [EIP-150's forwarding rule](https://eips.ethereum.org/EIPS/eip-150).
These sources explain EVM/compiler behavior; the repository tests are the evidence for this implementation.

## Retained recovery limitations — launch decisions, not resolved defects

**R-01: governance can still freeze.** Broken approved referendum code, its required identity/stake/policy dependencies,
or unavailable certified electorate state can prevent creating the vote needed to replace them. Kernel/router/timelock
are permanent execution roots. Even citizen-policy activation invokes an electorate rebuild hook. A recoverable
missed callback is not the same as a defective registry or policy.

**R-02: two negative-power modules can cross-lock replacements.** The exact Senate self-replacement exemption does
not exempt constitutional review, and the exact review self-replacement exemption does not exempt Senate. Both
distinct blocking modules and both action-batch orders are exercised in `UpgradeLivenessAudit.t.sol`. The owner
chose to keep these rules. This is a high-impact conditional architectural limitation, not an issue declared fixed.

**R-03: pointer replacement is not universal migration.** Most app/registry relationships include immutable references
or app-local pending state. Supported custody/loan/commitment continuity does not supply an importer for identity,
land, company, electorate, civic cases, debt or LP records. State migration requires a separately designed,
independently reviewed and reconciled procedure. Exact successor getters are compatibility checks, not proof that
successor bytecode is safe. Existing deployments do not acquire these fixes without a reviewed transition.

**R-04: independently executable transitions.** `executeActions` is atomic for that transaction, but its individual
approved actions can also be executed separately. Review every intermediate pointer configuration and overlapping
execution window; operator batching alone is not an on-chain dependency lock.

**R-05: compatibility of optional hooks.** Failed, over-budget or malformed optional negative-power reads are treated
as absent. Correct active records remain enforced. The immutable core cannot distinguish accidental failure from an
intentionally incompatible replacement. Future hook bytecode must fit the fixed ABI/gas contract, including after
chain gas repricing. This is explicitly documented, not concealed by a catch-all “safe upgrade” claim.

See [Upgrade and Liveness](Upgrade-And-Liveness.md) for the module-by-module map and activation procedure.
No administrator override was added to resolve these limitations.

## Verification of the remediation candidate

Toolchain: Forge 1.7.1, Solidity 0.8.36, Slither 0.11.5; Osaka, optimizer 200, no via-IR in deployable builds.
Normal runtime/creation/transaction limits were retained. These final-source checks supersede intermediate runs;
the packager additionally requires a clean, exact-commit freeze gate before producing the release ZIP.

| Check | Final result |
| --- | --- |
| Optimized full suite | **529 passed, 0 failed, 0 skipped**, 46 suites |
| Extended stateful campaign | **23 invariants plus 2 non-vacuity tests passed**, 7 suites; 256 runs at depth 256, seed `0x709`; each invariant reported 65,536 handler calls and zero handler-level reverts |
| Coverage campaign | **528 passed, 0 failed**, 46 suites; one 1,000-candidate stress instance excluded only from instrumentation, required in the optimized suite; the 100-candidate fixture covers the same count path |
| Aggregate instrumented coverage | Lines **81.53% (7,914/9,707)**; statements **84.32% (9,193/10,903)**; branches **47.83% (762/1,593)**; functions **88.47% (1,251/1,414)** |
| First-party production coverage | Summed over 52 reported `contracts/` files excluding mocks: lines **83.63% (6,241/7,463)**; statements **86.81% (7,438/8,568)**; branches **45.91% (611/1,331)**; functions **87.66% (980/1,118)**. Unreported/interface files are not invented coverage |
| Build and formatting | All deployable runtimes below 24,576 bytes and creation code below the normal limit; formatting and whitespace checks pass |
| Documentation and interfaces | **22 maintained Markdown documents**, **52 ABI exports**, exact compiled-source parity |
| Verification-tool tests | **11 passed**; documentation/ABI inventory and static-fingerprint tests |
| Unsuppressed static analysis | **432 labels**, 427 distinct normalized fingerprints: 6 High, 66 Medium, 266 Low, 94 Informational; full JSON reviewed, all High/Medium findings cross-reviewed independently within the AI-assisted team |
| Constitutional provenance | Pinned source PDF SHA-256 verified, without replacing the legal source or certifying constitutional validity |
| Production-script rehearsal | Fresh localhost-only two-stage mock-token/synthetic-genesis deployment passed: seven incumbents, continuity cycle, five case-review accounts, exact committee/app binding, sealed setup and retired kernel/router/office bootstrap |

The production branch coverage is an explicit human-audit assurance gap, not obscured by script/test coverage.
The package contains final test, coverage, invariant, size, ABI/docs, static and rehearsal evidence plus paired gas
measurements. The before/after cross-review logs are diagnostic history, not additional release source versions.

Test-instance counts include inherited cases and are not counts of independent security scenarios. Congress fixtures
and lending fixtures were separated from tests to remove repeated inheritance; counts are not directly comparable
to the baseline's.
Coverage includes script/test instrumentation and remains an incomplete assurance measure. Stateful handlers catch
expected rejected operations; failure flags and non-vacuity tests are needed to detect silent absence of progress.
Neither a finite fuzz campaign nor a clean static-baseline comparison proves absence of vulnerabilities.

## Measured efficiency and remaining simplification opportunities

The paired election measurements use setup in a separate transaction; measuring immediately after constructing
a fixture undercounts cold persisted-state costs.

| Persisted-state scenario | Baseline gas | Candidate gas |
| --- | ---: | ---: |
| 32 inserts into a 960-entry heap | 4,843,729 | 4,813,154 |
| One-candidate adaptive batch | — | 363,554 |
| Revalidate 31 disqualified provisional candidates | 3,824,595 | 2,936,510 |
| Scan 31 retained runner-ups with maximum metadata | 6,579,049 | 1,627,332 |
| Maximum supported 31-seat + 1-runner activation | — | 14,431,650 |

Changes: reserve an empty heap leaf instead of writing twice; remove ineligible provisional entries in reverse order;
read person/score facts instead of up to 2,048 bytes of irrelevant metadata; separate finalized results from future
scheduling. These preserve the voting rules. The insertion batch is adjustable, but outcome revalidation/activation
still has its own bounded cost. These are finite workload measurements, not arbitrary-population, future gas-price
or keeper-incentive guarantees.

CongressCandidateRegistry remains 23,904 runtime bytes: only **672 bytes below the 24,576-byte limit** specified by
[EIP-170](https://eips.ethereum.org/EIPS/eip-170). Retain this as a maintenance constraint. A wholesale state-registry
rewrite would enlarge the audit surface; isolate future additions only when measured requirements justify it.
Senate support aggregation remains a bounded live scan: cached totals would complicate occupancy/reappointment
invalidation. Paginated UI reads and UX cancellation of unaccepted initial-wallet proposals remain possible later
work, not silently included features.

## Other current controls and audit scope

The full current source remains in scope, including the previous approved civic due-process rules, independent
3-of-5 case committee, seven-day notice, one appeal, 30-day dismissal timeout and two-day post-upheld delay;
consent/nonces and current office-appointment checks; two distinct current Finance officers; direct occupied-seat
Senate majority with at least two votes and no President proxy; source-authorized decisions; land consent and
versioning; interest/reserve/rounding arithmetic; electorate snapshot maintenance; and two-stage sealed genesis.
These controls are not certified simply because their regression tests pass.

## Remaining mainnet requirements

- Independent human audit of every production source and deployment path, including fresh fixes and known recovery
  limits; independent remediation verification and explicit residual-risk acceptance.
- Real token/proxy/admin review and a production-state fork. The fixed oracle can become economically wrong; verify
  liquidity, interest, collateral, bad debt, liquidator incentives and all current deployment caps.
- Verified real genesis records and stake backing; independent controlling signers for offices and five reviewers;
  key loss, rotation, conflict and incident procedures. Distinct addresses do not prove independent people.
- Lawful notice/evidence publication and legal/constitutional approval. Hashes do not prove truth or availability;
  owner-approved protocol choices are not external legal certification.
- Resolve operational land/company signer continuity. A dissolved or directorless company holding land has no
  invented registrar takeover or universal court executor in this code.
- Frontend live-wallet/end-to-end checks, monitored keepers, rehearsed transitions, reproducible build/address
  manifests and operational sign-off. Local mock genesis is not a public deployment or production-state fork.

Nothing in this preparation pushes GitHub changes or upgrades a public chain. Start independent review with
[Auditor Handoff](Auditor-Handoff.md), [External Scope](Audit-Scope.md) and the complete unsuppressed
[Static Triage](Static-Analysis-Triage.md).
