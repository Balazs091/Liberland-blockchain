# Phase A acceptance and implementation gates

These 3 November 2026 acceptance criteria use baseline `dd0005c15d20754c50a0495cf6d48298b795e1a4`.
The architecture recommendations were accepted for development. Apply the relevant criteria to each release
and review later Justice decisions against these earlier scenarios. [Justice procedures](JUSTICE.md)

## Deliverable status

| Work | 3 November scope | Release requirement |
| --- | --- | --- |
| Source baseline | October baseline and November foundation source | Review final release diff and reproducible build |
| Architecture | Recommendations accepted; limited foundation implemented | Exact legal inputs and S01–S07 integration closure for affected slices |
| Authority map | Original source, new foundation gates and future workflows separated | Verify actual release deployment and independent controller arrangements |
| Interfaces | Actual token/restriction APIs and internal primitives; future typed workflow sketches | Exact legal parameters, writer and consumer integration |
| Genesis / conditional migration | Fresh mainnet genesis, manifest template and synthetic fixture | Actual genesis records, mapping, manifest commitment, workflow setup and full release rehearsal |
| Legal rules | All recommendations accepted; remaining concrete inputs listed by L ID | Full governing texts, exact tables and authority/effective-date evidence |
| Gas/algorithm proof | Reference models, restriction-registry tests and isolated cold-state primitive benchmarks | Legal allocation/mapping choices, integrated bounded progress and growth evidence |

## Foundation scope on 3 November

The foundation covered fixed supply, independent restrictions, module classification and USDC configuration.
The legacy localhost fixture uses seven synthetic citizens and a mock USDC at the canonical address. It exercises
preparation, completion and bootstrap retirement. The restriction registry was separate at that stage. The Justice
profile adds the standing writer, case decisions and electorate integration. [Engineering progress](ENGINEERING-PROGRESS.md)

## Worked specification vectors

| ID | Given and action | Required result | Dependencies |
| --- | --- | --- | --- |
| T01 | Identity admin appoints an unlinked clerk they control, then tries civic/recovery effects after cutover | Both lack the new standing authority; no effect | A02, S04/S07 |
| T02 | Valid admission recommendation but missing route-specific final approval | No citizenship grant unless the exact approved deemed rule applies | L01/L05 |
| T03 | Citizen has political restriction until Nov 10 and representation restriction until Dec 1 | On Nov 11 only representation remains restricted | L02, S01 |
| T04 | Additional political order to Nov 20 is stayed/rescinded | Earlier political order remains effective only until its own Nov 10 boundary | L02/L05, S01 |
| T05 | Restriction expires with no transaction for ten blocks | Direct current permission reflects expiry; no stale new aggregate certificate | L02, S02 |
| T06 | Keeper catches up in block N | Cannot certify N-1 retroactively; use a valid completed-block certificate afterwards | S02 |
| T07 | Membership/stake mutation occurs after a certificate in the same block | Final certificate for that block is refreshed or invalidated consistently | S02 |
| T08 | Citizen policy updated, old candidate/election pointers remain | Incompatible new paths reject; no silent mixed-rule activation | S07 |
| T09 | Active vote pins old policy while a new restriction becomes effective | Follow the expressly approved active-process rule; never silently change its snapshot | L10 |
| T10 | One Senator has enough seat weight but fewer than three distinct supporters | Minimum-person rule still fails where legally required | L04, S03 |
| T11 | Commission has seven people but exclusions leave two eligible | No three-person determination; record shortfall and use only lawful remedy | L03, S03 |
| T12 | A voting mandate expires without another transaction | Read/finalise follows approved decision-time rule; epoch alone cannot preserve invalid authority | L04 |
| T13 | Same approval used for another person, destination, amount, chain, revision or issuer | Exact hash/domain check rejects | S04 |
| T14 | Provisional order is authorised before full case finality | Execute only its authorised interim effect, no final removal or financial consequence | L05, S04 |
| T15 | Receipt consumed, downstream registry write reverts | Whole transaction rolls back; valid receipt is not lost | S04 |
| T16 | Stay arrives after approval but before execution | Stayed effect cannot execute; unrelated orders remain unchanged | L05 |
| T17 | 100 Exposed at finality is withdrawn, then replaced with 100 new Exposed | New units cannot replenish the earlier eligible compensation cohort | L07/L08, S05 |
| T18 | Liquidation bypasses vault entrypoints | Provenance and reservations still reconcile atomically | S05 |
| T19 | One of two reservations expires/is released | Other reservation and required loan floors remain protected | L08, S05 |
| T20 | Retired loan remains open with zero lien and captured floor | Preserve original lawful settlement/floor semantics | L08 |
| T21 | Beneficiary refuses restricted active stake | Cannot force that payout as if liquid compensation; follow approved election rule | L08 |
| T22 | Restoration pool underfunded or entitlement claimed twice | No new unfunded stake and no double payment | L08, S05 |
| T23 | Old wallet objects to exceptional recovery | Apply the approved hearing/interim rule, no invented automatic override | L06 |
| T24 | Destination becomes linked or old link changes before recovery executes | Exact expected-state/nonce check rejects stale effect | S04 |
| T25 | Voluntary migration uses old/new typed consent, then replays old signatures | Replay rejected; define ERC-1271 consent validity point | L06 |
| T26 | One of multiple accepted land disputes resolves | Other dispute lock remains | L12, S06 |
| T27 | Geometry/encumbrance affects another owner without their consent or exact judgment | No substantive registry mutation | L12, S06 |
| T28 | Land version changes after remedy approval | Stale remedy rejected, never reinterpreted | S06 |
| T29 | Cheap repeated complaints request automatic parcel locks | Standing/screening/expiry rules prevent an unreviewed permanent veto | L12 |
| T30 | Migration leaf is repeated, modified or sent on another chain/release | Defined idempotence/already-used result; modified/cross-domain import rejected | L09/L10, S07 |
| T31 | Any queue member executes alone, late, out of intended order or after another is cancelled | Approved partial-state invariant holds or transition is rejected before release | S07 |
| T32 | Writer or issuer replaced with open and consumed receipts | Approved continuity preserves rights and prevents replay/standing old powers | L10, S04/S07 |
| T33 | Operator withholds expiry/notice/execution transactions | No adverse outcome invented from inactivity; permitted timeouts remain submitter-independent | L05 |
| T34 | Membership change feeds generic good-standing check | Consumer-specific rule prevents accidental property/credit restrictions | L02/L08 |
| T35 | Public case storage/calldata links person to matter despite encrypted evidence | Privacy review rejects any contrary confidentiality claim | L11 |
| T36 | Unrelated metadata, wallet or independent-order revision changes after approval | Scoped precondition/retry preserves the original authorised effect without granting substituted content | S04 |

## Algorithm and gas evidence

For S01–S07, provide reference models, independently derived outcomes, adversarial boundary vectors and complexity bounds.
Verify each required integration as well as its isolated components.

Future implementation benchmarks must cover cold persisted state and maximum supported sizes: three-person case; Congress fallback; 100 Senate seats with distinct and duplicate people; exhausted rota; many historical orders; five-right insertion/stay/removal; expiry backlog; underfunded/failing 500,000-gas source callback; receipt consumption with failed downstream write; maximum parcel set; many claim cutoffs and migration leaves.

Test bounded progress independently of successful completion. Record non-vacuity counters for borrowing, repayment, liquidation, bad-debt handling, overlap/expiry, denied effects and interrupted migration. Retain the existing complete regression suite. Reject unbounded cleanup and prove consumed IDs, custody and snapshots remain correct between batches.

## Review and implementation approval

Each feature's review record must identify exact source/doc hashes, resolved L/S items, approved interface/effect schema, required operational services and independent reviewers. Proposed roles must be assigned to actual people by the project; this package does not appoint them.

Each integration needs the exact rules and evidence it consumes. Admission can proceed separately from unresolved land remedies.

Before activation, verify audited bytecode and constructor arguments, token and proxy controllers, authority retirement,
custody, snapshot certification, the applicable genesis or migration rehearsal, and the people responsible for notices,
records and keeper calls. Obtain release approval from the competent authority.
