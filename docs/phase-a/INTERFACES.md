# Phase A implemented interfaces and workflow proposals

Status: **IN PROGRESS; implemented foundation separated from future workflow sketches**. Baseline: `dd0005c15d20754c50a0495cf6d48298b795e1a4`; updated 3 November 2026. The user accepted the recommendations and authorised contract development. The production token and independent-restriction registry now have source interfaces; official legal workflows below remain proposals. No deployment or production activation is claimed. [Engineering progress](ENGINEERING-PROGRESS.md) records validation and limits.

These sketches follow [Architecture](../Architecture.md) and [Audit Scope](../Audit-Scope.md). The detailed rationale is the October 29 implementation analysis identified by hash in [Provenance](PROVENANCE.json). The [rights-consumer inventory](RIGHTS-CONSUMERS.csv) identifies the existing consumers that must be considered together. `L01`–`L14` refer to accepted principles with specific details/evidence still pending in the legal register. A dependency reference does not choose an unprovided rule or establish statutory authority.

## Implemented external foundation interfaces

### Liberland Merit

[Source](../../contracts/tokens/LiberlandMerit.sol) implements [ILLMToken](../../contracts/interfaces/ILLMToken.sol) using the pinned OpenZeppelin ERC20Capped implementation. Its constructor is `constructor(address genesisRecipient, uint256 genesisSupply)`. Supply is positive, in 18-decimal units and no greater than `70_000_000e18`; the nonzero recipient receives it once. The public token ABI is standard ERC20 metadata/transfers/allowances plus `cap()`. It has no post-construction mint/burn control, owner, proxy, blacklist or pause path. The user supplies actual genesis supply and allocation; remaining cap is permanently unmintable. Canonical stake accounting, not a token voting extension, determines protocol voting weight.

### Independent restriction facts

The exact implemented types and ABI are [MembershipTypes](../../contracts/types/MembershipTypes.sol) and [IMembershipRegistry](../../contracts/interfaces/IMembershipRegistry.sol). These are not the future lifecycle sketches below.

```solidity
// MembershipTypes fixed engineering storage labels, not legal consumer mappings:
enum Right { Political, Community, Appointive, Representation, AppointmentEligibility }
enum OrderStatus { Unset, Unstayed, Stayed, Revoked }

struct OrderInput {
    bytes32 personId;
    bytes32 orderId;
    uint16 restrictedMask;
    uint64 effectiveAt;
    uint64 expiresAt;
    bool indefinite;
}
struct RightsSummary {
    uint16 restrictedMask;
    uint16 indefiniteMask;
    uint64[5] restrictedUntil;
    uint256 personRevision;
}

// Only the kernel-selected IDENTITY_WRITER may call these:
function recordOrder(MembershipTypes.OrderInput calldata effect, bytes32 sourceReceiptId) external;
function stayOrder(bytes32 personId, bytes32 orderId, uint256 expectedRevision, bytes32 receiptId) external;
function resumeOrder(bytes32 personId, bytes32 orderId, uint256 expectedRevision, bytes32 receiptId) external;
function revokeOrder(bytes32 personId, bytes32 orderId, uint256 expectedRevision, bytes32 receiptId) external;

// Current read APIs (not historical certification or eligibility grants):
function identityRegistry() external view returns (address);
function orderOf(bytes32 personId, bytes32 orderId) external view returns (MembershipTypes.RestrictionOrder memory);
function rightsNow(bytes32 personId) external view returns (MembershipTypes.RightsSummary memory);
function isRestrictedNow(bytes32 personId, MembershipTypes.Right right) external view returns (bool);
function membershipRevisionOf(bytes32 personId) external view returns (uint256);
function electorateMutationCount() external view returns (uint256);
```

Order identity is scoped by `(personId, orderId)` and cannot be reused after revocation. Stored orders retain the original source receipt, scope/interval and their own revision. Relief checks the expected order revision, so unrelated person activity does not invalidate it. Current reads combine independent unstayed/unrevoked orders and observe exclusive finite expiry without cleanup. An indefinite order is represented explicitly. Unknown people have no restriction facts, which is never proof of eligibility.

Insertion accepts only already-effective, unexpired intervals and nonzero supported masks/receipt IDs. Future-start effects are rejected. Stays and resumptions preserve scope and original end; resumption cannot restart an expired order. Revocation is permanent and does not erase other orders. Registry events publicly link the subject and order, so L11's actual disclosure rule remains a prerequisite for workflow integration.

The registry does not authenticate the truth/legality of a receipt ID or implement its one-shot consumption: its sole future writer must authenticate the issuing workflow and consume the exact typed receipt atomically with the write. No official IdentityWriter or case app is installed by this slice. There is no citizenship/lifecycle setter, custody effect, electorate callback, future scheduler or historical rights certificate. `membershipRevisionOf` and `electorateMutationCount` advance on writes only; time expiry is invisible to those counters. Consumers must not treat a current zero restriction mask as membership, citizenship, credit permission or snapshot readiness.

## Future workflow sketches

Everything after this heading is proposed legal-workflow notation unless explicitly linked to implemented source. These sketches define boundaries while exact rule tables, disclosure choices and authority inputs are completed.

## Design constraints

- Stable facts remain in registries. Named apps own legal procedure and its finality. A narrow writer performs exact approved effects.
- No proposed API accepts an arbitrary target, selector, call value, executable calldata, or unrestricted civic record. An effect hash is a commitment checked against a closed typed payload, not permission to execute opaque bytes.
- Names below are exact responsibility boundaries, not a requirement to deploy every interface as another contract. Internal libraries share identical arithmetic/signature/stage predicates. No contract per person, case, order, or stage.
- `personId` is the stable subject and vote identity. Current active wallets authenticate people; appointment nonces and mandates authenticate offices. Several keys do not create several people. Key consent cannot establish independent human control.
- Finality is effect-specific. Provisional restrictions may become effective before final judgment where authorised; membership removal and financial settlement have their own finality gates. `effectiveAt`, `finalAt`, and `stayed` are distinct facts.
- Deadlines and maximum durations remain **L01/L05 pending**. No sketch creates a default 21-day, 30-day, or universal maximum rule. Approved calendar periods may require calendar arithmetic rather than a fixed seconds multiplier.
- Public `personId`/case links in these sketches assume public subject disclosure is permitted. **L11 is a storage-design gate.** Private documents, commitments, and matter-only events do not make calldata/storage confidential.

## Common fixed data and consumption protocol

The following is Solidity-like notation, not a drop-in source file. Financial values use `uint256`; narrow fields are candidates for packing after the actual write pattern and overflow bounds are measured.

```solidity
struct DecisionContext {
    bytes32 matterId;
    bytes32 subjectPersonId;
    bytes32 rulesVersion;
    uint64 organEpoch;
    uint64 rosterRevision;
    uint32 revision;
    uint8 stage;
}

struct ReceiptHeader {
    DecisionContext context;
    address issuer;             // exact issuing workflow/version
    bytes32 issuerVersion;
    bytes32 effectHash;         // full typed effect, not just outcome
    bytes32 reasonCommitment;
    uint64 decidedAt;
    uint64 effectiveAt;
    uint64 finalAt;              // zero does not mean automatically executable
    bool stayed;
    bool consumed;
}

enum VoteChoice { Abstain, For, Against }
```

Each typed hash includes its fixed type/domain tag, `block.chainid`, exact issuer/verifying contract, writer domain, `rulesVersion`, context and every material effect field. Use `abi.encode` for unambiguous structured hashing. The legal-rules version is immutable within a case revision unless an expressly approved transition reopens it. A receipt identifier alone is not authorisation.

**Execution sequence:**

1. Anyone calls the issuing workflow's named `execute...` method. That method loads the approved effect from its own state; the transaction submitter does not choose a replacement payload.
2. The workflow calls the registered domain writer's named method with `receiptId` and that typed effect. The writer authenticates the expected current workflow module, or an explicitly approved migration route. There is no operator-managed perpetual issuer allowlist.
3. The writer computes the expected typed hash and calls the issuer's matching `consume...` method. Only the registered writer for that effect can consume it. The issuer checks kind, context, effective/final conditions, stays and non-consumption, then marks consumption before returning the canonical header/effect.
4. The writer validates the exact transition and expected old relevant state/version, then writes. No incompatible fields can be changed by another effect type.
5. Any failure reverts the whole transaction, including consumption. Reentrancy protection and checks-effects-interactions are required on paths with external calls. Authentication failures fail closed.

Only the issuing workflow stores the authoritative consumed marker. Registry audit references are provenance, not a second independently mutable `executed` flag. A membership order may generate separate later stay/revocation receipts; its original application receipt remains consumed.

Intermediate Commission recommendations, Council proposals and body votes are **typed certificates**, not identity execution receipts. Their owner workflow verifies the exact certificate/context and records acceptance of that stage once. The legal effect receipt is issued by the case workflow only after its own route gates are satisfied. An intermediate certificate grants no direct registry write authority.

Replacement is a migration decision: retained current-pointer checks can strand old receipts, while recognising all old issuers forever would create hidden authority. Complete old cases first or use a constrained approved import with replay continuity; flag open cases under **L10**.

## Bodies and appointments

```solidity
enum BodyKind { Commission, Council, Panel }

struct AppointmentEffect {
    bytes32 nominationId;
    bytes32 personId;
    bytes32 rulesVersion;
    uint64 appointmentNonce;
    uint64 startsAt;
    uint64 endsAt;
}

struct MemberAuthorization {
    bytes32 personId;
    uint64 appointmentNonce;
    uint64 startsAt;
    uint64 endsAt;
    bool active;
}

// BodyMembershipRegistry: each instance has immutable BodyKind.
function memberAuthorization(bytes32 personId)
    external view returns (MemberAuthorization memory);
function modeContext()
    external view returns (uint8 mode, uint64 organEpoch, uint64 rosterRevision);
function applyAppointment(bytes32 receiptId, AppointmentEffect calldata effect) external;
function applyRemoval(bytes32 receiptId, bytes32 personId, uint64 expectedAppointmentNonce) external;

// BodyAppointmentApp: separate nomination, voting, veto and execution.
function nominateCommissioner(bytes32 personId, bytes32 sortKeyCommitment,
    bytes32 nominationCommitment) external returns (bytes32 nominationId);
function castCommissionerAppointmentVote(bytes32 nominationId, VoteChoice vote) external;
function castCommissionerRemovalVote(bytes32 proposalId, VoteChoice vote) external;
function castAppointmentVetoVote(bytes32 nominationId, VoteChoice vote) external;
function activateCommissioner(bytes32 nominationId) external;
function executeCommissionerRemoval(bytes32 proposalId) external;
function consumeAppointment(bytes32 receiptId, bytes32 expectedEffectHash)
    external returns (ReceiptHeader memory, AppointmentEffect memory);
function consumeRemoval(bytes32 receiptId, bytes32 expectedEffectHash)
    external returns (ReceiptHeader memory, bytes32 personId, uint64 appointmentNonce);
```

Authority:

- Nomination authenticates the legally specified current Interior Minister, person and mandate; Congress appointment/removal votes authenticate current occupied person seats; Senate veto authenticates the authorised seat holders under its separate threshold. Exact appointment/removal rules remain **L03/L04**.
- `activateCommissioner` and removal execution are permissionless after their gates. `BodyMembershipRegistry` is the registered writer that alone may call the appointment app's consumption methods; the app cannot pass arbitrary membership facts to the registry.
- Council and Panel appointment entrypoints must be separately named once their legal appointing bodies, veto rules and terms are approved. The sketch deliberately does not fill this gap with `appoint(BodyKind, address admin)`.
- `mode`/epoch does not substitute for real-time mandate checks. Term expiry can occur without a transaction; ballot execution rechecks the approved current facts. Fallback changes and roster revisions are different events.
- Public name sorting requires **L11** approval and a canonical normalisation/collation rule. A sort-key hash is only an evidence commitment; it does not prove alphabetical order. Roster ordering/changes need their own authoritative validation design.
- Existing [DecisionTypes](../../contracts/types/DecisionTypes.sol) cannot issue a commissioner appointment merely by supplying a `congressDecisionId`. This app must contain a real typed vote and decision path.

## Commission decisions

```solidity
struct AdmissionRecommendation {
    DecisionContext context;
    bytes32 applicationCommitment;
    bytes32 verificationAttestationId;
    bytes32 routeTypeHash;
    bool recommend;
}

function openAdmissionBallot(bytes32 applicationId, uint32 revision,
    AdmissionRecommendation calldata proposed) external returns (bytes32 ballotId);
function assignAdmissionPanel(bytes32 ballotId, uint32 maxRosterSteps) external;
function castAdmissionRecommendation(bytes32 ballotId, VoteChoice vote,
    bytes32 reasonCommitment) external;
function finalizeAdmissionRecommendation(bytes32 ballotId) external;
function admissionRecommendation(bytes32 ballotId)
    external view returns (AdmissionRecommendation memory, bytes32 certificateHash);

function declareInterest(bytes32 matterId, bytes32 declarationCommitment) external;
function objectToCommissioner(bytes32 matterId, bytes32 personId,
    bytes32 groundsCommitment) external;
```

Only `AdmissionPipeline` opens its admission ballot. A Commission case uses exactly its assigned people and current valid authorisations, with approved stage/epoch/revision binding. Congress fallback uses a distinct full-body route and denominator; it must never become a three-member Congress panel. `assignAdmissionPanel` may make bounded progress but cannot expose a discretion to choose commissioners. Concurrent roster/ready-queue changes must not alter a partially assigned panel silently.

Annulment decisions/reviews, provider accreditation, conflicts and objections need their **own named typed certificates** with the same context mechanics. Do not generalise this into `vote(kind, target, payload)` or accept an invented opaque outcome ID. Commission shortfalls, prior-stage exclusions, readiness order and objections remain **L03/L04**; approved legal rules must define the terminal shortfall behavior. Seven members do not guarantee three eligible disjoint decision-makers for every review.

## Admission and annulment effects

```solidity
enum AdmissionRoute { Regular, Descent, Birth }

struct VerificationEffect {
    bytes32 personId;
    bytes32 applicationId;
    bytes32 attestationId;
    bytes32 expectedIdentityStateHash;
    uint32 applicationRevision;
    uint8 verificationStatus;    // validated fixed enum values, never arbitrary civic fields
    uint8 ageClass;
}

struct AdmissionEffect {
    bytes32 personId;
    bytes32 applicationId;
    bytes32 expectedCivicStateHash;
    bytes32 acceptedRecommendationHash;
    uint32 applicationRevision;
    AdmissionRoute route;
    // target transition is fixed: lawful admission + Active membership
}

struct AnnulmentEffect {
    bytes32 personId;
    bytes32 originalAdmissionId;
    bytes32 expectedCivicStateHash;
    bytes32 lawfulFindingCommitment;
    // target transition is fixed: prospective annulment, no raw Revoked setter
}

// AdmissionPipeline
function submitApplication(AdmissionRoute route, bytes32 applicationCommitment,
    bytes32 destinationConsentCommitment) external returns (bytes32 applicationId);
function attachVerification(bytes32 applicationId, bytes calldata signedAttestation) external;
function acceptCommissionRecommendation(bytes32 applicationId, bytes32 ballotId) external;
function transmitRegularApplication(bytes32 applicationId) external;
function transmitRegularAfterDeadline(bytes32 applicationId) external;
function confirmRegularApplication(bytes32 applicationId) external;
function refuseRegularApplication(bytes32 applicationId, bytes32 reasonsCommitment) external;
function confirmRegularByDeemedOutcome(bytes32 applicationId) external;
function executeRegularAdmission(bytes32 applicationId) external;
function executeDescentRegistration(bytes32 applicationId) external;
function executeBirthGrant(bytes32 applicationId) external;
function consumeVerification(bytes32 receiptId, bytes32 expectedEffectHash)
    external returns (ReceiptHeader memory, VerificationEffect memory);
function consumeAdmission(bytes32 receiptId, bytes32 expectedEffectHash)
    external returns (ReceiptHeader memory, AdmissionEffect memory);

// AnnulmentApp
function initiateAnnulment(bytes32 originalAdmissionId, bytes32 groundsCommitment)
    external returns (bytes32 matterId);
function respondToAnnulment(bytes32 matterId, bytes32 responseCommitment) external;
function requestAnnulmentReview(bytes32 matterId, bytes32 groundsCommitment) external;
function executeAnnulment(bytes32 receiptId) external;
function consumeAnnulment(bytes32 receiptId, bytes32 expectedEffectHash)
    external returns (ReceiptHeader memory, AnnulmentEffect memory);
```

The route owns proof of who may submit for a child, independent identity evidence, recommendation acceptance, lawful service, review and route-specific Presidential/Ministerial acts. `bytes signedAttestation` is signature/claim evidence, not executable calldata: its schema binds accredited provider, subject/application/revision/commitment, declared result, chain/domain, nonce and expiry, with ERC-1271 support where relevant. Signature length, document commitments and batch work must be bounded; final values are engineering decisions.

Only the registered `IdentityWriter` may consume verification, admission or annulment receipts. Only the current authorised Minister/President may perform their named discretionary acts; expired terms/wallet migrations are revalidated. Transmission after a missed deadline and deemed outcomes are permissionless only when explicitly authorised by **L01/L05**. A Minister's transmit method does not imply a refusal power.

A legitimate verification correction must not become an alternative path to citizen status or hidden political exclusion. Metadata-only correction has a different effect type. Initial applicant creation/wallet acceptance must retain the current explicit destination-consent protection. Annulment must bind the original admission and its decision participants; permitted grounds, mandatory versus optional review and effective timing remain **L01/L03/L05**. No hash demonstrates the truth of fraud.

## Proposed membership lifecycle and typed writer integration

```solidity
enum MembershipBase { None, Active, Removed, Resigned, Annulled }

struct ProposedMembershipLifecycleSummary {
    MembershipBase base;        // lifecycle is not implemented in the restriction registry
    uint16 restrictedMask;
    uint16 indefiniteMask;
    uint64[5] restrictedUntil;
    uint256 personRevision;
}

struct MembershipOrderEffect {
    bytes32 personId;
    bytes32 orderId;
    bytes32 expectedMembershipStateHash;
    uint16 restrictedMask;
    uint64 effectiveAt;
    uint64 expiresAt;
    bool indefinite;
}

struct MembershipRemovalEffect {
    bytes32 personId;
    bytes32 expectedMembershipStateHash;
}

struct OrderReliefEffect {
    bytes32 personId;
    bytes32 orderId;
    bytes32 expectedOrderStateHash;
}

// Future lifecycle/scheduling extension, not the implemented restriction ABI:
function membershipStateHash(bytes32 personId) external view returns (bytes32);
function nextRelevantTransition(bytes32 personId) external view returns (uint64);
function removeMembership(MembershipRemovalEffect calldata effect, bytes32 receiptId) external;

// IdentityWriter: only named case workflow calls these receipt-backed transitions.
function admitCitizen(bytes32 receiptId, AdmissionEffect calldata effect) external;
function recordVerification(bytes32 receiptId, VerificationEffect calldata effect) external;
function annulAdmission(bytes32 receiptId, AnnulmentEffect calldata effect) external;
function applyMembershipOrder(bytes32 receiptId, MembershipOrderEffect calldata effect) external;
function applyMembershipRemoval(bytes32 receiptId, MembershipRemovalEffect calldata effect) external;
function applyMembershipStay(bytes32 receiptId, OrderReliefEffect calldata effect) external;
function revokeMembershipOrder(bytes32 receiptId, OrderReliefEffect calldata effect) external;
```

The implemented restriction registry already provides independent orders, indexed per-right heaps, explicit indefinite masks and current reads without cleanup. The proposed lifecycle summary above is not its current return type. Future-start scheduling and priority among base lifecycle/restoration effects still need separate specification. The five bit names remain a storage catalog until approved measures and consumers are mapped under L02/L14.

The named writer methods recognise only their expected issuing workflows and types. `DisciplineCaseApp` cannot call citizenship-changing writer methods. Annulment and renunciation have distinct provenance. Every write is checked against relevant old state; choose narrowly scoped hashes/nonces so unrelated metadata/case activity does not invalidate an otherwise valid legal effect.

Self-service renunciation and membership resignation require separate named methods with current active-person authentication, signatures/nonces where relayed, and explicit consequences under **L01/L02**. Metadata correction must use a separate `MetadataCorrectionEffect` containing only old metadata commitment and new metadata commitment/URI; verification/age/citizenship/order fields are absent. Do not add `setIdentityRecord` to the public writer interface.

The following completes the proposed foundation boundaries without choosing the blocked legal rules:

```solidity
struct ApplicantRegistrationEffect {
    bytes32 personId;
    bytes32 applicationId;
    bytes32 metadataCommitment;
    // absence required; fixed noncitizen/unverified facts, no political rights
}

struct InitialWalletEffect {
    bytes32 personId;
    bytes32 applicationId;
    address newWallet;
    bytes32 destinationConsentHash;
    uint256 personNonce;
    // no previous active wallet; destination must still be free
}

struct MembershipRestorationEffect {
    bytes32 personId;
    bytes32 expectedLifecycleStateHash;
    // approved lifecycle restoration only; does not erase independent orders
}

struct MetadataCorrectionEffect {
    bytes32 personId;
    bytes32 expectedMetadataHash;
    bytes32 newMetadataHash;
    string newMetadataURI;       // bounded and subject to L11 disclosure approval
}

// AdmissionPipeline: prospective destination accepts for the exact application.
function acceptInitialWallet(bytes32 applicationId) external;
function consumeApplicantRegistration(bytes32 receiptId, bytes32 expectedEffectHash)
    external returns (ReceiptHeader memory, ApplicantRegistrationEffect memory);
function consumeInitialWallet(bytes32 receiptId, bytes32 expectedEffectHash)
    external returns (ReceiptHeader memory, InitialWalletEffect memory);

// IdentityWriter: AdmissionPipeline only for applicant/initial-link receipts.
function registerApplicant(bytes32 receiptId, ApplicantRegistrationEffect calldata effect) external;
function linkInitialWallet(bytes32 receiptId, InitialWalletEffect calldata effect) external;

// IdentityWriter: current active person only; direct self-service, no official approval.
function renounceCitizenship() external;
function resignMembership() external;

// IdentityWriter: exact authorised case receipts only.
function restoreMembership(bytes32 receiptId, MembershipRestorationEffect calldata effect) external;
function correctMetadata(bytes32 receiptId, MetadataCorrectionEffect calldata effect) external;

// DisciplineCaseApp: only the registered IdentityWriter consumes restoration.
function consumeMembershipRestoration(bytes32 receiptId, bytes32 expectedEffectHash)
    external returns (ReceiptHeader memory, MembershipRestorationEffect memory);

// CommissionDecisionApp: only the registered IdentityWriter consumes lawful correction.
function consumeMetadataCorrection(bytes32 receiptId, bytes32 expectedEffectHash)
    external returns (ReceiptHeader memory, MetadataCorrectionEffect memory);
```

Applicant registration receipts attest a constrained procedural registration, not a collective citizenship finding. They cannot grant citizenship, choose arbitrary age/verification, or create Active membership. Initial destination acceptance is checked against the caller/current valid consent and application nonce. Preliminary registration, verification and initial linking remain distinct effects; an earlier receipt cannot be reused as an admission approval.

Membership admission, resignation, annulment and restoration require corresponding fixed registry methods callable only by IdentityWriter; none receives a generic lifecycle enum chosen by the caller. Renunciation/resignation preserve obligations and unrelated state under the approved rules. Self-service methods above assume direct active-wallet calls; optional relaying needs a separately reviewed nonce/domain/signature form, not a trusted relayer role. Metadata correction cannot act as age/verification correction. Every correction route is separately authorised under L01/L13 and rechecks the allowed field scope.

Restoration needs separate named receipts for lifecycle restoration and particular-order relief. It must not erase concurrent valid orders. Membership-registry writes advance a third electorate source revision and attempt a bounded callback to the current `ElectorateRegistryV2`; callback failure is detectable and catch-up is permissionless. A same-data write through [IdentityRegistry](../../contracts/registries/IdentityRegistry.sol) is only a temporary compatibility option, not the target interface.

## Discipline workflow

```solidity
function referMembershipCase(bytes32 personId, bytes32 referralCommitment)
    external returns (bytes32 matterId);
function submitDefence(bytes32 matterId, bytes32 defenceCommitment) external;
function proposeMembershipOrder(bytes32 matterId, MembershipOrderEffect calldata proposed,
    bytes32 reasonsCommitment) external returns (bytes32 proposalId);
function proposeMembershipRemoval(bytes32 matterId, MembershipRemovalEffect calldata proposed,
    bytes32 reasonsCommitment) external returns (bytes32 proposalId);
function castMembershipOrderVote(bytes32 proposalId, VoteChoice vote) external;
function castMembershipRemovalVote(bytes32 proposalId, VoteChoice vote) external;
function executeMembershipOrder(bytes32 receiptId) external;
function executeMembershipRemoval(bytes32 receiptId) external;
function consumeMembershipOrder(bytes32 receiptId, bytes32 expectedEffectHash)
    external returns (ReceiptHeader memory, MembershipOrderEffect memory);
function consumeMembershipRemoval(bytes32 receiptId, bytes32 expectedEffectHash)
    external returns (ReceiptHeader memory, MembershipRemovalEffect memory);
function consumeMembershipStay(bytes32 receiptId, bytes32 expectedEffectHash)
    external returns (ReceiptHeader memory, OrderReliefEffect memory);
function consumeOrderRevocation(bytes32 receiptId, bytes32 expectedEffectHash)
    external returns (ReceiptHeader memory, OrderReliefEffect memory);
```

Referrals authenticate lawful standing; submitting a complaint grants no power to impose a measure. Council proposal and Panel approval authenticate different authorised body contexts. Exact threshold/quorum/abstention/recusal rules are **L03/L04**. Only `IdentityWriter` consumes these execution receipts. Public execution is permissionless; it is not a new decision by the executor.

Provisional measures, reconsideration, restoration, set-aside and stays need explicit named state transitions and deadlines; they must not be represented by a generic `updateCaseStatus`. Conditional public office protection is checked both at proposal and effect execution under **L14**, without inventing a direct removal power for the Council. A membership order carries no financial amount; financial proposals have separate votes/receipts. No discipline entrypoint changes citizenship or calls unrestricted `slashStake`.

Service/response/historical evidence access, hearing completion and reasons remain approved legal predicates under **L05**. A `recordService` helper is not an admin assertion of delivery: its evidence schema, authorised attestors, challenges and legal start time must be agreed before coding. Timeout effects are named per stage. Financial appeals and membership appeals do not automatically share a stay rule.

## Right-specific reads and policy bundle

```solidity
function isOnCivicRoll(bytes32 personId) external view returns (bool);
function mayVoteNow(address wallet) external view returns (bool);
function mayProposeReferendum(address wallet) external view returns (bool);
function mayStandForCongress(address wallet) external view returns (bool);
function mayAcceptExecutiveAppointment(address wallet) external view returns (bool);
function mayRepresentMember(bytes32 personId) external view returns (bool);
function mayOriginateLoan(bytes32 personId) external view returns (bool);
```

These are separate named permission semantics, not a claim that each needs a separate policy deployment. They read compact facts/rights; no case-history arrays, KYC signatures or global expiry cleanup appear in a voting read. Repayment, current-key authentication, lawful withdrawal and access to a defence are **not** controlled by `mayVoteNow`. Good standing retains a documented compatibility meaning until callers migrate deliberately. No generic `canDo(uint8 action)` mask is required to replace readable consumer methods.

The coherent policy bundle includes citizen/rights policy, `VotingPowerPolicyV2`, `CandidateEligibilityPolicyV2`, and `CongressElectionPolicyV2`; each immutable dependency and electorate address must match the approved manifest. Existing [VotingPowerPolicy](../../contracts/policies/VotingPowerPolicy.sol), [CandidateEligibilityPolicy](../../contracts/policies/CandidateEligibilityPolicy.sol), and [CongressElectionPolicy](../../contracts/policies/CongressElectionPolicy.sol) are immutable bundles; replacing one kernel pointer does not rewire them.

**L02:** decide separately whether restricted members remain in constitutional civic-roll denominators and whether current restrictions affect already-cast votes. **L10:** decide ongoing-process treatment before replacing a pinned bundle. Preserve historical stake/eligibility snapshots and current-right checking as separate concepts; neither substitutes for the other.

## Electorate certification candidate

```solidity
struct SnapshotCertificate {
    uint48 blockNumber;
    uint64 blockTimestamp;
    uint64 epoch;
    uint64 nextRelevantTransitionAt;
    uint256 citizenCount;
    uint256 votingPower;
    uint256 identityMutationCount;
    uint256 stakeMutationCount;
    uint256 membershipMutationCount;
}

function syncPerson(bytes32 personId) external;
function rebuild(uint256 startIndex, uint32 maxCount) external returns (uint256 nextIndex);
function processExpiries(uint32 maxCount) external returns (uint32 processed);
function certifyCurrentBlock() external returns (SnapshotCertificate memory);
function certifiedCompletedSnapshot(uint48 blockNumber)
    external view returns (SnapshotCertificate memory);
```

**This is a Phase A executable-specification gate, not a solved algorithm.** Pick this design only if membership/time effects change the legal denominators. A simpler lawful model may leave civic-roll aggregates unchanged and check rights at the consumer.

Requirements for a viable implementation:

- Three source mutation counters/per-person revisions, deferred callbacks, bounded catch-up and explicit policy epochs. Existing identity/stake sources offer a maximum 500,000-gas callback; rights reads must fit without scanning history.
- The indexed due queue tracks actual relevant aggregate transitions, not every historical document. Process at most caller-bounded work; stale entries cannot require an unbounded cleanup before a view/vote.
- `certifyCurrentBlock` requires synchronized sources and no due relevant transition. Its stored timestamp is an observed chain value, not an untrusted caller-supplied historic time. The next transition is a validity horizon, not permission to invent a historic aggregate.
- Mutations later in the same block refresh/invalidate that block's tentative certificate. Failed callbacks and late catch-up move the safe boundary forward.
- Catch-up in block N cannot certify missing blocks N-1 or earlier retroactively. New process creation uses a validated completed-block certificate. A late keeper never makes the missed interval historically ready.
- Choosing older certificates instead of today's strict last-completed-block API is **L02/L10 pending**. Exact last-block certification can require a separate transaction in the preceding block; fee funding and liveness must be specified.
- Only certificates validated and pinned under the complete creation checks are authoritative historical inputs to those processes. A readable stale trace is not a universal historical-readiness proof.
- Prototype expiry before/after a block boundary, same-block source writes after certification, delayed keeper work, pending policy replacement, pinned old processes and partial callback failure. Do not accept a design merely because `isReady` checks three counters.

## Wallet recovery

```solidity
struct WalletReplacementEffect {
    bytes32 personId;
    address expectedOldWallet;
    address newWallet;
    bytes32 destinationConsentHash;
    uint256 personNonce;
}

function requestRecovery(bytes32 personId, address newWallet,
    bytes32 reVerificationCommitment, bytes calldata destinationConsent)
    external returns (bytes32 matterId);
function objectFromOldWallet(bytes32 matterId, bytes32 objectionCommitment) external;
function submitContestedRecoveryResponse(bytes32 matterId, bytes32 responseCommitment) external;
function executeRecovery(bytes32 receiptId) external;
function consumeRecovery(bytes32 receiptId, bytes32 expectedEffectHash)
    external returns (ReceiptHeader memory, WalletReplacementEffect memory);

// IdentityWriter: current RecoveryApp only; receipt consumption required.
function replaceRecoveredWallet(bytes32 receiptId, WalletReplacementEffect calldata effect) external;

// Separate consent-only workflow entrypoint; no official approval if authorised.
function migrateVoluntarily(address expectedOldWallet, address newWallet,
    uint256 personNonce, uint64 consentDeadline,
    bytes calldata oldWalletConsent, bytes calldata newWalletConsent) external;
```

`RecoveryApp` owns notice, re-verification, collective determinations, objections, hearing and finality. Only `IdentityWriter` consumes its receipt. Execution rechecks old active link, nonce, free destination and required consent; any stale condition reverts atomically. Signatures bind person and expected links, chain/domain, nonce and deadline, with ERC-1271 validity semantics explicitly defined.

The current [IdentityApp](../../contracts/apps/IdentityApp.sol) allows the old wallet to cancel. Changing that into a hearing is a substantive legal/security decision under **L06**, not just an implementation refactor. Neither permanent veto nor automatic override is presumed. Interim protection against a stolen active key is unresolved; do not add a blanket property freeze.

Senate second approval is **L06 pending**. If authorised, a separate narrow recovery determination workflow may read Senate seat facts. Do not extend SenateApp's negative-control hooks into a generic positive executor. Recovery never transfers external wallet balances or private keys; generic wallet-bound roles need separate treatment. Permissionless execution still needs an available fee payer.

## Financial and land boundary sketches

These reserve typed boundaries only. Complete cohort, priority, liquidity and remedy algorithms are not approved interfaces yet; see [financial and land design](FINANCIAL-AND-LAND-DESIGN.md). Names here must be reconciled before ABI approval.

```solidity
struct ReservationEffect {
    bytes32 claimId;
    bytes32 personId;
    bytes32 reservationId;
    uint256 amount;
    uint64 expiresAt;
    // priority is derived from authoritative proceeding/reservation facts
}

struct FinancialSettlementEffect {
    bytes32 claimId;
    bytes32 personId;
    bytes32 beneficiaryRef;
    address asset;
    uint256 maximumAward;
    uint48 finalityCutoffBlock;
    bytes32 eligibleCohortRef;
    bytes32 beneficiaryConsentHash;
    uint8 settlementMode;       // closed liquid/staked modes only, final enum pending
}

function executeCompensation(bytes32 receiptId) external;
function consumeCompensation(bytes32 receiptId, bytes32 expectedEffectHash)
    external returns (ReceiptHeader memory, FinancialSettlementEffect memory);

struct ParcelPrecondition {
    bytes32 parcelId;
    bytes32 expectedParcelVersionHash;
    bytes32 expectedTitleVersionHash;
}

struct LandTitleRemedy {
    bytes32 disputeId;
    bytes32 parcelId;
    bytes32 expectedParcelVersionHash;
    bytes32 expectedTitleVersionHash;
    bytes32 newPartyNamespace;
    bytes32 newPartyId;
    bytes32 lawfulJudgmentCommitment;
}

function executeTitleRemedy(bytes32 receiptId) external;
function consumeTitleRemedy(bytes32 receiptId, bytes32 expectedEffectHash)
    external returns (ReceiptHeader memory, LandTitleRemedy memory);
```

The registered financial settlement component alone consumes a financial receipt. Authorisation binds award, asset, beneficiary, settlement mode, finality cutoff, rules version and exact scope. A fresh execution quote validates current exposure/cohort/version/custody state; do not freeze unrelated account versions at the initial proposal and strand every award. `eligibleCohortRef` does not assume a Merkle publisher/proof architecture. No amount is taken from later deposits merely because an aggregate historic cap is large enough. Reservations/loans cannot double-claim the same free asset. Restricted active stake needs the required beneficiary choice/consent; it is not liquid payment. **L07/L08** block settlement activation.

`LandDisputeCaseApp` issues the legal remedy; `LandRegistryAppV2` is its registered narrow writer/consumer. A separate `LandExecutor` is optional only if an independently reviewed authority/size boundary justifies it. Boundary/subdivision/merge/encumbrance effects need their **own fixed payloads**, bounded precondition arrays for every affected parcel/title, and exact geometry/document commitments. Current parcel atomic batch bound is 16; any change must be justified and measured. Do not turn this sketch into `executeRemedy(kind, bytes data)`.

Execution checks finality/stays, current versions, all affected parties, remedy-specific authority and remaining dispute locks. Resolving one dispute cannot release another. If the stable registry cannot express a lawful remedy without bypassing another lock or inventing an owner signature, flag registry evolution rather than adding an unchecked override. Automatic complaint locks and substantive title remedies remain **L12** pending.

## Decisions required before interface freeze

| Decision | Interface consequence |
| --- | --- |
| L01 controlling legal text and commencement | Route catalog, permissible effects, legal version, effective dates |
| L02 membership rights, overlap, roll denominators | Order aggregation, rights readers, need for time-sensitive electorate replacement |
| L03 bodies, appointments and conflicts | Body instances, appointment/removal methods, roster and shortfall behavior |
| L04 vote denominators, mandates and modes | Certificate validation, epoch/revision and current-authorisation predicates |
| L05 service, deadlines, appeal/stay/finality | Named stage transitions and receipt-specific execution predicates |
| L06 recovery authority and objection handling | Second-check workflow, hearing, interim key protection |
| L07 exposure and acceptance | Asset classification and consent payloads |
| L08 compensation and existing loan priority | Allocation/cohort/settlement quote and custody interfaces |
| L09 historical record classification | Constrained import types and ambiguous-record treatment |
| L10 ongoing processes | Retained issuers, pinned policy bundles, migration replay continuity |
| L11 privacy | Whether proposed public subject/context structures are permissible at all |
| L12 land regulation | Remedy catalog, filing locks and writer scope |
| L13 special appointments, honorary Cabinet decisions and courts | Separate typed approval sources; no invented PM/court powers |
| L14 constitutional office protection | Precondition and referral rules; no direct office-removal shortcut |

Interface acceptance also requires adversarial vectors for wrong issuer/kind/context/effect, replay, stays after approval, old-state races, mandate expiry, duplicate person keys, overlapping order cancellation, missed time transitions, mixed policy bundles, migration interruption, and financial/land stale version conflicts. Gas/bytecode claims require measurements in the pinned compiler/EVM profile; these sketches promise bounded work, not numerical savings.
