// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import {PositionManager} from "./PositionManager.sol";
import {StakedUSDaiStorage} from "../StakedUSDaiStorage.sol";
import {PoolPositionManagerLogic} from "./PoolPositionManagerLogic.sol";

import {IPoolPositionManager} from "../interfaces/IPoolPositionManager.sol";
import {IPool} from "../interfaces/external/IPool.sol";
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";

/**
 * @title Pool Position Manager
 * @author MetaStreet Foundation
 */
abstract contract PoolPositionManager is
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    PositionManager,
    StakedUSDaiStorage,
    IPoolPositionManager
{
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;

    /*------------------------------------------------------------------------*/
    /* Constants */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Pools storage location
     * @dev keccak256(abi.encode(uint256(keccak256("stakedUSDai.pools")) - 1)) & ~bytes32(uint256(0xff));
     */
    bytes32 private constant POOLS_STORAGE_LOCATION = 0x0a32e6e3ec9caf40523489fb56ffc3afa6eadc68c0df235d444c084ba724fc00;

    /*------------------------------------------------------------------------*/
    /* Structures */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Pool position
     * @param ticks Ticks
     * @param redemptionIds Redemption ids
     */
    struct PoolPosition {
        EnumerableSet.UintSet ticks;
        mapping(uint128 => EnumerableSet.UintSet) redemptionIds;
    }

    /**
     * @custom:storage-location erc7201:stakedUSDai.pools
     */
    struct Pools {
        EnumerableSet.AddressSet pools;
        mapping(address => PoolPosition) position;
    }

    /*------------------------------------------------------------------------*/
    /* Immutable state */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Price oracle
     */
    IPriceOracle internal immutable _priceOracle;

    /*------------------------------------------------------------------------*/
    /* Constructor */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Constructor
     * @param priceOracle_ Price oracle
     */
    constructor(
        address priceOracle_
    ) {
        _priceOracle = IPriceOracle(priceOracle_);
    }

    /*------------------------------------------------------------------------*/
    /* Getter */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IPoolPositionManager
     */
    function pools() external view returns (address[] memory) {
        return _getPoolsStorage().pools.values();
    }

    /**
     * @inheritdoc IPoolPositionManager
     */
    function poolTicks(
        address pool
    ) external view returns (uint256[] memory) {
        return _getPoolsStorage().position[pool].ticks.values();
    }

    /**
     * @inheritdoc IPoolPositionManager
     */
    function priceOracle() external view returns (address) {
        return address(_priceOracle);
    }

    /*------------------------------------------------------------------------*/
    /* Internal helpers */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Get reference to ERC-7201 pools storage
     *
     * @return $ Reference to pools storage
     */
    function _getPoolsStorage() internal pure returns (Pools storage $) {
        assembly {
            $.slot := POOLS_STORAGE_LOCATION
        }
    }

    /**
     * @inheritdoc PositionManager
     */
    function _assets(
        PositionManager.ValuationType valuationType
    ) internal view virtual override returns (uint256 nav_) {
        return PoolPositionManagerLogic._assets(_getPoolsStorage(), _priceOracle, valuationType);
    }

    /*------------------------------------------------------------------------*/
    /* Permissioned API */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IPoolPositionManager
     */
    function poolDeposit(
        address pool,
        uint128 tick,
        uint256 usdaiAmount,
        uint256 poolCurrencyAmountMinimum,
        uint256 minShares,
        bytes calldata data
    ) external onlyRole(STRATEGY_ADMIN_ROLE) nonReentrant returns (uint256) {
        /* Get pool currency token */
        address poolCurrency = IPool(pool).currencyToken();

        /* Validate pool currency token is supported in price oracle */
        if (!_priceOracle.supportedToken(poolCurrency)) {
            revert UnsupportedCurrency(poolCurrency);
        }

        /* Get USDai balance */
        uint256 usdaiBalance = _usdai.balanceOf(address(this)) - _getRedemptionStateStorage().redemptionBalance;

        /* Validate USDai balance */
        if (usdaiAmount > usdaiBalance) revert InsufficientBalance();

        /* Swap USDai to pool currency token */
        uint256 poolCurrencyAmount =
            _usdai.withdraw(poolCurrency, usdaiAmount, poolCurrencyAmountMinimum, address(this), data);

        /* Add pool and tick */
        Pools storage position = _getPoolsStorage();
        position.pools.add(pool);
        position.position[pool].ticks.add(tick);

        /* Approve pool currency token */
        IERC20(poolCurrency).forceApprove(address(pool), poolCurrencyAmount);

        /* Deposit */
        uint256 shares = IPool(pool).deposit(tick, poolCurrencyAmount, minShares);

        /* Emit PoolDeposited */
        emit PoolDeposited(pool, tick, usdaiAmount, poolCurrencyAmount);

        return shares;
    }

    /**
     * @inheritdoc IPoolPositionManager
     */
    function poolRedeem(
        address pool,
        uint128 tick,
        uint256 shares
    ) external onlyRole(STRATEGY_ADMIN_ROLE) nonReentrant returns (uint128) {
        /* Redeem */
        uint128 redemptionId = IPool(pool).redeem(tick, shares);

        /* Add redemption ID */
        _getPoolsStorage().position[pool].redemptionIds[tick].add(redemptionId);

        /* Emit PoolRedeemed */
        emit PoolRedeemed(pool, tick, shares, redemptionId);

        return redemptionId;
    }

    /**
     * @inheritdoc IPoolPositionManager
     */
    function poolWithdraw(
        address pool,
        uint128 tick,
        uint128 redemptionId,
        uint256 poolCurrencyAmountMaximum,
        uint256 usdaiAmountMinimum,
        bytes calldata data
    ) external onlyRole(STRATEGY_ADMIN_ROLE) nonReentrant returns (uint256) {
        /* Withdraw */
        (uint256 withdrawnShares, uint256 poolCurrencyAmount) = IPool(pool).withdraw(tick, redemptionId);

        /* Validate pool currency amount */
        if (poolCurrencyAmount > poolCurrencyAmountMaximum) revert InvalidPoolCurrencyAmount();

        /* Garbage collect tick info and pool */
        PoolPositionManagerLogic._garbageCollect(_getPoolsStorage(), pool, tick, redemptionId);

        /* Check if withdraw produced currency */
        if (poolCurrencyAmount == 0) return 0;

        /* Get currency token */
        address poolCurrency = IPool(pool).currencyToken();

        /* Approve currency token */
        IERC20(poolCurrency).forceApprove(address(_usdai), poolCurrencyAmount);

        /* Swap currency token to USDai */
        uint256 usdaiAmount = _usdai.deposit(poolCurrency, poolCurrencyAmount, usdaiAmountMinimum, address(this), data);

        /* Emit PoolWithdrawn */
        emit PoolWithdrawn(pool, tick, withdrawnShares, redemptionId, poolCurrencyAmount, usdaiAmount);

        return usdaiAmount;
    }
}
