// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {KernelModule} from "../base/KernelModule.sol";
import {ICitizenEligibilityPolicy} from "../interfaces/ICitizenEligibilityPolicy.sol";
import {IStakeLienRegistry} from "../interfaces/IStakeLienRegistry.sol";
import {IStakeRegistry} from "../interfaces/IStakeRegistry.sol";
import {KernelModuleIds} from "../libraries/KernelModuleIds.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title StakeLienRegistry
/// @notice Stable fact registry for lending liens against active political stake.
contract StakeLienRegistry is IStakeLienRegistry, KernelModule, ReentrancyGuard {
    mapping(bytes32 personId => uint256 lienedStake) private _liens;
    mapping(bytes32 personId => uint256 retainedStakeFloor) private _retainedStakeFloors;
    mapping(bytes32 personId => address pool) private _loanBooks;

    /// @param kernelAddress The canonical kernel registry address.
    constructor(address kernelAddress) KernelModule(kernelAddress) {}

    /// @inheritdoc IStakeLienRegistry
    /// @dev Sourced live from the governed citizenship policy for positions that do not yet have a lien.
    function minimumRetainedStake() external view returns (uint256 amount) {
        return _currentMinimumRetainedStake();
    }

    /// @inheritdoc IStakeLienRegistry
    function retainedStakeFloorOf(bytes32 personId) external view returns (uint256 amount) {
        if (_loanBooks[personId] == address(0)) {
            return _currentMinimumRetainedStake();
        }

        return _retainedStakeFloors[personId];
    }

    /// @inheritdoc IStakeLienRegistry
    function lienedStakeOf(bytes32 personId) external view returns (uint256 amount) {
        return _liens[personId];
    }

    /// @inheritdoc IStakeLienRegistry
    function loanBookOf(bytes32 personId) external view returns (address pool) {
        return _loanBooks[personId];
    }

    /// @inheritdoc IStakeLienRegistry
    function increaseLien(bytes32 personId, uint256 amount) external nonReentrant {
        _requireCurrentLoanOrigin(msg.sender);
        _requireValidPersonId(personId);
        _requireValidAmount(amount);

        address owner = _loanBooks[personId];
        if (owner != address(0) && owner != msg.sender) {
            revert LoanBookConflict(personId, owner, msg.sender);
        }

        uint256 currentLienedStake = _liens[personId];
        uint256 newLienedStake = currentLienedStake + amount;
        uint64 updatedAt = uint64(block.timestamp);
        if (owner == address(0)) {
            uint256 retainedStakeFloor = _currentMinimumRetainedStake();
            _retainedStakeFloors[personId] = retainedStakeFloor;
            _loanBooks[personId] = msg.sender;
            emit RetainedStakeFloorUpdated(personId, 0, retainedStakeFloor, updatedAt);
            emit LoanBookOpened(personId, msg.sender);
        }
        _checkActiveStakeFloor(personId, newLienedStake, 0);
        _liens[personId] = newLienedStake;

        emit StakeLienIncreased(personId, amount, newLienedStake, updatedAt, msg.sender);
    }

    /// @inheritdoc IStakeLienRegistry
    function decreaseLien(bytes32 personId, uint256 amount) external nonReentrant {
        _requireLoanOwner(personId);
        _requireValidPersonId(personId);
        _requireValidAmount(amount);

        uint256 currentLien = _liens[personId];
        if (currentLien < amount) {
            revert InsufficientStakeLien(personId, currentLien, amount);
        }

        _reduceLien(personId, currentLien - amount);
    }

    /// @inheritdoc IStakeLienRegistry
    function closeLoan(bytes32 personId) external nonReentrant {
        _requireLoanOwner(personId);
        _closeLoan(personId);
    }

    /// @inheritdoc IStakeLienRegistry
    function settleLiquidation(
        bytes32 personId,
        bytes32 recipientPersonId,
        uint256 seizedStake,
        uint256 remainingLien,
        bool debtCleared
    ) external nonReentrant {
        _requireLoanOwner(personId);
        _requireValidPersonId(recipientPersonId);
        if (
            recipientPersonId == personId || seizedStake == 0 || remainingLien > _liens[personId]
                || (debtCleared && remainingLien != 0)
        ) {
            revert InvalidLiquidationSettlement(personId);
        }
        _checkActiveStakeFloor(personId, remainingLien, seizedStake);
        uint256 priorLien = _liens[personId];
        if (!_isCurrentLoanOrigin(msg.sender) && (seizedStake > priorLien || remainingLien > priorLien - seizedStake)) {
            revert RetiredLoanCollateralExceeded(personId, priorLien, seizedStake, remainingLien);
        }
        if (debtCleared) {
            _closeLoan(personId);
        } else {
            _reduceLien(personId, remainingLien);
        }
        // The canonical registry is the sole lending-transfer caller. Retired pool addresses never acquire a
        // general stake-transfer permission, and any downstream failure rolls back this entire settlement.
        IStakeRegistry(_kernel.getModule(KernelModuleIds.STAKE_REGISTRY))
            .transferActiveStake(personId, recipientPersonId, seizedStake);
        emit LienLiquidationSettled(personId, recipientPersonId, msg.sender, seizedStake, remainingLien, debtCleared);
    }

    function _reduceLien(bytes32 personId, uint256 newLien) private {
        uint256 reduction = _liens[personId] - newLien;
        _liens[personId] = newLien;
        if (reduction != 0) {
            emit StakeLienDecreased(personId, reduction, newLien, uint64(block.timestamp), msg.sender);
        }
    }

    function _closeLoan(bytes32 personId) private {
        _reduceLien(personId, 0);
        uint256 previousRetainedFloor = _retainedStakeFloors[personId];
        delete _retainedStakeFloors[personId];
        delete _loanBooks[personId];
        emit RetainedStakeFloorUpdated(personId, previousRetainedFloor, 0, uint64(block.timestamp));
        emit LoanBookClosed(personId, msg.sender);
    }

    function _checkActiveStakeFloor(bytes32 personId, uint256 lien, uint256 seizedStake) private view {
        IStakeRegistry stakeRegistry = IStakeRegistry(_kernel.getModule(KernelModuleIds.STAKE_REGISTRY));
        uint256 protectedFloor = stakeRegistry.protectedStakeFloorOf(personId);
        uint256 retainedFloor = _retainedStakeFloors[personId];
        uint256 requiredStake = (protectedFloor > retainedFloor ? protectedFloor : retainedFloor) + lien + seizedStake;
        uint256 activeStake = stakeRegistry.activeStakeOf(personId);
        if (requiredStake > activeStake) {
            revert LienExceedsActiveStake(personId, requiredStake, activeStake);
        }
    }

    function _currentMinimumRetainedStake() private view returns (uint256 amount) {
        return
            ICitizenEligibilityPolicy(_kernel.getModule(KernelModuleIds.CITIZEN_ELIGIBILITY_POLICY))
                .minimumCitizenStake();
    }

    function _requireCurrentLoanOrigin(address caller) private view {
        if (!_isCurrentLoanOrigin(caller)) {
            revert UnauthorizedStakeLienRegistryCaller(caller);
        }
    }

    function _isCurrentLoanOrigin(address caller) private view returns (bool) {
        return address(this) == _kernel.getModule(KernelModuleIds.STAKE_LIEN_REGISTRY)
            && caller == _kernel.getModule(KernelModuleIds.STAKE_LIEN_REGISTRY_AUTHORITY)
            && caller == _kernel.getModule(KernelModuleIds.STAKE_LIQUIDATION_AUTHORITY)
            && caller == _kernel.getModule(KernelModuleIds.USDC_LENDING_POOL_APP);
    }

    function _requireLoanOwner(bytes32 personId) private view {
        if (_loanBooks[personId] != msg.sender) {
            revert LoanBookConflict(personId, _loanBooks[personId], msg.sender);
        }
    }

    function _requireValidPersonId(bytes32 personId) private pure {
        if (personId == bytes32(0)) {
            revert InvalidPersonId(personId);
        }
    }

    function _requireValidAmount(uint256 amount) private pure {
        if (amount == 0) {
            revert InvalidLienAmount(amount);
        }
    }
}
