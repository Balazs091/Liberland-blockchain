# Static Analysis Notes

Slither output and implementation context for the submitted source. Detector severity labels are not confirmed
vulnerability ratings or an independent security verdict. Auditors should reproduce the scan and test each assumption.

## Current Slither 0.11.6 baseline — 5 November 2026

The [comprehensive review](Comprehensive-Review.md) repeats the unsuppressed scan on the final source. Counts remain
464 results (6 High, 70 Medium, 292 Low, 96 Informational), with 459 distinct normalized identities. Against the
3 November baseline, 463 report occurrences and 458 distinct identities are unchanged. One Low `timestamp` label
changes because `_validateInitialElectionWindow` now includes the upper bound
`votingEnd - nominationStart > policy.cycleDuration()`.

The duration check is the intended first-election liveness fix, after chronological/minimum-duration validation.
It adds no funds transfer or new authority. Both the original and final detector descriptions were reviewed and
retained in `final-slither-delta-review.json`; the old-code negative control proves the two excessive-duration
regressions. Only that reviewed fingerprint was replaced. No severity gate or detector suppression changed.

## Toolchain-update baseline — 3 November 2026

The Solidity 0.8.38, Foundry 1.9.0 and OpenZeppelin 5.7.0 build was scanned with Slither 0.11.6 and
crytic-compile 0.4.2: **176 contracts, 102 detectors, 464 results — 6 High, 70 Medium, 292 Low,
96 Informational**. The checked-in gate verifies all 459 distinct normalized identities and their multiplicity.
No detector/path filter or new local suppression was introduced. Existing upstream annotations remain unchanged
upstream source. Full reports and per-report source review are in the sibling `Toolchain-Upgrade-2026-11-03`
evidence directory; reproduction and validation are described in [Toolchain Upgrade](Toolchain-Upgrade.md).

Against the previous 465-result scan, **461 report occurrences are unchanged**, three are added/changed and four
are removed/changed. Every delta and all six unchanged High reports were reviewed. No new confirmed vulnerability
was identified in this comparison; existing authority, dependency, economic and recovery assumptions remain in scope.

| Added/changed or removed report | Source review |
| --- | --- |
| Added upstream `assembly`, Informational | OpenZeppelin adds `SafeERC20.tryGetDecimals`: a read-only call, return-length check and uint8 range check, returning zero on failure. No first-party source calls the new helper; existing token-transfer implementations are unchanged. |
| Changed `pragma` inventory, Informational | First-party pragmas are exact 0.8.38. Dependency ranges remain authentic upstream source. The new upstream decimals helper imports one additional IERC20Metadata interface alias. All contracts are compiled with the same pinned compiler. |
| Changed `solc-version`, Informational | The broad upstream `>=0.6.2` range warning now lists the additional interface alias. This range-based warning does not mean the pinned 0.8.38 build used an old compiler with the listed historic bugs. |
| Two removed `unused-return`, Medium | `recallUnrepresentedSeat` directly returns both outputs of `vacateAndFillSeatForPerson`; `_electorateSnapshotAt` directly returns both snapshot outputs after checking policy/registry binding. Their outputs were already forwarded. The updated analyzer removes these false-positive labels; no return-handling fix was made. |
| Four unchanged ERC20-pull High reports | Congress execution checks current-term support and exact decision-source authorization. Ministry execution requires the current minister to be the recorded source. Treasury funding accepts only the canonical funding authority, validates exact receipt, and runs under its reentrancy guard. Prepared action fields and allowances remain required; execution status is consumed before transfers. Replacement authority remains an audit assumption. |
| Unchanged UTC-boundary and modular-inverse High reports | Timestamp modulo computes a deterministic daily boundary, never a random selection. OpenZeppelin `Math.sol` is unchanged between 5.6.1 and 5.7.0; XOR is the intentional modular-inverse seed. |

The imported upstream signature changes were also reviewed. `LandRegistryApp` uses the fixed EIP-712 name
`Liberland Land Registry` and version `1`; both fit the new 31-byte limit. OpenZeppelin retains the deprecated
fallback storage slots. Its ERC-1271 checker now zero-pads dynamic signature bytes and rounds the encoded calldata
to a 32-byte boundary, retaining the original logical signature length and all return/magic-value checks. This
changes the land application's compiled runtime and needs a fresh deployment hash. Other upstream changes to
unimported bridges, forwarders, RSA and WebAuthn do not enter the first-party production compilation.

## Earlier Slither 0.11.5 baseline

The current scanner/dependency update is recorded in [Toolchain Upgrade](Toolchain-Upgrade.md). The tables and
source-specific comparisons below describe the earlier analyzer and dependency versions.

Slither 0.11.5 analyzed **176 contracts with 101 detectors on 3 November 2026** after the minimal
complexity cleanup, without suppressions: **465 results — 6 High, 72 Medium, 292 Low, 95 Informational**. The checked-in
earlier baseline included all results (460 distinct normalized fingerprints). Full reports, source hashes and per-report
triage are in the sibling `Minimal-Simplification-2026-11-03` evidence directory. All 148 contract-file hashes matched
that frozen source. Detector labels and their disappearance are not a security verdict.

## Reviewed simplification delta — 3 November 2026

Against the preceding 468-result governance/recovery scan, **456 report identities are unchanged**. Nine descriptions
are added/changed and twelve removed/changed. All six High identities remain unchanged. Every delta, all High
reports and the 24 Medium reports touching the ten modified contracts were reviewed; no new confirmed vulnerability
was identified. The gate checks both counts and the complete normalized identity multiset, without suppressions.

| Delta or affected surface | Source review |
| --- | --- |
| Six changed Cabinet `calls-loop`, Low | The renamed shared tally still traverses the bounded current Congress roster and retains active-person/wallet, cycle and tenure-nonce predicates. Appointment counting retains its distinct target/latest-person receipt checks. No generic voting engine or new electorate is introduced. |
| Cabinet/Company/lending `timestamp`, Low | Cabinet counting retains its existing cycle/nonce checks; company submission reuses the same existence and Rejected-status read; lending keeps the same elapsed-zero/positive and initialized/debt branches with one final policy refresh. No new deadline or time-based authority is introduced. |
| Two removed `incorrect-equality`, Medium, and one fewer timestamp label | Shared counting and complementary elapsed-nonzero control flow alter detector output. The underlying nonce/cycle/zero-time semantics remain. These removals are not claims that two vulnerabilities were fixed. |
| Four affected High ERC20-pull labels | Current office/decision authority, exact-source consent/allowance, preparing term, threshold and action fields are unchanged. Only common initialization was consolidated; source authorization and event sequence remain. Existing transfer/revoke/term/migration tests pass. |
| Unchanged High UTC-boundary and OpenZeppelin inverse labels | Deterministic UTC arithmetic is not random selection; the dependency's modular-inverse XOR expression is unchanged. Neither source was edited. |
| Remaining affected Medium equality/reentrancy/return/sentinel reports | Existing exact state/identity/zero/bucket predicates, reentrancy guards, exact receipt/settlement sequencing, sorted-plan zero sentinel, forwarded electorate snapshot and registration-existence probe remain. Ministry's common no-share check still runs before any pool call. RefApp's private helper retains typed payloads, origin, pinned policy and adoption time; the permanent timelock still validates at queue and execution. |

The prior governance/recovery scan below reported 468 results and 463 distinct identities. Its evidence remains in
`Governance-Recovery-2026-11-03`; the complexity report superseded it before the later toolchain update.

## Reviewed governance and recovery delta — 3 November 2026

Against the preceding 447-result predeployment scan, **437 report identities remain unchanged**. Ten descriptions
change and 21 reports are added: five Medium and 16 Low. All six High identities remain unchanged. Every added or
changed report, all High reports and the 22 Medium reports touching modified/new source were reviewed. No new
confirmed vulnerability was identified in that review; it does not replace independent audit or resolve the
documented governance, economic and recovery limits.

| New/changed reports | Source review and evidence |
| --- | --- |
| Five new `uninitialized-local`, Medium | Four bundle-order sentinels intentionally begin at Solidity's zero value; accepted IDs must be nonzero and strictly increase. The kernel rebuild flag is initially false and becomes true only for the exact citizen-policy slot. These are value types, with no uninitialized storage reference. Empty/duplicate/unsorted/max-size plan and successful/failed rebuild tests cover the paths. |
| Four changed lending `reentrancy-no-eth`, Medium | Reports reflect the accrual overload and empty-book completion helper. Both public repayment methods and all financial entrypoints remain `nonReentrant`. Exact receipt precedes debt release; canonical `closeLoan` has no mutable callback. Same-timestamp `accrueInterest` cannot add elapsed interest; completing the actual empty book resets its unit index and invalidates future terms. Broken-rule exits match healthy interest/reserves, token/downstream failure rolls back, and partial/multiple-borrower repayment remains strict. New borrowing, deposit and liquidation retain live-policy checks. Views during external calls remain unsuitable as pricing oracles. |
| Changed `incorrect-equality`, Medium, and remaining Medium impacts | The elapsed-zero predicate moved to `_accrueInterest(bool)`. The other ten equality reports on modified source concern exact zero shares/debt/assets, block/action sentinels and queue states. They are state-machine boundaries, not approximate market-price comparisons. The two unchanged `unused-return` reports are the directly forwarded electorate snapshot outputs and a try/read used solely as a registration-existence probe. Snapshot, queue, lending and atomic-upgrade tests exercise these boundaries. |
| Ten new `calls-loop`, Low, plus one moved description | Plan publication, validation, readiness and execution inspect at most 16 unique entries. The kernel validates everything, installs all pointers, then invokes at most one citizen-policy rebuild and verifies final pointers. No member is independently executable; stale addresses, runtime drift or callback failure revert the complete action. Existing `executeActions` remains an optional caller-sized batch of independent actions; execute one bundle when bounding transaction cost. The moved bootstrap rebuild call remains setup-only. |
| Four new synthetic-controller `reentrancy-events`, Low | Current Congress/current writer/current ledger checks and the Sepolia/fixed-subject gates precede a controller-domain nonce and typed MembershipRegistry call. The actual ledger has no mutable callback or custody. A failed mutation reverts nonce, state and events. Real citizen-vote replacement/rollback tests retain orders and immediately retire the old controller's authority. This synthetic driver is not an official legal issuer. |
| Two new `timestamp`, Low, plus two changed descriptions | The lending report follows the bool accrual overload. Kernel reports follow timestamp-bearing registry metadata through exact existing-address/rebuild/postcondition checks; none selects random outcomes or grants time-based emergency authority. Ordinary queue/adoption delays and negative controls remain. |
| Changed `pragma` and `cyclomatic-complexity`, Informational | Eight new interface/library/controller/validator/registry sources are pinned to 0.8.37; dependency ranges are unchanged. The referendum registry's explicit bundle-validation branch raises reported complexity from 26 to 28. It requires constitutional snapshots, the exact timelock context and no legislation/registration fields. The helper is immutable and read-only, with no independent authority. |

The six existing High labels still concern four authorised ERC20-pull paths, deterministic UTC boundary arithmetic
and OpenZeppelin's intentional XOR modular-inverse seed. Those source implementations and normalized findings are
unchanged; bundle execution supplies no token transfer or arbitrary calldata. Existing authorisation, dependency,
reentrancy and operational assumptions remain subject to review. The complete 468-report fingerprint multiset was
updated only after the above comparison and manual triage. No detector or source warning is suppressed.

## Reviewed predeployment delta

That scan analysed 168 contracts and retained 447 results (6 High, 69 Medium, 277 Low, 95 Informational; 442 distinct
normalized fingerprints).

Compared with the earlier 445-result Sepolia-preparation scan, 442 report identities are unchanged, three descriptions
change and two Low reports are added. The two additions are fixed four-minister reads now reached by both Prime
Minister readiness and appointment through the incompatibility check. The changed Cabinet equality/timestamp
predicates include the exact latest-wallet binding; the changed DecisionApp loop predicate includes its canonical
person receipt. These are bounded identity/nonce/mandate checks, not randomness or uncontrolled external execution.
Independent source review and before/after regressions accompany [the predeployment review](Predeployment-Review.md).
No finding is suppressed and no existing High/Medium label is declared resolved merely by a count comparison.

## Reviewed Sepolia-preparation delta

Against the earlier 3 November token/restriction scan, **436 report identities remain unchanged**, one informational
pragma inventory changes and eight Low reports appear. High/Medium/Informational totals are unchanged.

| New/changed report | Source review and evidence |
| --- | --- |
| Three `calls-loop`, Low, in seedSyntheticIdentities | The actual existence read, identity record write and wallet link write loop over exactly three fixed fixture people. Seeding is operator-only, one-shot and unavailable after bootstrap retirement. A failure reverts the seeded flag and all writes. Unit tests and actual local deployment receipts cover the bounded path. |
| Four restriction `reentrancy-events`, Low | The typed controller increments its synthetic nonce before calling the real MembershipRegistry. The registry performs read-only dependency/authority checks and internal writes, with no mutable callback. The controller's synthetic success event intentionally follows the canonical result. Failed writes revert nonce, state and events together. It has no custody or arbitrary target. |
| One seed `reentrancy-events`, Low | The actual IdentityRegistry can have an electorate callback generally. This isolated deployment registers no electorate, then retires bootstrap without installing a governance/timelock path; no callback module can be added afterward. The seed flag is set before writes and the fixed operator gate remains. This reasoning is specific to the isolated test environment, not a production seeding exemption. |
| Informational `pragma` inventory | Adds only ISepoliaMembershipController, SepoliaFoundationFixtures and SepoliaMembershipController, all pinned to 0.8.37. Removing exactly those three inventory entries reproduces the prior normalized fingerprint. |

Independent source review found no correction needed for these reports within the declared synthetic scope. No
detector is suppressed and no source guard is added just to silence a report. The controller cannot replace a real
legal issuer/writer. Dependencies, fixture scope or bootstrap/governance changes require renewed review.

## Earlier 3 November token/restriction delta

Against the 2 November scan, **431 report identities remain unchanged**, one pragma inventory identity changes and
five new reports appear. That earlier scan contained 437 results (432 distinct normalized fingerprints). No detector,
source warning or report is suppressed.

| Added/changed report | Review and practical limit |
| --- | --- |
| `unused-return`, Medium: MembershipRegistry internal heap removal | `remove(orderId)` reverts if the entry is absent and physically repairs its index. Its returned Entry contains metadata already fixed in the recorded order; the registry needs the removal, not that copy. Named stay/revoke and the independent scanning oracle cover the resulting state. No external success/error return is being discarded. Future library changes require renewed review. |
| Three `timestamp`, Low: recordOrder, rightsNow, resumeOrder | Explicit legal-time gates: reject future/new expired orders, remove a finite restriction at its exclusive end, and prevent a stay from restarting an expired period. Boundary tests include equality. This is intentional time dependence, not randomness. It does not solve legal notice, calendar periods, future scheduling or electorate certification. |
| `unimplemented-functions`, Informational: LiberlandMerit cap | The source explicitly overrides both ERC20Capped and ILLMToken, returning the inherited cap. Solidity compiles and deploys the concrete contract; the typed ILLMToken cap call, deployment validation and local deployed-token cap check succeed. This is treated as a false positive on that evidence; the detector’s internal cause is not established. The report remains visible; no interface or implementation is removed to silence it. |
| Aggregated `pragma`, Informational | Adds IMembershipRegistry, MembershipRegistry, LiberlandMerit and MembershipTypes, all pinned to 0.8.37. Removing exactly these four inventory entries reproduces the prior normalized fingerprint; dependency ranges are unchanged. |

These new reports were reviewed against the actual source and focused/integration tests. That review does not approve
future receipt authentication, issuer replacement, rights/privacy rules or token allocation. Existing High/Medium
labels and the economic/legal findings are not declared resolved by this slice.

The earlier 2 November scan had 432 results (6 High, 68 Medium, 264 Low, 94 Informational); only its pragma inventory
changed from September to include four internal libraries. The 17 September review had introduced two unused-return
reports for payout synchronization and land verification, plus description changes for safe deadline arithmetic,
lending index reset, complexity and the InterestRateBounds pragma inventory. Those are historical comparisons;
the counts and fingerprints above describe that pre-toolchain-update baseline.

## Earlier High detector labels

| Detector | Count | Implementation context and evidence |
| --- | ---: | --- |
| arbitrary-send-erc20 | 4 | DecisionApp's Congress pulls require source authorization of the exact decision ID; ministry execution requires the current minister to be the recorded source. MinistryTreasury.fund accepts only the governed DecisionApp funding authority. Approved amounts/recipients are immutable. Retain exact allowances and separately review replacement authority. Tests: Decisions and HighSeverityGovernance. |
| weak-prng | 1 | CongressElectionApp._nextDailyBoundary uses timestamp modulo for a deterministic UTC schedule, not randomness. Cadence/late-finalization tests cover the boundary. |
| incorrect-exp | 1 | Pinned OpenZeppelin Math.mulDiv deliberately uses XOR in the modular-inverse seed; exponentiation would be a bug. No local dependency patch made. Independently review pinned dependency provenance. |

## Earlier Medium detector labels

| Detector | Count | Implementation context and review questions |
| --- | ---: | --- |
| divide-before-multiply | 9 | All nine are in pinned OpenZeppelin Math.mulDiv/invMod: exact removal of factors of two, modular-inverse refinement and Euclidean division. Multiplying first or replacing modular arithmetic would change the algorithm. No local dependency patch or warning suppression was made. |
| incorrect-equality | 26 | Exact identity/appointment IDs, nonces, enum states, zero debt and custody/accounting matches. The zero-amount checks reject empty custody handoffs; removing them permits meaningless replays, not improved arithmetic. These are exact state checks, not market-price equality. |
| reentrancy-no-eth | 9 | Lending financial entrypoints and both custody vaults use nonReentrant. Repayment's private helper is reached only through guarded public methods. TreasuryVault marking calls the canonical budget registry before the vault-local receipt; the current registry makes no external state-changing callback, requires the current vault and permanently consumes an active request. Token transfer failure rolls back both receipts. Typed lien settlement holds its own guard across the canonical stake transfer. The unguarded accrueInterest cannot accrue more elapsed time in same-timestamp callbacks; the outer operation refreshes its final configuration. Reentrancy/transient read assumptions remain in scope; external callers must not treat mid-call quotes as pricing oracles. |
| uninitialized-local | 9 | Four bundle ordering sentinels and the rebuild boolean intentionally use Solidity's zero/false initialization; see the recovery delta above. CivicAppealReview's fixed memory array/per-iteration boolean are Solidity zero-initialized and bounded to five entries. StakeRegistry's loanBook and retainedStakeFloor locals are assigned by successful typed reads or the function reverts; a no-book branch returns before reading the floor. No uninitialized storage pointer exists. Broken-policy/no-loan and retained-zero-lien regressions cover both branches. |
| unused-return | 21 | Intentionally unused typed outputs or sub-record fields. Election progress uses canonical ranking status, not the ignored informational boolean from consider/removeSelected; runner-up reads discard unneeded ranking fields. Office cancellation ignores the informational sync result after the queue independently validates and reconciles the canceled action. Land acquisition consumes verification status, not political citizenship fields, preserving its previous eligibility rule. Reference-order fuzzing, finalization/next-cycle, cancellation and land regressions exercise these decisions. Review return-value drift with interface changes. |

## Earlier Low and informational detector labels

| Detector | Count | Implementation context and review questions |
| --- | ---: | --- |
| shadowing-local | 1 | Local naming warning; no authority/storage alias inferred. |
| calls-loop | 130 | Includes fixed civic reviewers, registry-bounded Senate seats, bounded election chunks/selection, at most 16 module-plan entries and caller-provided action batches. Bundle members cannot execute individually; ordinary action-batch members can. Reverse revalidation and narrow runner-up reads reduce data movement but do not eliminate loops. Heap cost grows logarithmically; finite stress tests do not prove unlimited-population liveness. |
| reentrancy-benign | 6 | State/authorization-checked cross-module workflows. Inspect callback order and the separately guarded asset paths; benign is a detector label, not an exemption from review. |
| reentrancy-events | 36 | Includes the four synthetic governed-controller methods reviewed above and CivicAppealReview.executeRuling emitting after the exact immutable app call. Votes are deleted first; the app closes/resolves the case before returning, and its ruling path makes no external state-changing callback. No arbitrary executor exists. |
| timestamp | 120 | Delays, expiries, cadence and term-based authorization are intentionally time-dependent; some kernel reports track metadata into exact pointer checks. OfficeRegistry checks the requested office's term expiry; it has no wallet/person reservation or other-office expiry condition. Civic filing/ruling deadlines are strict; timeout is inclusive, and upheld cases retain the later of notice and post-ruling delay. Boundary tests exist. Small timestamp variation and operator responsiveness remain assumptions. |
| assembly | 53 | Primarily pinned cryptography/math/memory utilities and callback handling. The hook-reader blocks use fixed-size allocated output buffers, bounded staticcall gas and indexed words only within the exact validated record size. Gas-underfunding, malformed-width/bool/length, oversized-return and live-hook tests exercise these boundaries. Future gas repricing remains a compatibility risk. |
| unimplemented-functions | 1 | LiberlandMerit implements the concrete cap override; typed calls and deployment checks pass. See the reviewed delta above; detector report retained. |
| pragma | 1 | Dependency version ranges differ; first-party Solidity and compiler are pinned to 0.8.37. |
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
