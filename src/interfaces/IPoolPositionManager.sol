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
     * @notice Pool deposited
     * @param pool Pool
     * @param tick Tick
     * @param usdaiAmount USDai amount
     * @param poolCurrencyAmount Pool currency amount
     */
    event PoolDeposited(address indexed pool, uint128 indexed tick, uint256 usdaiAmount, uint256 poolCurrencyAmount);

    /**
     * @notice Pool redeemed
     * @param pool Pool
     * @param tick Tick
     * @param shares Shares
     * @param redemptionId Redemption id
     */
    event PoolRedeemed(address indexed pool, uint128 indexed tick, uint256 shares, uint128 redemptionId);

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
     * @notice Request redemption from a pool
     * @param pool Address of the pool
     * @param tick Pool tick
     * @param shares Amount of shares to redeem
     * @return Redemption ID
     */
    function poolRedeem(address pool, uint128 tick, uint256 shares) external returns (uint128);

    /**
     * @notice Withdraw assets from a pool after redemption
     * @param pool Address of the pool
     * @param tick Pool tick
     * @param redemptionId ID of the redemption
     * @param poolCurrencyAmountMaximum Maximum amount of pool currency to withdraw
     * @param usdaiAmountMinimum Minimum amount of USDai to withdraw
     * @param data Data (for swap adapter)
     * @return USDai amount
     */
    function poolWithdraw(
        address pool,
        uint128 tick,
        uint128 redemptionId,
        uint256 poolCurrencyAmountMaximum,
        uint256 usdaiAmountMinimum,
        bytes calldata data
    ) external returns (uint256);
}
