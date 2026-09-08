# Release Readiness

Status: ready for external audit scoping and independent security review; **not authorized for mainnet launch**.
The package's `PROVENANCE.json` identifies the exact source commit, tree, dependency revisions and toolchain.
Verify the package checksums before relying on its contents.

## Submission contents and scope

The submission includes current contracts, interfaces, tests, deployment scripts, network parameters, documentation,
frontend ABIs and pinned dependency source, with reproducible verification evidence. Review every production path,
not just the test-covered scenarios. Mocks and demo-only modules are included to make their separation explicit;
they are not production assets or authorities.

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
| Election progress | Pinned-cycle finalization and next-cycle creation are separate operations. Finalization supports a 1–32 workload; next-cycle creation retains cadence and incumbent registration. Failed future scheduling does not reverse a completed result. See `EfficiencyAudit.t.sol` and Congress tests/invariants. |
| Senate support | Support is bounded by the stable registry's seat universe. Negative powers require an occupied-seat majority, at least two direct seat votes and any higher policy minimum; President proxy substitution is not provided. |
| Identity and civic process | Consent/nonces, current office appointments, seven-day notice, one appeal, an exact-case 3-of-5 committee, a 30-day dismissal timeout and a two-day post-upheld delay are in scope. Hashes and distinct addresses do not prove lawful evidence or independent controllers. |
| Finance and other domains | Treasury payout routing requires distinct current Finance officers. Source-authorized decisions, land consent/versioning, electorate synchronization, interest/reserve/rounding arithmetic and sealed two-stage genesis remain in scope. |

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
4. **Atomic batches do not lock members together.** `executeActions` is atomic for that invocation, but ready
   members can also execute individually. Review intermediate pointer states and overlapping execution windows.
5. **Optional hook compatibility is a trust boundary.** Failure is fail-open under the documented ABI/gas contract.
   The core cannot distinguish accidental failure from intentional incompatibility. Future hook implementations
   and chain gas repricing require renewed compatibility checks.
6. **Economic and legal inputs are not certified by code.** The fixed oracle can become economically wrong.
   Token/proxy controls, liquidity, liquidation incentives, bad debt, evidence availability, notice, legal grounds,
   real controllers and company/land signer continuity require independent assessment.

[Upgrade and Liveness](Upgrade-And-Liveness.md) contains the module-by-module dependency and recovery map.
These limits must be included in audit scoping and launch-risk decisions, not treated as deployment guarantees.

## Verification evidence

Toolchain: Forge 1.7.1, Solidity 0.8.36, Slither 0.11.5; Osaka, optimizer 200, no via-IR in deployable builds.
The source is tested without raising deployment-size or transaction-cap settings to conceal failures.
The source package requires a clean exact-commit release gate; raw results accompany it.

| Check | Recorded result |
| --- | --- |
| Optimized full suite | **529 passed, 0 failed, 0 skipped**, 46 suites |
| Extended stateful campaign | **23 invariants plus 2 non-vacuity tests passed**, 7 suites; 256 runs at depth 256, seed `0x709`; each invariant reported 65,536 handler calls and zero handler-level reverts |
| Coverage campaign | **528 passed, 0 failed**, 46 suites; one 1,000-candidate stress instance excluded only from instrumentation and required in the optimized suite; a 100-candidate fixture covers the same counting path |
| Aggregate instrumented coverage | Lines **81.53% (7,914/9,707)**; statements **84.32% (9,193/10,903)**; branches **47.83% (762/1,593)**; functions **88.47% (1,251/1,414)** |
| First-party production coverage | 52 reported `contracts/` files excluding mocks: lines **83.63% (6,241/7,463)**; statements **86.81% (7,438/8,568)**; branches **45.91% (611/1,331)**; functions **87.66% (980/1,118)** |
| Build and formatting | All deployable runtimes below 24,576 bytes and creation code below the normal limit; formatting and whitespace checks pass |
| Documentation and interfaces | **22 maintained Markdown documents**, **52 ABI exports**, exact compiled-source parity |
| Verification-tool tests | **11 passed**; documentation/ABI inventory and static-fingerprint tests |
| Unsuppressed static analysis | **432 labels**, 427 distinct normalized fingerprints: 6 High, 66 Medium, 266 Low, 94 Informational; see [Static Analysis Notes](Static-Analysis-Triage.md) and the raw JSON |
| Constitutional provenance | Pinned source PDF SHA-256 verified; this is not constitutional/legal certification |
| Production-script rehearsal | Localhost-only two-stage mock-token/synthetic-genesis deployment passed: seven incumbents, continuity cycle, five review accounts, committee/app binding, sealed setup and retired kernel/router/office bootstrap |

Test-instance counts include inherited cases and are not counts of independent security scenarios. Coverage excludes
unreported/interface files; the aggregate includes script/test instrumentation. **Production branch coverage of
45.91% is an assurance gap.** Stateful handlers catch expected rejections, so zero handler reverts is not proof that
every attempted operation succeeded; examine failure flags, ghost models and non-vacuity tests. These bounded
campaigns and scanner fingerprints are not formal verification or a security verdict.

## Performance and maintenance constraints

Measured election calls use fixture setup in a separate transaction to expose persisted-state costs.

| Scenario | Execution gas |
| --- | ---: |
| 32 inserts into a 960-entry heap | 4,813,154 |
| One-candidate adaptive batch | 363,554 |
| Revalidate 31 disqualified provisional candidates | 2,936,510 |
| Scan 31 retained runner-ups with maximum metadata | 1,627,332 |
| Maximum supported 31-seat + 1-runner activation | 14,431,650 |

Heap insertion is logarithmic. Selection revalidation and final seat activation have separate bounded costs that
are not reduced by the insertion workload selector. Finite measurements do not certify arbitrary population size,
future gas schedules or keeper incentives.

CongressCandidateRegistry is 23,904 runtime bytes, leaving **672 bytes** beneath the 24,576-byte limit. Treat this
as a maintenance constraint. Additional decomposition, paginated UI reads or new cancellation workflows require
measured requirements, explicit interfaces and their own review; they are not included features.

## Requirements before mainnet authorization

- Independent security review of the complete source, deployment paths and known limits, followed by verification
  of any required changes and explicit residual-risk acceptance.
- Production-state fork testing, exact real token/proxy/configuration review, economic assessment, liquidity and
  funding verification, and verified genesis identities/stake/office/elected-role records.
- Independent office/reviewer controllers, conflict checks, key-loss/rotation procedures, evidence retention and
  lawful notice/ruling procedures. Distinct addresses alone cannot establish these conditions.
- A lawful operational procedure for company-owned land when directors are lost or the company is dissolved.
  The contracts provide no general registrar takeover or universal judicial executor.
- Live-wallet frontend checks, monitored keepers, rehearsed transitions, verified address manifests and final
  operational/legal sign-off. No public deployment or production-state fork is claimed by the local rehearsal.

The external firm should independently evaluate these assumptions and report reproducible, revision-bound findings.
