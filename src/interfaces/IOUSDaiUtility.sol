// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUSDaiQueuedDepositor} from "./IUSDaiQueuedDepositor.sol";

/**
 * @title OUSDai Utility Interface
 * @author MetaStreet Foundation
 */
interface IOUSDaiUtility {
    /*------------------------------------------------------------------------*/
    /* Structures */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Action type
     */
    enum ActionType {
        Deposit,
        DepositAndStake,
        QueuedDeposit /* deposit only, or deposit and stake */
    }

    /*------------------------------------------------------------------------*/
    /* Errors */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Invalid address
     */
    error InvalidAddress();

    /**
     * @notice Unknown Action
     */
    error UnknownAction();

    /*------------------------------------------------------------------------*/
    /* Events */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Composer deposit event
     * @param dstEid Destination chain EID
     * @param depositToken Deposit token
     * @param recipient Recipient address
     * @param depositAmount Amount of deposit token
     * @param usdaiAmount Amount of USDai received
     */
    event ComposerDeposit(
        uint256 indexed dstEid,
        address indexed depositToken,
        address indexed recipient,
        uint256 depositAmount,
        uint256 usdaiAmount
    );

    /**
     * @notice Composer deposit and stake event
     * @param dstEid Destination chain EID
     * @param depositToken Token to deposit
     * @param recipient Recipient address
     * @param depositToken Deposit token
     * @param depositAmount Amount of deposit token
     * @param usdaiAmount Amount of USDai received
     * @param susdaiAmount Amount of Staked USDai received
     */
    event ComposerDepositAndStake(
        uint256 indexed dstEid,
        address indexed depositToken,
        address indexed recipient,
        uint256 depositAmount,
        uint256 usdaiAmount,
        uint256 susdaiAmount
    );

    /**
     * @notice Queued deposit event
     * @param queueType Queue type
     * @param depositToken Token to deposit
     * @param depositAmount Amount of tokens to deposit
     * @param recipient Recipient
     */
    event ComposerQueuedDeposit(
        IUSDaiQueuedDepositor.QueueType indexed queueType,
        address indexed depositToken,
        address indexed recipient,
        uint256 depositAmount
    );

    /**
     * @notice Action failed event
     * @param action Action that failed
     * @param reason Reason for action failure
     */
    event ActionFailed(string indexed action, bytes reason);

    /**
     * @notice Whitelisted OAdapters added event
     * @param oAdapters OAdapters added
     */
    event WhitelistedOAdaptersAdded(address[] oAdapters);

    /**
     * @notice Whitelisted OAdapters removed event
     * @param oAdapters OAdapters removed
     */
    event WhitelistedOAdaptersRemoved(address[] oAdapters);

    /*------------------------------------------------------------------------*/
    /* Permissioned API */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Add whitelisted OAdapters
     * @param oAdapters OAdapters to whitelist
     */
    function addWhitelistedOAdapters(
        address[] memory oAdapters
    ) external;

    /**
     * @notice Remove whitelisted OAdapters
     * @param oAdapters OAdapters to remove
     */
    function removeWhitelistedOAdapters(
        address[] memory oAdapters
    ) external;

    /**
     * @notice Rescue tokens
     * @param token Token to rescue
     * @param to Recipient address
     * @param amount Amount of tokens to rescue
     */
    function rescue(address token, address to, uint256 amount) external;
}
