// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title Predeposit Vault Interface
 * @author MetaStreet Foundation
 */
interface IPredepositVault {
    /*------------------------------------------------------------------------*/
    /* Structures */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Deposit type
     */
    enum DepositType {
        Deposit,
        DepositAndStake
    }

    /*------------------------------------------------------------------------*/
    /* Errors */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Invalid amount
     */
    error InvalidAmount();

    /**
     * @notice Invalid recipient
     */
    error InvalidRecipient();

    /*------------------------------------------------------------------------*/
    /* Events */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Deposited event
     * @param depositType Deposit type
     * @param depositToken Deposit token address
     * @param depositor Depositor address
     * @param recipient Recipient address
     * @param amount Deposit amount
     * @param dstEid Destination EID
     */
    event Deposited(
        DepositType indexed depositType,
        address indexed depositToken,
        address depositor,
        address indexed recipient,
        uint256 amount,
        uint32 dstEid
    );

    /**
     * @notice Withdrawn event
     * @param to Recipient address
     * @param amount Amount withdrawn
     */
    event Withdrawn(address indexed to, uint256 amount);

    /**
     * @notice Deposit cap updated event
     * @param depositCap New deposit cap
     */
    event DepositCapUpdated(uint256 depositCap);

    /*------------------------------------------------------------------------*/
    /* Getters */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Get deposit token address
     * @return Deposit token address
     */
    function depositToken() external view returns (address);

    /**
     * @notice Get deposit amount minimum
     * @return Deposit amount minimum
     */
    function depositAmountMinimum() external view returns (uint256);

    /**
     * @notice Get deposit cap information
     * @return cap Deposit cap
     * @return counter Current deposit counter
     */
    function depositCapInfo() external view returns (uint256 cap, uint256 counter);

    /*------------------------------------------------------------------------*/
    /* Public API */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Deposit tokens
     * @param depositType Type of deposit
     * @param amount Amount to deposit
     * @param recipient Recipient address
     */
    function deposit(DepositType depositType, uint256 amount, address recipient) external;

    /*------------------------------------------------------------------------*/
    /* Permissioned API */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Withdraw tokens
     * @param to Recipient address
     * @param amount Amount to withdraw
     */
    function withdraw(address to, uint256 amount) external;

    /**
     * @notice Rescue tokens
     * @param token Token to rescue
     * @param to Recipient address
     * @param amount Amount of tokens to rescue
     */
    function rescue(address token, address to, uint256 amount) external;

    /**
     * @notice Update deposit cap
     * @param depositCap New deposit cap
     * @param resetCounter Whether to reset the counter
     */
    function updateDepositCap(uint256 depositCap, bool resetCounter) external;
}
