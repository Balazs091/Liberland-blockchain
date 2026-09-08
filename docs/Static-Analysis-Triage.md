# Static Analysis Triage

Reviewed September 8, 2026 for this local audit candidate. This is AI-assisted internal triage, not independent
acceptance or a list of confirmed vulnerabilities. The external firm should challenge every disposition.

Slither 0.11.5 analyzed 155 contracts with 101 detectors, without suppressions: **423 results — 6 High, 60 Medium,
265 Low, 92 Informational**. The full JSON and text output accompany the audit package. The checked-in fingerprint
multiset retains descriptions, detector, severity, confidence and multiplicity while ignoring whitespace and line
movement. A matching baseline is a drift check, not proof of safety.

## High detector labels

| Detector | Count | Internal disposition and evidence |
| --- | ---: | --- |
| arbitrary-send-erc20 | 4 | DecisionApp's Congress pulls require source authorization of the exact decision ID; ministry execution requires the current minister to be the recorded source. MinistryTreasury.fund accepts only the governed DecisionApp funding authority. Approved amounts/recipients are immutable. Retain exact allowances and separately review replacement authority. Tests: Decisions and HighSeverityGovernance. |
| weak-prng | 1 | CongressElectionApp._nextDailyBoundary uses timestamp modulo for a deterministic UTC schedule, not randomness. Cadence/late-finalization tests cover the boundary. |
| incorrect-exp | 1 | Pinned OpenZeppelin Math.mulDiv deliberately uses XOR in the modular-inverse seed; exponentiation would be a bug. No local dependency patch made. Independently review pinned dependency provenance. |

## Medium detector labels

| Detector | Count | Internal disposition and limits |
| --- | ---: | --- |
| divide-before-multiply | 9 | All nine are in pinned OpenZeppelin Math.mulDiv/invMod: exact removal of factors of two, modular-inverse refinement and Euclidean division. Multiplying first or replacing modular arithmetic would change the algorithm. No local dependency patch or warning suppression was made. |
| incorrect-equality | 24 | Includes exact identity/appointment IDs, nonces, enum states, zero debt and custody/accounting matches. Newly added officer comparisons intentionally reject the same known person and stale/zero appointment IDs. These are exact authorization checks, not price equality. |
| reentrancy-no-eth | 8 | Value-moving lending entrypoints use nonReentrant; repayment's private helper is entered only through guarded public functions. The newly changed descriptions include the shared reserve-preview helper in the call graph, not a new unguarded value path. Registry references are immutable/trusted reviewed code; callback reads may observe transient state and must not be used as external pricing oracles. Other reports retain typed, state-checked module interactions. Review all external/module/token trust assumptions independently. |
| uninitialized-local | 2 | CivicAppealReview's fixed memory array and per-iteration boolean are Solidity zero-initialized. Only entries below the counted support are read; the maximum is five. No uninitialized storage pointer or assembly memory read exists. Distinct reviewer and matching-ruling tests exercise the vote count. |
| unused-return | 17 | Intentionally unused typed outputs or returned sub-record fields; callers validate the required state/status independently. Successful calls are not treated as proof of final election completion. Review return-value drift with interface changes. |

## Low and informational detector labels

| Detector | Count | Internal disposition and limits |
| --- | ---: | --- |
| shadowing-local | 1 | Local naming warning; no authority/storage alias inferred. |
| calls-loop | 114 | Includes five fixed civic reviewers, bounded Senate seats, bounded election chunks/selection, and caller-provided atomic action batches. Batch failure is atomic; caller gas cost is not a protocol-wide lock. The election heap grows logarithmically; the 1,000-candidate campaign is evidence, not an unlimited-population gas proof. |
| reentrancy-benign | 6 | State/authorization-checked cross-module workflows. Inspect callback order and the separately guarded asset paths; benign is a detector label, not an exemption from review. |
| reentrancy-events | 27 | Includes CivicAppealReview.executeRuling emitting after the exact immutable app call. Votes are deleted first; the app closes/resolves the case before returning, and its ruling path makes no external state-changing callback. No arbitrary executor exists. |
| timestamp | 117 | Delays, expiries, cadence and term-based authorization are intentionally time-dependent. Civic filing/ruling deadlines are strict; timeout is inclusive, and upheld cases retain the later of notice and post-ruling delay. Boundary tests exist. Small timestamp variation and operator responsiveness remain assumptions. |
| assembly | 51 | Primarily pinned cryptography/math/memory utilities plus reviewed callback gas handling. Not changed to satisfy scan labels. |
| pragma | 1 | Dependency version ranges differ; first-party Solidity and compiler are pinned to 0.8.36. |
| costly-loop | 17 | Bounded/genesis/explicit batch writes and incremental ranking. Whole-genesis gas and large-population costs need deployment/operational sizing. |
| cyclomatic-complexity | 5 | Constructor/workflow maintainability warning. Registry/ranking helper split creates headroom without adding authority. |
| solc-version | 5 | Dependency compiler ranges; actual build uses the recorded pinned compiler. |
| low-level-calls | 3 | Bounded electorate synchronization/signature utility paths, not a generic governance executor. |
| naming-convention | 3 | Style warnings; do not affect dispatch or authorization. |
| too-many-digits | 7 | Pinned library masks/constants; preserve audited bit patterns. |

The obsolete Senate vote-option helper was removed after proxy entry points were deleted. No detector suppression
was added. Compared with the preceding baseline, new findings principally describe civic-review loops/deadlines,
exact appointment checks and zero-initialized vote-count locals; removed proxy paths and the unused helper explain
the corresponding removals. Do not update counts/fingerprints for a future change without reviewing the complete
new JSON and recording the new disposition here.

Residual assumptions—independent signer control, lawful evidence/notice, token upgrade risks, fixed oracle economics,
and reviewed state/custody migrations—are launch requirements in [Internal Review](Internal-Audit-Report.md).
