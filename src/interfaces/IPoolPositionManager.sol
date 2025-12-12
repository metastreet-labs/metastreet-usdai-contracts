// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title Pool Position Manager Interface
 * @author MetaStreet Foundation
 */
interface IPoolPositionManager {
    /*------------------------------------------------------------------------*/
    /* Errors */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Invalid pool currency amount
     */
    error InvalidPoolCurrencyAmount();

    /*------------------------------------------------------------------------*/
    /* Events */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Pool withdrawn
     * @param pool Pool
     * @param tick Tick
     * @param shares Shares
     * @param redemptionId Redemption id
     * @param poolCurrencyAmount Pool currency amount
     * @param usdaiAmount USDai amount
     */
    event PoolWithdrawn(
        address indexed pool,
        uint128 indexed tick,
        uint256 shares,
        uint128 redemptionId,
        uint256 poolCurrencyAmount,
        uint256 usdaiAmount
    );

    /*------------------------------------------------------------------------*/
    /* Permissioned API */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Garbage collect a redemption / tick / pool
     * @param pool Address of the pool
     * @param tick Pool tick
     * @param redemptionId ID of the redemption
     */
    function poolGarbageCollect(
        address pool,
        uint128 tick,
        uint128 redemptionId
    ) external;
}
