# Predeployment contract review — 3 November 2026

**Historical baseline for the same day's follow-up:** [Governance and Recovery Review](Governance-Recovery-Review.md)
records the later governed Sepolia profile, indivisible upgrade plans and bounded debt-free financial exits.
Its source-specific checks supersede the earlier counts here. The zero-debt/full-book exception now narrows the
financial-policy lock described below; the old five-contract Sepolia lab remains isolated by design.

**Result: five verified issues corrected; bounded tests pass; an unconditional “cannot get stuck” or “every
replacement works without trouble” claim is not supported.** The isolated Sepolia deployment remains suitable for
synthetic component testing. It cannot demonstrate governed upgrades: its bootstrap is retired and it deliberately
installs no governance route. Production release remains blocked by the wider integration, migration and operational
requirements below. No public-network deployment was performed.

This review targets the current working source based on `dd0005c15d20754c50a0495cf6d48298b795e1a4`, including the
uncommitted foundation and review changes. A source-hash inventory and raw reports accompany the dated workspace
review evidence. This is an engineering review with independent cross-review within the task, not an external audit
or formal verification of all possible states and future replacement bytecode.

## User-facing issues corrected

| ID | Severity and user-visible problem | Correction and evidence |
| --- | --- | --- |
| R01 | Medium: a serving minister could become Prime Minister without leaving the ministry, despite the inverse appointment being forbidden | Cabinet readiness and execution both apply the existing person-bound minister check. Tests cover all four ministries, wallet migration, resignation and exact term expiry. |
| R02 | Medium: returning to an old wallet could restore a superseded Prime Minister appointment choice | A person's latest appointment receipt is canonical. Raw wallet records remain for provenance; old choices cannot reappear after recasting, and another person's receipt at a reassigned address is preserved. |
| R03 | Medium: withdrawn Congress decision support could reappear after a wallet round-trip; recasting from a new wallet also inflated the stored support count | Decision support has one canonical receipt per person. Recasting does not increment twice; the active new wallet can withdraw without first endorsing again. Tests include an earlier wallet reassigned to another Congress member. Stored intention counts remain distinct from live, currently eligible support. |
| R04 | Medium: an ordinary Law proposal could name a constitutional/treaty measure as its amendment target | The proposal must use a constitutional tier for a constitutional target. Ordinary amendments still vote, queue and enact. The contracts record the amendment relationship; they do not interpret legal text or themselves rewrite a constitution. |
| R05 | Low availability/validation issue: a budget could expire before its earliest possible approval | Creation rejects expiry before `votingEnd + max(adoptionDelay, budgetApprovalQueueDelay)` using widened arithmetic. Ordinary and emergency delay cases and a successful approval are tested. This does not guarantee a later payout fits the remaining window. |

Changes are confined to [CabinetApp](../contracts/apps/CabinetApp.sol),
[DecisionApp](../contracts/apps/DecisionApp.sol) and [ReferendumApp](../contracts/apps/ReferendumApp.sol).
Existing public interfaces, errors, enum ordinals and political thresholds are retained. No administrator, emergency
executor, arbitrary-call route or generic state migrator was added.

Reproducing tests are in [identity/executive review](../test/security/PredeploymentIdentityReview.t.sol) and
[governance review](../test/security/PredeploymentGovernanceReview.t.sol). Original affected tests were also rerun;
the final complete suite covers their combined source. Earlier-source failures are retained with the evidence.

## Upgrade and user-journey evidence

| Journey | What the tests demonstrate | Practical limit |
| --- | --- | --- |
| Governance policy replacement | Real citizen votes, threshold, queue and permissionless execution; an existing vote keeps its pinned rules while a new vote uses the new policy | A successful pointer update does not prove arbitrary approved code is compatible or honest |
| Preplanned rollback | A ballot opened while the original policy is still current can restore it after a cutover; both generic and dedicated election-policy routes are exercised | Finalize after cutover so the queue captures the intended incumbent; stale queued targets still fail |
| Referendum app plus registry-writer replacement | Two actual approved actions replace the app and its writer; the new app continues a registry-backed vote | An intermediate individual pointer update can temporarily fail. Batch members remain separately executable |
| Cabinet and identity app replacement | Canonical executive facts remain; paired writer/app changes can restore authority. Tests show pending app-local ballots or migration approvals are not imported | Drain or explicitly preserve/restart affected procedures; do not assume address replacement copies state |
| Staking and Treasury custody | Existing adversarial tests cover exact-successor handoff, rollback timing, token failure and stable paid-request replay protection | These are narrow same-ledger handoffs, not arbitrary record migration. Complete handoff after pointer activation |
| Retired lending books | All six activation orders for the pool/lien/liquidation pointers are enumerated. Old borrowers can repay after revocation, close their book, and use the successor; old LP positions can exit when liquidity exists | Financial transition tests use a synthetic authorised timelock caller; they do not pretend to repeat every public governance vote |
| Ministry Treasury | Old balances and old-pool shares remain in the original instance. Withdrawal works after restoring the required current office facts | The app resolves the **current** OfficeRegistry; replacing that ledger without office records can block exit |
| Land and companies | Stable records/pending company requests survive compatible app replacement; fresh land consent works on the new app; independent dispute locks are released individually | Old EIP-712 signatures are bound to the old app and require re-signing. A locked parcel is not automatically unlocked by replacement |
| New Sepolia token/restrictions | Actual five-contract deployment, allocation, authority retirement, failed-write rollback, independent orders, relief and clock-only expiry | It has three fictional subjects and a test-only operator, not collective legal decisions or upgrade governance |
| Public maintenance operations | Added user flows exercise Senate support withdrawal/re-addition, successor clearing, office rename, setup retirement, Congress recall, company maintenance and parcel draft/retirement | Permission failures and procedural locks are expected protections, not functions that should accept every input |

Additional evidence: [finance/property review](../test/security/PredeploymentFinanceLandReview.t.sol),
[existing upgrade adversarial tests](../test/security/UpgradeLivenessAudit.t.sol),
[custody replacement](../test/security/StakingVaultUpgrade.t.sol),
[Treasury replacement](../test/security/TreasuryUpgrade.t.sol),
[loan retirement](../test/security/LoanRetirementIndependentAudit.t.sol), and
[new synthetic state-machine tests](../test/invariant/SepoliaFoundationInvariant.t.sol).

The review deliberately retains same-address proposals: they can be useful preplanned rollback ballots. Rejecting
them merely because they match today's pointer would remove a tested recovery option. A genuinely unchanged-address
action still reverts safely and can expire without blocking unrelated governance.

## Stuck states and recovery limits that remain

| Limit | Concrete consequence and recovery boundary |
| --- | --- |
| Approved faulty governance dependency | A real upgrade test installs incompatible referendum policy code, then cannot create the repair proposal. A suitable pre-opened rollback can repair that particular case; it is not universal recovery from broken apps, registries or core code |
| Veto/review cross-lock | Constitutional review can block Senate replacement while Senate blocks review replacement. Existing tests show neither first action in a batch can execute. Exact self-replacement exceptions do not remove this cross-lock |
| Broken live financial policy | A replacement rate policy can block repayment and LP withdrawal until a compatible policy is restored. Tests demonstrate both the block and subsequent exit. If governance is also unavailable, no general recovery route exists |
| Missing state/process migration | Repointing a registry or stateful app does not move balances, pending approvals, claims, consumed IDs or ballots. The kernel supports address updates, not a completed migration for every module |
| Authority/quorum loss | Lost controlling keys or insufficient mandated votes can prevent an authorised transition. The fixed Prime Minister removal tally can become unreachable after vacancies; term expiry is a separate existing boundary |
| Accepted land dispute | There is no automatic dispute timeout. The parcel remains locked until an authorised resolution; unrelated remaining locks still apply. The current registrar workflow is not the proposed independent judicial system |
| External assets and liquidity | A token can reject transfers, and an LP cannot withdraw cash already lent out until liquidity returns. Accounting rollback prevents partial corruption; it cannot force an issuer or borrower to provide liquidity |
| Isolated Sepolia setup | Kernel bootstrap is permanently retired with no router/timelock installed. The test token cannot mint more supply, and the test operator cannot be replaced. Finite restrictions expire without a keeper; indefinite restrictions require that operator's relief. Lost operator control means redeploying this test environment |

These are concrete retained boundaries, not promises that retrying always helps. Do not add a hidden recovery
administrator to claim universal liveness. If recovery from approved faulty code, unavailable authorities or a
veto cross-lock is a required product property, it needs a separately specified, constitutionally authorised and
audited recovery design. The permanent core itself has no replacement mechanism.

Budget timing also remains conditional: approval at its earliest boundary is not enough to guarantee a fresh payout
can complete its additional officer/queue delays. Late finalization, vetoes, funding and the selected interval must
be reviewed before a real budget is proposed. The R05 correction only rejects an already-impossible approval window.

## Verification and coverage

- Final optimized suite: **772 tests across 63 suites passed**, zero failures/skips, seed `0x110304`.
- Extended audit profile: **759 tests passed** on the same production source before the final API-only additions.
  Its **24 invariant properties each ran 256 runs of 256 calls**: 1,572,864 reported handler calls in total,
  including filtered/no-op actions. Those are per-property campaign counts, not that many distinct real user
  transactions. The 13 API additions were separately exercised and included in the final complete suite.
- The synthetic restriction invariant compares the real controller/registry against an independent finite order
  ledger. Unexpected valid-call failures are recorded explicitly rather than silently discarded by the shared
  invariant configuration's revert allowance.
- Reference models: **34 tests passed**. Tooling checks: **11 tests passed**.
- Both disposable local deployment rehearsals passed: production-shaped genesis/activation and the isolated
  Sepolia foundation. They use synthetic records/assets and are not public-network or actual-USDC fork evidence.
- Coverage: **First-party instrumented production files: **88.01% lines, 93.58% functions, 51.66% branches**. The isolated five contracts: **96.15% lines, 100.0% functions, 78.31% branches**. These are execution coverage figures, not proof of correctness**. Coverage instrumentation excludes the single 1,000-candidate
  stress setup because of instrumentation cost; the optimized complete suite includes it. The 100-candidate path
  and the other tests remain instrumented. Reported production coverage excludes mocks and scripts.
- The ABI inventory lists **810 public/external function entries across 55 exported contracts**. Enumeration is
  not proof each selector, role, input and ordering is exhaustively verified. The [function coverage inventory](review/FUNCTION-COVERAGE.csv)
  exposes unexecuted instrumented functions rather than hiding them; the [public API inventory](review/PUBLIC-API-INVENTORY.csv)
  records the exported scope. The report still contains 74 unexecuted instrumented production functions; none of the zero-hit functions were classified as public/external state-changing entry points by the source-level check. Read/helper paths and untested branches still remain. Dependencies, scripts and unimplemented proposal workflows have separate limits.
- Static analysis remains unsuppressed; see [reviewed static findings](Static-Analysis-Triage.md). Scanner severity
  counts are not confirmed-vulnerability totals. Formatting, build-size, documentation and exact ABI checks are
  recorded with the final validation. `ReferendumApp` has 1,175 bytes of runtime-size margin; future additions must
  preserve the deployment limit.

## Deployment decision

Use the [isolated Sepolia runbook](Sepolia-Foundation-Deployment.md) only for testing the completed token and
restriction components, with the limitations above. It is not evidence that the whole proposal, upgrades or recovery
procedures are implemented. The production-shaped tests validate specified transitions; a mainnet release still
needs real genesis reconciliation, authenticated legal rules, an exact-asset production fork, verified replacement
bytecode, migration/process preservation, and operational authority checks.

The requested stronger acceptance condition — every function/order works and no reachable state can ever become
stuck — is **not met**. This review provides tested behaviours, corrected defects and explicit counterexamples,
rather than an unsupported guarantee.
