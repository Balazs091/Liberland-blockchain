# Draft Constitution Alignment

This document compares the current contracts with the draft supplied as `2024-09-24 Constitution.md`.
The reviewed source has SHA-256
`2EE19F4D26559B9ECE079B6EE84C12793B929D8CF56E82F7E7812F4769D06BA6`.

The draft is design guidance, not an immutable protocol specification. A difference is implemented only when the
draft's approach is simpler or comparably simple and is also clearer or safer. More complex political systems are
recorded as deliberate omissions or current-policy differences rather than partially implemented.

## Changes adopted from this review

1. Constitutional and sensitive-module referenda now implement the stated threshold exactly: supporting voters
   must be at least 50% of the snapshotted electorate and supporting voting power must be at least 65% of weighted
   votes actually cast. The former additional strict supporting-headcount majority incorrectly rejected an exact
   50% headcount even when the 65% weighted threshold passed.
2. Every Senate treasury-disbursement suspension and renewal now requires a nonzero `reasonHash` published by the
   holder of a seat that actively supports the suspension. The current hash is stored in the suspension record and
   emitted in the transition event, binding the on-chain transition to a Senator-authored written objection without
   storing unbounded text. The contracts cannot verify the contents or availability of that off-chain document.
3. Senate seat assignment, transfer, nominated succession, and succession claims now require the acquiring person
   to have current `Citizen` status. A holder who later renounces is not trapped: the holder may still transfer or
   vacate the seat under the current property-preserving model.
4. Pending Public Veto support now counts only currently eligible citizens. Read paths exclude stale support and the
   next cast prunes it, while a completed repeal keeps its historical final count.
5. Presidential ballots can be cast only after the incumbent term ends or the office becomes vacant. This prevents
   a successor election from being preloaded years before it can take effect.
6. Term-bound ministry-office authorization, including clerk reads, expires at the recorded term end without
   depending on a later cleanup transaction.

## Alignment matrix

| Draft subject | Current contract behavior | Disposition |
| --- | --- | --- |
| No compulsory taxation, State debt, central bank, or currency debasement (Art I §2) | The protocol has no tax collection, State borrowing, native-currency custody, or central-bank executor. LLM is hard-capped at 70,000,000 tokens; production validates that the external token exposes the exact cap, while the Treasury has no mint path. Open minting remains Sepolia/test-only and cannot exceed the same cap. The lending pool lends to individual eligible citizens, not to the State. | Aligned within the on-chain scope. The external production token bytecode and any upgrade surface still require independent review; legal/off-chain conduct is outside contract enforcement. |
| Tokenized proprietary civic titles (Art I §5) | Active LLM stake supplies merit voting power. Senate seats are fixed proprietary records with holder-controlled transfer and nominated succession. The contracts do not implement general co-ownership of every State asset or legal inheritance/pledge enforcement. | Partial. A complete proprietary-title system is a separate legal and technical project. |
| Rights, property, restitution, courts, warrants, and due process (Arts II-III) | Contracts use explicit custody and authority paths but do not adjudicate facts or legal rights. `CONSTITUTIONAL_REVIEW` is only an optional typed execution-pause hook, not a court system. `StakeRegistry` contains slash/recovery accounting, but production leaves its general post-genesis authority at the sealed setup module, so there is no live punishment workflow. | Intentionally unimplemented. A Judiciary requires case records, evidence, appeals, judicial appointments, and enforcement design. Any future slashing authority must be separately governed and audited. |
| Citizenship pledge and voluntary renunciation (Art IV §2) | Identity metadata can commit to off-chain onboarding evidence, but the contracts do not interpret an oath. A citizen can renounce directly without office approval and keeps the wallet link needed to recover stake. | Renunciation aligned. Pledge semantics remain an Identity Office/legal process rather than hardcoded text. |
| Citizens and Congress may propose laws; no law without referendum (Art IV §§4-6) | Bonded eligible citizens and Congress members can propose law referenda. Only a successful referendum can queue a `LegislationEnactment` action. Congress decisions cannot enact legislation. | Aligned. The proposal bond and schedules are replaceable law-level policy. |
| Congress alone proposes constitutional amendments (Art IV §8) | Only `createCongressConstitutionalAmendmentReferendum` exists. The app and policy both authenticate the current Congress member. | Aligned. |
| Constitutional threshold: at least 50% of citizens and 65% of cast weighted instruments (Art IV §8) | Electorate headcount and voting power are snapshotted at creation. The policy requires supporting headcount `>= 50%` and supporting power `>= 65%` of cast weighted turnout. Each person's vote uses active stake at the process's stored block checkpoint. | Aligned by this review. |
| Every citizen has an equal base referendum vote; merit weight is supplemental and bounded (Art IV §4.5) | V1 eligibility requires minimum active LLM stake, and voting power equals active stake without an equal base component or maximum merit cap. | Intentional current-policy difference. Adding a base unit and cap changes eligibility, quorum economics, snapshots, frontend math, and migration parameters; it is not a safe cleanup. Both policies remain governance-replaceable. |
| Public Veto is equality-oriented and may only repeal legislation or remove officials (Art IV §4.7) | `PublicVetoApp` is negative-only and person-counted, but participation still uses the v1 good-standing policy (including minimum stake) and the production threshold is a fixed two persons. Pending support counts only currently eligible persons and stale receipts are pruned on the next cast. It currently repeals active Law-tier legislation only and cannot enact, appoint, or remove officials. | Safe narrower implementation retained. Equal-base eligibility belongs with the broader voting-policy redesign; official removal needs role-specific thresholds and coordinated registry changes. The production threshold requires independent launch review. |
| Congress may temporarily return formally defective referenda (Art IV §6) | There is no Congress hold over a citizen referendum. Proposal validation rejects malformed on-chain payloads immediately. | Omitted. A temporary review/appeal process requires a new state machine and Judiciary integration. |
| Congress may adopt subordinate non-legislative decisions (Art IV §7) | `DecisionApp` provides enumerated Congress actions and cannot execute arbitrary calldata or create Law-tier records. | Aligned and intentionally bounded. |
| Congress alone proposes treaties (Art IV §9) | Constitutional amendments and international treaties share one legislation tier and the Congress-only constitutional proposal path. | Conservative but coarse. A separate treaty class and compatibility review would add substantial workflow and Judiciary scope. |
| Congress nominates judges and the President appoints them (Art IV §10) | No judicial personnel registry or appointment workflow exists. | Intentionally unimplemented with the Judiciary. |
| Congress appoints/removes a five-year Prime Minister (Art V §1) | Congress installs the Prime Minister for 1,825 days and removal requires at least the recorded appointment tally. | Substantially aligned. True Gregorian “five years to the day” would require calendar logic; v1 deliberately uses a fixed duration. |
| Prime Minister appoints four five-year ministers; Congress dismissal has appointment-dependent rules (Art V §2) | The four named ministry slots and five-year terms exist. The Prime Minister appoints but cannot unilaterally dismiss. Congress currently dismisses by strict occupied-seat majority; there is no Prime-Minister-initiated motion path or stored appointing-PM threshold per minister. A linked ministry office and all of its clerks lose authority immediately at term expiry. | Partial current-policy difference. Exact dismissal implementation needs additional minister mandate state and motion provenance, so it is not treated as a small change. |
| Executive organs are accountable to a ministry and may produce subordinate instruments (Art V §4) | Finance is wired to an operational ministry office. Identity, Land, and Company offices exist but are not represented as children of a ministry; the other three political ministries have no operational apps. | Partial. Parent-ministry facts and a subordinate-instrument workflow require new registries/policies. |
| Agents execute judicial orders (Art V §5) | No Agent personnel, warrant, or judicial-order execution system exists. | Intentionally unimplemented with the Judiciary. |
| Senate is a fixed proprietary body of exactly 100 non-dilutable seats held by citizens (Art VI §1.1-3) | `SenateSeatRegistry` has a compile-time 100-seat bound with no mint/increase function. Assignment, transfer, nominated succession, and succession claims require current `Citizen` status. Holders control transfer and successor nomination after genesis. Senate voting follows current seat ownership and is not automatically suspended if a holder later renounces citizenship. | Fixed supply and citizen-only acquisition are aligned. The live-citizenship condition is an intentional current-policy difference: separating continued property ownership from temporarily exercisable Senate power requires a new policy and edge-case rules. Legal inheritance and pledges remain off-chain. |
| Senate has strictly negative and custodial powers (Art VI §1.4-8) | Senate can cancel queued typed actions, veto eligible active referenda, repeal sub-legal measures, and temporarily suspend treasury disbursements. It has no positive executor. Suspensions auto-lapse and cannot outlive the queued action. The incumbent app cannot cancel or hold open the active referendum for, or cancel the queued action produced by, its exact `SENATE_APP` replacement, so a negative power cannot make its own implementation permanent. | Directionally aligned but narrower: general law repeal, official dismissal, records access, and judicial review are not implemented. |
| Senate disbursement objections and renewals must be reasoned and temporary (Art VI §1.6-8) | Suspensions and renewals are bounded by policy/action expiry. Each stores and emits the hash published by a currently supporting Senator. | Aligned by this review. The UI must resolve and display the referenced document; its contents remain off-chain. |
| President is Senate-elected, appoints two Senator Vice Presidents, has no residual appointment power, and serves five years (Art VI §2) | `HeadOfStateApp` uses one current-seat vote per occupied Senate seat, a fixed 1,825-day term, two Senator Vice Presidents, and no generic appointment function. A new presidential ballot is rejected while the incumbent remains in term. | Substantially aligned. Diplomatic/honours functions are off-chain. |
| First Vice President succeeds; the other may appoint a new second Vice President (Art VI §2.5) | The first eligible Vice President succeeds for the remainder of the term. Existing VP slots are cleared and the successor-President appoints replacements. | Intentional simplification. Preserving the second VP and transferring a one-time appointment power adds state and edge cases without a present operational need. |
| Senate seat proportional weight cannot be altered (Art VI §1.3) | Direct Senate support is one vote per occupied seat. The current President-proxy mechanism can amplify direct support by covering silent occupied seats, capped so proxy support cannot exceed direct support. | Intentional current-policy difference. It is bounded and already part of the reviewed v1 model, but it is not stated in this draft and should remain an explicit external-audit focus. |

## Constitutional concepts not represented on-chain

The following are not contract claims and should not be inferred from deployment: territorial sovereignty, foreign
neutrality, general civil/criminal law, private arbitration, evidence standards, warrants, judicial precedent,
diplomatic representation, honours, official immunity/liability, Senate access to meeting records, and the legal
meaning of State-property co-ownership.

Future modules may implement these areas after their constitutional and operational rules are defined. They should
use dedicated fact registries and bounded applications rather than extending the immutable core into a general
legal executor.
