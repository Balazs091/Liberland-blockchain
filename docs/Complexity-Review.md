# Minimal complexity review

The 3 November 2026 changes consolidate duplicate contract logic and preserve the deployment graph, powers,
external interfaces and storage layouts. The size comparison below precedes the
[Solidity 0.8.38 upgrade](Toolchain-Upgrade.md).

## Scope and changes

Ten contracts share or remove repeated logic.

| Contract | Bounded simplification | Safeguards retained |
| --- | --- | --- |
| ReferendumApp | Share four identical action-envelope builders and resolve schedule policy once within the read-only check | Each typed caller selects its exact action, target and payload. Origin, pinned policy commitment, adoption time, voting windows and delays remain |
| ActionTimelock | Combine identical single-pointer and registration payload validation and remove a pass-through memory-state wrapper | Separate queue and execution checks, expiry, replay protection, expected addresses, bundle hashes and negative powers remain |
| CabinetApp | Share the identical removal and dismissal ballot tally | Current Congress roster, active person wallet, cycle, tenure nonce and each distinct threshold remain. Appointment choices use a separate count |
| DecisionApp | Share common Congress decision initialization, matching the existing ministry initializer pattern | Typed validators, preparing term, historical majority, source consent, receipt ownership, event order and live execution checks remain |
| HeadOfStateApp | Resolve an eligible candidate's active senator identity once per operation | Zero-person rejection, occupied seat, active wallet, occupancy nonce, majority and President/VP restrictions remain |
| LLMStakingVault | Reuse the existing checked backing-surplus read instead of a duplicate backing checker | Same token balance/active-stake reads, insolvency revert, exact transfers, reentrancy guard and canonical-vault checks remain |
| MinistryTreasury | Remove a zero-share check repeated immediately by the shared withdrawal function | The common check rejects before any pool interaction. Office shares, roles, exact accounting and old-pool settlement remain |
| USDCLendingPoolApp | Use one common policy checkpoint after initialized accrual | Initialization, elapsed-zero/debt-zero handling, timestamps, interest/reserves, events and the bounded full-book exit rule remain |
| LandRegistry | Remove a parcel-number index write already performed by the input writer | New-ID/number uniqueness, version/lineage, locks, title ownership and index updates remain |
| CompanyRegistry | Reuse the existence result already checked by the submission validator | Rejected-only resubmission, unique name/number indexes, enumeration, validation and event order remain |

The public methods and permanent core still constrain typed actions. The shared envelope builder is private.

## Deliberately retained complexity

- Authorization in an app and write authorization in its registry defend separate callers and stay independent.
- Proposal, queue and execution checks run separately because approved code and pointers can change between them.
- Identity migration, lost-key recovery, civic notice and appeals have different consent, delay and finality rules.
  Senate veto, cancellation, suspension and repeal likewise keep their separate state machines.
- Historical voting snapshots, latest-person receipts, consumed payout IDs, accrual checkpoints, reserve remainder
  and loan-owner records preserve behavior across time and replacement.
- Stable registries remain preferred. Generic ledger import, emergency execution and automatic land unlocking are
  not added. The two synthetic controllers retain their different authority models.
- Separate calldata and memory title initializers avoid an extra copy. A second recovery ballot remains deferred.

## Verification and measurements

The ten contracts save 1,750 runtime bytes in total.

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

The changes preserve the 58 exported ABIs from this snapshot. Layout comparisons discard compiler AST identifiers
and retain slots, offsets, labels and recursive type structure.

Compare gas with fixed inputs on both revisions. Include proposal creation and finalization, candidate resolution,
parcel creation, incorporation and register/stake/unstake. Fuzz inputs can differ even with the same seed.

Use the [auditor commands](Auditor-Handoff.md#reproduce-the-checks) on the submitted source. Review branches and
authorization failures as well as line coverage. Missing Foundry coverage anchors can under-report execution.
