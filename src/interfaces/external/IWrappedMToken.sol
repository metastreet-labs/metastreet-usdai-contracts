// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title Wrapped M Token Interface
 */
interface IWrappedMToken is IERC20 {
    /**
     * @notice Starts earning for `account` if allowed by TTG
     * @param account The account to start earning for
     */
    function startEarningFor(
        address account
    ) external;

    /**
     * @notice Claims any claimable yield for `account`
     * @param account The account under which yield was generated
     * @return Yield claimed
     */
    function claimFor(
        address account
    ) external returns (uint240);

    /**
     * @notice Returns the yield accrued for `account`, which is claimable.
     * @param account The account being queried.
     * @return Yield that is claimable.
     */
    function accruedYieldOf(
        address account
    ) external view returns (uint240);

    /**
     * @notice Wraps `amount` of M tokens for `account`
     * @param account The account to wrap M tokens for
     * @param amount The amount of M tokens to wrap
     */
    function wrap(address account, uint256 amount) external;

    /**
     * @notice Returns the current index
     * @return The current index
     */
    function currentIndex() external view returns (uint128);

    /**
     * @notice Returns the last index for `account`
     * @param account The account to get the last index for
     * @return The last index for `account`
     */
    function lastIndexOf(
        address account
    ) external view returns (uint128);

    /**
     * @notice Returns the claim override recipient for `account`
     * @param account The account to get the claim override recipient for
     * @return The claim override recipient for `account`
     */
    function claimOverrideRecipientFor(
        address account
    ) external view returns (address);
}
