# Static Analysis Notes

Slither output and implementation context for the submitted source. Detector severity labels are not confirmed
vulnerability ratings or an independent security verdict. Auditors should reproduce the scan and test each assumption.

Slither 0.11.5 analyzed 156 contracts with 101 detectors, without suppressions: **430 results — 6 High, 66 Medium,
264 Low, 94 Informational**. The full JSON and text output accompany the audit package. The checked-in fingerprint
multiset retains descriptions, detector, severity, confidence and multiplicity while ignoring whitespace and line
movement. A matching baseline is a drift check, not proof of safety.

## High detector labels

| Detector | Count | Implementation context and evidence |
| --- | ---: | --- |
| arbitrary-send-erc20 | 4 | DecisionApp's Congress pulls require source authorization of the exact decision ID; ministry execution requires the current minister to be the recorded source. MinistryTreasury.fund accepts only the governed DecisionApp funding authority. Approved amounts/recipients are immutable. Retain exact allowances and separately review replacement authority. Tests: Decisions and HighSeverityGovernance. |
| weak-prng | 1 | CongressElectionApp._nextDailyBoundary uses timestamp modulo for a deterministic UTC schedule, not randomness. Cadence/late-finalization tests cover the boundary. |
| incorrect-exp | 1 | Pinned OpenZeppelin Math.mulDiv deliberately uses XOR in the modular-inverse seed; exponentiation would be a bug. No local dependency patch made. Independently review pinned dependency provenance. |

## Medium detector labels

| Detector | Count | Implementation context and review questions |
| --- | ---: | --- |
| divide-before-multiply | 9 | All nine are in pinned OpenZeppelin Math.mulDiv/invMod: exact removal of factors of two, modular-inverse refinement and Euclidean division. Multiplying first or replacing modular arithmetic would change the algorithm. No local dependency patch or warning suppression was made. |
| incorrect-equality | 26 | Exact identity/appointment IDs, nonces, enum states, zero debt and custody/accounting matches. The zero-amount checks reject empty custody handoffs; removing them permits meaningless replays, not improved arithmetic. These are exact state checks, not market-price equality. |
| reentrancy-no-eth | 9 | Lending financial entrypoints and both custody vaults use nonReentrant. Repayment's private helper is reached only through guarded public methods. TreasuryVault marking calls the canonical budget registry before the vault-local receipt; the current registry makes no external state-changing callback, requires the current vault and permanently consumes an active request. Token transfer failure rolls back both receipts. Typed lien settlement holds its own guard across the canonical stake transfer. The unguarded accrueInterest cannot accrue more elapsed time in same-timestamp callbacks; the outer operation refreshes its final configuration. Reentrancy/transient read assumptions remain in scope; external callers must not treat mid-call quotes as pricing oracles. |
| uninitialized-local | 4 | CivicAppealReview's fixed memory array/per-iteration boolean are Solidity zero-initialized and bounded to five entries. StakeRegistry's loanBook and retainedStakeFloor locals are assigned by successful typed reads or the function reverts; a no-book branch returns before reading the floor. No uninitialized storage pointer exists. Broken-policy/no-loan and retained-zero-lien regressions cover both branches. |
| unused-return | 18 | Intentionally unused typed outputs or sub-record fields. Election progress uses canonical ranking status, not the ignored informational boolean from consider/removeSelected; runner-up reads intentionally discard unneeded ranking fields. Reference-order fuzzing and explicit finalization/next-cycle tests exercise these decisions. Review return-value drift with interface changes. |

## Low and informational detector labels

| Detector | Count | Implementation context and review questions |
| --- | ---: | --- |
| shadowing-local | 1 | Local naming warning; no authority/storage alias inferred. |
| calls-loop | 115 | Includes five fixed civic reviewers, fixed registry-bounded Senate seats, bounded election chunks/selection, and caller-provided atomic action batches. The overload call graphs share the same internal finalizer; reverse revalidation and narrow runner-up reads reduce data movement but do not eliminate loops. A batch is atomic when called, but its members can be executed individually. Heap cost grows logarithmically; finite stress tests do not prove unlimited-population liveness. |
| reentrancy-benign | 6 | State/authorization-checked cross-module workflows. Inspect callback order and the separately guarded asset paths; benign is a detector label, not an exemption from review. |
| reentrancy-events | 27 | Includes CivicAppealReview.executeRuling emitting after the exact immutable app call. Votes are deleted first; the app closes/resolves the case before returning, and its ruling path makes no external state-changing callback. No arbitrary executor exists. |
| timestamp | 115 | Delays, expiries, cadence and term-based authorization are intentionally time-dependent. OfficeRegistry checks the requested office's term expiry; it has no wallet/person reservation or other-office expiry condition. Civic filing/ruling deadlines are strict; timeout is inclusive, and upheld cases retain the later of notice and post-ruling delay. Boundary tests exist. Small timestamp variation and operator responsiveness remain assumptions. |
| assembly | 53 | Primarily pinned cryptography/math/memory utilities and callback handling. The hook-reader blocks use fixed-size allocated output buffers, bounded staticcall gas and indexed words only within the exact validated record size. Gas-underfunding, malformed-width/bool/length, oversized-return and live-hook tests exercise these boundaries. Future gas repricing remains a compatibility risk. |
| pragma | 1 | Dependency version ranges differ; first-party Solidity and compiler are pinned to 0.8.36. |
| costly-loop | 17 | Bounded/genesis/explicit batch writes and incremental ranking. Whole-genesis gas and large-population costs need deployment/operational sizing. |
| cyclomatic-complexity | 5 | Constructor/workflow maintainability warning. The registry uses a separate immutable ranking helper with no independent authority. |
| solc-version | 5 | Dependency compiler ranges; actual build uses the recorded pinned compiler. |
| low-level-calls | 3 | Bounded electorate synchronization/signature utility paths, not a generic governance executor. |
| naming-convention | 3 | Style warnings; do not affect dispatch or authorization. |
| too-many-digits | 7 | Pinned library masks/constants; preserve the specified bit patterns. |

The scan is unsuppressed. Its checked-in fingerprint multiset includes every normalized finding with multiplicity.
Counts alone cannot establish identity or severity of a changed finding. Compare the full output whenever source or
tooling changes and document the rationale before updating the fingerprint baseline.

Static analysis is not a release-safety verdict. Cross-module custody, retirement, replacement deadlocks and migration
assumptions require direct state-machine review even when a scanner produces no specific finding.

Residual assumptions—independent signer control, lawful evidence/notice, token upgrade risks, fixed oracle economics,
and reviewed state/custody migrations—are launch requirements in [Release Readiness](Release-Readiness.md).
