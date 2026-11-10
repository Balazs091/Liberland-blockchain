# Phase A genesis and conditional migration plan

The 3 November 2026 plan selects fresh mainnet genesis. It uses baseline
`dd0005c15d20754c50a0495cf6d48298b795e1a4`. Activation requires a verified deployment inventory, L09/L10 inputs
and separate release approval. [Deployment inventory](DEPLOYMENT-INVENTORY.csv), [Justice genesis](JUSTICE.md#fresh-genesis-and-review)

## Preconditions and branch selection

| Branch | Required fact | Treatment |
| --- | --- | --- |
| G | No live production deployment with rights/assets to preserve | New coherent genesis under an approved import manifest |
| T | Existing testnet/demo only | Preserve provenance and user expectations; prefer a clearly announced fresh demo where permitted |
| L | Live state or assets exist | Release-specific governance, state/process/custody migration and rehearsal |
| U | Deployment facts unavailable or inconsistent | Remain in inventory/design; do not select G by assumption |

The 29 October decision selected branch G on Ethereum mainnet, chain ID 1. Verify the demo separately and use
official production records and parameters for genesis. Liberland Merit uses 18 decimals and a 70 million cap.
Production validation requires canonical Ethereum L1 USDC with 6 decimals. The genesis input owner supplies the
official records, fixed LLM supply and recipient, appointments and manifest. [Implementation decisions](IMPLEMENTATION-DECISIONS.md#user-decision)

For each actual network record chain ID, finalized inventory block/hash, kernel/core addresses, runtime/constructor identity, every authority and immutable dependency, tokens/proxies, source revision and confirmation evidence. Record setup/kernel/router bootstrap state independently. Verify operational controllers and signer availability; different addresses do not prove different people.

## Required state inventory

| State category | Required export and reconciliation | Decision |
| --- | --- | --- |
| Identity | All person IDs, raw enum ordinals, verification/age/finalSuspension, metadata commitments, active/revoked links, mutation counters | L09 |
| Membership | Approved target membership/rights mapping and source evidence; unknown grounds quarantined for review | L02/L09 |
| Proceedings | Pending civic notices, appeals, recovery/migration nonces, consent, pinned reviewers and deadlines | L05/L06/L10 |
| Political processes | Active referenda/cycles, policies/snapshot blocks, candidate/person ballots and institutional mandates | L04/L10 |
| Stake/custody | Per-person/aggregate stake, protected floors, backing, source checkpoints and every mutation authority | L07/L08 |
| Lending | Each original pool, cash/shares/scaled debt/index, loan-book ownership, lien and captured retained floor | L08 |
| Treasury | Budget envelopes, commitments, consumed request IDs, routed actions and original reconciliation writers | Existing commitments preserved |
| Land | Titles/parties/versions, accepted dispute counts, pending claims, encumbrances, signature nonces | L12 |
| Governance | Queued targets/payloads, independent executability, cancellation/review hooks and expiry | S07 |

Exports must reconcile to the selected finalized block. Private case evidence stays in an access-controlled evidence store; publish only approved commitments.

## Import manifest design

[Manifest template](MIGRATION-MANIFEST.template.json) and [review schema](MIGRATION-MANIFEST.schema.json) are review artifacts. Their status is DRAFT and execution authorisation is false. Validation checks structure, not legal approval, cryptographic correctness, live state or readiness. Unknown addresses/blocks/roots are null, never fabricated. `targetChainId` is now `1`. The schema field `openLegalDecisions` retains IDs for exact missing rules/evidence even though the recommendations are accepted; it does not ask for their reapproval. Manifest approval rows describe the exact release/manifest review, not the earlier project acceptance. The schema has no asset section; asset choices are recorded in [the decision record](IMPLEMENTATION-DECISIONS.md) rather than adding unsupported fields.

The future enforced import must bind chain, release, source block/hash, source and target addresses, input mapping version and legal-rules hash. Per-person leaves bind the exact old relevant state hash, target typed facts and unique import index. Canonical ABI leaf encoding and domain separation must be specified before root generation; JSON serialization is not the cryptographic encoding.

Approval authorises exact facts/root, not whoever submits leaves. Proof submission may be permissionless once facts are committed. Consume each leaf once, bound batches, reconcile expected counts/totals, preserve replay markers and close the importer permanently. Repeated identical work is either an explicit harmless no-op or a defined already-consumed error; altered payloads can never overwrite accepted facts.

The existing setup contract is not already a manifest-proof importer. Its owner can configure genesis facts while open. A signed spreadsheet or document alone does not constrain the deployed code. A future constrained importer or independently approved exact script boundary is required; any such implementation needs separate review.

## Genesis sequence

1. Verify Ethereum mainnet chain ID 1, official source records and all asset/controller risks. Build and review the project-owned Liberland Merit token with an explicit positive fixed genesis supply no greater than 70 million and a nonzero recipient. Record the supply/distribution from the user's genesis package; no later minting or unused-cap issuance is possible. Verify canonical Ethereum USDC at `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48` and its 6-decimal behaviour. Keep demo inputs separate.
2. Approve controlling legal text/mapping and exact genesis manifest. Resolve affected L items; record signers/evidence and source hashes.
3. Rehearse and review the release-specific deployment of stable facts, custody, body facts, typed workflows and a consistent policy bundle before any authorised broadcast. Verify constructor arguments, module classes and authority paths before activation. The implemented restriction registry currently has no official IdentityWriter, lifecycle, policy/electorate integration or production-script installation; those future integrations cannot be assumed from compilation.
4. Fund exact stake backing before crediting balances. Import only approved facts/appointments; establish rights and person identity before granting voting authority.
5. Reconcile all imports, wallet uniqueness, custody totals, mandates, policy dependencies and receipt/nonces. Disable import/setup/bootstrap through their actual gates.
6. Complete the electorate rebuild/certification in completed blocks under the chosen R0/R1 rule. Confirm no due relevant expiry or callback mismatch. The new registry's write counters do not advance on time expiry and it has no electorate callback/scheduler; they are insufficient to certify time-dependent snapshots by themselves.
7. Activate permitted new procedures only after legal, security and operational gates. Fresh demo activation and production activation have separate approvals.

Do not add a permanent recovery admin or leave an unsealed import path as insurance.

## Live transition policy

Default recommendation: finish active political processes under their approved pinned rules before incompatible cutover where legally and operationally feasible. The preservation principle is accepted; concrete L10 category facts and transition rules are still pending. It is not authority to discard a process or force debt repayment. If waiting cannot produce a valid transition, use a narrowly reviewed compatibility or import design; do not claim automatic continuity.

| Existing item | Recommended treatment for decision | Forbidden shortcut |
| --- | --- | --- |
| Citizen record | Preserve proven citizenship; map membership under approved rules | Reinterpret existing enum ordinals |
| Suspended/Revoked/finalSuspension | Approved category/evidence mapping with review of unknown grounds | Guess fraud versus discipline or auto-promote |
| Civic appeal | Finish in original pinned process or carry exact procedural rights into approved replacement | Blanket cancellation with an event |
| Recovery/voluntary migration | Preserve consent/nonces/deadlines or lawfully reopen with notice | Execute an obsolete destination or reset objection rights |
| Referendum/election | Finish under pinned bundle, or approved restart/adapter with notice | Change snapshots/thresholds silently |
| Final unused decision | Exact recognised old completion path or constrained imported receipt | Indefinite arbitrary old-issuer allowlist |
| Loan/LP position | Retain original accounting and permitted settlement or consensual/audited migration | Pointer swap interpreted as debt migration |
| Land dispute | Preserve version, lock count, standing and response/appeal rights | Clear all locks during writer replacement |
| Treasury queued request | Respect pinned targets and permanent paid markers | Release paid budget capacity or replay a consumed request |

## Pointer and authority cutover

The current timelock permits each queued action to execute alone. A submitted batch is not a dependency lock. The following stages define the desired invariants, not an executable universal transaction order. S07 must resolve the actual deployed dependency graph and validate each allowed ordering before branch L can proceed.

| State | Permitted powers and operations | Evidence required before advancing |
| --- | --- | --- |
| M0 Baseline | Existing approved procedures remain active | Finalized inventory and legal transition policy |
| M1 Staged | New modules registered but have no standing fact/custody authority; no new legal effects | Bytecode, interfaces, exact modules, complete reviewed action set |
| M2 Transition | Old/new authority states may coexist across domains; new paths reject incompatible dependencies; unaffected approved operations preserved | S07 state matrix, legal treatment of any unavoidable interruption and valid queued recovery route |
| M3 Imported | Exact records reconciled, old writer retired in migrated domain, import closed | Counts, old/new hashes, receipts/nonces, no surviving bootstrap bypass |
| M4 Certified | Bundle internally consistent, current sources synchronized, historical gap boundaries valid | Completed-block certificate and consumer checks |
| M5 Activated | Only legally approved, reviewed workflows operational | Per-feature legal/security/operator acceptance |

For identity, inventory and prepare changes to the standing identity authority, membership source, electorate and all four policy dependencies. Verify existing referendum/election registry authorities and router-origin module references independently; they are separate IDs. For land and finance, transition only their approved domains. A partial Phase B release must not unexpectedly move collateral or alter land authority.

New modules should carry an immutable reviewed release/dependency commitment or equivalent exact consistency checks and reject operations until their required dependencies and migration status agree. A release identifier alone is not enough: verify the actual addresses/registries and policy references. Readiness activation must follow a fixed predicate or exact approved certificate, not an operator-controlled switch granting discretion.

Existing old apps have no universal pause or new-case-disable method. Do not assume one. Retiring a registry writer prevents its effective writes, but may still allow inert local requests; a frontend toggle is not a security control. Determine which old functions remain reachable, including queued targets and pinned reviewers, and either preserve their approved effect path or prove that all substantive writes fail after the intended retirement. Any compatibility exception must be exact, time/state constrained and unable to originate new powers.

Test partial states at least for: voting pointer before electorate; electorate before voting; citizen before candidate/election; identity writer before import; body app before appointment authority; financial pointer before backing handoff; old pool with changed registry pointers; land case app before writer; and independently executed/expired/cancelled queue members. If a state cannot be made safe without changing an immutable core, the proposed transition is rejected and redesigned. Do not hide that incompatibility behind the batch assumption.

## Custody and original settlement

Vault backing handoff is a separate exact operation; a pointer update does not move tokens. New withdrawals/credits must be unavailable until the successor has verified backing and compatible accounting. Preserve old LP shares/debt, captured floors, original loan-book settlement and treasury paid receipts. Inspect original reconciliation authority, not just the live pointer.

Phase D requires the feasibility choice in [Financial and land design](FINANCIAL-AND-LAND-DESIGN.md). Before genesis, unified accounting is preferred. For live books, compatible hooks, run-off/refinance or a segregated migration need explicit proof. Loan run-off is not a guaranteed finite schedule. Restoration requires independent real funding.

## Stop conditions and recovery

Stop before the next effectful stage if: chain/block/hash differs; constructor/runtime or token assumptions differ; manifest changes; an unknown authority remains; records or backing fail reconciliation; a decision is stayed; a required legal answer is open; dependencies split; a queue member expires/is cancelled; a receipt can replay; or certification has an unexplained gap.

Before M2, stage inactive modules without affecting the old release. During M2, do not assume the broken electorate can authorise a repair vote. Any exact governance recovery actions must already be valid, approved, unexpired and compatible; negative-control deadlocks may still prevent execution. There is no guaranteed recovery route or emergency administrator. If no safe continuation exists, reject the plan before execution.

After new user mutations, swapping pointers back is not a rollback. Produce a new reconciliation and forward correction under the lawful governance path. Preserve original ledgers and evidence. Do not migrate an asset twice or reinstate a retired authorisation to bypass review.

## Rehearsal and release evidence

Rehearse from the inventory block on the correct chain/fork with realistic values and active processes. Include adversarial transaction order, interruption, repeated leaves, hostile old requests, expired approvals, late expiry processing, non-signing recipients and token failures. Record gas, bytecode, output state hashes, all pointer states, custody totals and permissions before/during/after.

Before any live migration, review the actual manifest, root, proofs and rehearsal evidence. [Acceptance](ACCEPTANCE.md)
