// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

import {DecisionThresholds} from "../../contracts/libraries/DecisionThresholds.sol";
import {DeterminationHash} from "../../contracts/libraries/DeterminationHash.sol";
import {ReceiptConsumption} from "../../contracts/libraries/ReceiptConsumption.sol";

/// @dev Test-only wrapper: arithmetic supplies no political authority or denominator choice.
contract DecisionMathHarness {
    /// @notice Exposes strict-majority arithmetic for boundary tests.
    function majority(uint256 support, uint256 total) external pure returns (bool) {
        return DecisionThresholds.hasStrictMajority(support, total);
    }

    /// @notice Exposes two-thirds arithmetic for boundary tests.
    function twoThirds(uint256 support, uint256 total) external pure returns (bool) {
        return DecisionThresholds.hasTwoThirds(support, total);
    }
}

/// @dev Test-only storage wrapper, deliberately without approval logic to demonstrate the library's limited scope.
contract ConsumptionStorageHarness {
    using ReceiptConsumption for ReceiptConsumption.State;

    ReceiptConsumption.State private _receipts;

    /// @notice Exposes mechanical consumption; this harness has no legal effects or deployed authority.
    function consume(bytes32 digest) external {
        _receipts.consume(digest);
    }

    /// @notice Reads test consumption storage.
    function consumed(bytes32 digest) external view returns (bool) {
        return _receipts.isConsumed(digest);
    }
}

/// @dev Synthetic issuer for testing composition, not a proposed legal body or production approval contract.
contract DeterminationIssuerHarness is EIP712 {
    using ReceiptConsumption for ReceiptConsumption.State;

    error UnauthorizedApproval();
    error InvalidIssuer();
    error UnauthorizedWriter();
    error UnknownApproval(bytes32 digest);
    error ApprovalAlreadyExists();
    error NotEffective();
    error NotFinal();
    error Stayed();

    struct Approval {
        bool exists;
        bool requiresFinal;
        bool stayed;
        uint64 effectiveAt;
        uint64 finalAt;
    }

    address private immutable _testAuthority;
    mapping(bytes32 digest => Approval approval) private _approvals;
    ReceiptConsumption.State private _receipts;

    constructor(address testAuthority) EIP712("DecisionPrimitiveTest", "1") {
        _testAuthority = testAuthority;
    }

    /// @notice Composes the struct commitment with OpenZeppelin's chain- and issuer-bound EIP-712 domain.
    function digest(DeterminationHash.Context memory context) public view returns (bytes32) {
        return _hashTypedDataV4(DeterminationHash.hashStruct(context));
    }

    /// @notice Records synthetic approval from the test authority; hashing a context alone never calls this method.
    function recordApproval(
        DeterminationHash.Context calldata context,
        uint64 effectiveAt,
        uint64 finalAt,
        bool requiresFinal
    ) external {
        if (msg.sender != _testAuthority) revert UnauthorizedApproval();
        if (context.issuer != address(this)) revert InvalidIssuer();
        if (context.writer == address(0)) revert UnauthorizedWriter();
        bytes32 receipt = digest(context);
        if (_approvals[receipt].exists) revert ApprovalAlreadyExists();
        _approvals[receipt] = Approval(true, requiresFinal, false, effectiveAt, finalAt);
    }

    /// @notice Applies a synthetic stay to an existing test approval.
    function setStay(bytes32 receipt, bool stayed) external {
        if (msg.sender != _testAuthority) revert UnauthorizedApproval();
        if (!_approvals[receipt].exists) revert UnknownApproval(receipt);
        _approvals[receipt].stayed = stayed;
    }

    /// @notice Consumes only an approved, executable test effect requested by its committed writer.
    function consume(DeterminationHash.Context calldata context) external returns (bytes32 receipt) {
        if (context.issuer != address(this)) revert InvalidIssuer();
        if (msg.sender != context.writer) revert UnauthorizedWriter();
        receipt = digest(context);
        Approval memory approval = _approvals[receipt];
        if (!approval.exists) revert UnknownApproval(receipt);
        if (approval.stayed) revert Stayed();
        if (approval.effectiveAt == 0 || block.timestamp < approval.effectiveAt) revert NotEffective();
        if (approval.requiresFinal && (approval.finalAt == 0 || block.timestamp < approval.finalAt)) {
            revert NotFinal();
        }
        _receipts.consume(receipt);
    }

    /// @notice Reads canonical synthetic issuer consumption state.
    function consumed(bytes32 receipt) external view returns (bool) {
        return _receipts.isConsumed(receipt);
    }
}

/// @dev Synthetic exact-effect writer: it can update one bytes32 test value, never arbitrary targets or calldata.
contract DeterminationWriterHarness {
    error WrongWriter();
    error StaleRelevantState();
    error DownstreamFailure();

    DeterminationIssuerHarness private immutable _issuer;
    bytes32 private _scopedState;
    bytes32 private _unrelatedMetadata;

    constructor(DeterminationIssuerHarness issuer, bytes32 initialScopedState) {
        _issuer = issuer;
        _scopedState = initialScopedState;
    }

    /// @notice Executes a synthetic approved effect; any downstream failure reverts issuer consumption too.
    function applyEffect(DeterminationHash.Context calldata context, bool downstreamFailure) external {
        if (context.writer != address(this)) revert WrongWriter();
        _issuer.consume(context);
        if (context.expectedStateHash != _scopedState) revert StaleRelevantState();
        if (downstreamFailure) revert DownstreamFailure();
        _scopedState = context.effectHash;
    }

    /// @notice Changes unrelated synthetic metadata, which is deliberately outside the effect's relevant scope.
    function setUnrelatedMetadata(bytes32 metadata) external {
        _unrelatedMetadata = metadata;
    }

    /// @notice Reads the synthetic relevant state.
    function scopedState() external view returns (bytes32) {
        return _scopedState;
    }

    /// @notice Reads unrelated synthetic metadata.
    function unrelatedMetadata() external view returns (bytes32) {
        return _unrelatedMetadata;
    }
}

/// @notice Verifies unwired arithmetic, context commitments and mechanical receipt-consumption composition.
contract DecisionPrimitivesTest is Test {
    DecisionMathHarness private _math;
    DeterminationIssuerHarness private _issuer;
    DeterminationWriterHarness private _writer;

    bytes32 private constant INITIAL_STATE = keccak256("test scoped state");
    bytes32 private constant NEXT_STATE = keccak256("test next scoped state");

    /// @notice Creates test-only components with no kernel registration or production write permissions.
    function setUp() public {
        vm.warp(100);
        _math = new DecisionMathHarness();
        _issuer = new DeterminationIssuerHarness(address(this));
        _writer = new DeterminationWriterHarness(_issuer, INITIAL_STATE);
    }

    /// @notice Empty denominators never pass either threshold.
    function testZeroDenominatorDoesNotPass() public view {
        assertFalse(_math.majority(0, 0));
        assertFalse(_math.twoThirds(0, 0));
    }

    /// @notice Impossible support counts revert rather than being interpreted as approval.
    function testInvalidTalliesRevert() public {
        vm.expectRevert(abi.encodeWithSelector(DecisionThresholds.InvalidTally.selector, 1, 0));
        _math.majority(1, 0);
        vm.expectRevert(abi.encodeWithSelector(DecisionThresholds.InvalidTally.selector, 8, 7));
        _math.twoThirds(8, 7);
    }

    /// @notice All small tallies match independent exact integer comparisons, including ties and rounding.
    function testSmallThresholdsExhaustively() public view {
        for (uint256 total = 1; total <= 32; ++total) {
            for (uint256 support; support <= total; ++support) {
                assertEq(_math.majority(support, total), support * 2 > total);
                assertEq(_math.twoThirds(support, total), support * 3 >= total * 2);
            }
        }
    }

    /// @notice Full-width denominators do not overflow while testing boundary support.
    function testThresholdsAtUint256Maximum() public view {
        uint256 total = type(uint256).max;
        uint256 twoThirds = (total / 3) * 2;
        assertFalse(_math.majority(total / 2, total));
        assertTrue(_math.majority(total / 2 + 1, total));
        assertFalse(_math.twoThirds(twoThirds - 1, total));
        assertTrue(_math.twoThirds(twoThirds, total));
        assertTrue(_math.majority(total, total));
        assertTrue(_math.twoThirds(total, total));
    }

    /// @notice Full-width valid tallies match an independently decomposed two-thirds reference.
    function testFuzzThresholdsMatchIntegerReference(uint256 support, uint256 total) public view {
        vm.assume(support <= total);
        uint256 remainder = total % 3;
        uint256 required = (total / 3) * 2 + (remainder * 2 + 2) / 3;
        assertEq(_math.twoThirds(support, total), total != 0 && support >= required);
        assertEq(_math.majority(support, total), support > total - support);
    }

    /// @notice Every invalid full-width tally fails both helpers without arithmetic overflow.
    function testFuzzInvalidTalliesRevert(uint256 support, uint256 total) public {
        vm.assume(support > total);
        vm.expectRevert(abi.encodeWithSelector(DecisionThresholds.InvalidTally.selector, support, total));
        _math.majority(support, total);
        vm.expectRevert(abi.encodeWithSelector(DecisionThresholds.InvalidTally.selector, support, total));
        _math.twoThirds(support, total);
    }

    /// @notice The static struct encoding agrees with independently assembled EIP-712 primitive field words.
    function testHashMatchesCanonicalStaticFieldEncoding() public view {
        DeterminationHash.Context memory context = _context();
        bytes32[14] memory words;
        words[0] = keccak256(
            "Determination(bytes32 matterId,bytes32 subjectCommitment,bytes32 rulesVersion,bytes32 decisionType,bytes32 effectHash,bytes32 expectedStateHash,address issuer,address writer,uint256 nonce,uint64 bodyEpoch,uint64 rosterRevision,uint32 revision,uint8 stage)"
        );
        words[1] = context.matterId;
        words[2] = context.subjectCommitment;
        words[3] = context.rulesVersion;
        words[4] = context.decisionType;
        words[5] = context.effectHash;
        words[6] = context.expectedStateHash;
        words[7] = bytes32(uint256(uint160(context.issuer)));
        words[8] = bytes32(uint256(uint160(context.writer)));
        words[9] = bytes32(context.nonce);
        words[10] = bytes32(uint256(context.bodyEpoch));
        words[11] = bytes32(uint256(context.rosterRevision));
        words[12] = bytes32(uint256(context.revision));
        words[13] = bytes32(uint256(context.stage));
        assertEq(DeterminationHash.hashStruct(context), keccak256(abi.encode(words)));
    }

    /// @notice Mutating any independently bound field changes the commitment.
    function testEveryContextFieldIsBound() public view {
        bytes32 original = DeterminationHash.hashStruct(_context());
        for (uint256 field; field < 13; ++field) {
            DeterminationHash.Context memory changed = _context();
            if (field == 0) changed.matterId = keccak256("other matter");
            else if (field == 1) changed.subjectCommitment = keccak256("other subject");
            else if (field == 2) changed.rulesVersion = keccak256("other rules");
            else if (field == 3) changed.decisionType = keccak256("OtherEffect(bytes32 value)");
            else if (field == 4) changed.effectHash = keccak256("other exact effect");
            else if (field == 5) changed.expectedStateHash = keccak256("other relevant state");
            else if (field == 6) changed.issuer = address(0x1234);
            else if (field == 7) changed.writer = address(0x5678);
            else if (field == 8) changed.nonce += 1;
            else if (field == 9) changed.bodyEpoch += 1;
            else if (field == 10) changed.rosterRevision += 1;
            else if (field == 11) changed.revision += 1;
            else changed.stage += 1;
            assertNotEq(DeterminationHash.hashStruct(changed), original);
        }
    }

    /// @notice Domain composition matches the existing OpenZeppelin EIP-712 convention.
    function testDigestUsesChainAndVerifyingContractDomain() public view {
        bytes32 separator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("DecisionPrimitiveTest"),
                keccak256("1"),
                block.chainid,
                address(_issuer)
            )
        );
        assertEq(
            _issuer.digest(_context()),
            MessageHashUtils.toTypedDataHash(separator, DeterminationHash.hashStruct(_context()))
        );
    }

    /// @notice The same context has distinct digests for different application domains and chains.
    function testDigestChangesAcrossApplicationsAndChains() public {
        DeterminationHash.Context memory context = _context();
        bytes32 original = _issuer.digest(context);
        DeterminationIssuerHarness other = new DeterminationIssuerHarness(address(this));
        assertNotEq(other.digest(context), original);
        uint256 originalChain = block.chainid;
        vm.chainId(originalChain + 1);
        assertNotEq(_issuer.digest(context), original);
        vm.chainId(originalChain);
        assertEq(_issuer.digest(context), original);
    }

    /// @notice A digest alone supplies no approval, signature or legal authority.
    function testUnsignedUnapprovedDigestCannotExecute() public {
        DeterminationHash.Context memory context = _context();
        bytes32 receipt = _issuer.digest(context);
        vm.expectRevert(abi.encodeWithSelector(DeterminationIssuerHarness.UnknownApproval.selector, receipt));
        _writer.applyEffect(context, false);
        assertFalse(_issuer.consumed(receipt));
        assertEq(_writer.scopedState(), INITIAL_STATE);
    }

    /// @notice The harness separately authenticates approval and consumption callers before using storage helpers.
    function testUnauthorizedApprovalAndWriterFail() public {
        DeterminationHash.Context memory context = _context();
        vm.prank(address(0xBAD));
        vm.expectRevert(DeterminationIssuerHarness.UnauthorizedApproval.selector);
        _issuer.recordApproval(context, 100, 100, true);
        _approve(context, true, 100, 100);
        vm.expectRevert(DeterminationIssuerHarness.UnauthorizedWriter.selector);
        _issuer.consume(context);
        assertFalse(_issuer.consumed(_issuer.digest(context)));
    }

    /// @notice A successfully applied receipt cannot be consumed again, even if its original state is now stale.
    function testApprovedReceiptExecutesOnce() public {
        DeterminationHash.Context memory context = _context();
        _approve(context, true, 100, 100);
        bytes32 receipt = _issuer.digest(context);
        _writer.applyEffect(context, false);
        assertTrue(_issuer.consumed(receipt));
        assertEq(_writer.scopedState(), NEXT_STATE);
        vm.expectRevert(abi.encodeWithSelector(ReceiptConsumption.ReceiptAlreadyConsumed.selector, receipt));
        _writer.applyEffect(context, false);
    }

    /// @notice A downstream write failure atomically restores the issuer's unconsumed state for a safe retry.
    function testDownstreamFailureRollsBackConsumption() public {
        DeterminationHash.Context memory context = _context();
        _approve(context, true, 100, 100);
        bytes32 receipt = _issuer.digest(context);
        vm.expectRevert(DeterminationWriterHarness.DownstreamFailure.selector);
        _writer.applyEffect(context, true);
        assertFalse(_issuer.consumed(receipt));
        assertEq(_writer.scopedState(), INITIAL_STATE);
        _writer.applyEffect(context, false);
        assertTrue(_issuer.consumed(receipt));
    }

    /// @notice A stale relevant-state commitment cannot consume a receipt or change the writer's state.
    function testStaleRelevantStateRollsBackConsumption() public {
        DeterminationHash.Context memory context = _context();
        context.expectedStateHash = keccak256("stale relevant state");
        _approve(context, true, 100, 100);
        bytes32 receipt = _issuer.digest(context);
        vm.expectRevert(DeterminationWriterHarness.StaleRelevantState.selector);
        _writer.applyEffect(context, false);
        assertFalse(_issuer.consumed(receipt));
        assertEq(_writer.scopedState(), INITIAL_STATE);
    }

    /// @notice Unrelated metadata neither changes a narrowly scoped receipt nor prevents its approved effect.
    function testUnrelatedScopedStateDoesNotInvalidateReceipt() public {
        DeterminationHash.Context memory context = _context();
        _approve(context, true, 100, 100);
        bytes32 receipt = _issuer.digest(context);
        bytes32 metadata = keccak256("unrelated new metadata");
        _writer.setUnrelatedMetadata(metadata);
        assertEq(_issuer.digest(context), receipt);
        _writer.applyEffect(context, false);
        assertTrue(_issuer.consumed(receipt));
        assertEq(_writer.unrelatedMetadata(), metadata);
    }

    /// @notice Altered effects and case revisions cannot borrow an existing approval.
    function testEffectAndRevisionSubstitutionCannotUseApproval() public {
        DeterminationHash.Context memory context = _context();
        _approve(context, true, 100, 100);
        context.effectHash = keccak256("substituted effect");
        vm.expectRevert(
            abi.encodeWithSelector(DeterminationIssuerHarness.UnknownApproval.selector, _issuer.digest(context))
        );
        _writer.applyEffect(context, false);
        context = _context();
        context.revision += 1;
        vm.expectRevert(
            abi.encodeWithSelector(DeterminationIssuerHarness.UnknownApproval.selector, _issuer.digest(context))
        );
        _writer.applyEffect(context, false);
    }

    /// @notice An approval on one chain does not authorise consumption on another chain.
    function testCrossChainReplayCannotUseApproval() public {
        DeterminationHash.Context memory context = _context();
        _approve(context, true, 100, 100);
        uint256 originalChain = block.chainid;
        bytes32 receipt = _issuer.digest(context);
        vm.chainId(originalChain + 1);
        bytes32 otherReceipt = _issuer.digest(context);
        vm.expectRevert(abi.encodeWithSelector(DeterminationIssuerHarness.UnknownApproval.selector, otherReceipt));
        _writer.applyEffect(context, false);
        assertFalse(_issuer.consumed(receipt));
        vm.chainId(originalChain);
        _writer.applyEffect(context, false);
        assertTrue(_issuer.consumed(receipt));
    }

    /// @notice App replacement inherits neither approval nor consumption storage; continuity requires migration.
    function testNewIssuerDoesNotInheritApprovalsOrConsumedMarkers() public {
        DeterminationHash.Context memory original = _context();
        _approve(original, true, 100, 100);
        bytes32 originalReceipt = _issuer.digest(original);
        _writer.applyEffect(original, false);
        DeterminationIssuerHarness replacement = new DeterminationIssuerHarness(address(this));
        DeterminationWriterHarness nextWriter = new DeterminationWriterHarness(replacement, INITIAL_STATE);
        DeterminationHash.Context memory context = _context();
        context.issuer = address(replacement);
        context.writer = address(nextWriter);
        bytes32 replacementReceipt = replacement.digest(context);
        assertNotEq(originalReceipt, replacementReceipt);
        assertFalse(replacement.consumed(originalReceipt));
        vm.expectRevert(abi.encodeWithSelector(DeterminationIssuerHarness.UnknownApproval.selector, replacementReceipt));
        nextWriter.applyEffect(context, false);
        assertTrue(_issuer.consumed(originalReceipt));
    }

    /// @notice Effectiveness and finality are distinct; provisional effects need not wait for finality.
    function testInterimAndFinalEffectsHaveDistinctConditions() public {
        DeterminationHash.Context memory interim = _context();
        _approve(interim, false, 100, 200);
        _writer.applyEffect(interim, false);
        DeterminationHash.Context memory finalEffect = _context();
        finalEffect.nonce += 1;
        finalEffect.expectedStateHash = NEXT_STATE;
        finalEffect.effectHash = keccak256("final synthetic state");
        _approve(finalEffect, true, 100, 200);
        bytes32 receipt = _issuer.digest(finalEffect);
        vm.expectRevert(DeterminationIssuerHarness.NotFinal.selector);
        _writer.applyEffect(finalEffect, false);
        assertFalse(_issuer.consumed(receipt));
        vm.warp(200);
        _writer.applyEffect(finalEffect, false);
        assertTrue(_issuer.consumed(receipt));
    }

    /// @notice A missing finality timestamp cannot accidentally make a final-only effect executable.
    function testMissingFinalityDoesNotPassFinalGate() public {
        DeterminationHash.Context memory context = _context();
        _approve(context, true, 100, 0);
        vm.expectRevert(DeterminationIssuerHarness.NotFinal.selector);
        _writer.applyEffect(context, false);
        assertFalse(_issuer.consumed(_issuer.digest(context)));
    }

    /// @notice Not-yet-effective and stayed receipts remain unconsumed until their permitted conditions hold.
    function testEffectiveTimeAndStayGateConsumption() public {
        DeterminationHash.Context memory context = _context();
        _approve(context, false, 200, 300);
        bytes32 receipt = _issuer.digest(context);
        vm.expectRevert(DeterminationIssuerHarness.NotEffective.selector);
        _writer.applyEffect(context, false);
        vm.warp(200);
        _issuer.setStay(receipt, true);
        vm.expectRevert(DeterminationIssuerHarness.Stayed.selector);
        _writer.applyEffect(context, false);
        assertFalse(_issuer.consumed(receipt));
        _issuer.setStay(receipt, false);
        _writer.applyEffect(context, false);
        assertTrue(_issuer.consumed(receipt));
    }

    /// @notice Mechanical consumption rejects zero and replay, without claiming authorisation on its own.
    function testStoragePrimitiveRejectsZeroAndDuplicateDigest() public {
        ConsumptionStorageHarness storageHarness = new ConsumptionStorageHarness();
        vm.expectRevert(ReceiptConsumption.InvalidReceiptDigest.selector);
        storageHarness.consume(bytes32(0));
        assertFalse(storageHarness.consumed(bytes32(0)));
        bytes32 receipt = _issuer.digest(_context());
        storageHarness.consume(receipt);
        assertTrue(storageHarness.consumed(receipt));
        vm.expectRevert(abi.encodeWithSelector(ReceiptConsumption.ReceiptAlreadyConsumed.selector, receipt));
        storageHarness.consume(receipt);
        // The same unapproved digest is still unapproved in the distinct authenticated issuer workflow.
        vm.expectRevert(abi.encodeWithSelector(DeterminationIssuerHarness.UnknownApproval.selector, receipt));
        _writer.applyEffect(_context(), false);
    }

    function _approve(DeterminationHash.Context memory context, bool requiresFinal, uint64 effectiveAt, uint64 finalAt)
        private
    {
        _issuer.recordApproval(context, effectiveAt, finalAt, requiresFinal);
    }

    function _context() private view returns (DeterminationHash.Context memory) {
        return DeterminationHash.Context({
            matterId: keccak256("test matter"),
            subjectCommitment: keccak256("test subject"),
            rulesVersion: keccak256("test rules version"),
            decisionType: keccak256("SyntheticEffect(bytes32 newScopedState)"),
            effectHash: NEXT_STATE,
            expectedStateHash: INITIAL_STATE,
            issuer: address(_issuer),
            writer: address(_writer),
            nonce: 1,
            bodyEpoch: 2,
            rosterRevision: 3,
            revision: 4,
            stage: 5
        });
    }
}
