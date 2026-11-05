# Minimal complexity review

Prepared 3 November 2026, after [Governance and Recovery Review](Governance-Recovery-Review.md). The user selected
the minimal approach and explicitly deferred a separate recovery ballot. This pass reduces repeated internal logic
without extending the deployment graph, legal powers, external interfaces or storage layout.

This report records the pre-toolchain-update source and measurements. The subsequent Solidity 0.8.38 and
dependency update changes the audit target; [Toolchain Upgrade](Toolchain-Upgrade.md) records its verification.
The bytecode, gas, coverage and scanner figures below belong to this earlier comparison.

## Scope and changes

Review covered the core and referendum path, identity/elections/executive workflows, finance/custody, land/company
records, membership primitives and the synthetic controllers. The retained edits affect ten existing contracts:

| Contract | Bounded simplification | Safeguards retained |
| --- | --- | --- |
| ReferendumApp | Share four identical action-envelope builders; resolve schedule policy once within the read-only check | Each typed caller selects its exact action/target/payload; origin, pinned policy commitment, adoption time, voting windows and delays remain |
| ActionTimelock | Combine identical single-pointer/registration payload validation; remove a pass-through memory-state wrapper | Separate queue and execution checks, expiry, replay protection, expected addresses, bundle hashes and negative powers remain |
| CabinetApp | Share the identical removal/dismissal ballot tally | Current Congress roster, active person wallet, cycle, tenure nonce and each distinct threshold remain; appointment choice counting stays separate |
| DecisionApp | Share common Congress decision initialization, matching the existing ministry initializer pattern | Typed validators, preparing term, historical majority, source consent, receipt ownership, event order and live execution checks remain |
| HeadOfStateApp | Resolve an eligible candidate's active senator identity once per operation | Zero-person rejection, occupied seat, active wallet, occupancy nonce, majority and President/VP restrictions remain |
| LLMStakingVault | Reuse the existing checked backing-surplus read instead of a duplicate backing checker | Same token balance/active-stake reads, insolvency revert, exact transfers, reentrancy guard and canonical-vault checks remain |
| MinistryTreasury | Remove a zero-share check repeated immediately by the shared withdrawal function | The common check still rejects before any pool interaction; office shares, roles, exact accounting and old-pool settlement remain |
| USDCLendingPoolApp | Use one common policy checkpoint after initialized accrual | Initialization, elapsed-zero/debt-zero handling, timestamps, interest/reserves, events and the bounded full-book exit rule remain |
| LandRegistry | Remove a parcel-number index write already performed by the input writer | New-ID/number uniqueness, version/lineage, locks, title ownership and index updates remain |
| CompanyRegistry | Reuse the existence result already checked by the submission validator | Rejected-only resubmission, unique name/number indexes, enumeration, validation and event order remain |

No new contract, library, public method, state field, execution origin or recovery power is introduced. These are
internal source changes for a fresh deployment, not an upgrade already applied to any public network. Sharing a
private typed action-envelope builder does not expose arbitrary execution; the public methods and permanent core
continue to constrain actions.

## Deliberately retained complexity

- Authorization in an app and write authorization in its registry defend separate callers and stay independent.
- Proposal, queue and execution validation protect different moments; approved code/pointers can change between them.
- Identity migration, lost-key recovery, civic notice and appeals have different consent, delay and finality rules.
  Senate veto, cancellation, suspension and repeal likewise keep their separate state machines.
- Historical voting snapshots, latest-person receipts, consumed payout IDs, accrual checkpoints, reserve remainder
  and loan-owner records retain behavior across time or replacement. No demonstrated redundant storage was removed.
- Stable registries remain preferred. Generic ledger import, emergency execution and automatic land unlocking are
  not added. The two synthetic controllers retain their different authority models.
- The calldata/memory title initializers remain explicit: removing that small duplication would add a fixed copying
  tradeoff without enough benefit in this pass. A second recovery ballot requires a future explicit instruction.
- Small unconnected Phase A decision/hash/receipt libraries remain source-only foundations. They add no runtime or
  authority to the current deployment and are not evidence that future legal workflows are complete.

## Verification and measurements

Before-source snapshots, exact patches, compiled ABI/storage comparisons, same-seed gas comparisons and final
combined-source verification are retained in the sibling workspace directory `Minimal-Simplification-2026-11-03`.
The previous `Governance-Recovery-2026-11-03` evidence describes the baseline, not this new bytecode.

All ten changed contracts are smaller, saving **1,750 runtime bytes in total**. Their combined formatted source is
6,639 lines versus 6,690 before (51 fewer lines). The main benefit is fewer duplicate implementations of the same
rule; source line count and Ethereum's bytecode limit are not measures of audit completeness.

| Contract | Runtime before → after, bytes | Saved |
| --- | ---: | ---: |
| ReferendumApp | 21,255 → 20,764 | 491 |
| ActionTimelock | 18,985 → 18,963 | 22 |
| LLMStakingVault | 7,929 → 7,619 | 310 |
| MinistryTreasury | 6,764 → 6,678 | 86 |
| USDCLendingPoolApp | 18,226 → 18,190 | 36 |
| LandRegistry | 18,616 → 18,601 | 15 |
| CompanyRegistry | 10,553 → 10,544 | 9 |
| CabinetApp | 18,319 → 18,035 | 284 |
| DecisionApp | 16,383 → 15,920 | 463 |
| HeadOfStateApp | 7,985 → 7,951 | 34 |

Every exported ABI remains exactly equal to its baseline: 58 contracts, 834 function entries. Normalized compiled
storage layouts match for all ten changes and six additional comparison contracts; normalization removes compiler
AST identifiers while retaining slots, offsets, labels and recursive type structure. No production contract or
dependency is added. Build size and creation-code limits pass with the original optimizer/EVM settings.

Same-seed before/after comparisons use the existing fixed test fixtures. Citizen proposal creation saves about
4,084–4,085 gas in the measured calls; Congress proposal calls save about 2,051–2,052 gas. Candidate identity reuse
also reduces repeated reads. Parcel creation saves 176 gas and company submission 159 gas in the selected flows.
Small tradeoffs remain: the largest measured executive unit-test increase is 641 gas, and the largest percentage
increase is 0.09039%; the shared backing read adds 182 gas to one complete register/stake/unstake journey. RefApp
finalization's measured median rises by 91 gas. These bounded costs are retained for clearer shared logic and lower
deployed size. Fuzz mean gas is not used as same-input proof: case mixes may differ even with the same seed.

| Combined-source check | Result |
| --- | --- |
| Optimized complete suite | **816 passed**, 67 suites, zero failed/skipped, seed `0x110307`; includes the 1,000-candidate stress fixture |
| Extended stateful campaign | **24 invariants plus six supporting/non-vacuity tests passed**; 256 runs × 256 calls per invariant, seed `0x110308`; 1,572,864 reported handler calls, zero handler-level reverts |
| Instrumented coverage | **815 passed**, 67 suites. Only the documented 1,000-candidate instrumentation exception; the 100-candidate counting path remains |
| First-party non-mock coverage | Lines 88.24% (6,927/7,850); functions 93.94% (1,101/1,172); branches 52.83% (756/1,431) |
| Source/reference tooling | 34 reference-model and 11 verification-tool tests passed; documentation, 58 exact ABIs, formatting and whitespace checks pass |
| Unsuppressed Slither | 465 labels / 460 distinct normalized identities: 6 High, 72 Medium, 292 Low, 95 Informational; all deltas manually reviewed |
| Fresh mined localhost rehearsal | Production: 85/85 deployment transactions; governed Sepolia: 101/101 deployment transactions plus real citizen upgrade/rollback exercises; all eight recorded runtime hashes matched mined code |

The prior isolated five-contract foundation profile is not redeployed for this cleanup: its five sources and
deployment dependencies are unchanged. The new full production/governed profiles were rehearsed against exact final
compiled input snapshots. Production rehearsal uses synthetic genesis and a local USDC test double, not a fork
verification of Ethereum's actual issuer-controlled USDC implementation. No public network was changed.

Static triage reviewed nine added/changed descriptions, twelve removed/changed descriptions, all six High reports
and 24 Medium reports affecting modified source. No new confirmed vulnerability was identified; fewer labels do
not establish stronger safeguards. See [Static Analysis Notes](Static-Analysis-Triage.md).

Existing tests and assertions are retained. Overall branch coverage of 52.83% remains a review gap. Foundry emitted
197,548 coverage-anchor warnings; raw warnings and LCOV are retained, and missing anchors may under-report execution.
Seventy-one instrumented non-mock functions have zero hits; a simple source-level screen found no public/external
non-view mutator among them, but this is not exhaustive role/input/order coverage. Reported invariant handler calls
are not unique user transactions or proof that every attempted action succeeded. The source remains an uncommitted
working tree, and this engineering review is not an independent audit or production launch approval.
