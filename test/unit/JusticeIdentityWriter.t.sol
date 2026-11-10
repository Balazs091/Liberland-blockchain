// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";

import {JusticeIdentityWriter} from "../../contracts/apps/JusticeIdentityWriter.sol";
import {ConstitutionKernel} from "../../contracts/core/ConstitutionKernel.sol";
import {IJusticeIdentityWriter} from "../../contracts/interfaces/IJusticeIdentityWriter.sol";
import {KernelModuleIds} from "../../contracts/libraries/KernelModuleIds.sol";
import {IdentityRegistry} from "../../contracts/registries/IdentityRegistry.sol";
import {StakeRegistry} from "../../contracts/registries/StakeRegistry.sol";
import {IdentityTypes} from "../../contracts/types/IdentityTypes.sol";

contract JusticeIssuerMarker {}

contract JusticeIdentityWriterTest is Test {
    bytes32 private constant _PERSON = keccak256("person");
    bytes32 private constant _OTHER_PERSON = keccak256("other-person");
    bytes32 private constant _EVIDENCE = keccak256("identity evidence");
    bytes32 private constant _METADATA = keccak256("existing metadata");
    address private constant _OLD = address(0xA11CE);
    address private constant _DESTINATION = address(0xB0B);
    address private constant _OTHER = address(0xCACE);

    ConstitutionKernel private _kernel;
    IdentityRegistry private _identity;
    JusticeIdentityWriter private _writer;
    address private _justiceApp;

    function setUp() public {
        vm.warp(1_000_000);
        _kernel = new ConstitutionKernel(address(this));
        _identity = new IdentityRegistry(address(_kernel));
        _writer = new JusticeIdentityWriter(address(_identity));
        _justiceApp = address(new JusticeIssuerMarker());
        _kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_REGISTRY, address(_identity));
        _kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_REGISTRY_AUTHORITY, address(_writer));
        _kernel.bootstrapSetModule(KernelModuleIds.JUSTICE_APP, _justiceApp);
        _kernel.bootstrapSetModule(KernelModuleIds.INITIAL_SETUP_AUTHORITY, address(this));
    }

    function testTypedEffectsRequireExactCurrentJusticeAppEvenDuringBootstrap() public {
        _kernel.bootstrapSetModule(KernelModuleIds.OFFICE_EXECUTOR, address(this));
        vm.expectRevert(abi.encodeWithSelector(IJusticeIdentityWriter.UnauthorizedJusticeApp.selector, address(this)));
        _writer.executeAdmission(_PERSON, _OLD, _EVIDENCE, IdentityTypes.AgeClass.Adult);

        address successor = address(new JusticeIssuerMarker());
        _kernel.bootstrapSetModule(KernelModuleIds.JUSTICE_APP, successor);
        vm.expectRevert(abi.encodeWithSelector(IJusticeIdentityWriter.UnauthorizedJusticeApp.selector, _justiceApp));
        vm.prank(_justiceApp);
        _writer.executeAnnulment(_PERSON);

        vm.prank(successor);
        _writer.executeAdmission(_PERSON, _OLD, _EVIDENCE, IdentityTypes.AgeClass.Adult);
        assertEq(_identity.activeWalletOf(_PERSON), _OLD);
    }

    function testRetiredWriterAndNoncanonicalIdentityCannotMutate() public {
        _seed(_PERSON, _OLD, IdentityTypes.CitizenshipStatus.Citizen, false);
        _kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_REGISTRY_AUTHORITY, address(this));
        // The registry's setup route would accept this writer during bootstrap. The writer must still reject.
        _kernel.bootstrapSetModule(KernelModuleIds.INITIAL_SETUP_AUTHORITY, address(_writer));
        vm.expectRevert(
            abi.encodeWithSelector(IJusticeIdentityWriter.IdentityWriterNotCurrent.selector, address(_writer))
        );
        vm.prank(_justiceApp);
        _writer.executeAnnulment(_PERSON);

        _kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_REGISTRY_AUTHORITY, address(_writer));
        IdentityRegistry successor = new IdentityRegistry(address(_kernel));
        _kernel.bootstrapSetModule(KernelModuleIds.IDENTITY_REGISTRY, address(successor));
        vm.expectRevert(
            abi.encodeWithSelector(IJusticeIdentityWriter.IdentityRegistryNotCurrent.selector, address(_identity))
        );
        vm.prank(_OLD);
        _writer.renounceCitizenship();
        assertEq(
            uint8(_identity.getIdentityRecord(_PERSON).citizenshipStatus),
            uint8(IdentityTypes.CitizenshipStatus.Citizen)
        );
    }

    function testFreshAdmissionCreatesVerifiedPersonAndOneActiveWallet() public {
        _admit(_PERSON, _OLD);
        IdentityTypes.IdentityRecord memory record = _identity.getIdentityRecord(_PERSON);
        assertEq(record.metadataHash, _EVIDENCE);
        assertEq(uint8(record.citizenshipStatus), uint8(IdentityTypes.CitizenshipStatus.Citizen));
        assertEq(uint8(record.verificationStatus), uint8(IdentityTypes.VerificationStatus.Verified));
        assertEq(uint8(record.ageClass), uint8(IdentityTypes.AgeClass.Adult));
        assertEq(_identity.activeWalletOf(_PERSON), _OLD);
        assertEq(_identity.activeWalletCountOf(_PERSON), 1);
        assertEq(_identity.electorateRevisionOf(_PERSON), 2);

        vm.expectRevert(abi.encodeWithSelector(IJusticeIdentityWriter.IdentityCannotBeAdmitted.selector, _PERSON));
        _admit(_PERSON, _OLD);
        assertEq(_identity.electorateRevisionOf(_PERSON), 2);
    }

    function testExistingApplicantKeepsActiveWalletAndUnrelatedFacts() public {
        _seed(_PERSON, _OLD, IdentityTypes.CitizenshipStatus.EResident, false);
        vm.expectRevert(
            abi.encodeWithSelector(IJusticeIdentityWriter.ActiveWalletChanged.selector, _PERSON, _DESTINATION, _OLD)
        );
        _admit(_PERSON, _DESTINATION);

        _admit(_PERSON, _OLD);
        IdentityTypes.IdentityRecord memory record = _identity.getIdentityRecord(_PERSON);
        assertEq(uint8(record.citizenshipStatus), uint8(IdentityTypes.CitizenshipStatus.Citizen));
        assertEq(uint8(record.verificationStatus), uint8(IdentityTypes.VerificationStatus.Verified));
        assertEq(uint8(record.ageClass), uint8(IdentityTypes.AgeClass.Adult));
        assertEq(record.metadataHash, _METADATA);
        assertEq(record.metadataURI, "ipfs://existing");
        assertTrue(record.correctionFlag);
        assertEq(_identity.activeWalletOf(_PERSON), _OLD);
        assertEq(_identity.electorateRevisionOf(_PERSON), 3);
    }

    function testVacantApplicantCannotTakeLinkedWallet() public {
        _seed(_PERSON, address(0), IdentityTypes.CitizenshipStatus.None, false);
        _seed(_OTHER_PERSON, _OLD, IdentityTypes.CitizenshipStatus.EResident, false);
        vm.expectRevert(abi.encodeWithSelector(IJusticeIdentityWriter.DestinationWalletAlreadyLinked.selector, _OLD));
        _admit(_PERSON, _OLD);
        assertEq(
            uint8(_identity.getIdentityRecord(_PERSON).citizenshipStatus), uint8(IdentityTypes.CitizenshipStatus.None)
        );

        _admit(_PERSON, _DESTINATION);
        assertEq(_identity.activeWalletOf(_PERSON), _DESTINATION);
        assertEq(_identity.activeWalletOf(_OTHER_PERSON), _OLD);
        assertEq(_identity.getIdentityRecord(_PERSON).metadataHash, _METADATA);
    }

    function testRevocationSuspensionAndFinalSuspensionBlockOrdinaryAdmission() public {
        _seed(_PERSON, _OLD, IdentityTypes.CitizenshipStatus.Revoked, false);
        _seed(_OTHER_PERSON, _OTHER, IdentityTypes.CitizenshipStatus.Suspended, false);
        bytes32 finalSuspension = keccak256("final suspension");
        _seed(finalSuspension, address(0), IdentityTypes.CitizenshipStatus.None, true);
        vm.expectRevert(abi.encodeWithSelector(IJusticeIdentityWriter.IdentityCannotBeAdmitted.selector, _PERSON));
        _admit(_PERSON, _OLD);
        vm.expectRevert(abi.encodeWithSelector(IJusticeIdentityWriter.IdentityCannotBeAdmitted.selector, _OTHER_PERSON));
        _admit(_OTHER_PERSON, _OTHER);
        vm.expectRevert(
            abi.encodeWithSelector(IJusticeIdentityWriter.IdentityCannotBeAdmitted.selector, finalSuspension)
        );
        _admit(finalSuspension, _DESTINATION);
    }

    function testAnnulmentPreservesVerificationMetadataWalletAndStake() public {
        _seed(_PERSON, _OLD, IdentityTypes.CitizenshipStatus.Citizen, true);
        StakeRegistry stake = _withStake(_PERSON);
        vm.prank(_justiceApp);
        _writer.executeAnnulment(_PERSON);

        IdentityTypes.IdentityRecord memory record = _identity.getIdentityRecord(_PERSON);
        assertEq(uint8(record.citizenshipStatus), uint8(IdentityTypes.CitizenshipStatus.Revoked));
        assertEq(uint8(record.verificationStatus), uint8(IdentityTypes.VerificationStatus.Pending));
        assertEq(uint8(record.ageClass), uint8(IdentityTypes.AgeClass.Minor));
        assertEq(record.metadataHash, _METADATA);
        assertEq(record.metadataURI, "ipfs://existing");
        assertTrue(record.correctionFlag);
        assertTrue(record.finalSuspension);
        assertEq(_identity.activeWalletOf(_PERSON), _OLD);
        assertEq(stake.activeStakeOf(_PERSON), 9000 ether);

        vm.expectRevert(abi.encodeWithSelector(IJusticeIdentityWriter.IdentityNotCitizen.selector, _PERSON));
        vm.prank(_justiceApp);
        _writer.executeAnnulment(_PERSON);
    }

    function testCitizenshipRestorationRequiresRevokedStatusAndPreservesAllOtherFacts() public {
        _seed(_PERSON, _OLD, IdentityTypes.CitizenshipStatus.Citizen, true);
        vm.prank(_justiceApp);
        vm.expectRevert(abi.encodeWithSelector(IJusticeIdentityWriter.IdentityNotRevoked.selector, _PERSON));
        _writer.executeCitizenshipRestoration(_PERSON);
        vm.prank(_justiceApp);
        _writer.executeAnnulment(_PERSON);
        StakeRegistry stake = _withStake(_PERSON);
        uint256 revision = _identity.electorateRevisionOf(_PERSON);
        vm.expectRevert(abi.encodeWithSelector(IJusticeIdentityWriter.UnauthorizedJusticeApp.selector, address(this)));
        _writer.executeCitizenshipRestoration(_PERSON);
        vm.prank(_justiceApp);
        _writer.executeCitizenshipRestoration(_PERSON);
        IdentityTypes.IdentityRecord memory record = _identity.getIdentityRecord(_PERSON);
        assertEq(uint8(record.citizenshipStatus), uint8(IdentityTypes.CitizenshipStatus.Citizen));
        assertEq(uint8(record.verificationStatus), uint8(IdentityTypes.VerificationStatus.Pending));
        assertEq(uint8(record.ageClass), uint8(IdentityTypes.AgeClass.Minor));
        assertEq(record.metadataHash, _METADATA);
        assertEq(record.metadataURI, "ipfs://existing");
        assertTrue(record.correctionFlag);
        assertTrue(record.finalSuspension);
        assertEq(_identity.activeWalletOf(_PERSON), _OLD);
        assertEq(_identity.electorateRevisionOf(_PERSON), revision + 1);
        assertEq(stake.activeStakeOf(_PERSON), 9000 ether);
        vm.prank(_justiceApp);
        vm.expectRevert(abi.encodeWithSelector(IJusticeIdentityWriter.IdentityNotRevoked.selector, _PERSON));
        _writer.executeCitizenshipRestoration(_PERSON);
    }

    function testRenunciationRequiresActiveCitizenAndAllowsFreshApprovedReadmission() public {
        _seed(_PERSON, _OLD, IdentityTypes.CitizenshipStatus.Citizen, false);
        vm.expectRevert(abi.encodeWithSelector(IJusticeIdentityWriter.InactiveWallet.selector, _OTHER));
        vm.prank(_OTHER);
        _writer.renounceCitizenship();

        vm.prank(_OLD);
        _writer.renounceCitizenship();
        assertEq(
            uint8(_identity.getIdentityRecord(_PERSON).citizenshipStatus), uint8(IdentityTypes.CitizenshipStatus.None)
        );
        assertEq(_identity.activeWalletOf(_PERSON), _OLD);
        assertEq(_identity.getIdentityRecord(_PERSON).metadataHash, _METADATA);
        vm.expectRevert(abi.encodeWithSelector(IJusticeIdentityWriter.IdentityNotCitizen.selector, _PERSON));
        vm.prank(_OLD);
        _writer.renounceCitizenship();

        _admit(_PERSON, _OLD);
        assertEq(
            uint8(_identity.getIdentityRecord(_PERSON).citizenshipStatus),
            uint8(IdentityTypes.CitizenshipStatus.Citizen)
        );
    }

    function testAdulthoodOnlyChangesVerifiedMinorAgeAndPreservesCitizenOrEResidentFacts() public {
        for (uint256 i; i < 2; ++i) {
            bytes32 personId = i == 0 ? _PERSON : _OTHER_PERSON;
            address wallet = i == 0 ? _OLD : _OTHER;
            IdentityTypes.CitizenshipStatus status =
                i == 0 ? IdentityTypes.CitizenshipStatus.Citizen : IdentityTypes.CitizenshipStatus.EResident;
            _seed(personId, wallet, status, true);
            vm.prank(_justiceApp);
            vm.expectRevert(
                abi.encodeWithSelector(IJusticeIdentityWriter.IdentityCannotRecognizeAdulthood.selector, personId)
            );
            _writer.executeAdulthood(personId);
            _identity.setIdentityRecord(
                personId,
                IdentityTypes.IdentityRecordInput({
                    metadataHash: _METADATA,
                    metadataURI: "ipfs://existing",
                    verificationStatus: IdentityTypes.VerificationStatus.Verified,
                    citizenshipStatus: status,
                    ageClass: IdentityTypes.AgeClass.Minor,
                    correctionFlag: true,
                    finalSuspension: true
                })
            );
            uint256 revision = _identity.electorateRevisionOf(personId);
            vm.expectRevert(
                abi.encodeWithSelector(IJusticeIdentityWriter.UnauthorizedJusticeApp.selector, address(this))
            );
            _writer.executeAdulthood(personId);
            vm.prank(_justiceApp);
            _writer.executeAdulthood(personId);
            IdentityTypes.IdentityRecord memory record = _identity.getIdentityRecord(personId);
            assertEq(uint8(record.ageClass), uint8(IdentityTypes.AgeClass.Adult));
            assertEq(uint8(record.citizenshipStatus), uint8(status));
            assertEq(uint8(record.verificationStatus), uint8(IdentityTypes.VerificationStatus.Verified));
            assertEq(record.metadataHash, _METADATA);
            assertEq(record.metadataURI, "ipfs://existing");
            assertTrue(record.correctionFlag);
            assertTrue(record.finalSuspension);
            assertEq(_identity.activeWalletOf(personId), wallet);
            assertEq(_identity.electorateRevisionOf(personId), revision + 1);
            vm.prank(_justiceApp);
            vm.expectRevert(
                abi.encodeWithSelector(IJusticeIdentityWriter.IdentityCannotRecognizeAdulthood.selector, personId)
            );
            _writer.executeAdulthood(personId);
        }
    }

    function testVoluntaryMigrationRequiresExactConsentAndOldLinkMayCancel() public {
        _admit(_PERSON, _OLD);
        StakeRegistry stake = _withStake(_PERSON);
        uint64 expiresAt = uint64(block.timestamp + 1 days);
        bytes32 first = _request(_OLD, _DESTINATION, expiresAt);
        vm.expectRevert(
            abi.encodeWithSelector(IJusticeIdentityWriter.WalletMigrationDestinationOnly.selector, _OTHER, _DESTINATION)
        );
        vm.prank(_OTHER);
        _writer.acceptWalletMigration(_PERSON, first);
        vm.expectRevert(
            abi.encodeWithSelector(IJusticeIdentityWriter.WalletMigrationSourceOnly.selector, _DESTINATION, _OLD)
        );
        vm.prank(_DESTINATION);
        _writer.cancelWalletMigration(_PERSON, first);
        vm.prank(_OLD);
        _writer.cancelWalletMigration(_PERSON, first);

        bytes32 second = _request(_OLD, _DESTINATION, expiresAt);
        assertNotEq(first, second);
        vm.expectRevert(
            abi.encodeWithSelector(IJusticeIdentityWriter.InvalidWalletMigrationRequest.selector, _PERSON, first)
        );
        vm.prank(_DESTINATION);
        _writer.acceptWalletMigration(_PERSON, first);
        vm.prank(_DESTINATION);
        _writer.acceptWalletMigration(_PERSON, second);
        assertEq(_identity.activeWalletOf(_PERSON), _DESTINATION);
        assertEq(_identity.activeWalletCountOf(_PERSON), 1);
        assertEq(uint8(_identity.getWalletLink(_OLD).status), uint8(IdentityTypes.WalletLinkStatus.Revoked));
        assertEq(stake.activeStakeOf(_PERSON), 9000 ether);
        (, bytes32 activeRequest) = _writer.getWalletMigration(_PERSON);
        assertEq(activeRequest, bytes32(0));

        vm.expectRevert(abi.encodeWithSelector(IJusticeIdentityWriter.InactiveWallet.selector, _OLD));
        vm.prank(_OLD);
        _writer.renounceCitizenship();
    }

    function testVoluntaryMigrationRejectsExpiryAndConcurrentDestinationLink() public {
        _admit(_PERSON, _OLD);
        uint64 expiresAt = uint64(block.timestamp + 1 days);
        bytes32 first = _request(_OLD, _DESTINATION, expiresAt);
        vm.warp(expiresAt);
        vm.expectRevert(abi.encodeWithSelector(IJusticeIdentityWriter.WalletMigrationExpired.selector, expiresAt));
        vm.prank(_DESTINATION);
        _writer.acceptWalletMigration(_PERSON, first);

        bytes32 second = _request(_OLD, _DESTINATION, expiresAt + 1 days);
        _admit(_OTHER_PERSON, _DESTINATION);
        vm.expectRevert(
            abi.encodeWithSelector(IJusticeIdentityWriter.DestinationWalletAlreadyLinked.selector, _DESTINATION)
        );
        vm.prank(_DESTINATION);
        _writer.acceptWalletMigration(_PERSON, second);
        assertEq(_identity.activeWalletOf(_PERSON), _OLD);
        assertEq(_identity.activeWalletOf(_OTHER_PERSON), _DESTINATION);
    }

    function testExceptionalRecoveryRequiresExpectedActiveLinkAndClearsVoluntaryRequest() public {
        _admit(_PERSON, _OLD);
        bytes32 pending = _request(_OLD, _OTHER, uint64(block.timestamp + 1 days));
        vm.expectRevert(
            abi.encodeWithSelector(IJusticeIdentityWriter.ActiveWalletChanged.selector, _PERSON, address(0), _OLD)
        );
        vm.prank(_justiceApp);
        _writer.executeRecovery(_PERSON, address(0), _DESTINATION);
        vm.expectRevert(
            abi.encodeWithSelector(IJusticeIdentityWriter.ActiveWalletChanged.selector, _PERSON, _OTHER, _OLD)
        );
        vm.prank(_justiceApp);
        _writer.executeRecovery(_PERSON, _OTHER, _DESTINATION);

        vm.prank(_justiceApp);
        _writer.executeRecovery(_PERSON, _OLD, _DESTINATION);
        assertEq(_identity.activeWalletOf(_PERSON), _DESTINATION);
        assertEq(_identity.electorateRevisionOf(_PERSON), 4);
        vm.expectRevert(
            abi.encodeWithSelector(IJusticeIdentityWriter.InvalidWalletMigrationRequest.selector, _PERSON, pending)
        );
        vm.prank(_OTHER);
        _writer.acceptWalletMigration(_PERSON, pending);
    }

    function _admit(bytes32 personId, address wallet) private {
        vm.prank(_justiceApp);
        _writer.executeAdmission(personId, wallet, _EVIDENCE, IdentityTypes.AgeClass.Adult);
    }

    function _request(address caller, address destination, uint64 expiresAt) private returns (bytes32) {
        vm.prank(caller);
        return _writer.requestWalletMigration(destination, expiresAt);
    }

    function _seed(bytes32 personId, address wallet, IdentityTypes.CitizenshipStatus status, bool finalSuspension)
        private
    {
        _identity.setIdentityRecord(
            personId,
            IdentityTypes.IdentityRecordInput({
                metadataHash: _METADATA,
                metadataURI: "ipfs://existing",
                verificationStatus: IdentityTypes.VerificationStatus.Pending,
                citizenshipStatus: status,
                ageClass: IdentityTypes.AgeClass.Minor,
                correctionFlag: true,
                finalSuspension: finalSuspension
            })
        );
        if (wallet != address(0)) _identity.setWalletLink(personId, wallet, IdentityTypes.WalletLinkStatus.Active);
    }

    function _withStake(bytes32 personId) private returns (StakeRegistry stake) {
        stake = new StakeRegistry(address(_kernel));
        _kernel.bootstrapSetModule(KernelModuleIds.LLM_STAKING_VAULT, address(this));
        stake.increaseStake(personId, 9000 ether);
    }
}
