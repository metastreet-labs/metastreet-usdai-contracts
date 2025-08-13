// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/interfaces/IERC4626.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Create2.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardTransientUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/MulticallUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import {IOFT as IOFT_, SendParam, MessagingFee} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFTCore.sol";

import "./ReceiptToken.sol";

import "src/interfaces/IUSDai.sol";
import {IStakedUSDai as IStakedUSDai_} from "src/interfaces/IStakedUSDai.sol";
import "src/interfaces/IUSDaiQueuedDepositor.sol";

/**
 * @title IOFT (extension of LayerZero's IOFT)
 * @author MetaStreet Foundation
 */
interface IOFT is IOFT_ {
    function decimalConversionRate() external view returns (uint256);
}

/**
 * @title IStakedUSDai (extension of IStakedUSDai)
 * @author MetaStreet Foundation
 */
interface IStakedUSDai is IStakedUSDai_ {
    function transfer(address to, uint256 amount) external returns (bool);
}

/**
 * @title USDai Queued Depositor
 * @author MetaStreet Foundation
 */
contract USDaiQueuedDepositor is
    MulticallUpgradeable,
    ReentrancyGuardTransientUpgradeable,
    AccessControlUpgradeable,
    IUSDaiQueuedDepositor
{
    using OptionsBuilder for bytes;
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

    /**
     * @notice Gas limit
     */
    uint128 internal constant GAS_LIMIT = 200_000;

    /*------------------------------------------------------------------------*/
    /* Constants */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Fixed point scale
     */
    uint256 internal constant FIXED_POINT_SCALE = 1e18;

    /**
     * @notice Whitelisted tokens storage location
     * @dev keccak256(abi.encode(uint256(keccak256("usdaiQueuedDepositor.whitelistedTokens")) - 1)) &
     * ~bytes32(uint256(0xff));
     */
    bytes32 private constant WHITELISTED_TOKENS_STORAGE_LOCATION =
        0xae8373c513d60a87649c929c9ed639f44732aae4408e77a19fe920d679776700;

    /**
     * @notice Queue state storage location
     * @dev keccak256(abi.encode(uint256(keccak256("usdaiQueuedDepositor.queueState")) - 1)) & ~bytes32(uint256(0xff));
     */
    bytes32 private constant QUEUE_STATE_STORAGE_LOCATION =
        0xde17916dd48def670a35b2a4d73c98b59c767a72e42b298050b9c5cddd25fa00;

    /**
     * @notice Receipt tokens storage location
     * @dev keccak256(abi.encode(uint256(keccak256("usdaiQueuedDepositor.receiptTokens")) - 1)) &
     * ~bytes32(uint256(0xff));
     */
    bytes32 private constant RECEIPT_TOKENS_STORAGE_LOCATION =
        0x0b1935fa33a5b9486fb92ab02635f3c9d624ac3df1e1ee01c88d6052bb824d00;

    /*------------------------------------------------------------------------*/
    /* Immutable state */
    /*------------------------------------------------------------------------*/

    /**
     * @notice USDai token
     */
    IUSDai internal immutable _usdai;

    /**
     * @notice USDai OAdapter
     */
    IOFT internal immutable _usdaiOAdapter;

    /**
     * @notice Staked USDai token
     */
    IStakedUSDai internal immutable _stakedUsdai;

    /**
     * @notice Staked USDai OAdapter
     */
    IOFT internal immutable _stakedUsdaiOAdapter;

    /**
     * @notice USDai OAdapter decimal conversion rate
     */
    uint256 internal immutable _usdaiDecimalConversionRate;

    /**
     * @notice Staked USDai OAdapter decimal conversion rate
     */
    uint256 internal immutable _stakedUsdaiDecimalConversionRate;

    /**
     * @notice Receipt token implementation
     */
    address internal immutable _receiptTokenImplementation;

    /*------------------------------------------------------------------------*/
    /* State */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Receipt token
     */
    ReceiptToken internal _queuedUSDaiToken;

    /**
     * @notice Queued deposit receipt token
     */
    ReceiptToken internal _queuedStakedUSDaiToken;

    /*------------------------------------------------------------------------*/
    /* Structures */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Queue
     * @dev head Queue item at index that will be serviced next
     * @dev pending Total amount of deposit pending to be serviced
     * @dev queue Queue of items
     */
    struct Queue {
        uint256 head;
        uint256 pending;
        QueueItem[] queue;
    }

    /**
     * @custom:storage-location erc7201:usdaiQueuedDepositor.queueState
     */
    struct QueueState {
        mapping(QueueType => mapping(address => Queue)) queues;
    }

    /**
     * @custom:storage-location erc7201:usdaiQueuedDepositor.whitelistedTokens
     */
    struct WhitelistedTokens {
        EnumerableSet.AddressSet whitelistedTokens;
        mapping(address => uint256) minAmounts;
    }

    /**
     * @custom:storage-location erc7201:usdaiQueuedDepositor.receiptTokens
     */
    struct ReceiptTokens {
        ReceiptToken queuedUSDaiToken;
        ReceiptToken queuedStakedUSDaiToken;
    }

    /*------------------------------------------------------------------------*/
    /* Constructor */
    /*------------------------------------------------------------------------*/

    /**
     * @notice sUSDai Constructor
     * @param usdai_ USDai token
     * @param stakedUsdai_ Staked USDai token
     * @param usdaiOAdapter_ USDai OAdapter
     * @param stakedUsdaiOAdapter_ Staked USDai OAdapter
     * @param receiptTokenImplementation_ Receipt token implementation
     */
    constructor(
        address usdai_,
        address stakedUsdai_,
        address usdaiOAdapter_,
        address stakedUsdaiOAdapter_,
        address receiptTokenImplementation_
    ) {
        _usdai = IUSDai(usdai_);
        _stakedUsdai = IStakedUSDai(stakedUsdai_);

        _usdaiOAdapter = IOFT(usdaiOAdapter_);
        _stakedUsdaiOAdapter = IOFT(stakedUsdaiOAdapter_);

        _usdaiDecimalConversionRate = _usdaiOAdapter.decimalConversionRate();
        _stakedUsdaiDecimalConversionRate = _stakedUsdaiOAdapter.decimalConversionRate();

        _receiptTokenImplementation = receiptTokenImplementation_;

        _disableInitializers();
    }

    /*------------------------------------------------------------------------*/
    /* Initialization  */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Initialize the contract
     * @param admin Default admin address
     * @param whitelistedTokens_ Whitelisted tokens
     * @param minAmounts Minimum amounts
     */
    function initialize(
        address admin,
        address[] memory whitelistedTokens_,
        uint256[] memory minAmounts
    ) external initializer {
        /* Validate input */
        if (whitelistedTokens_.length != minAmounts.length) revert InvalidParameters();

        /* Initialize dependencies */
        __Multicall_init();
        __ReentrancyGuardTransient_init();
        __AccessControl_init();

        /* Whitelist tokens */
        for (uint256 i; i < whitelistedTokens_.length; i++) {
            if (whitelistedTokens_[i] == address(0)) revert InvalidToken();
            _getWhitelistedTokensStorage().whitelistedTokens.add(whitelistedTokens_[i]);
            _getWhitelistedTokensStorage().minAmounts[whitelistedTokens_[i]] = minAmounts[i];
        }

        /* Get receipt tokens storage */
        ReceiptTokens storage receiptTokens = _getReceiptTokensStorage();

        /* Deploy queued USDai receipt token */
        receiptTokens.queuedUSDaiToken = _createReceiptTokenProxy("Queued USDai", "qUSDai");

        /* Deploy queued staked USDai receipt token */
        receiptTokens.queuedStakedUSDaiToken = _createReceiptTokenProxy("Queued Staked USDai", "qsUSDai");

        /* Grant roles */
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
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

    /**
     * @notice Get reference to ERC-7201 whitelisted tokens storage
     *
     * @return $ Reference to whitelisted tokens storage
     */
    function _getWhitelistedTokensStorage() internal pure returns (WhitelistedTokens storage $) {
        assembly {
            $.slot := WHITELISTED_TOKENS_STORAGE_LOCATION
        }
    }

    /**
     * @notice Get reference to ERC-7201 receipt tokens storage
     *
     * @return $ Reference to receipt tokens storage
     */
    function _getReceiptTokensStorage() internal pure returns (ReceiptTokens storage $) {
        assembly {
            $.slot := RECEIPT_TOKENS_STORAGE_LOCATION
        }
    }

    /**
     * @notice Create a receipt token proxy
     * @param name Token name
     * @param symbol Token symbol
     * @return ReceiptToken The deployed receipt token proxy
     */
    function _createReceiptTokenProxy(string memory name, string memory symbol) internal returns (ReceiptToken) {
        address proxy = address(
            new ERC1967Proxy(
                address(_receiptTokenImplementation), abi.encodeWithSignature("initialize(string,string)", name, symbol)
            )
        );
        return ReceiptToken(proxy);
    }

    /**
     * @notice Remove dust from the amount
     * @param amountLD Amount in local decimals
     * @param isUsdai Whether the amount is USDai
     * @return Amount in local decimals after removing dust
     */
    function _removeDust(uint256 amountLD, bool isUsdai) internal view virtual returns (uint256) {
        uint256 decimalConversionRate = isUsdai ? _usdaiDecimalConversionRate : _stakedUsdaiDecimalConversionRate;

        return (amountLD / decimalConversionRate) * decimalConversionRate;
    }

    /**
     * @notice Transfer USDai or sUSDai locally
     * @dev Try-catch to prevent denial-of-service due to blacklisted accounts
     * @param queueType Queue type
     * @param recipient Recipient
     * @param transferAmount Transfer amount
     */
    function _transferLocal(QueueType queueType, address recipient, uint256 transferAmount) internal {
        if (queueType == QueueType.Deposit) {
            try _usdai.transfer(recipient, transferAmount) {}
            catch (bytes memory reason) {
                /* Emit the failed action event */
                emit ActionFailed("USDai local transfer", reason);
            }
        } else {
            try _stakedUsdai.transfer(recipient, transferAmount) {}
            catch (bytes memory reason) {
                /* Emit the failed action event */
                emit ActionFailed("Staked USDai local transfer", reason);
            }
        }
    }

    /**
     * @notice Transfer the USDai or sUSDai to the recipient
     * @param queueType Queue type
     * @param item Queue item
     * @param transferAmount Transfer amount
     */
    function _transfer(QueueType queueType, QueueItem memory item, uint256 transferAmount) internal {
        /* If the transfer amount is 0, return */
        if (transferAmount == 0) return;

        /* If the destination EID is 0, transfer is local */
        if (item.dstEid == 0) {
            /* Transfer the USDai or sUSDai to the recipient */
            _transferLocal(queueType, item.recipient, transferAmount);

            return;
        }

        /* Get the OAdapter */
        IOFT oAdapter = queueType == QueueType.Deposit ? _usdaiOAdapter : _stakedUsdaiOAdapter;

        /* Build send param */
        SendParam memory sendParam = SendParam({
            dstEid: item.dstEid,
            to: bytes32(uint256(uint160(item.recipient))),
            amountLD: transferAmount,
            minAmountLD: _removeDust(transferAmount, queueType == QueueType.Deposit),
            extraOptions: OptionsBuilder.newOptions().addExecutorLzReceiveOption(GAS_LIMIT, 0),
            composeMsg: "",
            oftCmd: ""
        });

        /* Quote send */
        MessagingFee memory fee = oAdapter.quoteSend(sendParam, false);

        /* Validate that the contract has enough balance to cover the native fee */
        if (address(this).balance < fee.nativeFee) revert InsufficientBalance();

        /* Send */
        try oAdapter.send{value: fee.nativeFee}(sendParam, fee, payable(address(this))) {}
        catch (bytes memory reason) {
            /* Transfer the USDai or sUSDai to the recipient */
            _transferLocal(queueType, item.recipient, transferAmount);

            /* Emit the failed action event */
            emit ActionFailed("Send", reason);
        }
    }

    /**
     * @notice Deposit USDai
     * @param depositToken Deposit token
     * @param serviceAmount Service amount
     * @param usdaiAmountMinimum USDai amount minimum
     * @param path Path
     * @return USDai amount
     */
    function _depositUsdai(
        address depositToken,
        uint256 serviceAmount,
        uint256 usdaiAmountMinimum,
        bytes memory path
    ) internal returns (uint256) {
        /* Validate deposit token */
        if (!_getWhitelistedTokensStorage().whitelistedTokens.contains(depositToken)) revert InvalidToken();

        /* Validate service amount and usdai amount minimum */
        if (serviceAmount == 0 || usdaiAmountMinimum == 0) revert InvalidAmount();

        /* Approve the USDai contract to spend the deposit token */
        IERC20(depositToken).forceApprove(address(_usdai), serviceAmount);

        /* Deposit the deposit token */
        return _usdai.deposit(depositToken, serviceAmount, usdaiAmountMinimum, address(this), path);
    }

    /**
     * @notice Process queue
     * @param queueType Queue type
     * @param depositToken Deposit token
     * @param serviceAmount Service amount
     * @param amount Amount
     */
    function _processQueue(QueueType queueType, address depositToken, uint256 serviceAmount, uint256 amount) internal {
        /* Get queue state */
        Queue storage queue = _getQueueStateStorage().queues[queueType][depositToken];

        uint256 head = queue.head;
        uint256 remainingServiceAmount = serviceAmount;
        while (remainingServiceAmount > 0 && head < queue.queue.length) {
            QueueItem storage item = queue.queue[head];

            /* Calculate serviced deposit and transfer amount */
            uint256 servicedDeposit = Math.min(item.pendingDeposit, remainingServiceAmount);
            uint256 transferAmount = Math.mulDiv(amount, servicedDeposit, serviceAmount);

            /* Burn receipt token. Note: unable to cache outside while loop due to stack too deep error */
            queueType == QueueType.Deposit
                ? _getReceiptTokensStorage().queuedUSDaiToken.burn(item.recipient, servicedDeposit)
                : _getReceiptTokensStorage().queuedStakedUSDaiToken.burn(item.recipient, servicedDeposit);

            /* Update remaining service amount */
            remainingServiceAmount -= servicedDeposit;
            item.pendingDeposit -= servicedDeposit;

            /* Transfer the USDai or sUSDai to the recipient */
            _transfer(queueType, item, transferAmount);

            /* Emit the serviced event */
            emit Serviced(
                queueType,
                depositToken,
                head,
                item.depositor,
                servicedDeposit,
                transferAmount,
                item.recipient,
                item.dstEid
            );

            /* Update head */
            if (item.pendingDeposit == 0) head++;
        }

        /* Validate remaining service amount */
        if (remainingServiceAmount != 0) revert InvalidQueueState();

        /* Update queue state */
        queue.head = head;
        queue.pending -= serviceAmount;
    }

    /**
     * @notice Deposit token to mint USDai
     * @param data Data
     */
    function _deposit(
        bytes memory data
    ) internal {
        /* Decode the message */
        (address depositToken, uint256 serviceAmount, uint256 usdaiAmountMinimum, bytes memory path) =
            abi.decode(data, (address, uint256, uint256, bytes));

        /* Validate service amount is more than or equal to the pending deposit */
        if (_getQueueStateStorage().queues[QueueType.Deposit][depositToken].pending < serviceAmount) {
            revert InvalidAmount();
        }

        /* Deposit USDai */
        uint256 usdaiAmount = _depositUsdai(depositToken, serviceAmount, usdaiAmountMinimum, path);

        /* Process queue */
        _processQueue(QueueType.Deposit, depositToken, serviceAmount, usdaiAmount);
    }

    /**
     * @notice Deposit token to mint USDai and then stake USDai
     * @param data Data
     */
    function _depositAndStake(
        bytes memory data
    ) internal {
        /* Decode the message */
        (address depositToken, uint256 serviceAmount, uint256 usdaiAmountMinimum, bytes memory path, uint256 minShares)
        = abi.decode(data, (address, uint256, uint256, bytes, uint256));

        /* Validate service amount is more than or equal to the pending deposit and min shares is not 0 */
        if (
            _getQueueStateStorage().queues[QueueType.DepositAndStake][depositToken].pending < serviceAmount
                || minShares == 0
        ) revert InvalidAmount();

        /* Deposit USDai */
        uint256 usdaiAmount = _depositUsdai(depositToken, serviceAmount, usdaiAmountMinimum, path);

        /* Approve the staked USDai contract to spend the USDai */
        _usdai.approve(address(_stakedUsdai), usdaiAmount);

        /* Stake the USDai */
        uint256 susdaiAmount = _stakedUsdai.deposit(usdaiAmount, address(this), minShares);

        /* Process queue */
        _processQueue(QueueType.DepositAndStake, depositToken, serviceAmount, susdaiAmount);
    }

    /*------------------------------------------------------------------------*/
    /* Getters  */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IUSDaiQueuedDepositor
     */
    function usdai() external view returns (address) {
        return address(_usdai);
    }

    /**
     * @inheritdoc IUSDaiQueuedDepositor
     */
    function usdaiOAdapter() external view returns (address) {
        return address(_usdaiOAdapter);
    }

    /**
     * @inheritdoc IUSDaiQueuedDepositor
     */
    function stakedUsdai() external view returns (address) {
        return address(_stakedUsdai);
    }

    /**
     * @inheritdoc IUSDaiQueuedDepositor
     */
    function stakedUsdaiOAdapter() external view returns (address) {
        return address(_stakedUsdaiOAdapter);
    }

    /**
     * @inheritdoc IUSDaiQueuedDepositor
     */
    function whitelistedTokens() external view returns (address[] memory) {
        return _getWhitelistedTokensStorage().whitelistedTokens.values();
    }

    /**
     * @inheritdoc IUSDaiQueuedDepositor
     */
    function isWhitelistedToken(
        address token
    ) external view returns (bool) {
        return _getWhitelistedTokensStorage().whitelistedTokens.contains(token);
    }

    /**
     * @inheritdoc IUSDaiQueuedDepositor
     */
    function whitelistedTokenMinAmount(
        address token
    ) external view returns (uint256) {
        return _getWhitelistedTokensStorage().minAmounts[token];
    }

    /**
     * @inheritdoc IUSDaiQueuedDepositor
     */
    function receiptTokenImplementation() external view returns (address) {
        return address(_receiptTokenImplementation);
    }

    /**
     * @inheritdoc IUSDaiQueuedDepositor
     */
    function queuedUSDaiToken() external view returns (address) {
        return address(_getReceiptTokensStorage().queuedUSDaiToken);
    }

    /**
     * @inheritdoc IUSDaiQueuedDepositor
     */
    function queuedStakedUSDaiToken() external view returns (address) {
        return address(_getReceiptTokensStorage().queuedStakedUSDaiToken);
    }

    /**
     * @inheritdoc IUSDaiQueuedDepositor
     */
    function queueInfo(
        QueueType queueType,
        address depositToken,
        uint256 offset,
        uint256 count
    ) external view returns (uint256, uint256, QueueItem[] memory) {
        Queue storage queue = _getQueueStateStorage().queues[queueType][depositToken];

        /* Clamp on count */
        count = Math.min(count, queue.queue.length - offset);

        /* Create arrays */
        QueueItem[] memory queueItems = new QueueItem[](count);

        /* Fill array */
        for (uint256 i = offset; i < offset + count; i++) {
            queueItems[i - offset] = queue.queue[i];
        }

        return (queue.head, queue.pending, queueItems);
    }

    /**
     * @inheritdoc IUSDaiQueuedDepositor
     */
    function queueItem(
        QueueType queueType,
        address depositToken,
        uint256 index
    ) external view returns (QueueItem memory) {
        return _getQueueStateStorage().queues[queueType][depositToken].queue[index];
    }

    /*------------------------------------------------------------------------*/
    /* Public API  */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IUSDaiQueuedDepositor
     * @dev LayerZero endpoint ID for testnets follows 40xxx, and mainnets follows 30xxx
     */
    function deposit(
        QueueType queueType,
        address depositToken,
        uint256 amount,
        address recipient,
        uint32 dstEid
    ) external nonReentrant returns (uint256) {
        /* Validate deposit token */
        if (!_getWhitelistedTokensStorage().whitelistedTokens.contains(depositToken)) revert InvalidToken();

        /* Validate deposit amount */
        if (amount == 0 || _getWhitelistedTokensStorage().minAmounts[depositToken] > amount) revert InvalidAmount();

        /* Validate recipient */
        if (recipient == address(0)) revert InvalidRecipient();

        /* Transfer the deposit token to the queue depositor */
        IERC20(depositToken).transferFrom(msg.sender, address(this), amount);

        /* Get queue */
        Queue storage queue = _getQueueStateStorage().queues[queueType][depositToken];

        /* Get queue index */
        uint256 queueIndex = queue.queue.length;

        /* Add item to queue */
        queue.queue.push(
            QueueItem({pendingDeposit: amount, depositor: msg.sender, recipient: recipient, dstEid: dstEid})
        );

        /* Update queue pending */
        queue.pending += amount;

        /* Mint receipt token */
        if (queueType == QueueType.Deposit) {
            _getReceiptTokensStorage().queuedUSDaiToken.mint(recipient, amount);
        } else if (queueType == QueueType.DepositAndStake) {
            _getReceiptTokensStorage().queuedStakedUSDaiToken.mint(recipient, amount);
        } else {
            revert InvalidQueueType();
        }

        /* Emit Deposit event */
        emit Deposit(queueType, depositToken, queueIndex, msg.sender, amount, recipient);

        return queueIndex;
    }

    /*------------------------------------------------------------------------*/
    /* Permissioned API  */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IUSDaiQueuedDepositor
     */
    function service(
        QueueType queueType,
        bytes calldata data
    ) external payable nonReentrant onlyRole(CONTROLLER_ADMIN_ROLE) {
        if (queueType == QueueType.Deposit) {
            _deposit(data);
        } else if (queueType == QueueType.DepositAndStake) {
            _depositAndStake(data);
        } else {
            revert InvalidQueueType();
        }
    }

    /**
     * @inheritdoc IUSDaiQueuedDepositor
     */
    function rescue(address token, address to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        IERC20(token).transfer(to, amount);
    }

    /**
     * @inheritdoc IUSDaiQueuedDepositor
     */
    function withdrawETH(address to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        (bool success,) = to.call{value: amount}("");
        success;
    }

    /**
     * @inheritdoc IUSDaiQueuedDepositor
     */
    function addWhitelistedTokens(
        address[] memory tokens,
        uint256[] memory minAmounts
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        /* Validate input */
        if (tokens.length != minAmounts.length) revert InvalidParameters();

        /* Set whitelisted tokens */
        for (uint256 i; i < tokens.length; i++) {
            if (tokens[i] == address(0)) revert InvalidToken();
            _getWhitelistedTokensStorage().whitelistedTokens.add(tokens[i]);
            _getWhitelistedTokensStorage().minAmounts[tokens[i]] = minAmounts[i];
        }

        /* Emit whitelisted tokens added event */
        emit WhitelistedTokensAdded(tokens, minAmounts);
    }

    /**
     * @inheritdoc IUSDaiQueuedDepositor
     */
    function removeWhitelistedTokens(
        address[] memory tokens
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i; i < tokens.length; i++) {
            _getWhitelistedTokensStorage().whitelistedTokens.remove(tokens[i]);
            _getWhitelistedTokensStorage().minAmounts[tokens[i]] = 0;
        }

        /* Emit whitelisted tokens removed event */
        emit WhitelistedTokensRemoved(tokens);
    }
}
