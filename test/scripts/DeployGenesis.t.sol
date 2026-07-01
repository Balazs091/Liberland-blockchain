// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";

import {Deploy} from "../../scripts/Deploy.s.sol";
import {IConstitutionKernel} from "../../contracts/interfaces/IConstitutionKernel.sol";
import {IdentityTypes} from "../../contracts/types/IdentityTypes.sol";
import {OfficeTypes} from "../../contracts/types/OfficeTypes.sol";

contract DeployGenesisHarness is Deploy {
    function deployForTest() external {
        address deployer = address(this);

        _financeOfficeAdmin = address(0xF1A0);
        _identityOfficeAdmin = address(0x1D);
        _landOfficeAdmin = address(0x1A2D);
        _companyRegistryOfficeAdmin = address(0xC0);

        _deployCore(deployer);
        _deployRegistries();
        _deployPoliciesAndApps(deployer);
        _registerModules();
        _configureOriginAuthorities();
        _seedGenesisState();
        _assertReadyForBootstrapDisable();
        _sealAndDisableBootstrap();
    }

    function totalIdentityCount() external view returns (uint256 count) {
        return _identityRegistry.totalIdentityCount();
    }

    function identityRecord(bytes32 personId) external view returns (IdentityTypes.IdentityRecord memory record) {
        return _identityRegistry.getIdentityRecord(personId);
    }

    function activeStakeOf(bytes32 personId) external view returns (uint256 amount) {
        return _stakeRegistry.activeStakeOf(personId);
    }

    function occupiedSenateSeatCount() external view returns (uint32 count) {
        return _senateSeatRegistry.occupiedSeatCount();
    }

    function currentCongressOccupiedSeatCount() external view returns (uint32 count) {
        return _congressCandidateRegistry.getCurrentOfficeTerm().occupiedSeatCount;
    }

    function currentPresident() external view returns (address president) {
        return _presidentRegistry.currentPresident();
    }

    function officeRecord(bytes32 officeId) external view returns (OfficeTypes.OfficeRecord memory record) {
        return _officeRegistry.getOfficeRecord(officeId);
    }

    function setupAuthoritySealed() external view returns (bool isSetupSealed) {
        return _initialSetupAuthority.isSealed();
    }

    function kernelBootstrapAuthority() external view returns (address authority) {
        return IConstitutionKernel(address(_kernel)).bootstrapAuthority();
    }

    function routerBootstrapAuthority() external view returns (address authority) {
        return _router.bootstrapAuthority();
    }

    function officeExecutorBootstrapAuthority() external view returns (address authority) {
        return _officeExecutor.bootstrapAuthority();
    }
}

contract DeployGenesisTest is Test {
    bytes32 internal constant PERSON_ONE_ID = bytes32(uint256(1));
    bytes32 internal constant PERSON_TWO_ID = bytes32(uint256(2));
    bytes32 internal constant PERSON_THREE_ID = bytes32(uint256(3));
    bytes32 internal constant PERSON_FOUR_ID = bytes32(uint256(4));
    bytes32 internal constant FINANCE_OFFICE_ID = keccak256("office.ministry-finance");
    bytes32 internal constant IDENTITY_OFFICE_ID = keccak256("office.identity");
    bytes32 internal constant LAND_OFFICE_ID = keccak256("office.land");
    bytes32 internal constant COMPANY_REGISTRY_OFFICE_ID = keccak256("office.company-registry");

    address internal constant WALLET_ONE = address(0xA11CE);
    address internal constant WALLET_TWO = address(0xB0B);
    address internal constant WALLET_THREE = address(0xCAFE);
    address internal constant WALLET_FOUR = address(0xD00D);

    function test_DeploySeedsDeterministicGenesisBeforeSeal() public {
        _setGenesisEnv();

        DeployGenesisHarness harness = new DeployGenesisHarness();
        harness.deployForTest();

        assertEq(harness.totalIdentityCount(), 4);
        assertEq(harness.identityRecord(PERSON_ONE_ID).metadataHash, keccak256("genesis-citizen-one"));
        assertEq(
            uint256(harness.identityRecord(PERSON_TWO_ID).citizenshipStatus),
            uint256(IdentityTypes.CitizenshipStatus.Citizen)
        );
        assertEq(harness.activeStakeOf(PERSON_THREE_ID), 12_000 * 1e18);

        assertEq(harness.occupiedSenateSeatCount(), 2);
        assertEq(harness.currentCongressOccupiedSeatCount(), 2);
        assertEq(harness.currentPresident(), WALLET_ONE);

        assertEq(harness.officeRecord(FINANCE_OFFICE_ID).admin, address(0xF1A0));
        assertEq(harness.officeRecord(IDENTITY_OFFICE_ID).admin, address(0x1D));
        assertEq(harness.officeRecord(LAND_OFFICE_ID).admin, address(0x1A2D));
        assertEq(harness.officeRecord(COMPANY_REGISTRY_OFFICE_ID).admin, address(0xC0));

        assertTrue(harness.setupAuthoritySealed());
        assertEq(harness.kernelBootstrapAuthority(), address(0));
        assertEq(harness.routerBootstrapAuthority(), address(0));
        assertEq(harness.officeExecutorBootstrapAuthority(), address(0));
    }

    function _setGenesisEnv() private {
        _setEnv("GENESIS_CITIZEN_COUNT", "4");
        // LLM uses standard 18 decimals; genesis stakes are base units (whole LLM * 1e18).
        _setCitizenEnv(0, PERSON_ONE_ID, WALLET_ONE, 20_000 * 1e18, keccak256("genesis-citizen-one"));
        _setCitizenEnv(1, PERSON_TWO_ID, WALLET_TWO, 7_500 * 1e18, keccak256("genesis-citizen-two"));
        _setCitizenEnv(2, PERSON_THREE_ID, WALLET_THREE, 12_000 * 1e18, keccak256("genesis-citizen-three"));
        _setCitizenEnv(3, PERSON_FOUR_ID, WALLET_FOUR, 6_000 * 1e18, keccak256("genesis-citizen-four"));

        _setEnv("GENESIS_SENATE_SEAT_COUNT", "2");
        _setEnv("GENESIS_SENATE_SEAT_0_CITIZEN_INDEX", "0");
        _setEnv("GENESIS_SENATE_SEAT_1_CITIZEN_INDEX", "2");

        _setEnv("GENESIS_CONGRESS_MEMBER_COUNT", "4");
        _setEnv("GENESIS_CONGRESS_MEMBER_0_CITIZEN_INDEX", "0");
        _setEnv("GENESIS_CONGRESS_MEMBER_1_CITIZEN_INDEX", "2");
        _setEnv("GENESIS_CONGRESS_MEMBER_2_CITIZEN_INDEX", "1");
        _setEnv("GENESIS_CONGRESS_MEMBER_3_CITIZEN_INDEX", "3");

        _setEnv("GENESIS_PRESIDENT_CITIZEN_INDEX", "0");
        _setEnv("GENESIS_PRESIDENT_MANDATE_HASH", vm.toString(keccak256("genesis-president-mandate")));
    }

    function _setCitizenEnv(uint256 index, bytes32 personId, address wallet, uint256 activeStake, bytes32 metadataHash)
        private
    {
        string memory prefix = string.concat("GENESIS_CITIZEN_", vm.toString(index));
        _setEnv(string.concat(prefix, "_PERSON_ID"), vm.toString(personId));
        _setEnv(string.concat(prefix, "_WALLET"), vm.toString(wallet));
        _setEnv(string.concat(prefix, "_ACTIVE_STAKE"), vm.toString(activeStake));
        _setEnv(string.concat(prefix, "_METADATA_HASH"), vm.toString(metadataHash));
        _setEnv(string.concat(prefix, "_METADATA_URI"), string.concat("ipfs://genesis/citizen-", vm.toString(index)));
    }

    function _setEnv(string memory key, string memory value) private {
        // forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv(key, value);
    }
}
