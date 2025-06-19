// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC4626.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/MulticallUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import "./interfaces/IUSDai.sol";
import "./interfaces/IStakedUSDai.sol";

/**
 * @title USDai Utility
 * @author MetaStreet Foundation
 */
contract USDaiUtility is MulticallUpgradeable, ReentrancyGuardUpgradeable, AccessControlUpgradeable {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;

    /*------------------------------------------------------------------------*/
    /* Roles */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Controller admin role
     */
    bytes32 internal constant CONTROLLER_ADMIN_ROLE = keccak256("CONTROLLER_ADMIN_ROLE");

    /*------------------------------------------------------------------------*/
    /* Constants */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Fixed point scale
     */
    uint256 internal constant FIXED_POINT_SCALE = 1e18;

    /**
     * @notice Whitelisted tokens storage location
     * @dev keccak256(abi.encode(uint256(keccak256("usdaiUtility.whitelistedTokens_")) - 1)) & ~bytes32(uint256(0xff));
     */
    bytes32 private constant WHITELISTED_TOKENS_STORAGE_LOCATION =
        0xc6ad599b80e437d86c31abd9e2cd5c6ce030f11e9dbae11bc05446f7af4d4900;

    /**
     * @notice Queue state storage location
     * @dev keccak256(abi.encode(uint256(keccak256("usdaiUtility.queueState_")) - 1)) & ~bytes32(uint256(0xff));
     */
    bytes32 private constant QUEUE_STATE_STORAGE_LOCATION =
        0xc6ad599b80e437d86c31abd9e2cd5c6ce030f11e9dbae11bc05446f7af4d4900;

    /*------------------------------------------------------------------------*/
    /* Immutable state */
    /*------------------------------------------------------------------------*/

    /**
     * @notice USDai token
     */
    IUSDai internal immutable _usdai;

    /**
     * @notice Staked USDai token
     */
    IStakedUSDai internal immutable _stakedUsdai;

    /*------------------------------------------------------------------------*/
    /* Structures */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Queue type
     */
    enum QueueType {
        DEPOSIT,
        DEPOSIT_AND_STAKE
    }

    /**
     * @notice Queue item
     * @dev pendingDeposit Amount of deposit pending to be serviced
     * @dev depositor Address of the depositor
     * @dev recipient Address of the recipient
     */
    struct QueueItem {
        uint256 pendingDeposit;
        address depositor;
        address recipient;
    }

    /**
     * @notice Queue
     * @dev head Queue item at index that will be serviced next
     * @dev pending Total amount of deposit pending to be serviced
     * @dev queue Queue of items
     * @dev queueIndexes Mapping of depositor to queue indexes
     */
    struct Queue {
        uint256 head;
        uint256 pending;
        QueueItem[] queue;
        mapping(address => EnumerableSet.UintSet) queueIndexes;
    }

    /**
     * @custom:storage-location erc7201:usdaiUtility.queueState
     */
    struct QueueState {
        mapping(QueueType => mapping(address => Queue)) queues;
    }

    /**
     * @custom:storage-location erc7201:usdaiUtility.whitelistedTokens
     */
    struct WhitelistedTokens {
        EnumerableSet.AddressSet whitelistedTokens;
    }

    /*------------------------------------------------------------------------*/
    /* Errors */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Insufficient balance
     */
    error InsufficientBalance();

    /**
     * @notice Invalid queue state
     */
    error InvalidQueueState();

    /**
     * @notice Invalid queue type
     */
    error InvalidQueueType();

    /**
     * @notice Invalid token
     */
    error InvalidToken();

    /**
     * @notice Invalid recipient
     */
    error InvalidRecipient();

    /**
     * @notice Invalid amount
     */
    error InvalidAmount();

    /*------------------------------------------------------------------------*/
    /* Events */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Deposit event
     * @param queueType Queue type
     * @param depositToken Deposit token
     * @param queueIndex Queue index
     * @param amount Amount
     * @param recipient Recipient
     */
    event Deposit(
        QueueType indexed queueType,
        address indexed depositToken,
        uint256 indexed queueIndex,
        uint256 amount,
        address recipient
    );

    /**
     * @notice Deposit serviced event
     * @param depositor Depositor
     * @param depositToken Deposit token
     * @param queueIndex Queue index
     * @param servicedDeposit Serviced deposit
     * @param transferAmount Transfer amount
     * @param recipient Recipient
     */
    event DepositServiced(
        address indexed depositor,
        address indexed depositToken,
        uint256 indexed queueIndex,
        uint256 servicedDeposit,
        uint256 transferAmount,
        address recipient
    );

    /**
     * @notice Deposit and stake serviced event
     * @param depositor Depositor
     * @param depositToken Deposit token
     * @param queueIndex Queue index
     * @param servicedDeposit Serviced deposit
     * @param transferAmount Transfer amount
     * @param recipient Recipient
     */
    event DepositAndStakeServiced(
        address indexed depositor,
        address indexed depositToken,
        uint256 indexed queueIndex,
        uint256 servicedDeposit,
        uint256 transferAmount,
        address recipient
    );

    /*------------------------------------------------------------------------*/
    /* Constructor */
    /*------------------------------------------------------------------------*/

    /**
     * @notice sUSDai Constructor
     * @param usdai_ USDai token
     * @param stakedUsdai_ Staked USDai token
     */
    constructor(address usdai_, address stakedUsdai_) {
        _usdai = IUSDai(usdai_);
        _stakedUsdai = IStakedUSDai(stakedUsdai_);

        _disableInitializers();
    }

    /*------------------------------------------------------------------------*/
    /* Initialization  */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Initialize the contract
     * @param admin Default admin address
     * @param whitelistedTokens Whitelisted tokens
     */
    function initialize(address admin, address[] memory whitelistedTokens) external initializer {
        __Multicall_init();
        __ReentrancyGuard_init();
        __AccessControl_init();

        /* Grant roles */
        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        /* Whitelist tokens */
        for (uint256 i; i < whitelistedTokens.length; i++) {
            if (whitelistedTokens[i] == address(0)) revert InvalidToken();

            _getWhitelistedTokensStorage().whitelistedTokens.add(whitelistedTokens[i]);
        }
    }

    /*------------------------------------------------------------------------*/
    /* Internal helpers  */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Get reference to ERC-7201 queue state storage
     *
     * @return $ Reference to queue state storage
     */
    function _getQueueStateStorage() internal pure returns (QueueState storage $) {
        assembly {
            $.slot := QUEUE_STATE_STORAGE_LOCATION
        }
    }

    function _getWhitelistedTokensStorage() internal pure returns (WhitelistedTokens storage $) {
        assembly {
            $.slot := WHITELISTED_TOKENS_STORAGE_LOCATION
        }
    }

    function _deposit(
        bytes memory data
    ) internal {
        /* Decode the message */
        (address depositToken, uint256 serviceAmount, uint256 usdaiAmountMinimum, bytes memory path) =
            abi.decode(data, (address, uint256, uint256, bytes));

        /* Validate deposit token */
        if (!_getWhitelistedTokensStorage().whitelistedTokens.contains(depositToken)) revert InvalidToken();

        /* Validate service amount and usdai amount minimum */
        if (serviceAmount == 0 || usdaiAmountMinimum == 0) revert InvalidAmount();

        /* Validate deposit token balance */
        if (IERC20(depositToken).balanceOf(address(this)) < serviceAmount) revert InsufficientBalance();

        /* Approve the USDai contract to spend the deposit token */
        IERC20(depositToken).forceApprove(address(_usdai), serviceAmount);

        /* Deposit the deposit token */
        uint256 usdaiAmount = _usdai.deposit(depositToken, serviceAmount, usdaiAmountMinimum, address(this), path);

        /* Get queue state */
        Queue storage queue = _getQueueStateStorage().queues[QueueType.DEPOSIT][depositToken];

        uint256 head = queue.head;
        uint256 remainingServiceAmount = serviceAmount;
        while (remainingServiceAmount > 0 && head < queue.queue.length) {
            QueueItem storage item = queue.queue[head];

            uint256 servicedDeposit = Math.min(item.pendingDeposit, remainingServiceAmount);
            uint256 transferAmount = Math.mulDiv(usdaiAmount, servicedDeposit, serviceAmount);

            remainingServiceAmount -= servicedDeposit;
            item.pendingDeposit -= servicedDeposit;

            if (transferAmount != 0) {
                _usdai.transfer(item.recipient, transferAmount);

                emit DepositServiced(
                    item.depositor, depositToken, head, servicedDeposit, transferAmount, item.recipient
                );
            }

            if (item.pendingDeposit == 0) head++;
        }

        /* Validate remaining service amount */
        if (remainingServiceAmount != 0) revert InvalidQueueState();

        /* Update queue state */
        queue.head = head;
        queue.pending -= remainingServiceAmount;
    }

    function _depositAndStake(
        bytes memory data
    ) internal {
        /* Decode the message */
        (address depositToken, uint256 serviceAmount, uint256 usdaiAmountMinimum, bytes memory path, uint256 minShares)
        = abi.decode(data, (address, uint256, uint256, bytes, uint256));

        /* Validate deposit token */
        if (!_getWhitelistedTokensStorage().whitelistedTokens.contains(depositToken)) revert InvalidToken();

        /* Validate service amount and usdai amount minimum */
        if (serviceAmount == 0 || usdaiAmountMinimum == 0) revert InvalidAmount();

        /* Validate deposit token balance */
        if (IERC20(depositToken).balanceOf(address(this)) < serviceAmount) revert InsufficientBalance();

        /* Approve the USDai contract to spend the deposit token */
        IERC20(depositToken).forceApprove(address(_usdai), serviceAmount);

        /* Deposit the deposit token */
        uint256 usdaiAmount = _usdai.deposit(depositToken, serviceAmount, usdaiAmountMinimum, address(this), path);

        /* Approve the staked USDai contract to spend the USDai */
        _usdai.approve(address(_stakedUsdai), usdaiAmount);

        /* Stake the USDai */
        uint256 susdaiAmount = _stakedUsdai.deposit(usdaiAmount, address(this), minShares);

        /* Get queue state */
        Queue storage queue = _getQueueStateStorage().queues[QueueType.DEPOSIT_AND_STAKE][depositToken];

        uint256 head = queue.head;
        uint256 remainingServiceAmount = serviceAmount;
        while (remainingServiceAmount > 0 && head < queue.queue.length) {
            QueueItem storage item = queue.queue[head];

            uint256 servicedDeposit = Math.min(item.pendingDeposit, remainingServiceAmount);
            uint256 transferAmount = Math.mulDiv(susdaiAmount, servicedDeposit, serviceAmount);

            remainingServiceAmount -= servicedDeposit;
            item.pendingDeposit -= servicedDeposit;

            if (transferAmount != 0) {
                IERC20(address(_stakedUsdai)).transfer(item.recipient, transferAmount);

                emit DepositAndStakeServiced(
                    item.depositor, depositToken, head, servicedDeposit, transferAmount, item.recipient
                );
            }

            if (item.pendingDeposit == 0) head++;
        }

        /* Validate remaining service amount */
        if (remainingServiceAmount != 0) revert InvalidQueueState();

        /* Update queue state */
        queue.head = head;
        queue.pending -= remainingServiceAmount;
    }

    /*------------------------------------------------------------------------*/
    /* Getteres  */
    /*------------------------------------------------------------------------*/

    /* TODO: Add getters */

    /*------------------------------------------------------------------------*/
    /* Public API  */
    /*------------------------------------------------------------------------*/

    function deposit(
        address depositToken,
        uint256 amount,
        address recipient,
        QueueType queueType
    ) external nonReentrant {
        /* Validate deposit token */
        if (!_getWhitelistedTokensStorage().whitelistedTokens.contains(depositToken)) revert InvalidToken();

        /* Validate deposit amount */
        if (amount == 0) revert InvalidAmount();

        /* Validate recipient */
        if (recipient == address(0)) revert InvalidRecipient();

        /* Get queue */
        Queue storage queue = _getQueueStateStorage().queues[queueType][depositToken];

        /* Get queue index */
        uint256 queueIndex = queue.queue.length;

        /* Add item to queue */
        queue.queue.push(QueueItem({pendingDeposit: amount, depositor: msg.sender, recipient: recipient}));

        /* Update queue pending */
        queue.pending += amount;

        /* Add item to caller's queue indexes */
        queue.queueIndexes[recipient].add(queueIndex);

        /* Emit Deposit event */
        emit Deposit(queueType, depositToken, queueIndex, amount, recipient);
    }

    /*------------------------------------------------------------------------*/
    /* Permissioned API  */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Service a queue
     * @param queueType Queue type
     * @param data Data
     */
    function service(QueueType queueType, bytes calldata data) external onlyRole(CONTROLLER_ADMIN_ROLE) {
        if (queueType == QueueType.DEPOSIT) {
            _deposit(data);
        } else if (queueType == QueueType.DEPOSIT_AND_STAKE) {
            _depositAndStake(data);
        } else {
            revert InvalidQueueType();
        }
    }
}
