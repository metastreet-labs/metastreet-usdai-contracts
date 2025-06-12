// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import {PoolPositionManager} from "./PoolPositionManager.sol";
import {PositionManager} from "./PositionManager.sol";

import {IPool} from "../interfaces/external/IPool.sol";
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";

/**
 * @title Pool Position Manager Logic
 * @author MetaStreet Foundation
 */
library PoolPositionManagerLogic {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;

    /*------------------------------------------------------------------------*/
    /* Constants */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Fixed point scale
     */
    uint256 private constant FIXED_POINT_SCALE = 1e18;

    /*------------------------------------------------------------------------*/
    /* Internal helpers */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Get assets
     * @param poolsStorage Pools storage
     * @param priceOracle Price oracle
     * @param valuationType Valuation type
     * @return nav NAV
     */
    function _assets(
        PoolPositionManager.Pools storage poolsStorage,
        IPriceOracle priceOracle,
        PositionManager.ValuationType valuationType
    ) external view returns (uint256 nav) {
        /* Compute NAV */
        for (uint256 i; i < poolsStorage.pools.length(); i++) {
            IPool pool = IPool(poolsStorage.pools.at(i));

            /* Get pool value in terms of USDai and add to NAV */
            nav += _value(priceOracle, pool.currencyToken(), _getPoolPosition(poolsStorage, pool, valuationType));
        }
    }

    /*------------------------------------------------------------------------*/
    /* Helpers */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Get pool position
     * @param poolsStorage Pools storage
     * @param pool Pool
     * @param valuationType Valuation type
     * @return Pool position value
     */
    function _getPoolPosition(
        PoolPositionManager.Pools storage poolsStorage,
        IPool pool,
        PositionManager.ValuationType valuationType
    ) internal view returns (uint256) {
        /* Get pool position */
        PoolPositionManager.PoolPosition storage position = poolsStorage.position[address(pool)];

        /* Compute value across all ticks */
        uint256 value;
        for (uint256 i; i < position.ticks.length(); i++) {
            uint128 tick = uint128(position.ticks.at(i));

            /* Get shares */
            (uint256 shares,) = pool.deposits(address(this), tick);

            /* Get pending shares */
            uint256 pendingShares;
            for (uint256 j; j < position.redemptionIds[tick].length(); j++) {
                (uint128 pending,,) = pool.redemptions(address(this), tick, uint128(position.redemptionIds[tick].at(j)));
                pendingShares += pending;
            }

            value += (
                valuationType == PositionManager.ValuationType.OPTIMISTIC
                    ? pool.depositSharePrice(tick) * (shares + pendingShares)
                    : pool.redemptionSharePrice(tick) * (shares + pendingShares)
            ) / FIXED_POINT_SCALE;
        }

        return value;
    }

    /**
     * @notice Cleans up tracking data for a redemption, tick, or pool if fully serviced and empty.
     * @param poolsStorage Pools storage
     * @param pool Pool address
     * @param tick Tick
     * @param redemptionId Redemption ID to check and potentially garbage collect
     */
    function _garbageCollect(
        PoolPositionManager.Pools storage poolsStorage,
        address pool,
        uint128 tick,
        uint128 redemptionId
    ) external {
        /* Check if the specific redemption is fully serviced */
        (uint128 pendingShares,,) = IPool(pool).redemptions(address(this), tick, redemptionId);
        if (pendingShares != 0) return;

        PoolPositionManager.PoolPosition storage position = poolsStorage.position[pool];

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
        delete poolsStorage.position[pool];
        poolsStorage.pools.remove(pool);
    }

    /*
     * @notice Get value in USDai
     * @param priceOracle Price oracle
     * @param currencyToken Currency token address
     * @param amount Amount of currency token
     * @return Value in USDai
     */
    function _value(IPriceOracle priceOracle, address currencyToken, uint256 amount) internal view returns (uint256) {
        /* Get price of currency token in terms of USDai */
        uint256 price = priceOracle.price(currencyToken);

        /* Get decimals of currency token */
        uint256 decimals = IERC20Metadata(currencyToken).decimals();

        return Math.mulDiv(amount, price, 10 ** decimals);
    }
}
