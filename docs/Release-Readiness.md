# Release readiness

Mainnet launch requires an independent audit, approved legal workflows, verified genesis and assets, and operational
approval. The separate recovery ballot remains deferred.

For a commit-based handoff, include every new source/test/script, freeze one commit and tree, and pass
`bash scripts/audit-freeze-check.sh` on a clean checkout. A working-tree archive must instead identify its exact
source inventory and archive checksum, record its base commit, and state that the candidate has not been published.
[Auditor Handoff](Auditor-Handoff.md) defines both formats.

## Evidence for the submitted revision

Record the full commit, tree and recursive submodule revisions. Attach the CI run and clean-tree freeze log for
that commit, along with coverage, Slither findings, runtime sizes, ABI parity and local rehearsal evidence. Record
the storage and selector changes in the company and land registries and the corresponding migration requirements.
See [Auditor Handoff](Auditor-Handoff.md).

### Earlier November verification

The 10 November published justice baseline was `00da5bce5a4ac75fb35c8adc2e1168d43ad82d17`. GitHub CI verified
that commit. The justice genesis notes also record the synthetic rehearsal. [GitHub CI](https://github.com/Balazs091/Liberland-blockchain/actions/runs/42818112204)
· [Justice procedures](phase-a/JUSTICE.md).

The 5 November internal review and source archive cover the earlier working-tree snapshot. The compiler upgrade
records its own runtime and verification results. [Comprehensive Review](Comprehensive-Review.md) ·
[Toolchain Upgrade](Toolchain-Upgrade.md).

### Earlier 3 November verification

The following figures belong to [Complexity Review](Complexity-Review.md), before the compiler/dependency update.
The separately checksummed publication snapshot preserves that earlier source and its evidence.

| Check | Recorded result |
| --- | --- |
| Complete optimized suite | 816 passed in 67 suites; zero failed/skipped |
| Extended stateful campaign | 24 invariant properties plus six supporting tests; 256 runs at depth 256; 1,572,864 reported handler calls |
| Coverage | 815 tests passed with the one documented instrumentation exception; first-party non-mock lines 88.24%, functions 93.94%, branches 52.83% |
| Static analysis | 465 unsuppressed labels, 460 normalized identities: 6 High, 72 Medium, 292 Low, 95 Informational; reviewed deltas retained |
| Interfaces and layout | 58 exact ABI exports; 834 function entries; all ten simplified contracts retain their compiled storage layouts |
| Local deployment | Fresh production setup and governed Sepolia deployment/upgrade/rollback rehearsals passed; no current-source public deployment |
| Reference/tooling tests | 34 reference-model tests; 20 repository verification-tool tests |

That coverage run recorded 197,548 anchor warnings. The detector triage records which scanner labels were
investigated and how they were classified. [Complexity Review](Complexity-Review.md) ·
[Static Analysis Notes](Static-Analysis-Triage.md).

## Submission contents and scope

Include the contracts, interfaces, tests, deployment scripts, network parameters, docs, 63 frontend ABIs and
pinned dependency source. Review the production paths and the boundaries that keep mock assets and synthetic
authorities confined to test deployments.

The optional justice profile adds signed collective procedures, membership and welfare eligibility, and voluntary
compensation. Public activation requires the adopted charter, verified rosters and production genesis inputs.
See [Justice procedures](phase-a/JUSTICE.md) and [Recovery Decisions](Recovery-Decisions.md).

The source supports review of contract behavior and synthetic deployment. A production-state fork, verified real
genesis records, intended token/proxy configurations, signer-controller attestations and operational/legal procedures
are separate inputs the project must supply for deployment approval. See [Auditor Handoff](Auditor-Handoff.md)
and [External Audit Scope](Audit-Scope.md).

## Current controls and verification targets

| Area | Current behavior and evidence to challenge |
| --- | --- |
| Governance hook boundaries | Optional Senate/review reads use fixed-size buffers, exact canonical ABI validation and a 100,000-gas allowance. Caller underfunding reverts; genuinely failed, over-budget or malformed optional reads are treated as absent. Test `UpgradeLivenessAudit.t.sol` against both valid powers and invalid responses. |
| Loan ownership and retirement | The stable lien registry records one owning book per person. Ownership and the captured floor persist through zero-lien residual debt until explicit closure. New borrowing requires matching canonical ledgers and all three pool-authority pointers. Test `WorkflowLivenessAudit.t.sol`, `LoanRetirementIndependentAudit.t.sol` and lending invariants. |
| Retired collateral limits | Retired health, liquidation and bad-debt calculations use the smaller of active surplus and recorded lien. Settlement requires `seizedStake + remainingLien <= priorLien`. Current pools use the documented all-active-surplus model; later unpledged stake cannot enlarge a retired book's numerical rights. |
| Custody transitions | `handoffBacking()` and `handoffAsset(asset)` have an already-governed compatible successor, exact token receipt and no caller-selected recipient. Retired staking operations and Treasury disbursement are blocked; Treasury deposits remain recoverable through handoff. These are custody helpers, not universal state migration. |
| Payout accounting | Commitments retain their original writer only for settlement. Paid request IDs have permanent receipts in the retained budget registry; they cannot be reserved again or released as unspent. Spent settlement requires execution. Historical queue synchronization uses the action's original vault receipt. Different IDs for one invoice still require off-chain deduplication. |
| Elections and terms | Pinned-cycle finalization and next-cycle creation are separate operations. Finalization supports a 1–32 workload. Seated Congress members retain their mandates through stake loss, welfare or temporary political restrictions. Citizenship loss and the separate zero-active-wallet rule remain recall grounds. |
| Senate support | Support is bounded by the stable registry's seat universe. Negative powers require an occupied-seat majority, at least two direct seat votes and any higher policy minimum; President proxy substitution is not provided. |
| Identity and civic process | Review the legacy seven-day notice and 3-of-5 civic appeals separately from the optional justice writer, charter-bound rosters, signed decisions and voluntary compensation. Check both profiles through two-stage genesis. |
| Finance | Treasury payout routing requires distinct current Finance officers. Review source-authorized decisions, interest, reserves, rounding and custody. |
| Land and companies | Dispute actions require a verified Land Office clerk and a registrar from a different verified identity. The company registry blocks removal of the last active director and terminal dissolution while the company holds an active title. Verify those guards after transfers, parcel changes and lease closure. |
| Shared office administrators | One wallet or person may hold multiple offices. Per-office role checks, expiry, appointment identifiers and clerk invalidation remain independent. Holding multiple offices cannot supply both payout/civic approvals. Only the mainnet genesis script requires distinct initial admins; later cross-office controller separation is operational. |
| Configuration and arithmetic | Timelock, migration, welfare and Congress schedule constructors reject unsupported durations. Timelock/referendum schedules reject overflowing deadlines; Senate suspension caps widened arithmetic at the action expiry. Lending rejects incompatible rate scales and rates above 200% nominal APR before checkpointing; an entirely empty debt book resets its index without repricing any active claim. |
| Bounded reads and lifecycle records | Eligibility reads fixed-size identity facts instead of dynamic metadata. Electorate rebuild clamps workloads before addition. Pending companies cannot leave permanent filings across rejection/resubmission; approved suspended/dissolving companies retain compliance filing. Senate callers cannot spoof another repeal origin to evade the registry's tier restriction. |

Passing tests support these implementation descriptions; they do not establish the absence of vulnerabilities.

## Known limitations requiring external review

1. **Governance availability is conditional.** Broken referendum code, identity/stake/policy dependencies or
   unavailable certified electorate state can prevent the vote needed to replace them. Kernel/router/timelock are
   permanent execution roots. Citizen-policy activation also depends on the electorate rebuild hook. Permissionless
   synchronization can repair a missed callback, not arbitrary defective bytecode.
2. **Negative powers can cross-lock replacement.** The Senate exemption applies to its own exact replacement;
   the constitutional-review exemption applies to its own exact replacement. Review can block Senate replacement
   while Senate blocks review replacement. This high-impact conditional limit is not resolved by either batch order.
   The design has no secondary recovery ballot, permanent administrator or general exemption from negative powers.
3. **Pointer replacement does not migrate records.** Immutable references and app-local pending state require
   explicit transition design. Custody/loan/commitment helpers do not import identity, land, company, electorate,
   civic cases, debt or LP records. Exact successor getters check compatibility, not honest bytecode. Replacing a
   ledger requires preserving its receipts, facts and pending obligations through a separately reviewed migration.
4. **Separate actions do not lock members together.** `executeActions` retains independently executable members.
   Use the new typed module bundle for related existing non-Core pointers: it commits and executes the complete
   group in one action. Bundles exclude Senate/review replacements and do not migrate state or custody.
5. **Optional hook compatibility is a trust boundary.** Failure is fail-open under the documented ABI/gas contract.
   The core cannot distinguish accidental failure from intentional incompatibility. Future hook implementations
   and chain gas repricing require renewed compatibility checks.
6. **Economic and legal inputs are not certified by code.** The fixed oracle can become economically wrong.
   Token/proxy controls, liquidity, liquidation incentives, bad debt, evidence availability, notice, legal grounds,
   real controllers and company/land signer continuity require independent assessment.
7. **Ordinary voting has no headcount quorum.** Two qualifying citizens can pass an ordinary repeal referendum
   if their stake meets the quorum and nobody supplies enough opposing votes. They cannot repeal by petition alone.
   The existing thresholds are retained on both networks; they are not testnet-only settings.
8. **Vacancies can constrain dismissal and decisions.** Succession fills seats only while eligible runner-ups
   remain. PM removal retains the original appointment-support tally; pending Congress decisions retain their
   prepared threshold and cannot cross terms. These rules are deliberately retained, not fixed by assuming
   Congress can never shrink. The PM and President have distinct appointment/removal workflows.
9. **Budget approval is not a repealable law-registry entry.** The retained Law-tier referendum path records a
   budget envelope. Ordinary law repeal does not revoke it or its queued payouts. Fiscal revocation would require
   a separately approved lifecycle; no such power is implied by the phrase "budget law".
10. **Debt horizon and director key loss.** The lending-rate ceiling was tested over a finite horizon. A director
    can sign a sale while the company is suspended or winding down. If the director loses access to the wallet,
    the Company Registry Office must record a replacement under a status that permits appointments. Historical
    signerless titles need a lawful succession process before import.
11. **Company and land cutover requires both registries.** The new registry guards reject protected writes when the
    opposite canonical registry cannot answer. Reconcile active title counts, company directors, parcel and title
    records, encumbrances and unresolved disputes before rebinding the registry, policy, app and authority pointers.
    Confirm dispute officers can act after cutover and obtain fresh app-bound approvals and signatures.

[Upgrade and Liveness](Upgrade-And-Liveness.md) contains the module-by-module dependency and recovery map.
These limits must be included in audit scoping and launch-risk decisions, not treated as deployment guarantees.

## Historical September verification evidence

Verification is source-specific. Package provenance must identify this implementation and its tests; do not reuse
a source archive or verification manifest from a different revision. Fuzzed coverage reruns may vary slightly.

Historical toolchain: Forge 1.7.1, Solidity 0.8.37, Slither 0.11.5; Osaka, optimizer 200, no via-IR in deployable builds.
The source is tested without raising deployment-size or transaction-cap settings to conceal failures.
Checks below were run on 17 September 2026 against the local working source derived from
`ccea1facde0cedb491dc864a2f4dc00e3a04c4bd`, including application changes beyond compiler pragmas.
The separate 11 September compiler-only benchmark is historical; see [Compiler Upgrade](Compiler-Upgrade.md).
The workspace evidence directory `Full-Solidity-Review-2026-09-17`, alongside the repository, contains source
hashes, test/coverage logs, unsuppressed static output and the source-specific review. It is not a committed release
archive or a replacement for the final clean-tree gate.

### Earlier local checks

| Check | Recorded result |
| --- | --- |
| Optimized full suite | **612 passed, 0 failed, 0 skipped**, 49 suites; seed `0x917`; includes 13 independent typed-payload/lifecycle/reentrant-target regressions |
| Extended stateful campaign | **23 invariants plus 2 non-vacuity tests passed** on 0.8.37, 7 suites; 256 runs at depth 256, seed `0x709`; each invariant reported 65,536 handler calls and zero handler-level reverts |
| Build and formatting | All deployable runtimes below 24,576 bytes and creation code below the normal limit; formatting and whitespace checks pass |
| Documentation and interfaces | **23 maintained Markdown documents**, **52 regenerated ABI exports**, exact compiled-source parity. Additive constant getters/errors and the empty-book reset event are included; no new production storage field or reordered field was introduced by this hardening. |
| Verification-tool tests | **11 passed**; documentation/ABI inventory and static-fingerprint tests |
| Unsuppressed static analysis | **432 labels**, 427 distinct normalized fingerprints: 6 High, 68 Medium, 264 Low, 94 Informational. Two informational-return reports and ten changed descriptions were reviewed; no detector was suppressed. See [Static Analysis Notes](Static-Analysis-Triage.md). |

| Check | Historical September result |
| --- | --- |
| Coverage campaign | **611 passed, 0 failed**, 49 suites; one 1,000-candidate stress instance excluded only from instrumentation and required in the optimized suite; a 100-candidate fixture covers the same counting path |
| Aggregate instrumented coverage | Lines **82.10% (7,997/9,740)**; statements **84.75% (9,266/10,933)**; branches **49.75% (794/1,596)**; functions **89.00% (1,262/1,418)** |
| First-party production coverage | 52 reported `contracts/` files excluding mocks: lines **84.30% (6,306/7,480)**; statements **87.34% (7,500/8,587)**; branches **48.16% (641/1,331)**; functions **88.18% (985/1,117)** |
| Constitutional provenance | Pinned source PDF SHA-256 verified; this is not constitutional/legal certification |
| Production-script rehearsal | Localhost-only two-stage mock-token/synthetic-genesis deployment passed: seven incumbents, continuity cycle, five review accounts, committee/app binding, sealed setup and retired kernel/router/office bootstrap |

The public Sepolia deployment remains the separately recorded 8 September revision
`33f501417b7fd5cbba1f43f044d9f8348acd1c7c`, compiled with 0.8.36. Its 92 successful transactions, 51 source sets
(48 Exact Match and 3 Similar Match) and 63 module pointers are historical deployment evidence, not a deployment or
explorer verification of this checkout. No public chain was changed by these local checks. See
[Sepolia Deployment](Sepolia-Demo-Deployment.md).

Test-instance counts include inherited cases and are not counts of independent security scenarios. Coverage excludes
unreported/interface files; the aggregate includes script/test instrumentation. **Production branch coverage of
48.16% is an assurance gap.** Stateful handlers catch expected rejections, so zero handler reverts is not proof that
every attempted operation succeeded; examine failure flags, ghost models and non-vacuity tests. These bounded
campaigns and scanner fingerprints are not formal verification or a security verdict.

Permanent-core coverage after adversarial payload/reentry tests:

| Component | Lines | Branches |
| --- | ---: | ---: |
| ActionTimelock | 93.86% (321/342) | 88.61% (70/79) |
| ConstitutionKernel | 95.83% (138/144) | 75.00% (18/24) |
| GovernanceRouter | 89.11% (90/101) | 69.57% (16/23) |
| BoundedGovernanceHook | 100% (37/37) | 100% (8/8) |

These percentages do not establish exhaustive state-machine coverage or prove the correctness of replacement code.

## Earlier performance measurements

Measured election calls use fixture setup in a separate transaction to expose persisted-state costs.

| Scenario | Execution gas |
| --- | ---: |
| 32 inserts into a 960-entry heap | 4,813,154 |
| One-candidate adaptive batch | 363,554 |
| Revalidate 31 disqualified provisional candidates | 2,637,085 |
| Scan 31 retained runner-ups with maximum metadata | 1,337,264 |
| Maximum supported 31-seat + 1-runner activation | 14,132,194 |

Compared with the same cold-state fixtures in the compiler-only benchmark, fixed-size eligibility reads reduce
these last three calls by approximately 10.2%, 17.8% and 2.1%, respectively. Heap insertion is unchanged. These are
fixture measurements, not promises about every transaction or future gas schedules.

Heap insertion is logarithmic. Selection revalidation and final seat activation have separate bounded costs that
are not reduced by the insertion workload selector. Finite measurements do not certify arbitrary population size,
future gas schedules or keeper incentives.

That build's `CongressCandidateRegistry` measured 23,904 runtime bytes against the 24,576-byte limit. Check the
submitted build with `forge build --sizes`.

## Requirements before mainnet authorization

- Independent security review of the complete source, deployment paths and known limits, followed by verification
  of any required changes and explicit residual-risk acceptance.
- Production-state fork testing, exact real token/proxy/configuration review, economic assessment, liquidity and
  funding verification, and verified genesis identities/stake/office/elected-role records.
- Independent office/reviewer controllers, conflict checks, key-loss/rotation procedures, evidence retention and
  lawful notice/ruling procedures. Distinct addresses alone cannot establish these conditions.
- A lawful procedure to replace a lost director and resolve historical titles without an authorized signer.
- A verified Land Office administrator and clerk with distinct person IDs and independent controllers before
  opening the two-officer dispute workflow.
- Live-wallet frontend checks, monitored keepers, rehearsed transitions, verified address manifests and final
  operational/legal sign-off. The separately recorded public Sepolia demo is not a production-state fork or mainnet
  rehearsal with real assets/controllers; the localhost production-script rehearsal remains synthetic.

The external firm should independently evaluate these assumptions and report reproducible, revision-bound findings.
