// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IPool as IPool_} from "metastreet-contracts-v2/interfaces/IPool.sol";

/**
 * @notice Extension of the MetaStreet V2 IPool interface
 */
interface IPool is IPool_ {
    /**
     * @notice Get deposit
     * @param account Account
     * @param tick Tick
     * @return Shares, Redemption ID
     */
    function deposits(address account, uint128 tick) external view returns (uint128, uint128);

    /**
     * @notice Get redemption
     * @param account Account
     * @param tick Tick
     * @param redemptionId Redemption ID
     * @return Pending, index, target
     */
    function redemptions(
        address account,
        uint128 tick,
        uint128 redemptionId
    ) external view returns (uint128, uint128, uint128);

    /**
     * @notice Get deposit share price
     * @param tick Tick
     * @return Deposit share price
     */
    function depositSharePrice(
        uint128 tick
    ) external view returns (uint256);

    /**
     * @notice Get redemption share price
     * @param tick Tick
     * @return Redemption share price
     */
    function redemptionSharePrice(
        uint128 tick
    ) external view returns (uint256);
}
