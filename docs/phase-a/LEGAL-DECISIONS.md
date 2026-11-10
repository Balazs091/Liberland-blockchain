# Legal and governance implementation register

The 3 November 2026 decision accepted the engineering recommendations and authorised contract development.
This register uses source `dd0005c15d20754c50a0495cf6d48298b795e1a4` and the 19 October guide and presentation.
The guide's Rev. 3.2 and article references still require the complete controlling text and commencement records.
The 10 November Justice profile records the later implementation choices. [Implementation decision record](IMPLEMENTATION-DECISIONS.md),
[Justice procedures](JUSTICE.md)

## Status and recording rules

- **ACCEPTED / INPUTS PENDING** means the recommendation is accepted and the named details are outstanding.
- Contract work may proceed within the accepted boundaries. A dependent legal effect needs its specified rules and authority before activation; no generic administrator or arbitrary executor may fill a gap.
- Confirm the statutory approving authorities, full legal texts, versions and effective dates before activation.
- The roles below are proposed coordinators, not appointments. O03 assigns the user responsibility for supplying genesis inputs; actual records, approvers, independent checkers and dates remain to be provided.
- Record later answers by ID, exact scope and exceptions, supporting text/version, effective date and actual approving authority. Record a partial answer as partial rather than resetting an accepted principle to OPEN.

## L01 Governing text and commencement

**Status: ACCEPTED / INPUTS PENDING. Coordinator:** legal lead with authorised legislative/governance representative.

**Accepted:** Version each procedure's rules; use bounded design assumptions while keeping unsupported powers inactive; reconcile regular admission, descent, birth, honorary recognition, renunciation, annulment and court exceptions individually. The presentation and guide are not treated as the legislation itself.

**Still needed:** Complete controlling Citizenship Act/Constitution texts, version/hash, adoption and commencement records, constitutional authority and transition clauses. Supply route-specific signers, minor/guardian rules, provider accreditation authority, Minister/President acts and silence/deemed outcomes.

**Dependent completion:** Legal-version identifiers and enforceable authority/route rules. Independent mechanics may continue.

## L02 Membership rights and constitutional headcount

**Status: ACCEPTED / INPUTS PENDING. Coordinator:** citizenship/governance legal lead.

**Accepted:** Keep citizenship separate from membership. Track right-specific independent orders and preserve unrelated property, repayment and defence rights. Overlap, staying and reversal must not clear another order. Do not equate political restriction with a lending ban.

**Still needed:** A rights-by-measure table, including membership lifecycle effects and any future-start measures. Choose constitutional headcount treatment: **R0**, restricted people remain counted while their current rights are restricted; or **R1**, specified restrictions also change the constitutional roll. The accepted recommendation deliberately did not select this legal denominator.

**Dependent completion:** Rights-consumer integration and electorate/policy bundle. Storage for independent currently effective orders can be implemented without choosing R0/R1.

## L03 Appointments, conflicts and shortfalls

**Status: ACCEPTED / INPUTS PENDING. Coordinator:** institutional-procedure legal lead.

**Accepted:** Person-bound appointments with explicit terms/nonces; defined incompatibilities, prior-participant exclusions and lawful shortfall remedies. Keep Commission and disciplinary Council/Panel appointments separate. An operator cannot choose substitutes or reduce a threshold. Canonical roster ordering needs an approved rule.

**Still needed:** Nomination, appointment, veto, removal and replacement authority for each body; terms and qualifications; conflict and objection rules; stage-by-stage exclusions; lawful remedy when eligible members are insufficient; sorting/publication rules. Identify the constitutional basis for any new positive Senate approval or adjudication role.

**Dependent completion:** Typed appointment issuer, roster/rota and assigned panel procedures. Existing DecisionApp does not itself issue commissioner appointments.

## L04 Votes, mandates and mode changes

**Status: ACCEPTED / INPUTS PENDING. Coordinator:** constitutional/governance legal lead.

**Accepted:** Use a rule table per decision. Count Senate seats separately from distinct people; distinguish mode epoch, roster revision and appointment nonce. Read-time term expiry must matter without a cleanup transaction. A generic majority rule cannot substitute for the table.

**Still needed:** Each decision's quorum, denominator, threshold, abstention/recusal/vacancy treatment and decision-time eligibility. Specify whether incomplete votes survive wallet migration, term expiry, seat transfer, Congress turnover or fallback mode changes, and which deadlines survive.

**Dependent completion:** Real body ballots and finalisation. Arithmetic helpers can be tested independently of a legal denominator.

## L05 Notice, clocks, legal effect, finality and stays

**Status: ACCEPTED / INPUTS PENDING. Coordinator:** procedural-law lead with notice operations lead.

**Accepted:** Distinguish approval, effect, finality, stay and execution. Define each clock separately; a published hash alone is not service or access to evidence. Preserve lawful provisional effects and make execution deterministic after its gates. A keeper's absence cannot invent a legal outcome.

**Still needed:** Valid service evidence/channels, start events and exact deadlines, fixed versus calendar periods, applicable interim effects, appeal/stay rules and silence/deemed exceptions. Resolve the guide/PPT difference: is annulment review **mandatory**, or **available on request before a deadline**?

**Dependent completion:** Route/case state machines, service attestations, timeouts, finality and execution gates.

## L06 Wallet recovery and contested hearing

**Status: ACCEPTED / INPUTS PENDING. Coordinator:** identity/recovery legal lead with security lead.

**Accepted:** Require destination consent, current identity/link/nonce checks, accredited evidence, lawful notice, independent authorised review and a defined contested hearing. Voluntary dual-key migration remains separate. Recovery does not move external balances or reveal private keys. Neither automatic override nor an indefinite old-key veto is presumed.

**Still needed:** Select the second body and its legal authority: independent Commission review, expressly authorised Senate review, or another named body. Specify notice periods, old-key objection/hearing/appeal rules and any temporary compromised-key protections. The prior recommendation asked for this choice; it did not select one.

**Dependent completion:** Exceptional recovery authority and finalisation, and any change to current old-wallet cancellation protection.

## L07 Legacy/Exposed Merits, consent and cutoff

**Status: ACCEPTED / INPUTS PENDING. Coordinator:** staking/property legal lead with accounting lead.

**Accepted:** Preserve pre-existing commitments until a lawful explicit rule. Bind informed acceptance to person, terms, amount/scope, nonce and time. Third-party funding does not prove recipient consent. Later deposits must not refill an exhausted earlier claim cohort. Preserve provenance across every canonical mutation.

**Still needed:** Genesis classifications and effective date, acceptance terms, eligible claim cohorts and treatment of withdrawals, transfers, liquidations and restoration. Choose an allocation and rounding rule with worked examples. The reference model demonstrates that repeated small pro-rata withdrawals can differ from one larger withdrawal; that model is not an approved accounting rule.

**Dependent completion:** Production exposure ledger and canonical stake accounting changes, including all liquidation paths.

## L08 Compensation, loans and funded restoration

**Status: ACCEPTED / INPUTS PENDING. Coordinator:** financial/property legal lead with lending/custody lead.

**Accepted:** Preserve existing loan rights; prevent double pledging; independent claim reservations; finality/provenance limits; real allocated restoration funding. Political and financial effects require separate approvals. Active stake is not a liquid payout, and slashing accounting alone is not compensation payment.

**Still needed:** Exact priority among lender liens, reservations, final claims and pending claims; lawful stage for financial restrictions; new borrowing against reserved amounts; liquid versus active-stake settlement and beneficiary choice; funding and restoration source; competing-claim/insolvency treatment. No treasury bailout is assumed.

**Dependent completion:** Reservations, compensation, loan interactions, settlement and restoration. A vault-only hook is insufficient because direct stake liquidation paths exist.

## L09 Historical and genesis mapping

**Status: ACCEPTED / INPUTS PENDING. Coordinator:** records legal lead with register custodian.

**Accepted:** Evidence-based category mapping with an explicit review path for unknown/disputed grounds. Preserve original records and enum meanings. No blanket restoration, exclusion or promotion from an ambiguous status.

**Still needed:** Official source/version and person records, historical decisions/reasons and appeals, mapping categories and authorised ambiguity/notice process. O03 assigns supply of genesis inputs to the user; the actual records are pending.

**Dependent completion:** Genesis mapping, import leaves and eligibility of ambiguous records.

## L10 Process rights at fresh production genesis

**Status: ACCEPTED / INPUTS PENDING. Coordinator:** transition legal lead with deployment/operations lead.

**Accepted:** Fresh production deployment; verify demo separately. No automatic import of demo proceedings. Preserve valid official process rights and pinned rules; decide treatment by category rather than blanket cancellation. If a live migration is later added, its individual executable steps and intermediate states require review.

**Still needed:** Identify official unfinished applications, appeals, recoveries, votes, financial claims and land disputes that genesis must recognise. For each category, give the continuation/import/restart rule and lawful notice/consent. Explicitly record evidence when a category does not apply.

**Dependent completion:** Genesis procedural import and activation manifest. The Oct29 demo probe is not production source data or a fresh verification.

## L11 Public facts and private evidence

**Status: ACCEPTED / INPUTS PENDING. Coordinator:** privacy legal lead with information-security lead.

**Accepted:** Specify the public/private boundary before case storage and event design; keep evidence access controlled and encrypted as appropriate. Salt commitments where useful. Do not claim case numbers, encrypted documents or pointer changes hide or erase public transaction history.

**Still needed:** A public-field list covering person/subject links, case existence, votes, outcomes, reasons, body members and commissioner names; retention, access and delivery rules. Choose public procedure with private evidence, or confidentiality of subjects/case existence requiring a substantially different design. The recommendation required this choice rather than assuming public subjects.

**Dependent completion:** Public case APIs/events, vote submissions, KYC/notice retention and commissioner publication. A person-linked registry inherently exposes its on-chain facts and cannot itself satisfy confidential-subject requirements.

## L12 Land jurisdiction, consent, locks and remedies

**Status: ACCEPTED / INPUTS PENDING. Coordinator:** land-law lead with registry custodian.

**Accepted:** Preserve dual-consent sales; separate adjudication from recording; finite exact remedies with version checks; independent dispute locks; service/appeal/stay controls. Filing alone cannot gain an assumed automatic lock or title-transfer power.

**Interim safeguard implemented:** A verified Land Office clerk must approve each exact dispute action before a distinct verified registrar can finalize it. The current process records outcomes and applies or lifts case locks. A separate land law is still needed for adjudication and remedies.

**Still needed:** Adopted land regulation, named bodies/jurisdiction, appointment rules, exact title/boundary/encumbrance remedies, consent exceptions, filing screening, lock creation/release/stay/relief rules and example judgments. Specify any proposed seven-day lock's lawful trigger and abuse controls.

**Dependent completion:** Land case app, adjudication bodies and authoritative registry writer/remedy interfaces.

## L13 Special roles, Cabinet, courts and delegations

**Status: ACCEPTED / INPUTS PENDING. Coordinator:** constitutional/institutional legal lead.

**Accepted:** Narrow named powers with explicit mandates, scope and expiry. A Prime Minister signature is not presumed to be a collective Cabinet decision. Honorary recognition grants no political citizenship. Judicial effects use typed authenticated judgments rather than arbitrary operations.

**Still needed:** Presiding-officer selection and authority; permitted urgent delegations and term; collective Cabinet composition/quorum/voting for honorary recognition; authenticated court/judge appointments, jurisdiction and exact judgment/confirmation/stay powers.

**Dependent completion:** Honorary route, urgent measures, presiding officer and judicial interfaces.

## L14 Constitutional-office protection

**Status: ACCEPTED / INPUTS PENDING. Coordinator:** constitutional legal lead with competent office authority.

**Accepted:** Refer protected consequences to the competent constitutional procedure. Separate membership ending, right restriction, ordinary dismissal and constitutional removal. Revalidate relevant person-bound office facts at the legally required stages; discipline is not a shortcut to remove an office-holder.

**Still needed:** Office-by-measure protection/referral table for Presidency, Senate, Congress and executive offices, including which office duties remain exercisable, permissible restrictions outside those duties, competent body and time-of-check rules.

**Dependent completion:** Protected office consequences and appointment/representation policies.

## Operational answers and remaining inputs

| ID | Recorded answer on 3 November | Remaining input |
|---|---|---|
| O01 | **RESOLVED:** Ethereum mainnet, chain ID `1` | Release engineering verifies EVM compatibility and network state; no new network preference question |
| O02 | **RESOLVED direction:** implement Liberland Merit; canonical Ethereum L1 USDC. Engineering selects 18 decimals and retains existing 70 million LLM cap | Actual LLM fixed genesis supply and recipient/allocation; token release verification. Canonical USDC is `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48`, 6 decimals ([Circle](https://developers.circle.com/stablecoins/usdc-contract-addresses)) |
| O03 | **OWNER RECORDED:** the user will supply all genesis inputs | Actual official records, asset allocations/backing, appointments, approvals, independent checker and delivery date |

The 3 November questions collect the remaining facts and rule choices at that date. [Decision-maker questions](DECISION-MAKER-QUESTIONS.md)

## Later decision record format

Use the existing ID and record exact rule/exception, approving authority and legal basis, supporting text/version/hash, decision and effective dates, actual owner and technical consequence. Status may be **ACCEPTED / INPUTS PENDING**, **PARTIALLY SPECIFIED** or **SPECIFIED WITH EVIDENCE**. Deployment authorisation and final release verification are separate from this implementation register.
