// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {KernelModule} from "../base/KernelModule.sol";
import {IJusticeApp} from "../interfaces/IJusticeApp.sol";
import {IJusticeDecisions} from "../interfaces/IJusticeDecisions.sol";
import {IJusticeIdentityWriter} from "../interfaces/IJusticeIdentityWriter.sol";
import {IJusticeCompensation} from "../interfaces/IJusticeCompensation.sol";
import {IIdentityRegistry} from "../interfaces/IIdentityRegistry.sol";
import {IMembershipRegistry} from "../interfaces/IMembershipRegistry.sol";
import {IPresidentRegistry} from "../interfaces/IPresidentRegistry.sol";
import {IExecutiveRegistry} from "../interfaces/IExecutiveRegistry.sol";
import {ISenateSeatRegistry} from "../interfaces/ISenateSeatRegistry.sol";
import {ICongressCandidateRegistry} from "../interfaces/ICongressCandidateRegistry.sol";
import {KernelModuleIds} from "../libraries/KernelModuleIds.sol";
import {JusticeTypes} from "../types/JusticeTypes.sol";
import {MembershipTypes} from "../types/MembershipTypes.sol";
import {IdentityTypes} from "../types/IdentityTypes.sol";
import {ExecutiveTypes} from "../types/ExecutiveTypes.sol";

/// @notice Permissionless submission of exact, already approved justice decisions.
/// @dev Signers attest service, access to evidence, hearing, reasons and eligibility for execution in recordHash.
///      The protocol checks signatures and time limits; private evidence and proceedings stay off-chain.
contract JusticeApp is IJusticeApp, KernelModule, EIP712 {
    bytes32 private constant _DECISION_TYPEHASH = keccak256(
        "Decision(uint8 action,bytes32 decisionId,bytes32 personId,bytes32 effectHash,bytes32 reasonHash,bytes32 recordHash,uint64 noticeAt,uint64 deadline,uint256 stateRevision)"
    );
    bytes32 private constant _CONSENT_TYPEHASH = keccak256("DestinationConsent(bytes32 decisionDigest)");
    uint256 private constant _NOTICE = 21 days;
    uint256 private constant _RECOVERY_NOTICE = 30 days;
    uint256 private constant _MAX_SIGNATURE_LENGTH = 4096;

    IIdentityRegistry private immutable _identity;
    IMembershipRegistry private immutable _membership;
    IJusticeDecisions private immutable _decisions;
    IJusticeIdentityWriter private immutable _identityWriter;
    IJusticeCompensation private immutable _compensation;

    bytes32 private immutable _rulesHash;
    uint64 private immutable _termEndsAt;
    uint32 private immutable _maxRestrictionDuration;
    uint16 private immutable _allowedRights;
    uint8[5] private _bodySizes;
    mapping(bytes32 personId => uint8 bodies) private _bodyMask;

    constructor(
        address kernelAddress,
        address identityRegistry,
        address membershipRegistry,
        address decisions,
        address identityWriterAddress,
        address compensation,
        JusticeTypes.Charter memory limits,
        bytes32[][5] memory rosters
    ) KernelModule(kernelAddress) EIP712("Liberland Justice", "1") {
        _identity = IIdentityRegistry(identityRegistry);
        _membership = IMembershipRegistry(membershipRegistry);
        _decisions = IJusticeDecisions(decisions);
        _identityWriter = IJusticeIdentityWriter(identityWriterAddress);
        _compensation = IJusticeCompensation(compensation);
        if (
            _identity.kernel() != kernelAddress || _membership.kernel() != kernelAddress
                || _membership.identityRegistry() != identityRegistry || _decisions.kernel() != kernelAddress
                || _identityWriter.kernel() != kernelAddress || _identityWriter.identityRegistry() != identityRegistry
                || _compensation.kernel() != kernelAddress || _compensation.identityRegistry() != identityRegistry
        ) revert InvalidCharter();
        if (
            limits.rulesHash == bytes32(0) || limits.termEndsAt <= block.timestamp || limits.maxRestrictionDuration == 0
                || limits.maxRestrictionDuration > 365 days || limits.allowedRights == 0
                || (limits.allowedRights & ~MembershipTypes.SUPPORTED_RIGHTS_MASK) != 0
        ) revert InvalidCharter();
        _rulesHash = limits.rulesHash;
        _termEndsAt = limits.termEndsAt;
        _maxRestrictionDuration = limits.maxRestrictionDuration;
        _allowedRights = limits.allowedRights;
        for (uint8 i; i < rosters.length; ++i) {
            JusticeTypes.Body body = JusticeTypes.Body(i);
            bytes32[] memory members = rosters[i];
            if (members.length < 3 || members.length > 15) revert InvalidRoster(body, bytes32(0));
            _bodySizes[i] = uint8(members.length);
            uint8 group = i < uint8(JusticeTypes.Body.Council) ? 7 : 24;
            for (uint256 j; j < members.length; ++j) {
                bytes32 person = members[j];
                if (person == bytes32(0) || (_bodyMask[person] & group) != 0) revert InvalidRoster(body, person);
                _bodyMask[person] |= uint8(1) << i;
                emit JusticeMemberAppointed(body, person);
            }
        }
    }

    /// @inheritdoc IJusticeApp
    function identityWriter() external view returns (address) {
        return address(_identityWriter);
    }

    /// @inheritdoc IJusticeApp
    function isCurrent() public view returns (bool) {
        return _isModuleCaller(KernelModuleIds.JUSTICE_APP, address(this))
            && _isModuleCaller(KernelModuleIds.IDENTITY_WRITER, address(this))
            && _isModuleCaller(KernelModuleIds.IDENTITY_REGISTRY_AUTHORITY, address(_identityWriter))
            && _isModuleCaller(KernelModuleIds.IDENTITY_REGISTRY, address(_identity))
            && _isModuleCaller(KernelModuleIds.MEMBERSHIP_REGISTRY, address(_membership))
            && _isModuleCaller(KernelModuleIds.JUSTICE_DECISIONS, address(_decisions))
            && _isModuleCaller(KernelModuleIds.JUSTICE_COMPENSATION, address(_compensation));
    }

    /// @inheritdoc IJusticeApp
    function charter() external view returns (JusticeTypes.Charter memory) {
        return JusticeTypes.Charter(_rulesHash, _termEndsAt, _maxRestrictionDuration, _allowedRights);
    }

    /// @inheritdoc IJusticeApp
    function bodyMembership(JusticeTypes.Body body, bytes32 personId)
        external
        view
        returns (uint256 size, bool member)
    {
        return (_bodySizes[uint8(body)], _belongs(body, personId));
    }

    /// @inheritdoc IJusticeApp
    function decisionStateRevision(JusticeTypes.Action action, bytes32 personId) public view returns (uint256) {
        if (action == JusticeTypes.Action.Recover) return _decisions.recoveryRevisionOf(personId);
        return _identity.electorateRevisionOf(personId);
    }

    /// @inheritdoc IJusticeApp
    function decisionDigest(JusticeTypes.Decision calldata decision) public view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(_DECISION_TYPEHASH, decision)));
    }

    /// @inheritdoc IJusticeApp
    function destinationConsentDigest(JusticeTypes.Decision calldata decision) public view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(_CONSENT_TYPEHASH, decisionDigest(decision))));
    }

    /// @inheritdoc IJusticeApp
    function executeIdentity(
        JusticeTypes.Decision calldata decision,
        JusticeTypes.IdentityEffect calldata effect,
        JusticeTypes.Approvals calldata approvals
    ) external {
        bytes32 digest = _validate(decision, keccak256(abi.encode(effect)), approvals.publicReasonURI);
        bytes32 subject = decision.personId;
        if (decision.action == JusticeTypes.Action.Admit) {
            if (
                decision.noticeAt != 0 || effect.ageClass == IdentityTypes.AgeClass.Undefined
                    || effect.priorDecisionId != bytes32(0)
            ) revert InvalidEffect();
            _verifyBody(JusticeTypes.Body.Admission, decision, digest, approvals.first);
            _verifyAdmissionOfficers(decision, effect, digest, approvals);
            _checkSignature(subject, effect.wallet, destinationConsentDigest(decision), approvals.destination);
            bytes32[] memory signers = new bytes32[](approvals.first.length);
            for (uint256 i; i < signers.length; ++i) {
                signers[i] = approvals.first[i].personId;
            }
            _decisions.consume(decision.decisionId);
            _decisions.recordAdmission(subject, signers);
            _identityWriter.executeAdmission(subject, effect.wallet, decision.recordHash, effect.ageClass);
        } else if (decision.action == JusticeTypes.Action.Annul) {
            if (effect.wallet != address(0) || effect.priorDecisionId != bytes32(0) || !_emptyAdmissionFields(effect)) {
                revert InvalidEffect();
            }
            _waitForNotice(decision.noticeAt, _NOTICE);
            _requireUnprotected(subject);
            _verifyBody(JusticeTypes.Body.Annulment, decision, digest, approvals.first);
            _verifyBody(JusticeTypes.Body.AnnulmentReview, decision, digest, approvals.second);
            _decisions.consume(decision.decisionId);
            _decisions.recordAnnulment(subject, decision.decisionId);
            _identityWriter.executeAnnulment(subject);
        } else if (decision.action == JusticeTypes.Action.Recover) {
            if (effect.priorDecisionId != bytes32(0) || !_emptyAdmissionFields(effect)) revert InvalidEffect();
            _waitForNotice(decision.noticeAt, _RECOVERY_NOTICE);
            _verifyCouncilPanel(decision, digest, approvals);
            _checkSignature(subject, effect.wallet, destinationConsentDigest(decision), approvals.destination);
            _decisions.consume(decision.decisionId);
            // Recovery names the stable person, so moving their old active link cannot veto the decision.
            _decisions.advanceRecovery(subject);
            _identityWriter.executeRecovery(subject, _identity.activeWalletOf(subject), effect.wallet);
        } else if (decision.action == JusticeTypes.Action.RecognizeAdulthood) {
            if (
                decision.noticeAt != 0 || !_emptyAdmissionFields(effect) || effect.priorDecisionId != bytes32(0)
                    || effect.wallet != _identity.activeWalletOf(subject)
            ) revert InvalidEffect();
            _verifyBody(JusticeTypes.Body.Admission, decision, digest, approvals.first);
            _checkSignature(subject, effect.wallet, destinationConsentDigest(decision), approvals.destination);
            _decisions.consume(decision.decisionId);
            _identityWriter.executeAdulthood(subject);
        } else if (decision.action == JusticeTypes.Action.RestoreCitizenship) {
            if (effect.wallet != address(0) || !_emptyAdmissionFields(effect) || effect.priorDecisionId == bytes32(0)) {
                revert InvalidEffect();
            }
            _verifyBody(JusticeTypes.Body.Annulment, decision, digest, approvals.first);
            _verifyBody(JusticeTypes.Body.AnnulmentReview, decision, digest, approvals.second);
            _decisions.consume(decision.decisionId);
            _decisions.clearAnnulment(subject, effect.priorDecisionId);
            _identityWriter.executeCitizenshipRestoration(subject);
        } else {
            revert InvalidEffect();
        }
        _emitDecision(decision, approvals.publicReasonURI);
    }

    /// @inheritdoc IJusticeApp
    function executeMembership(
        JusticeTypes.Decision calldata decision,
        JusticeTypes.MembershipEffect calldata effect,
        JusticeTypes.Approvals calldata approvals
    ) external {
        JusticeTypes.Action action = decision.action;
        if (action < JusticeTypes.Action.Restrict || action > JusticeTypes.Action.RevokeOrder) revert InvalidEffect();
        bytes32 digest = _validate(decision, keccak256(abi.encode(effect)), approvals.publicReasonURI);
        bytes32 subject = decision.personId;
        (, IdentityTypes.CitizenshipStatus status,,) = _identity.getCitizenshipSummary(subject);
        if (status != IdentityTypes.CitizenshipStatus.Citizen) revert InvalidEffect();
        if (action == JusticeTypes.Action.Restrict || action == JusticeTypes.Action.RemoveMembership) {
            _waitForNotice(decision.noticeAt, _NOTICE);
            _requireUnprotected(subject);
        }
        _verifyCouncilPanel(decision, digest, approvals);
        _decisions.consume(decision.decisionId);
        if (action == JusticeTypes.Action.Restrict) {
            if (
                effect.orderId != bytes32(0) || effect.revision != 0 || effect.rights == 0
                    || (effect.rights & ~_allowedRights) != 0 || effect.expiresAt <= block.timestamp
                    || effect.expiresAt > uint256(decision.noticeAt) + _NOTICE + _maxRestrictionDuration
            ) revert InvalidEffect();
            _membership.recordOrder(
                MembershipTypes.OrderInput(
                    subject, decision.decisionId, effect.rights, uint64(block.timestamp), effect.expiresAt, false
                ),
                digest
            );
        } else {
            if (effect.rights != 0 || effect.expiresAt != 0) revert InvalidEffect();
            if (action == JusticeTypes.Action.RemoveMembership || action == JusticeTypes.Action.RestoreMembership) {
                if (effect.orderId != bytes32(0)) revert InvalidEffect();
                _membership.setMembershipRemoved(
                    subject, action == JusticeTypes.Action.RemoveMembership, effect.revision, digest
                );
            } else if (action == JusticeTypes.Action.StayOrder) {
                _membership.stayOrder(subject, effect.orderId, effect.revision, digest);
            } else if (action == JusticeTypes.Action.ResumeOrder) {
                _requireUnprotected(subject);
                _membership.resumeOrder(subject, effect.orderId, effect.revision, digest);
            } else {
                _membership.revokeOrder(subject, effect.orderId, effect.revision, digest);
            }
        }
        _emitDecision(decision, approvals.publicReasonURI);
    }

    /// @inheritdoc IJusticeApp
    function executeFinancial(
        JusticeTypes.Decision calldata decision,
        JusticeTypes.FinancialEffect calldata effect,
        JusticeTypes.Approvals calldata approvals
    ) external {
        bytes32 digest = _validate(decision, keccak256(abi.encode(effect)), approvals.publicReasonURI);
        _verifyCouncilPanel(decision, digest, approvals);
        _decisions.consume(decision.decisionId);
        if (decision.action == JusticeTypes.Action.Compensate) {
            _waitForNotice(decision.noticeAt, _NOTICE);
            _compensation.award(
                decision.decisionId,
                effect.referenceId,
                decision.personId,
                effect.beneficiary,
                effect.amount,
                effect.cutoffBlock,
                effect.termsHash
            );
        } else if (decision.action == JusticeTypes.Action.RestoreMerits) {
            if (
                effect.beneficiary != bytes32(0) || effect.cutoffBlock != 0 || effect.termsHash != bytes32(0)
                    || _compensation.getAward(effect.referenceId).subject != decision.personId
            ) revert InvalidEffect();
            _compensation.restore(effect.referenceId, effect.amount);
        } else {
            revert InvalidEffect();
        }
        _emitDecision(decision, approvals.publicReasonURI);
    }

    function _validate(JusticeTypes.Decision calldata decision, bytes32 effectHash, string calldata publicReasonURI)
        private
        view
        returns (bytes32)
    {
        if (_kernel.bootstrapAuthority() != address(0) || !isCurrent()) revert InactiveJustice();
        if (
            decision.personId == bytes32(0) || decision.decisionId == bytes32(0) || decision.reasonHash == bytes32(0)
                || decision.recordHash == bytes32(0) || decision.effectHash != effectHash
                || bytes(publicReasonURI).length == 0 || bytes(publicReasonURI).length > 256
                || decision.reasonHash != keccak256(bytes(publicReasonURI)) || decision.deadline <= block.timestamp
                || decision.deadline > _termEndsAt
                || decision.stateRevision != decisionStateRevision(decision.action, decision.personId)
        ) revert InvalidDecision();
        return decisionDigest(decision);
    }

    function _verifyCouncilPanel(
        JusticeTypes.Decision calldata decision,
        bytes32 digest,
        JusticeTypes.Approvals calldata approvals
    ) private view {
        _verifyBody(JusticeTypes.Body.Council, decision, digest, approvals.first);
        _verifyBody(JusticeTypes.Body.Panel, decision, digest, approvals.second);
    }

    function _verifyBody(
        JusticeTypes.Body body,
        JusticeTypes.Decision calldata decision,
        bytes32 digest,
        JusticeTypes.Signature[] calldata signatures
    ) private view {
        uint256 size = _bodySizes[uint8(body)];
        uint256 required = size / 2 + 1;
        if (signatures.length < required || signatures.length > size) revert InsufficientApproval(body, required);
        bytes32 previous;
        for (uint256 i; i < signatures.length; ++i) {
            bytes32 member = signatures[i].personId;
            if (
                member <= previous || member == decision.personId || !_belongs(body, member)
                    || (decision.action == JusticeTypes.Action.Annul
                        && _decisions.admittedBy(decision.personId, member))
            ) revert InvalidApproval(member);
            _checkSignature(member, _eligibleWallet(member), digest, signatures[i].signature);
            previous = member;
        }
    }

    function _verifyAdmissionOfficers(
        JusticeTypes.Decision calldata decision,
        JusticeTypes.IdentityEffect calldata effect,
        bytes32 digest,
        JusticeTypes.Approvals calldata approvals
    ) private view {
        IPresidentRegistry president = IPresidentRegistry(_kernel.getModule(KernelModuleIds.PRESIDENT_REGISTRY));
        IExecutiveRegistry executive = IExecutiveRegistry(_kernel.getModule(KernelModuleIds.EXECUTIVE_REGISTRY));
        bytes32 presidentId = president.currentPresidentPersonId();
        ExecutiveTypes.MinisterRecord memory minister = executive.getMinister(ExecutiveTypes.MinistryKind.Interior);
        bytes32 ministerId = minister.personId;
        if (
            !president.isPresidentInTerm() || !executive.isMinisterInTerm(ExecutiveTypes.MinistryKind.Interior)
                || president.presidencyNonce() != effect.presidencyNonce
                || keccak256(abi.encode(minister)) != effect.ministerMandateHash || presidentId == ministerId
                || presidentId == decision.personId || ministerId == decision.personId
                || _belongs(JusticeTypes.Body.Admission, presidentId)
                || _belongs(JusticeTypes.Body.Admission, ministerId)
        ) revert InvalidApproval(ministerId);
        _checkSignature(ministerId, _eligibleWallet(ministerId), digest, approvals.minister);
        _checkSignature(presidentId, _eligibleWallet(presidentId), digest, approvals.president);
    }

    function _eligibleWallet(bytes32 personId) private view returns (address wallet) {
        (
            IdentityTypes.VerificationStatus verification,
            IdentityTypes.CitizenshipStatus status,
            IdentityTypes.AgeClass age,
            bool suspended
        ) = _identity.getCitizenshipSummary(personId);
        if (
            verification != IdentityTypes.VerificationStatus.Verified
                || status != IdentityTypes.CitizenshipStatus.Citizen || age != IdentityTypes.AgeClass.Adult || suspended
                || _membership.membershipRemoved(personId)
                || _membership.isRestrictedNow(personId, MembershipTypes.Right.Appointive)
        ) revert InvalidApproval(personId);
        return _identity.activeWalletOf(personId);
    }

    function _checkSignature(bytes32 personId, address wallet, bytes32 digest, bytes calldata signature) private view {
        if (
            wallet == address(0) || signature.length == 0 || signature.length > _MAX_SIGNATURE_LENGTH
                || !SignatureChecker.isValidSignatureNow(wallet, digest, signature)
        ) revert InvalidApproval(personId);
    }

    function _belongs(JusticeTypes.Body body, bytes32 personId) private view returns (bool) {
        return (_bodyMask[personId] & (uint8(1) << uint8(body))) != 0;
    }

    function _waitForNotice(uint64 noticeAt, uint256 delay) private view {
        uint256 earliest = uint256(noticeAt) + delay;
        if (noticeAt == 0 || block.timestamp < earliest) revert NoticePending(earliest);
    }

    function _emptyAdmissionFields(JusticeTypes.IdentityEffect calldata effect) private pure returns (bool) {
        return effect.ageClass == IdentityTypes.AgeClass.Undefined
            && effect.route == JusticeTypes.AdmissionRoute.Regular && effect.presidencyNonce == 0
            && effect.ministerMandateHash == bytes32(0);
    }

    function _requireUnprotected(bytes32 personId) private view {
        IPresidentRegistry president = IPresidentRegistry(_kernel.getModule(KernelModuleIds.PRESIDENT_REGISTRY));
        ISenateSeatRegistry senate = ISenateSeatRegistry(_kernel.getModule(KernelModuleIds.SENATE_SEAT_REGISTRY));
        ICongressCandidateRegistry congress =
            ICongressCandidateRegistry(_kernel.getModule(KernelModuleIds.CONGRESS_CANDIDATE_REGISTRY));
        IExecutiveRegistry executive = IExecutiveRegistry(_kernel.getModule(KernelModuleIds.EXECUTIVE_REGISTRY));
        if (
            (president.isPresidentInTerm()
                    && (president.currentPresidentPersonId() == personId
                        || president.vicePresidentPersonId(0) == personId
                        || president.vicePresidentPersonId(1) == personId)) || senate.isActiveSeatHolderPerson(personId)
                || congress.isActiveCongressMember(_identity.activeWalletOf(personId))
                || (executive.isPrimeMinisterInTerm() && executive.getPrimeMinister().personId == personId)
        ) revert ProtectedOffice(personId);
        for (uint8 i = 1; i <= uint8(ExecutiveTypes.MinistryKind.Justice); ++i) {
            ExecutiveTypes.MinistryKind ministry = ExecutiveTypes.MinistryKind(i);
            if (executive.isMinisterInTerm(ministry) && executive.getMinister(ministry).personId == personId) {
                revert ProtectedOffice(personId);
            }
        }
    }

    function _emitDecision(JusticeTypes.Decision calldata decision, string calldata publicReasonURI) private {
        emit JusticeDecisionExecuted(
            decision.decisionId,
            decision.personId,
            decision.action,
            decision.reasonHash,
            decision.recordHash,
            publicReasonURI
        );
    }
}
