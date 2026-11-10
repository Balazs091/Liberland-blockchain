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

The 10 November published justice baseline was `00da5bce5a4ac75fb35c8adc2e1168d43ad82d17`.
[GitHub CI](https://github.com/Balazs091/Liberland-blockchain/actions/runs/42818112204).

The 5 November source archive identifies a separate working-tree snapshot. See the
[archive and verification record](Comprehensive-Review.md).

### Earlier 3 November verification

Separate records identify the source and results for the 3 November baseline and the subsequent compiler and
dependency upgrade. [Complexity Review](Complexity-Review.md) · [Toolchain Upgrade](Toolchain-Upgrade.md).

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

## Historical September revisions

The 17 September snapshot used `ccea1facde0cedb491dc864a2f4dc00e3a04c4bd` as its base, with Forge 1.7.1,
Solidity 0.8.37 and Slither 0.11.5. See [Compiler Upgrade](Compiler-Upgrade.md) for the earlier compiler baseline.

### Coverage interpretation

Inspect uncovered branches on the submitted revision. Inherited tests contribute to the test count, and stateful
handlers catch expected rejections. Check their failure flags, ghost models and non-vacuity tests.

The 8 September public Sepolia deployment used `33f501417b7fd5cbba1f43f044d9f8348acd1c7c` and Solidity 0.8.36.
Its deployment and explorer records apply to that revision. [Sepolia Deployment](Sepolia-Demo-Deployment.md).

## Election gas and runtime size

Use the [cold-state fixtures](../test/security/EfficiencyAudit.t.sol) to measure insertion, candidate revalidation,
runner-up succession and final seat activation. Heap insertion is logarithmic. Reducing the insertion workload
does not reduce the separate cost of revalidation or activation. Check `CongressCandidateRegistry` against the
24,576-byte runtime limit with `forge build --sizes`.

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
