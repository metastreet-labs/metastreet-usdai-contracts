// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title USDai Queued Depositor Interface
 * @author MetaStreet Foundation
 */
interface IUSDaiQueuedDepositor {
    /*------------------------------------------------------------------------*/
    /* Structures */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Queue type
     */
    enum QueueType {
        Deposit,
        DepositAndStake
    }

    /**
     * @notice Queue item
     * @dev pendingDeposit Amount of deposit pending to be serviced
     * @dev dstEid Destination EID
     * @dev depositor Address of the depositor
     * @dev recipient Address of the recipient
     */
    struct QueueItem {
        uint256 pendingDeposit;
        uint32 dstEid;
        address depositor;
        address recipient;
    }

    /**
     * @notice Swap type
     */
    enum SwapType {
        Default,
        Aggregator
    }

    /*------------------------------------------------------------------------*/
    /* Errors */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Invalid input
     */
    error InvalidParameters();

    /**
     * @notice Invalid caller
     */
    error InvalidCaller();

    /**
     * @notice Invalid token
     */
    error InvalidToken();

    /**
     * @notice Invalid amount
     */
    error InvalidAmount();

    /**
     * @notice Invalid EIDs
     */
    error InvalidEids(uint32 srcEid, uint32 dstEid);

    /**
     * @notice Invalid share price
     */
    error InvalidSharePrice();

    /**
     * @notice Insufficient balance
     */
    error InsufficientBalance();

    /**
     * @notice Invalid queue state
     */
    error InvalidQueueState();

    /**
     * @notice Invalid recipient
     */
    error InvalidRecipient();

    /**
     * @notice Invalid queue type
     */
    error InvalidQueueType();

    /**
     * @notice Invalid swap type
     */
    error InvalidSwapType();

    /**
     * @notice Invalid slippage
     */
    error InvalidSlippage();

    /**
     * @notice Invalid aggregator swap
     */
    error InvalidAggregatorSwap(bytes reason);

    /*------------------------------------------------------------------------*/
    /* Events */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Deposit event
     * @param queueType Queue type
     * @param depositToken Deposit token
     * @param queueIndex Queue index
     * @param depositor Depositor
     * @param amount Amount
     * @param recipient Recipient
     */
    event Deposit(
        QueueType indexed queueType,
        address indexed depositToken,
        uint256 indexed queueIndex,
        address depositor,
        uint256 amount,
        address recipient
    );

    /**
     * @notice Serviced event
     * @param queueType Queue type
     * @param depositToken Deposit token
     * @param queueIndex Queue index
     * @param depositor Depositor
     * @param servicedDeposit Serviced deposit
     * @param transferAmount Transfer amount
     * @param recipient Recipient
     * @param dstEid Destination EID
     */
    event Serviced(
        QueueType indexed queueType,
        address indexed depositToken,
        uint256 indexed queueIndex,
        address depositor,
        uint256 servicedDeposit,
        uint256 transferAmount,
        address recipient,
        uint32 dstEid
    );

    /**
     * @notice Whitelisted tokens added
     * @param tokens Tokens
     * @param minAmounts Minimum amounts
     */
    event WhitelistedTokensAdded(address[] tokens, uint256[] minAmounts);

    /**
     * @notice Whitelisted tokens removed
     * @param tokens Tokens
     */
    event WhitelistedTokensRemoved(address[] tokens);

    /**
     * @notice Deposit cap updated
     * @param cap Deposit cap
     */
    event DepositCapUpdated(uint256 cap);

    /**
     * @notice Deposit EID whitelist updated
     * @param srcEid Source EID
     * @param dstEid Destination EID
     * @param whitelisted Whitelisted
     */
    event DepositEidWhitelistUpdated(uint32 indexed srcEid, uint32 indexed dstEid, bool whitelisted);

    /**
     * @notice Action failed
     * @param action Action
     * @param reason Reason
     */
    event ActionFailed(string action, bytes reason);

    /*------------------------------------------------------------------------*/
    /* Getters */
    /*------------------------------------------------------------------------*/

    /**
     * @notice USDai
     * @return USDai
     */
    function usdai() external view returns (address);

    /**
     * @notice USDai OAdapter
     * @return USDai OAdapter
     */
    function usdaiOAdapter() external view returns (address);

    /**
     * @notice Staked USDai
     * @return Staked USDai
     */
    function stakedUsdai() external view returns (address);

    /**
     * @notice Staked USDai OAdapter
     * @return Staked USDai OAdapter
     */
    function stakedUsdaiOAdapter() external view returns (address);

    /**
     * @notice Staked USDai
     * /**
     * @notice Whitelisted tokens
     * @return Whitelisted tokens
     */
    function whitelistedTokens() external view returns (address[] memory);

    /**
     * @notice Whitelisted token min amount
     * @param token Token
     * @return Min amount
     */
    function whitelistedTokenMinAmount(
        address token
    ) external view returns (uint256);

    /**
     * @notice Check if a token is whitelisted
     * @param token Token
     * @return True if the token is whitelisted, false otherwise
     */
    function isWhitelistedToken(
        address token
    ) external view returns (bool);

    /**
     * @notice Receipt token implementation
     * @return Receipt token implementation
     */
    function receiptTokenImplementation() external view returns (address);

    /**
     * @notice Queued USDai Token
     * @return Queued USDai Token
     */
    function queuedUSDaiToken() external view returns (address);

    /**
     * @notice Queued Staked USDai Token
     * @return Queued Staked USDai Token
     */
    function queuedStakedUSDaiToken() external view returns (address);

    /**
     * @notice Queue info
     * @param queueType Queue type
     * @param depositToken Deposit token
     * @param offset Offset
     * @param count Count
     * @return head Queue item to be serviced next
     * @return pending Pending amount of deposit to be serviced
     * @return queueItems Queue items
     */
    function queueInfo(
        QueueType queueType,
        address depositToken,
        uint256 offset,
        uint256 count
    ) external view returns (uint256 head, uint256 pending, QueueItem[] memory queueItems);

    /**
     * @notice Queue item
     * @param queueType Queue type
     * @param depositToken Deposit token
     * @param index Index
     * @return Queue item
     */
    function queueItem(
        QueueType queueType,
        address depositToken,
        uint256 index
    ) external view returns (QueueItem memory);

    /**
     * @notice Deposit cap info
     * @return Deposit cap
     * @return Deposit counter
     */
    function depositCapInfo() external view returns (uint256, uint256);

    /**
     * @notice Deposit EID whitelist
     * @param srcEid Source EID
     * @param dstEid Destination EID
     * @return Whitelisted
     */
    function depositEidWhitelist(uint32 srcEid, uint32 dstEid) external view returns (bool);

    /*------------------------------------------------------------------------*/
    /* Public API */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Deposit
     * @param queueType Queue type
     * @param depositToken Deposit token
     * @param amount Amount
     * @param recipient Recipient
     * @param srcEid Source EID
     * @param dstEid Destination EID
     * @return Queue index
     */
    function deposit(
        QueueType queueType,
        address depositToken,
        uint256 amount,
        address recipient,
        uint32 srcEid,
        uint32 dstEid
    ) external returns (uint256);

    /*------------------------------------------------------------------------*/
    /* Permissioned API */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Service a queue
     * @param queueType Queue type
     * @param data Data
     */
    function service(QueueType queueType, bytes calldata data) external payable;

    /**
     * @notice Rescue tokens
     * @param token Token
     * @param to Destination address
     * @param amount Amount of tokens to rescue
     */
    function rescue(address token, address to, uint256 amount) external;

    /**
     * @notice Withdraw ETH
     * @param to Destination address
     * @param amount Amount of ETH to rescue
     */
    function withdrawETH(address to, uint256 amount) external;

    /**
     * @notice Add whitelisted tokens
     * @param tokens Tokens to whitelist
     * @param minAmounts Minimum amounts
     */
    function addWhitelistedTokens(address[] calldata tokens, uint256[] calldata minAmounts) external;

    /**
     * @notice Remove whitelisted tokens
     * @param tokens Tokens to remove
     */
    function removeWhitelistedTokens(
        address[] calldata tokens
    ) external;

    /**
     * @notice Update deposit cap and reset deposit counter
     * @param depositCap Deposit cap
     * @param resetCounter Reset counter
     */
    function updateDepositCap(uint256 depositCap, bool resetCounter) external;

    /**
     * @notice Update deposit cap and reset deposit counter
     * @param srcEid Source EID
     * @param dstEid Destination EID
     * @param whitelisted Whitelisted
     */
    function updateDepositEidWhitelist(uint32 srcEid, uint32 dstEid, bool whitelisted) external;
}
