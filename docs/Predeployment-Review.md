# Predeployment contract review — 3 November 2026

This source record covers the 3 November 2026 changes based on `dd0005c15d20754c50a0495cf6d48298b795e1a4`.
The same day's [governance and recovery changes](Governance-Recovery-Review.md) add governed Sepolia staging,
atomic upgrade plans and an exception for debt-free and final-loan exits. The five-contract Sepolia foundation
retires bootstrap without installing a governance route.

## User-facing issues corrected

| ID | Severity and user-visible problem | Correction |
| --- | --- | --- |
| R01 | Medium: a serving minister could become Prime Minister without leaving the ministry, despite the inverse appointment being forbidden | Cabinet readiness and execution both check the person's current ministerial appointment. |
| R02 | Medium: returning to an old wallet could restore a superseded Prime Minister appointment choice | A person's latest appointment receipt is canonical. Raw wallet records remain for provenance. Recasting supersedes old choices and preserves another person's receipt at a reassigned address. |
| R03 | Medium: withdrawn Congress decision support could reappear after a wallet round-trip. Recasting from a new wallet also inflated the stored support count | Decision support has one canonical receipt per person. The active new wallet can withdraw without endorsing again. Stored intention counts and live eligible support are distinct. |
| R04 | Medium: an ordinary Law proposal could name a constitutional or treaty measure as its amendment target | A constitutional target requires a constitutional tier. The contracts record the amendment relationship. |
| R05 | Low: a budget could expire before its earliest possible approval | Creation rejects expiry before `votingEnd + max(adoptionDelay, budgetApprovalQueueDelay)` using widened arithmetic. A payout may still fall outside the remaining window. |

Changes are confined to [CabinetApp](../contracts/apps/CabinetApp.sol),
[DecisionApp](../contracts/apps/DecisionApp.sol) and [ReferendumApp](../contracts/apps/ReferendumApp.sol).
Existing public interfaces, errors, enum ordinals and political thresholds are retained. No administrator, emergency
executor, arbitrary-call route or generic state migrator was added.

Reproduce these cases in [identity and executive checks](../test/security/PredeploymentIdentityReview.t.sol) and
[governance checks](../test/security/PredeploymentGovernanceReview.t.sol).

## Upgrade and user-journey evidence

| Journey | Contract behavior | Practical limit |
| --- | --- | --- |
| Governance policy replacement | Citizen votes reach the threshold, queue the action and allow permissionless execution. An existing vote keeps its pinned rules while a new vote uses the new policy | Review compatibility and behavior of the replacement policy |
| Preplanned rollback | A ballot opened while the original policy is current can restore it after a cutover through the generic or dedicated election-policy route | Finalize after cutover so the queue captures the intended incumbent. Stale queued targets fail |
| Referendum app plus registry-writer replacement | Two approved actions replace the app and its writer. The new app continues a registry-backed vote | An intermediate individual pointer update can temporarily fail. Batch members remain separately executable |
| Cabinet and identity app replacement | Paired writer and app changes preserve canonical executive facts. Pending app-local ballots and migration approvals require explicit handling | Drain, preserve or restart pending procedures |
| Staking and Treasury custody | Handoff targets the exact successor. The budget registry retains paid-request replay protection | Complete same-ledger custody handoff after pointer activation. Record migration is separate |
| Retired lending books | Old borrowers can repay after revocation, close their book and use the successor. Old LP positions can exit when liquidity exists | Review pool, lien and liquidation pointer ordering and the conditions for settlement |
| Ministry Treasury | Old balances and old-pool shares remain in the original instance. Withdrawal works after restoring the required current office facts | The app reads the current OfficeRegistry. Replacing that ledger without office records can block exit |
| Land and companies | Stable records and pending company requests survive compatible app replacement. The new app accepts fresh land consent. Dispute locks release individually | EIP-712 signatures bind the app address and require re-signing. Existing parcel locks survive replacement |
| Sepolia token and restrictions | Five contracts cover allocation, authority retirement, independent orders, relief and time-based expiry | The foundation has three synthetic subjects, a test-only operator and no upgrade governance |

Reproduce related cases in [finance and property](../test/security/PredeploymentFinanceLandReview.t.sol),
[upgrade liveness](../test/security/UpgradeLivenessAudit.t.sol),
[custody replacement](../test/security/StakingVaultUpgrade.t.sol),
[Treasury replacement](../test/security/TreasuryUpgrade.t.sol),
[loan retirement](../test/security/LoanRetirementIndependentAudit.t.sol), and
[the Sepolia foundation invariant](../test/invariant/SepoliaFoundationInvariant.t.sol).

A proposal may target the current address so a rollback ballot can open before cutover. An action that still
targets an unchanged address at execution reverts and can expire without blocking unrelated governance.

## Stuck states and recovery limits that remain

| Limit | Concrete consequence and recovery boundary |
| --- | --- |
| Approved faulty governance dependency | An incompatible referendum policy can block creation of the repair proposal. A preopened rollback helps only if its existing authorization and execution path still work |
| Veto and review cross-lock | Constitutional review can block Senate replacement while Senate blocks review replacement. Exact self-replacement exceptions leave this cross-lock in place |
| Broken live financial policy | A replacement rate policy can block repayment and LP withdrawal until a compatible policy is restored. The later [governance and recovery changes](Governance-Recovery-Review.md) narrow this for debt-free and final-loan exits |
| Missing state or process migration | Repointing a registry or stateful app changes its address. Balances, pending approvals, claims, consumed IDs and ballots need separate migration |
| Authority or quorum loss | Lost controlling keys or insufficient votes can prevent an authorized transition. Vacancies can put the fixed Prime Minister removal tally out of reach. Term expiry follows its own rule |
| Accepted land dispute | The parcel stays locked until an authorized resolution. Unrelated locks continue to apply. See the [current land workflow](Land-Cadastre.md#office-workflow) |
| External assets and liquidity | A token can reject transfers, and an LP must wait for liquidity to withdraw cash already lent out |
| Isolated Sepolia setup | Kernel bootstrap retires without installing the router or timelock. The token has fixed supply. Finite restrictions expire without a keeper. Indefinite restrictions require relief from the test operator. Losing that operator requires redeployment |

The permanent core has no replacement mechanism. Recovery from unavailable authorities or a veto cross-lock
requires separate constitutional authority. For budget proposals, allow time for officer action, queue delays,
funding and possible vetoes after approval.

## Verification and coverage

Use the [auditor commands](Auditor-Handoff.md#reproduce-the-checks) on the submitted revision. The optimized suite
includes the 1,000-candidate stress case. The coverage profile instruments the equivalent 100-candidate path.
Review error branches, role changes and ordering cases separately. The synthetic restriction invariant compares
controller and registry state with a finite order ledger and records unexpected failures of valid calls.

The [historical public API inventory](review/PUBLIC-API-INVENTORY.csv) covers the earlier exported scope. See
[Static Analysis Notes](Static-Analysis-Triage.md) for the scanner findings and assumptions.

## Deployment decision

Use the [isolated Sepolia runbook](Sepolia-Foundation-Deployment.md) for the token and restriction components.
A mainnet release requires real genesis reconciliation, authenticated legal rules, a fork using the intended
assets, verified replacement bytecode, preservation of records and pending proceedings, and verified operator
authority.
