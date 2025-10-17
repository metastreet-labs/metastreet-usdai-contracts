// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IDepositTimelock {
    /*------------------------------------------------------------------------*/
    /* Errors */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Invalid amount
     */
    error InvalidAmount();

    /**
     * @notice Invalid deposit
     */
    error InvalidDeposit();

    /**
     * @notice Invalid address
     */
    error InvalidAddress();

    /**
     * @notice Invalid bytes32
     */
    error InvalidBytes32();

    /**
     * @notice Invalid data
     */
    error InvalidData();

    /**
     * @notice Invalid swap
     */
    error InvalidSwap(bytes reason);

    /**
     * @notice Invalid timestamp
     */
    error InvalidTimestamp();

    /**
     * @notice Unsupported token
     */
    error UnsupportedToken();

    /*------------------------------------------------------------------------*/
    /* Events */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Emitted when deposit is made
     * @param depositor Depositor address
     * @param target Target contract that can withdraw
     * @param context Context identifier
     * @param token Token address
     * @param amount Amount deposited
     * @param expiration Expiration timestamp
     */
    event Deposited(
        address indexed depositor,
        address indexed target,
        bytes32 indexed context,
        address token,
        uint256 amount,
        uint64 expiration
    );

    /**
     * @notice Emitted when deposit is canceled
     * @param depositor Depositor address
     * @param target Target contract
     * @param context Context identifier
     */
    event Canceled(address indexed depositor, address indexed target, bytes32 indexed context);

    /**
     * @notice Emitted when deposit is withdrawn
     * @param withdrawer Withdrawer address
     * @param depositor Depositor address
     * @param context Context identifier
     * @param depositToken Deposit token address
     * @param withdrawToken Withdraw token address
     * @param depositAmount Deposit amount
     * @param withdrawAmount Withdraw amount
     */
    event Withdrawn(
        address indexed withdrawer,
        address indexed depositor,
        bytes32 indexed context,
        address depositToken,
        address withdrawToken,
        uint256 depositAmount,
        uint256 withdrawAmount
    );

    /**
     * @notice Emitted when swap adapter is added
     * @param token Token address
     * @param swapAdapter Swap adapter address
     */
    event SwapAdapterAdded(address indexed token, address indexed swapAdapter);

    /**
     * @notice Emitted when swap adapter is removed
     * @param token Token address
     */
    event SwapAdapterRemoved(address indexed token);

    /*------------------------------------------------------------------------*/
    /* Getters */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Get deposit information
     * @param depositor Depositor address
     * @param target Target contract address
     * @param context Context identifier
     * @return token Token address
     * @return amount Amount deposited
     * @return expiration Expiration timestamp
     */
    function depositInfo(
        address depositor,
        address target,
        bytes32 context
    ) external view returns (address token, uint256 amount, uint64 expiration);

    /**
     * @notice Get deposit balance
     * @param depositor Depositor address
     * @param token Token address
     * @return balance Balance
     */
    function depositBalance(address depositor, address token) external view returns (uint256);

    /*------------------------------------------------------------------------*/
    /* Depositor API */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Deposit tokens with timelock
     * @param target Target contract that can withdraw
     * @param context Context identifier
     * @param token Token address
     * @param amount Amount to deposit
     * @param expiration Expiration timestamp
     * @return Token ID
     */
    function deposit(
        address target,
        bytes32 context,
        address token,
        uint256 amount,
        uint64 expiration
    ) external returns (uint256);

    /**
     * @notice Cancel deposit after expiration
     * @param target Target contract
     * @param context Context identifier
     * @return Amount returned
     */
    function cancel(address target, bytes32 context) external returns (uint256);

    /*------------------------------------------------------------------------*/
    /* Withdrawer API */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Withdraw deposit (only callable by target before expiration)
     * @param context Context identifier
     * @param depositor Depositor address
     * @param withdrawToken Token to withdraw
     * @param swapData Swap data
     * @param amount Minimum amount to withdraw
     * @return Withdraw amount
     */
    function withdraw(
        bytes32 context,
        address depositor,
        address withdrawToken,
        bytes calldata swapData,
        uint256 amount
    ) external returns (uint256);

    /*------------------------------------------------------------------------*/
    /* Permissioned API */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Add swap adapter
     * @param token Token address
     * @param swapAdapter Swap adapter address
     */
    function addSwapAdapter(address token, address swapAdapter) external;

    /**
     * @notice Remove swap adapter
     * @param token Token address
     */
    function removeSwapAdapter(
        address token
    ) external;
}
