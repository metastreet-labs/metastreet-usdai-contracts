// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import {PositionManager} from "./PositionManager.sol";
import {StakedUSDaiStorage} from "../StakedUSDaiStorage.sol";

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

    /**
     * @notice Fixed point scale
     */
    uint256 private constant FIXED_POINT_SCALE = 1e18;

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
    function poolPosition(address pool, ValuationType valuationType) external view returns (TickPosition[] memory) {
        /* Get pool position */
        PoolPosition storage position = _getPoolsStorage().position[address(pool)];

        /* Get ticks */
        uint256[] memory ticks_ = position.ticks.values();

        /* Initialize ticks */
        TickPosition[] memory ticks = new TickPosition[](ticks_.length);

        /* Add ticks */
        for (uint256 i; i < ticks_.length; i++) {
            /* Add to ticks */
            ticks[i] = _getTickPosition(position, IPool(pool), uint128(ticks_[i]), valuationType);
        }

        return ticks;
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
        ValuationType valuationType
    ) internal view virtual override returns (uint256) {
        /* Get all pools */
        address[] memory pools_ = _getPoolsStorage().pools.values();

        /* Compute NAV */
        uint256 nav_;
        for (uint256 i; i < pools_.length; i++) {
            /* Get pool */
            IPool pool = IPool(pools_[i]);

            /* Get all ticks */
            PoolPosition storage position = _getPoolsStorage().position[address(pool)];
            uint256[] memory ticks = position.ticks.values();

            /* Compute value for each tick in terms of pool currency */
            uint256 value;
            for (uint256 j; j < ticks.length; j++) {
                /* Compute value of shares */
                value += _getTickPosition(position, IPool(pool), uint128(ticks[j]), valuationType).value;
            }

            /* Get value in USDai and add to NAV */
            nav_ += _value(pool.currencyToken(), value);
        }

        /* Return NAV */
        return nav_;
    }

    /**
     * @notice Get tick position
     * @param position Pool position
     * @param pool Pool
     * @param tick Tick
     * @param valuationType Valuation type
     * @return Tick position
     */
    function _getTickPosition(
        PoolPosition storage position,
        IPool pool,
        uint128 tick,
        ValuationType valuationType
    ) private view returns (TickPosition memory) {
        /* Get shares */
        (uint128 shares,) = pool.deposits(address(this), tick);

        /* Get redemption IDs */
        uint256[] memory redemptionIds = position.redemptionIds[tick].values();

        /* Get pending shares */
        uint128 pendingShares;
        for (uint256 j; j < redemptionIds.length; j++) {
            (uint128 pending,,) = pool.redemptions(address(this), tick, uint128(redemptionIds[j]));
            pendingShares += pending;
        }

        /* Return tick */
        return TickPosition({
            tick: tick,
            shares: shares,
            pendingShares: pendingShares,
            value: (
                valuationType == ValuationType.OPTIMISTIC
                    ? pool.depositSharePrice(tick) * uint256(shares + pendingShares)
                    : pool.redemptionSharePrice(tick) * uint256(shares + pendingShares)
            ) / FIXED_POINT_SCALE,
            redemptionIds: redemptionIds
        });
    }

    /**
     * @notice Cleans up tracking data for a redemption, tick, or pool if fully serviced and empty.
     * @param pool Pool address
     * @param tick Tick
     * @param redemptionId Redemption ID to check and potentially garbage collect
     */
    function _garbageCollect(address pool, uint128 tick, uint128 redemptionId) internal {
        /* Check if the specific redemption is fully serviced */
        (uint128 pendingShares,,) = IPool(pool).redemptions(address(this), tick, redemptionId);
        if (pendingShares != 0) return;

        /* Get pool position */
        Pools storage pools_ = _getPoolsStorage();
        PoolPosition storage position = pools_.position[pool];

        /* Remove the fully serviced redemption ID */
        position.redemptionIds[tick].remove(redemptionId);

        /* Check if the tick can be removed */
        if (position.redemptionIds[tick].length() != 0) return;

        /* Check if the tick has deposits */
        (uint128 depositedShares,) = IPool(pool).deposits(address(this), tick);
        if (depositedShares != 0) return;

        /* Remove the tick from the pool */
        position.ticks.remove(tick);

        /* Check if the pool itself can be removed */
        if (position.ticks.length() != 0) return;

        /* Remove the entire pool position and pool */
        delete pools_.position[pool];
        pools_.pools.remove(pool);
    }

    /*
     * @notice Get value in USDai
     * @param currencyToken Currency token address
     * @param amount Amount of currency token
     * @return Value in USDai
     */
    function _value(address currencyToken, uint256 amount) internal view returns (uint256) {
        /* Get price of currency token in terms of USDai */
        uint256 price = _priceOracle.price(currencyToken);

        /* Get decimals of currency token */
        uint256 decimals = IERC20Metadata(currencyToken).decimals();

        return Math.mulDiv(amount, price, 10 ** decimals);
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
        IERC20(poolCurrency).approve(address(pool), poolCurrencyAmount);

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
        uint256 usdaiAmountMinimum,
        bytes calldata data
    ) external onlyRole(STRATEGY_ADMIN_ROLE) nonReentrant returns (uint256) {
        /* Withdraw */
        (uint256 withdrawnShares, uint256 poolCurrencyAmount) = IPool(pool).withdraw(tick, redemptionId);

        /* Garbage collect tick info and pool */
        _garbageCollect(pool, tick, redemptionId);

        /* Get currency token */
        address poolCurrency = IPool(pool).currencyToken();

        /* Approve currency token */
        IERC20(poolCurrency).approve(address(_usdai), poolCurrencyAmount);

        /* Swap currency token to USDai */
        uint256 usdaiAmount = _usdai.deposit(poolCurrency, poolCurrencyAmount, usdaiAmountMinimum, address(this), data);

        /* Emit PoolWithdrawn */
        emit PoolWithdrawn(pool, tick, withdrawnShares, redemptionId, poolCurrencyAmount, usdaiAmount);

        return usdaiAmount;
    }
}
