# Remaining implementation inputs for decision makers

These questions record the remaining inputs on 3 November 2026, after the engineering recommendations were accepted.
Check the 10 November Justice decisions before using this list for a new review. [Justice procedures](JUSTICE.md)

**Already settled:** Fresh production deployment on Ethereum mainnet, chain ID 1; project-built Liberland Merit with 18 decimals and the existing 70 million cap; canonical Ethereum USDC; the user supplies all genesis inputs. The implemented LLM contract has a fixed constructor-funded supply and no later mint authority. Its actual supply and recipient are genesis inputs.

## Needed for identity, membership and appointments

1. **L01 — Which exact rules apply?** Supply the complete Citizenship Act and Constitution versions, adoption/effective dates and transition rules. For each admission route, identify the required officials, guardian/minor rules, identity-provider approval and any approval by silence.
2. **L02 — Who counts in a constitutional vote?** Does a citizen with temporarily restricted political rights remain in the electorate headcount (**R0**), or do specified restrictions also remove them from that headcount (**R1**)? Supply the list of rights each measure restricts, including any future-start measures. Keeping restrictions separate has already been accepted.
3. **L03/L04 — Who appoints and who can decide?** For Commission, Council and Panel, provide appointment/removal/veto powers, terms, conflicts, prior-participant exclusions and the lawful fallback when too few people can act. Provide each decision's quorum, approval threshold, abstention/vacancy treatment and whether unfinished votes survive changes of members or mandates. Identify the basis for any new positive Senate role.
4. **L05 — When do decisions take effect?** Specify valid notice/delivery proof, each deadline and start event, calendar versus fixed periods, appeals and stays. Is annulment review always required, or available only if requested in time? Separating approval, effect, finality and execution is accepted; the exact rules are still needed.
5. **L11 — What may be public?** Provide a list for case existence, subject identity, votes, reasons, outcomes and officials' names, plus access and retention rules. May cases and subjects be public while evidence stays private, or must those links also be confidential? This choice changes the architecture.
6. **L14 — Which office duties are protected?** List restrictions that may apply to Presidents, Senators, Congress members and other protected office-holders, which duties remain, and which separate body can remove them. The protection against removal through ordinary discipline is accepted.

## Needed for the additional procedures

7. **L06 — Who gives the recovery second approval?** Select another independent Commission panel, an expressly authorised Senate role, or another named body. Specify old-key objections, contested hearings, notice period, appeals and permitted temporary protection. Independent review and a hearing have already been accepted.
8. **L07 — Which Merits can satisfy a claim?** Supply genesis Legacy/Exposed classifications, acceptance terms and effective dates. Choose the withdrawal/transfer/liquidation allocation and rounding rule, with examples. Later deposits staying outside exhausted older claim cohorts is accepted; the actual accounting rule remains to be supplied.
9. **L08 — Who gets paid first, and from where?** Order lender liens and competing reservations/claims; specify when borrowing/withdrawal restrictions begin, liquid payment versus restricted stake, who chooses, and the real source of restoration funding after reversal. Preventing double pledging and protecting existing loan rights are accepted.
10. **L12 — What can a land ruling change?** Supply the adopted regulation, deciding bodies, allowed title/boundary/encumbrance remedies, consent exceptions and lock screening/release/appeal rules. Separate judging and recording, dual-consent ordinary sales and independent locks are accepted.
11. **L13 — Who has the special powers?** Specify collective Cabinet approval of honorary recognition, the Congress presiding officer, narrow urgent delegations and their expiry, and which authenticated courts/judges may issue particular stays or judgments. No broad judicial executor is proposed.

## Genesis package to be supplied by the user

12. **L09/L10/O03 — Official starting records:** People and lawful status, source evidence and ambiguous-record review categories, stake balances/classifications and backing, offices/body appointments, and any unfinished official proceedings production must recognise. State explicitly when a category has none. Demo data is not imported by default. Name the approving authority and independent checker.
13. **O02/O03 — Token distribution:** Actual fixed LLM genesis supply (not exceeding 70 million), recipient or allocation plan, institutional reserves and stake-backing funding. Any amount below the cap leaves the remainder permanently unmintable under the proposed fixed-supply contract. Confirm any desired staged-issuance requirement before token deployment.

For each response, include the ID, exact answer and exceptions, supporting text and version, approving authority and
effective date. Include the official genesis data when available. Keep private keys and credentials separate.
