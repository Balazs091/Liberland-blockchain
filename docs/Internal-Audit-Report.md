# Current Internal Code Review

Review date: September 8, 2026. Target: the local audit candidate built from the working tree on
`agent/frontend-howto-audit-build`, incorporating the owner's approved remediation.
The packaged `PROVENANCE.json` identifies the exact frozen commit, tree, tag and dependencies.
**Verdict: prepared for independent human-led audit; not approved for mainnet.**

This is AI-assisted internal engineering work, not an independent security certification. Source tracing,
regression tests, stateful fuzzing, static-analysis comparison, documentation/ABI checks and a synthetic local
deployment were used. A passing suite does not prove absence of vulnerabilities. External report claims are not
accepted merely because they appear in a report, and this document makes no claim about another firm's authorship.

## Remediation disposition

| Area | Current implementation and evidence |
| --- | --- |
| Binding civic appeals | Seven-day notice, one appeal, a pinned purpose-limited 3-of-5 committee, exact case/outcome/evidence digest, 30-day deadline, dismissal on timeout, and the later of notice expiry or two days after an upheld ruling. Subjects cannot withdraw their own case by becoming an officer. Identity unit tests and IdentityLifecycleInvariant exercise these boundaries. |
| Identity consent and replay | Initial destination consent; exact nonce-bound migration consent; two-officer exceptional recovery. Current appointment IDs are rechecked at finalization; same-block revocation/regrant and office reactivation cannot revive approvals. Known aliases cannot act as distinct proposing/approving officers. Renunciation retires the one-time citizenship grant, so reinstatement cannot bypass the civic process. |
| Finance separation | Every payout has an actual proposer and distinct current approving officer. Routing rechecks both appointment IDs and the original proposer's spending policy/limits. Sensitive payouts require an admin proposal; a clerk may independently approve or route. Approval withdrawal works only before routing; already-routed actions use the cancellation path. TreasuryAndOffices tests cover aliases, reappointment, expiry and policy checks. |
| Senate concentration | Every negative power uses strict occupied-seat majority, a floor of two direct seats and any higher policy minimum. President proxy entry points/storage are removed. Occupancy-bound support and live thresholds are rechecked. Senate tests include occupied-seat fuzzing and obsolete-entrypoint rejection. |
| Borrow quote correctness | One preview index supplies personal/global capacity and pending reserve-adjusted liquidity. The quote inverts scaled-debt rounding rather than subtracting rounded asset debts. Unknown/ineligible borrowers quote zero. Lending regressions/fuzzing check the exact quote and quote-plus-one boundaries; the stateful handler flags failed positive same-state quotes. |
| Election assurance and size | Final outcome assembly moves to the existing immutable ranking helper; the canonical registry still revalidates and records facts. Dedicated count invariants cover policy replacement, migration, disqualification and independent sorting. Optimized tests exercise 100 and 1,000 candidates in bounded chunks and maximum-length candidate metadata. |
| Handoff consistency | Current-only docs, 52 regenerated ABIs, committee manifest/schema fields, mandatory five-reviewer deployment inputs, pinned static baseline and repeatable verification tooling. No live manifest or old review verdict is treated as source authority. |

These changes build on the existing custody, electorate, source-consent, public repeal, land, treasury-reconciliation,
module-classification and two-stage genesis hardening. Their full surface remains in scope for independent review,
not just the latest edits. See [External Scope](Audit-Scope.md) and [Governance](Governance.md).

## Verified evidence

Toolchain: Forge 1.7.1, Solidity 0.8.36, Slither 0.11.5; Osaka, optimizer 200. Deployable builds use no via-IR,
code-size override or transaction-gas-cap bypass.

| Check | Result |
| --- | --- |
| Full optimized suite | **498 passed, 0 failed, 0 skipped**, 36 suites; inherited test instances are included, not 498 independent scenarios |
| Extended stateful campaign | **23 invariants plus 2 deterministic non-vacuity tests passed**; 7 suites, 256 runs at depth 256, seed `0x709`; each invariant reports 65,536 handler calls and zero handler-level reverts |
| Coverage campaign | **496 passed, 0 failed**; the two inherited 1,000-candidate stress instances are explicitly filtered only from coverage because instrumented fixture setup exceeds the harness gas budget. The optimized full suite requires them; the 100-candidate fixture instruments the same counting path |
| Aggregate coverage | Lines **80.41% (7,392/9,193)**; statements **83.36% (8,599/10,316)**; branches **46.51% (726/1,561)**; functions **87.73% (1,165/1,328)** |
| Optimized build | All deployable runtimes below 24,576 bytes and creation code below the normal limit |
| Frontend interfaces | **52 exports** regenerated and checked against compiled source |
| Verification-tool tests | **11 passed**; link/ABI inventory and finding-fingerprint regression checks |
| Static analysis | **423 unsuppressed results**, 418 distinct normalized fingerprints: 6 High, 60 Medium, 265 Low, 92 Informational; see [Triage](Static-Analysis-Triage.md) |
| Constitutional input | Pinned PDF SHA-256 verified; no substitution or claim of legal certification |
| Production-script rehearsal | Fresh two-stage **localhost-only** mock-token/synthetic-genesis deployment; seven incumbents, continuity cycle, committee/app binding, five reviewer manifest entries, sealed setup, retired kernel/router/office bootstrap |

Coverage includes test/script instrumentation; it is not production-only coverage. Branch coverage remains an
assurance gap for the external firm. Stateful handlers catch expected rejected actions, so zero handler reverts
does not mean every attempted protocol operation succeeded; separate failure flags and non-vacuity tests help
detect vacuous campaigns. Randomized testing is bounded, not exhaustive or formal verification.

The optimized 1,000-candidate fixture verifies each measured finalization call below 12 million execution gas,
with no admission quota; this is a finite-size test, not a proof for arbitrary population or economic keeper
incentives. Cold-state and real-chain transaction overhead must be remeasured on the intended deployment.

Principal packaged evidence: full-suite, extended-invariant, coverage, optimized-size, ABI/docs, tooling and static
logs, the full Slither JSON, local rehearsal outputs and the clean-tree freeze-gate result. The initial failed
coverage stress attempt is not a passing check; the documented filtered coverage command is the reproducible one.
The package records checksums so evidence cannot silently be paired with another source revision.

## Runtime headroom and further code improvements

| Contract | Runtime bytes | Remaining bytes |
| --- | ---: | ---: |
| CongressCandidateRegistry | 23,904 | **672** |
| SenateApp | 20,215 | 4,361 |
| IdentityApp | 19,339 | 5,237 |
| USDCLendingPoolApp | 15,565 | 9,011 |
| OfficeExecutor | 10,741 | 13,835 |
| CivicAppealReview | 3,792 | 20,784 |

The registry's headroom is improved but still narrow. Treat 672 bytes as a maintenance constraint, not a resolved
long-term sizing problem. The authority-free immutable ranking helper is worth retaining; further decomposition
should follow measured needs and separate review, without moving canonical facts or adding a mutable executor.
A wholesale rewrite is not recommended.

Other non-blocking implementation opportunities include paginated election UI reads and a nonce-bound correction/
cancellation workflow for an unaccepted initial-wallet proposal. They are not silently added to this candidate.

## Explicit retained risks and launch requirements

- **Independent authority is partly operational.** Distinct addresses and known-person checks do not prove distinct
  real controllers, guardians or recovery paths. Office admins can appoint clerks. Verify disjoint controlling
  signers, responsive Identity/Finance officers and five independently controlled review accounts. Generic office
  appointments are wallet-bound; audit known/historical aliases and off-chain conflicts, not just active addresses.
- **Civic due process is not truth verification.** Hashes do not prove evidence availability, lawful grounds, notice
  delivery or reasoned judgment. Publish procedures and retain documents. Timeout intentionally dismisses unanswered
  appeals. Fixed reviewer rotation does not transfer existing notices; replacing IdentityApp requires state/process
  migration. Owner approval is not independent constitutional/legal approval.
- **Finance separation is scoped to treasury payouts.** Existing ministry balance spending and explicitly sourced
  Congress/ministry decisions retain their separately documented policies; they do not acquire a new universal
  two-signature requirement. After routing, revoking an officer is not action cancellation.
- **Economics and external assets remain launch blockers.** The fixed 1 LLM = 2 USDC oracle can become economically
  wrong. Mainnet uses 30% LTV, 40% liquidation threshold, 15% bonus/reserves and the documented caps; these values are
  not economic certification. Verify exact token bytecode/proxy powers, real liquidity/liquidators, bad debt and
  funding reserves on a production-state fork.
- **Module replacement remains trusted governance.** An exact-address vote does not migrate state/custody or prove
  compatible behavior. Current negative-hook fail-open conditions and exact self-replacement exceptions are
  deliberate boundaries. Defective approved referendum code can impair liveness; no recovery backdoor was added.
- **Land/company lifecycle and omitted law remain explicit.** Prevent a company from losing its operational
  directors/status while it holds land until a lawful recovery/disposition procedure is agreed. The candidate
  has no general court, arbitrary registrar seizure, broad slashing authority or universal emergency executor.
- **No operational launch is claimed.** No public deployment, frontend live-wallet smoke test, production-state fork,
  real genesis verification or external human audit was performed here. Existing public addresses are not upgraded
  by these changes. Human findings, accepted residual risks and final operational/legal sign-off must precede launch.

## Auditor starting point

Use [Auditor Handoff](Auditor-Handoff.md), verify the archive/commit provenance, and independently challenge the
state machines and assumptions above. Run the checked-in freeze gate on the clean repository, or the equivalent
commands documented for the source archive. The package is a candidate for that review, not its conclusion.
