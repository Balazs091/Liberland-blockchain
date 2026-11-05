# Engineering progress

Updated **3 November 2026** against baseline `dd0005c15d20754c50a0495cf6d48298b795e1a4` plus the uncommitted working changes. A read-only check on 3 November confirms that origin/main remains at that baseline. The user accepted all recommendations and confirmed Ethereum mainnet, canonical USDC, a project-built LLM token and user-supplied genesis. This authorises implementation. No public-network deployment or production activation has been performed.

## Current verification

Current compiler/dependency verification is recorded in [Toolchain Upgrade](../Toolchain-Upgrade.md). The preceding
[Complexity Review](../Complexity-Review.md) recorded 816 optimized contract tests, 24 extended invariant properties,
58 exact ABI exports and 465 unsuppressed Slither labels under its earlier toolchain. Repository publication and
audit packaging are described in [Release Readiness](../Release-Readiness.md). The governed Sepolia
profile now rehearses real upgrades/rollback; the isolated foundation remains a separate five-contract fixture.
The sections below retain their earlier source-specific results and do not describe the final candidate.

## Earlier predeployment review

The later [deep review](../Predeployment-Review.md) fixes five verified issues in the wider Cabinet, Decision and
Referendum apps, while preserving existing ABIs and thresholds. It adds actual policy/app replacement, rollback,
wallet round-trip, settlement and API-gap journeys plus the synthetic order state machine. The final optimized suite
passes 772 tests; 24 invariant properties also passed the deeper 256-by-256 audit campaign on the same production
source. The review demonstrates retained stuck states and does not grant production approval or a universal
upgrade/recovery guarantee. The earlier preparation figures below are historical evidence.

## Earlier Sepolia foundation preparation

The isolated [Sepolia foundation deployment](../Sepolia-Foundation-Deployment.md) is now implemented and locally
rehearsed. It uses the actual `LiberlandMerit`, `IdentityRegistry`, `MembershipRegistry` and `ConstitutionKernel`,
plus an explicitly test-only `SepoliaMembershipController`. The script and controller reject other chain IDs.
Three fixed synthetic people receive 10,000 liquid LLM each; the operator retains 970,000 of the fixed one-million
supply. The operator uses a dedicated Sepolia credential, not the production-key variable.

The controller can seed only the fixed identities once while kernel bootstrap is active. Bootstrap is retired after
setup; the operator then exercises named restriction operations only for those three subjects. This is an isolated
test environment with no governance router/timelock, staking, USDC or actual legal decision workflow. It does not
modify the mainnet deployment or existing full Sepolia demo.

Earlier slice verification: **716 contract tests across 57 suites passed**, seed `0x1103`, zero failures/skips; this adds
19 controller tests and 9 deployment integration tests to the earlier 688. The 34 reference-model and 11 tooling
tests pass. Formatting, build-size and shell syntax checks pass. Slither reports 445 unsuppressed results (6 High, 69 Medium, 275 Low, 95 Informational); eight added Low reports
cover the bounded fixture loop and success-event order, plus an informational pragma inventory change. The delta
is reviewed in [Static triage](../Static-Analysis-Triage.md). All 55 exported ABIs match current source exactly.

The disposable localhost rehearsal used chain ID 11155111 and successfully mined **11 deployment transactions**
(total 7,901,671 gas; largest 1,635,398), followed by **7 restriction transactions** (total 1,367,694 gas; largest
316,131). It checked all five runtime hashes against mined code, fresh allocation/bindings, retired bootstrap,
unauthorised calls/reseeding, overlapping orders, scoped stays/resumption/revocation, exact-boundary expiry without
counter mutation, and indefinite-order relief. Its receipts are local evidence, not a public Sepolia deployment.
No public-network transactions were sent.

The prepared manifest is separate from the old demo and mainnet manifests. A simulation can write it; successful
public receipts and independent runtime/source verification are still required to describe a public deployment as
verified. The read-only verifier checks the initial token allocation, so run it before deliberate tester transfers.

## Earlier 3 November implementation slice

The validation figures in the sections below record the earlier token/restriction slice; the newer Sepolia
preparation milestones are above; final results are linked under Current verification.

### Earlier implemented components

| Component | Behaviour | Integration boundary |
| --- | --- | --- |
| [LiberlandMerit](../../contracts/tokens/LiberlandMerit.sol) | Non-upgradeable ERC20, 18 decimals, existing 70 million cap; positive configured supply minted once to an explicit recipient | Actual supply, allocation recipient and backing await genesis inputs; unused cap is permanently unmintable |
| [DeployMerit](../../scripts/DeployMerit.s.sol) | Separate mainnet-only asset deployment with explicit supply/recipient/provenance inputs and constructor/runtime manifest | Script is implemented and locally rehearsed; nothing deployed to mainnet |
| [Mainnet preflight](../../scripts/Deploy.s.sol) | Pins native Ethereum USDC; rejects a substituted environment address, missing code or wrong decimals before broadcasts | Metadata checks still do not authenticate arbitrary LLM code; exact runtime and live USDC controllers need release verification |
| [MembershipRegistry](../../contracts/registries/MembershipRegistry.sol) | Person-bound, independent fixed-right orders; named stays/resumptions/revocations; current expiry without cleanup; scoped revision checks | Sole current kernel-selected IdentityWriter gate; official writer and legal workflows not implemented or registered; no citizenship/lifecycle/financial effects |
| [Kernel classifications](../../contracts/core/ConstitutionKernel.sol) | Membership registry is State; IdentityWriter is Authority | IDs/classes grant no standing permission and deploy neither module; constitutional replacement thresholds remain |
| Frontend exports | Separate production token and restriction registry ABIs | Existing demo token ABI remains separate; no frontend automatically adopts the new workflows |

Restriction summaries use five fixed engineering bit labels from the brief. Policies still need the exact rights-to-consumer table. Zero restrictions do not prove citizenship, membership or eligibility. Original order scope, interval and receipt provenance remain fixed; lifting one order preserves other orders. Future-start/new already-expired orders are rejected. Stays do not extend the original end.

The registry's source revisions advance on recorded writes only. Clock expiry changes direct reads without advancing counters. There is deliberately no electorate callback or claim that the current counters certify time-sensitive historical snapshots. It also records receipt references rather than deciding their legal truth: the future issuer/writer must authenticate and consume an exact receipt atomically. Public subject/order facts require the actual disclosure policy before integration.

The earlier threshold/hash/receipt libraries remain internal primitives; `TimedRestrictionSet` now has the concrete registry consumer. Existing IdentityApp administrator procedures and existing financial/land workflows remain unchanged. The new registry is not installed in the production deployment manifest.

### Earlier slice validation

- **688 Foundry tests passed across 55 suites**, seed `0x1103`, zero failures/skips. This includes the existing governance/custody/invariant suite, 11 token tests, 20 registry tests and deployment/classification checks. The two fuzzed token checks and restriction scanning-oracle checks ran 256 cases each.
- **34 independent Python model tests passed.** Their financial rounding counterexample remains an unresolved algorithm choice, not an approved settlement formula.
- `forge fmt --check`, `forge build --sizes`, shell syntax and whitespace checks pass. Runtime sizes are 1,925 bytes for LiberlandMerit and 7,251 bytes for MembershipRegistry, below the EVM contract-size limit.
- Slither 0.11.5 reports **437 findings**: 6 High, 69 Medium, 267 Low and 95 Informational. The reviewed delta is one optional internal return value, three intended time predicates, a concrete token-cap override false positive and the pragma inventory. All 431 other report identities match. No detector is suppressed; see [Static triage](../Static-Analysis-Triage.md). A baseline is a drift check, not an independent audit or production verdict.
- All **54 frontend ABI exports** have exact current-source parity; documentation target checks pass. The two added exports are LiberlandMerit and MembershipRegistry.
- Independent source review found no correctness defect in the declared token/restriction foundation. It does not establish the future issuer, legal process, privacy or electorate integration.

The first deployment-input test run exposed shared-environment races in the test fixture. Environment mutation cases now run sequentially within their test; the complete suite passes. No production behaviour was relaxed to accommodate the tests.

## Local deployment rehearsal

The updated disposable-localhost rehearsal used the real fixed-supply LLM contract and a **local USDC test double installed at the canonical address**. It is not a mainnet fork or real-USDC code/controller verification. Seven synthetic people were funded; the separate protocol preparation and confirmed-block completion stages succeeded. Setup was sealed and kernel/router/executor bootstrap retired.

| Stage | Successful local transactions | Actual total gas | Largest single transaction gas |
| --- | ---: | ---: | ---: |
| LLM token | 1 | 579,883 | 579,883 |
| Protocol preparation | 76 | 103,922,427 | 6,926,942 |
| Genesis completion | 7 | 5,088,318 | 4,873,435 |

These are synthetic local receipt measurements, not a mainnet gas-price quote or full proposal deployment estimate. The existing protocol genesis path is exercised; the new legal workflows are absent. No public RPC or production assets were used. Evidence is retained in the dated workspace engineering-evidence folder, including the rehearsal summaries and manifests.

## Remaining inputs and integration

[The accepted decisions](IMPLEMENTATION-DECISIONS.md) and [remaining input list](DECISION-MAKER-QUESTIONS.md) replace the prior open recommendation questions. The accepted principles will not be sent for reapproval. Concrete legal text, body/threshold/notice tables, constitutional-headcount choice, recovery second body, privacy fields, financial priority/allocation and official genesis data remain needed.

Next is the typed appointment/admission workflow and sole writer, followed by the complete rights-policy bundle. Their accepted boundaries are fixed; exact rules must come from those inputs. Financial provenance and compensation retain their separate feasibility/rounding/priority gates. Phase A and production readiness are not declared complete.

## Previous foundation — 2 November 2026

The following records the earlier slice at its original date; statements about unchanged workflows and ABIs describe that historical state.

Updated 2 November 2026 against baseline `dd0005c15d20754c50a0495cf6d48298b795e1a4`. The user authorised smart-contract development and requested a forwardable question list. Production deployment, funds movement and new legal powers have not been authorised by this change.

### Implemented foundation

| Component | Implemented responsibility | Limit |
| --- | --- | --- |
| [DecisionThresholds](../../contracts/libraries/DecisionThresholds.sol) | Overflow-safe strict-majority and two-thirds arithmetic; rejects support above denominator; zero denominator never passes | Chooses no quorum, eligible set, abstention rule or legal majority |
| [DeterminationHash](../../contracts/libraries/DeterminationHash.sol) | Fixed EIP-712 struct commitment to matter, subject commitment, rules/type/effect/scoped state, issuer/writer, nonce, body epoch, roster revision, revision and stage | Caller must compose a chain/contract domain, validate typed payload and authenticate lawful approval |
| [ReceiptConsumption](../../contracts/libraries/ReceiptConsumption.sol) | Canonical one-time marker for a nonzero full domain-separated digest | Supplies no authorisation, finality or stay check; new deployments do not inherit old consumed state |
| [TimedRestrictionSet](../../contracts/libraries/TimedRestrictionSet.sol) | Indexed maximum-expiry set with arbitrary physical removal, explicit indefinite entries and cleanup-free current reads | Only already-effective OR-combined restrictions; no legal rights catalog, future activation or historical certification |

All four are internal libraries. No existing application, registry, policy, authority, external ABI or deployment script imports them. They add no standing writer or legal effect. Production integration will require exact named consumers and the relevant legal answers.

The receipt test harness composes the struct hash through the existing OpenZeppelin EIP712 implementation. EIP-712 supplies structured hashing/domain separation; it does not itself supply replay protection or legal approval. See the [standard](https://eips.ethereum.org/EIPS/eip-712). The separate consumption marker and authenticated case state remain necessary.

### Models and adversarial examples

[Reference model instructions](../../test/reference/README.md) distinguish assumptions from implemented protocol rules.

- Snapshot examples exercise both possible membership-denominator branches, clock-only expiry, missed callbacks, same-block writes, late catch-up, completed-block certification and an empty rebuild. They are not a bounded production electorate implementation.
- Person/seat examples distinguish weighted votes, distinct supporters and wallet migration.
- Explicit financial lots demonstrate why an old aggregate balance cannot identify eligible pre-finality assets after withdrawals/redeposits. Direct stake transfer examples cover the path that a vault-only hook misses.
- The candidate financial allocation still has a split-withdrawal rounding bias. It remains unselected. Loan/claim priority and transfer classification are scenario inputs, not newly adopted policy.

Solidity tests use an independent scanning oracle for heap results and 256 fuzz sequences of 128 operations, arithmetic boundary/fuzz checks, all context-field mutations, EIP-712 chain/app separation, unauthorised/unapproved receipts, double consumption, scoped-state changes, interim/final/stayed conditions and downstream failure rollback. These harnesses demonstrate primitive composition, not integrated admission or disciplinary authority.

### Gas interpretation

Persisted cold fixtures compare 8, 64 and 256 entries. Measure the external harness execution segment with fresh state snapshots and record it separately from total test gas, transaction overhead or storage refunds. Heap read work is independent of entry count; heap writes repair the index and cost more than the simple unordered scan baseline. No universal gas-saving claim follows.

The same maximum-expiry ID is the heap root and scan-array tail. That removal benchmark is deliberately an expensive heap position versus the cheapest scan position, not a representative or worst-case comparison of all removals. Both baselines use the same descending-ID tie-break. Histories/future activation/keeper work remain outside these measurements. Whole-test fixture/oracle gas is not a deployable transaction cost; the figures below measure only the specified cold external call segment.

| Persisted entries | Heap latest | Scan latest | Heap add | Scan add | Heap root removal | Scan tail removal |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 8 | 10,737 | 44,969 | 124,035 | 72,915 | 87,047 | 23,744 |
| 64 | 10,737 | 320,455 | 173,356 | 72,915 | 152,974 | 23,744 |
| 256 | 10,737 | 1,265,816 | 206,237 | 72,915 | 196,928 | 23,744 |

These numbers support fixed-work current reads and show their write cost. They do not settle legal overlap semantics, full membership callback costs or the final production data structure.

### Historical verification

- Full Foundry run with seed `0x1102`: **652 tests passed across 52 suites**, zero failures/skips. Includes 23 decision-primitive tests and 17 restriction-set tests, with the six cold benchmark scenarios.
- Independent Python examples: **34 tests passed**, including both denominator branches and the known financial-rounding counterexample. The empty-population epoch/catch-up liveness defect found in review is corrected and covered.
- Build-size and formatting checks pass. Existing deployed-workflow source files, deployment scripts and frontend ABI files are unchanged; all 52 exported ABIs retain exact current-source parity.
- Slither 0.11.5 reports the same 432 severity-labelled results. Only its informational pragma inventory fingerprint changes to list the four new pinned files. The other 431 report identities match; see [Static triage](../Static-Analysis-Triage.md). A matching baseline is not a safety verdict, especially before these primitives have real consumers.
- No deployment or transaction was performed. Existing administrator-led workflows have not yet been replaced by the proposed collective procedures.
