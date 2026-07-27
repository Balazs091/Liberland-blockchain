// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {KernelModule} from "../base/KernelModule.sol";
import {IMinistryTreasury} from "../interfaces/IMinistryTreasury.sol";
import {IOfficeRegistry} from "../interfaces/IOfficeRegistry.sol";
import {IUSDCLendingPoolApp} from "../interfaces/IUSDCLendingPoolApp.sol";
import {KernelModuleIds} from "../libraries/KernelModuleIds.sol";
import {OfficeTypes} from "../types/OfficeTypes.sol";

/// @title MinistryTreasury
/// @notice Shared office-keyed ERC20 treasury for ministries/offices, with in-house lending-pool supply so idle
///         funds earn. Funding is Congress-controlled (a funding-authority module); spending is minister-controlled,
///         with clerks bounded by a minister-set daily limit; pool supply/withdraw is minister-only.
/// @dev Balances are keyed by office ID and roles are resolved live from the OfficeRegistry, so offices Congress
///      creates later can hold and manage funds with no change to this contract. The controlling "minister" is the
///      office admin; "clerks" are the office clerks.
contract MinistryTreasury is KernelModule, ReentrancyGuard, IMinistryTreasury {
    using SafeERC20 for IERC20;

    struct DailySpend {
        uint64 day;
        uint256 spent;
    }

    mapping(bytes32 officeId => mapping(address asset => uint256 balance)) private _balances;
    mapping(bytes32 officeId => mapping(address pool => uint256 shares)) private _poolShares;
    mapping(bytes32 officeId => mapping(address asset => uint256 dailyLimit)) private _clerkDailyLimit;
    mapping(bytes32 officeId => mapping(address clerk => mapping(address asset => DailySpend spend))) private
        _clerkSpend;

    constructor(address kernelAddress) KernelModule(kernelAddress) {}

    /// @inheritdoc IMinistryTreasury
    function balanceOf(bytes32 officeId, address asset) external view returns (uint256 amount) {
        return _balances[officeId][asset];
    }

    /// @inheritdoc IMinistryTreasury
    function poolSharesOf(bytes32 officeId) external view returns (uint256 shares) {
        return _poolShares[officeId][address(_lendingPool())];
    }

    /// @inheritdoc IMinistryTreasury
    function poolSharesAt(bytes32 officeId, address pool) external view returns (uint256 shares) {
        return _poolShares[officeId][pool];
    }

    /// @inheritdoc IMinistryTreasury
    function clerkDailyLimit(bytes32 officeId, address asset) external view returns (uint256 dailyLimit) {
        return _clerkDailyLimit[officeId][asset];
    }

    /// @inheritdoc IMinistryTreasury
    function clerkSpentToday(bytes32 officeId, address clerk, address asset) external view returns (uint256 amount) {
        DailySpend storage record = _clerkSpend[officeId][clerk][asset];
        return record.day == _currentDay() ? record.spent : 0;
    }

    /// @inheritdoc IMinistryTreasury
    function fund(bytes32 officeId, address asset, address from, uint256 amount) external nonReentrant {
        if (msg.sender != _kernel.getModule(KernelModuleIds.MINISTRY_TREASURY_FUNDING_AUTHORITY)) {
            revert UnauthorizedFundingAuthority(msg.sender);
        }
        _requireAsset(asset);
        _requireAmount(amount);
        if (from == address(0)) {
            revert InvalidRecipient(from);
        }
        _requireActiveOffice(officeId);

        // The funding source's approved tokens are pulled in a single transfer. Only the gating funding authority
        // (msg.sender) can trigger this, so the source's approval to this treasury cannot be spent arbitrarily.
        uint256 balanceBefore = IERC20(asset).balanceOf(address(this));
        IERC20(asset).safeTransferFrom(from, address(this), amount);
        uint256 received = IERC20(asset).balanceOf(address(this)) - balanceBefore;
        if (received != amount) {
            revert UnexpectedAssetAmount(amount, received);
        }

        _balances[officeId][asset] += received;

        emit MinistryFunded(officeId, asset, received, from, uint64(block.timestamp));
    }

    /// @inheritdoc IMinistryTreasury
    function setClerkDailyLimit(bytes32 officeId, address asset, uint256 dailyLimit) external {
        _requireAsset(asset);
        _requireMinister(officeId, msg.sender);

        _clerkDailyLimit[officeId][asset] = dailyLimit;

        emit ClerkDailyLimitSet(officeId, asset, dailyLimit, msg.sender, uint64(block.timestamp));
    }

    /// @inheritdoc IMinistryTreasury
    function spend(bytes32 officeId, address asset, address recipient, uint256 amount) external nonReentrant {
        _requireAsset(asset);
        _requireAmount(amount);
        if (recipient == address(0)) {
            revert InvalidRecipient(recipient);
        }

        // Minister (office admin) spends freely; a clerk is bound by the minister-set daily limit for this asset.
        OfficeTypes.OfficeRole role = _resolveActiveOfficeRole(officeId, msg.sender);
        if (role == OfficeTypes.OfficeRole.Clerk) {
            _consumeClerkDailyAllowance(officeId, msg.sender, asset, amount);
        }

        uint256 balance = _balances[officeId][asset];
        if (balance < amount) {
            revert InsufficientMinistryBalance(officeId, asset, balance, amount);
        }

        _balances[officeId][asset] = balance - amount;
        IERC20 token = IERC20(asset);
        uint256 recipientBalanceBefore = token.balanceOf(recipient);
        token.safeTransfer(recipient, amount);
        uint256 received = token.balanceOf(recipient) - recipientBalanceBefore;
        if (received != amount) {
            revert UnexpectedAssetAmount(amount, received);
        }

        emit MinistrySpent(officeId, asset, recipient, amount, msg.sender, uint64(block.timestamp));
    }

    /// @inheritdoc IMinistryTreasury
    function supplyToPool(bytes32 officeId, uint256 amount) external nonReentrant returns (uint256 shares) {
        _requireAmount(amount);
        _requireMinister(officeId, msg.sender);

        IUSDCLendingPoolApp pool = _lendingPool();
        address asset = pool.usdc();

        uint256 balance = _balances[officeId][asset];
        if (balance < amount) {
            revert InsufficientMinistryBalance(officeId, asset, balance, amount);
        }

        _balances[officeId][asset] = balance - amount;
        IERC20(asset).forceApprove(address(pool), amount);
        shares = pool.deposit(amount, address(this));
        _poolShares[officeId][address(pool)] += shares;

        emit MinistrySuppliedToPool(officeId, address(pool), amount, shares, uint64(block.timestamp));
    }

    /// @inheritdoc IMinistryTreasury
    function withdrawFromPool(bytes32 officeId, uint256 amount) external nonReentrant returns (uint256 shares) {
        _requireAmount(amount);
        _requireMinister(officeId, msg.sender);

        return _withdrawFromPool(officeId, _lendingPool(), amount);
    }

    /// @inheritdoc IMinistryTreasury
    function withdrawFromPoolAt(bytes32 officeId, address pool, uint256 amount)
        external
        nonReentrant
        returns (uint256 shares)
    {
        _requireAmount(amount);
        _requireMinister(officeId, msg.sender);

        uint256 officeShares = _poolShares[officeId][pool];
        if (officeShares == 0) {
            revert NoMinistryPoolShares(officeId, pool);
        }

        return _withdrawFromPool(officeId, IUSDCLendingPoolApp(pool), amount);
    }

    function _withdrawFromPool(bytes32 officeId, IUSDCLendingPoolApp pool, uint256 amount)
        private
        returns (uint256 shares)
    {
        address poolAddress = address(pool);
        uint256 officeShares = _poolShares[officeId][poolAddress];
        if (officeShares == 0) {
            revert NoMinistryPoolShares(officeId, poolAddress);
        }

        address asset = pool.usdc();

        uint256 balanceBefore = IERC20(asset).balanceOf(address(this));
        shares = pool.withdraw(amount, address(this));

        if (officeShares < shares) {
            revert InsufficientMinistryPoolShares(officeId, poolAddress, officeShares, shares);
        }
        _poolShares[officeId][poolAddress] = officeShares - shares;

        uint256 received = IERC20(asset).balanceOf(address(this)) - balanceBefore;
        _balances[officeId][asset] += received;

        emit MinistryWithdrewFromPool(officeId, poolAddress, received, shares, uint64(block.timestamp));
    }

    /// @dev The window is a per-UTC-day bucket (`block.timestamp / 1 days`), not a trailing 24h rolling window: the
    ///      spent-today counter resets at 00:00 UTC. A minister who wants tighter control revokes the clerk.
    function _consumeClerkDailyAllowance(bytes32 officeId, address clerk, address asset, uint256 amount) private {
        uint256 dailyLimit = _clerkDailyLimit[officeId][asset];
        uint64 today = _currentDay();
        DailySpend storage record = _clerkSpend[officeId][clerk][asset];

        uint256 spentToday = record.day == today ? record.spent : 0;
        uint256 newSpent = spentToday + amount;
        if (newSpent > dailyLimit) {
            revert ClerkDailyLimitExceeded(officeId, clerk, asset, spentToday, dailyLimit, amount);
        }

        record.day = today;
        record.spent = newSpent;
    }

    function _resolveActiveOfficeRole(bytes32 officeId, address caller)
        private
        view
        returns (OfficeTypes.OfficeRole role)
    {
        IOfficeRegistry officeRegistry = _officeRegistry();
        OfficeTypes.OfficeRecord memory record = officeRegistry.getOfficeRecord(officeId);
        if (record.officeId == bytes32(0) || !record.active) {
            revert InvalidMinistryOffice(officeId);
        }

        role = officeRegistry.roleOf(officeId, caller);
        if (role == OfficeTypes.OfficeRole.None) {
            revert UnauthorizedMinistryCaller(officeId, caller);
        }
    }

    function _requireMinister(bytes32 officeId, address caller) private view {
        if (_resolveActiveOfficeRole(officeId, caller) != OfficeTypes.OfficeRole.Admin) {
            revert UnauthorizedMinistryCaller(officeId, caller);
        }
    }

    function _requireActiveOffice(bytes32 officeId) private view {
        OfficeTypes.OfficeRecord memory record = _officeRegistry().getOfficeRecord(officeId);
        if (record.officeId == bytes32(0) || !record.active) {
            revert InvalidMinistryOffice(officeId);
        }
    }

    function _officeRegistry() private view returns (IOfficeRegistry registry) {
        return IOfficeRegistry(_kernel.getModule(KernelModuleIds.OFFICE_REGISTRY));
    }

    function _lendingPool() private view returns (IUSDCLendingPoolApp pool) {
        return IUSDCLendingPoolApp(_kernel.getModule(KernelModuleIds.USDC_LENDING_POOL_APP));
    }

    function _currentDay() private view returns (uint64 day) {
        return uint64(block.timestamp / 1 days);
    }

    function _requireAsset(address asset) private view {
        if (asset == address(0) || asset.code.length == 0) {
            revert InvalidAsset(asset);
        }
    }

    function _requireAmount(uint256 amount) private pure {
        if (amount == 0) {
            revert InvalidAmount(amount);
        }
    }
}
