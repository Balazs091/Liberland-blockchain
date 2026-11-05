# Governance and recovery hardening

Prepared 3 November 2026, following [Predeployment Review](Predeployment-Review.md). This is a source-specific
engineering review, not an external audit, a production launch approval or proof that every possible stuck state
can be recovered. No public-network deployment has been performed.

The later [Complexity Review](Complexity-Review.md) simplifies internal duplication while retaining the same
safeguards. Its source-specific verification supersedes the bytecode measurements and working-tree evidence here.
A separate recovery ballot remains deferred by user instruction.

## Changes

| Problem | Implemented change | Remaining boundary |
| --- | --- | --- |
| The isolated token/restriction lab cannot exercise governance | A separate full governed Sepolia deployment uses fixed-supply LiberlandMerit, controlled synthetic voter accounts, sealed bootstrap, normal referenda and the timelock | Existing isolated deployments are not retrofitted. Mock USDC, accelerated parameters and the four-subject Congress controller are test-only |
| Separate approved pointer actions can execute in a partial order | One typed bundle action installs an immutable plan of up to 16 sorted existing non-Core pointers, all or none | A bundle changes pointers, not storage/custody. Senate/review replacements retain separate routes; no veto exception is borrowed |
| Replacement code or incumbents may differ from the approved plan | Plans bind chain/kernel/registry, complete update entries and evidence; ballot validates structure, queue and execution verify incumbents and runtime hashes | Code hashes and matching dependency getters do not certify honest code, compatible storage or a lawful migration |
| A broken future financial policy can prevent an otherwise independent final exit | A debt-free LP withdrawal or repayment closing all global debt uses the already validated accrual interval, preserving interest/reserves, exact receipt and lien closure | Partial repayment, closing only one of several loans and LP withdrawal while debt remains still require live policies; no ongoing-debt fallback is silently chosen |
| Recovery procedures and new legal authority were mixed together | The recovery runbook specifies existing synchronization, compatible repair/rollback, custody handoff and reconciliation paths; RC01–RC07 identify additional decisions | No emergency administrator, arbitrary executor, discretionary sweep, debt forgiveness or veto override is added |

The original `executeActions` convenience batch remains available and its members remain independently executable.
The new `ModuleBundleUpdate` is a distinct single action with no separately executable members. Existing action and
referendum enum values are retained, with new values appended. Existing constructors and public methods remain;
new bundle methods and read-only helper/manifest fields are additive. This changes fresh-deployment bytecode,
including the immutable core, and cannot patch old deployed core contracts.

`ReferendumApp` creates its own immutable read-only `ReferendumProposalValidator`. The helper shares no writer or
execution authority and cannot be changed by an operator. This keeps deployable app runtime below the normal size
limit while retaining the existing proposal checks and revert selectors.

## Verification

Final combined-source results and source hashes are recorded in the adjacent workspace evidence directory
`Governance-Recovery-2026-11-03`. The optimized complete suite passed **816 tests in 67 suites**, zero failures or
skips, seed `0x110305`, including the 1,000-candidate stress case. Earlier task logs and the older review's test counts
are historical evidence, not final attestation for this change. Extended campaigns and static-analysis results are
recorded separately against the same contract source.

| Check | Final result |
| --- | --- |
| Complete optimized suite | 816 passed; 67 suites; no failures/skips; seed `0x110305` |
| Extended stateful campaign | 24 invariants plus six supporting/non-vacuity tests passed in eight suites; 256 runs × 256 calls per invariant; seed `0x110306`; 1,572,864 reported handler calls, zero handler-level reverts |
| Independent reference/tooling checks | 34 reference-model tests and 11 verification-tool tests passed |
| Instrumented coverage | 815 tests passed; only the documented 1,000-candidate stress instance excluded, with the 100-candidate path instrumented. Non-mock first-party source: 88.25% lines, 93.95% functions, 52.72% branches |
| Build limits | All deployable runtimes within 24,576 bytes. ReferendumApp: 21,255; immutable validator: 8,074; ActionTimelock: 18,985; plan registry: 2,937; lending pool: 18,226 bytes |
| Public interfaces | 58 exported ABIs have exact compiled-source parity; 834 function entries enumerated in the updated review inventory |
| Unsuppressed static analysis | 176 contracts, 101 detectors; 468 labels: 6 High, 74 Medium, 293 Low, 95 Informational; 463 distinct normalized fingerprints |
| Mined localhost rehearsals | Fresh production two-stage setup, isolated foundation, and governed Sepolia passed. Governed controller replacement and rollback used citizen votes and the normal delayed single-action bundle |

Scanner labels are retained. Every added/changed report, all six High reports and the 22 Medium reports touching
changed/new sources were manually reviewed; no new confirmed vulnerability was identified. The baseline matches
the completed report's counts and normalized identity multiset, rather than only its severity totals. See
[Static Analysis Notes](Static-Analysis-Triage.md). This is not a zero-finding scan or external audit clearance.

The extended handlers exercise bounded state spaces and catch expected failures; reported handler calls are not
unique user transactions, and zero handler-level reverts does not prove every attempted operation succeeded.
Separate successful journeys and persisted failure flags remain important evidence.

The new registry/validator/bundle-library group reports 100% function coverage and the governed synthetic controller
reports 100% function coverage, including all of its mutators. Their branch coverage is 59.26% and 63.64%
respectively. The permanent core reports 93.04% lines and 79.33% branches. Overall production branch coverage of
52.72% remains an assurance gap. Seventy-one instrumented non-mock functions have zero recorded hits; a source-level
screen found no public/external non-view mutator among them, but this does not establish role/input/order coverage.
Foundry emitted 197,661 coverage-anchor warnings, including dependency and test-helper instrumentation; missing
anchors may under-report execution. Full warnings and LCOV are retained. These are tool-reported measurements,
not proof of exhaustive execution or the accuracy of every coverage anchor.

The production rehearsal uses synthetic genesis and a local test double at the canonical USDC address. It is not a
fork verification of Ethereum's actual USDC implementation or controller powers. Governed and isolated Sepolia
rehearsals independently matched all ten recorded runtime hashes against mined code. Source hashes remained stable;
no checkout credentials or public RPC were used.

Targeted tests cover real citizen/Congress ballots, constitutional thresholds, app/writer continuity, forward and
preopened reverse plans, stale targets, runtime drift, malformed plans, bounded counts, callback rollback, retained
negative controls, lending economic equivalence and failed-transfer rollback. Deployment rehearsals use disposable
localhost chains only, with complete sealing and manifest/read-back checks.

## Recovery limits and decisions

Use [Recovery Plan](Recovery-Plan.md) before every upgrade and incident. It requires exact dependency inventory,
preserved records/receipts, rehearsal of both directions, a valid execution window and reconciliation of real assets.
Preopened rollback helps only while a suitable authorised finalizer and its dependencies still work. It cannot
repair arbitrary broken governance, replace the permanent core or recover assets an external issuer will not move.

[Recovery Decisions](Recovery-Decisions.md) contains the forwardable options and recommendations: a narrow separate
citizen repair route; mutual-veto adjudication; ongoing-debt exit terms; stalled land proceedings; concrete pending
process migration; lawful role/key succession; and immutable-core/external-asset disaster claims. None is activated
merely by documentation. Existing accepted network, asset and genesis decisions remain unchanged.

The new profile is suitable for synthetic governance staging after the recorded checks pass and controlled test
addresses are supplied locally. Production still requires the agreed legal inputs, reviewed real genesis, an
independent security review and a frozen source-specific release/deployment manifest.
