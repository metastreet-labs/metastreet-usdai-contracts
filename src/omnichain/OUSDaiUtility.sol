// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroComposer.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/libs/OFTComposeMsgCodec.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFTCore.sol";

import "../interfaces/IOUSDaiUtility.sol";
import "../interfaces/IUSDai.sol";
import "../interfaces/IStakedUSDai.sol";
import "../interfaces/IUSDaiQueuedDepositor.sol";

/**
 * @title Omnichain Utility
 * @author MetaStreet Foundation
 */
contract OUSDaiUtility is ILayerZeroComposer, ReentrancyGuardUpgradeable, AccessControlUpgradeable, IOUSDaiUtility {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    /*------------------------------------------------------------------------*/
    /* Constants */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Implementation version
     */
    string public constant IMPLEMENTATION_VERSION = "1.2";

    /*------------------------------------------------------------------------*/
    /* Immutable state */
    /*------------------------------------------------------------------------*/

    /**
     * @notice The LayerZero endpoint for this contract to interact with
     */
    address internal immutable _endpoint;

    /**
     * @notice The USDai contract on the destination chain
     */
    IUSDai internal immutable _usdai;

    /**
     * @notice The USDai adapter on the destination chain
     */
    IOFT internal immutable _usdaiOAdapter;

    /**
     * @notice The StakedUSDai contract on the destination chain
     */
    IStakedUSDai internal immutable _stakedUsdai;

    /**
     * @notice The StakedUSDai adapter on the destination chain
     */
    IOFT internal immutable _stakedUsdaiOAdapter;

    /**
     * @notice The USDai queued depositor on the destination chain
     */
    IUSDaiQueuedDepositor internal immutable _usdaiQueuedDepositor;

    /*------------------------------------------------------------------------*/
    /* State */
    /*------------------------------------------------------------------------*/

    /**
     * @notice The whitelisted OAdapters
     */
    EnumerableSet.AddressSet internal _whitelistedOAdapters;

    /*------------------------------------------------------------------------*/
    /* Constructor */
    /*------------------------------------------------------------------------*/

    /**
     * @dev Constructs a new PingPong contract instance
     * @param endpoint_ The LayerZero endpoint for this contract to interact with
     * @param usdai_ The USDai contract on the destination chain
     * @param stakedUsdai_ The StakedUSDai contract on the destination chain
     * @param usdaiOAdapter_ The USDai adapter on the destination chain
     * @param stakedUsdaiOAdapter_ The StakedUSDai adapter on the destination chain
     */
    constructor(
        address endpoint_,
        address usdai_,
        address stakedUsdai_,
        address usdaiOAdapter_,
        address stakedUsdaiOAdapter_,
        address usdaiQueuedDepositor_
    ) {
        _disableInitializers();

        _endpoint = endpoint_;
        _usdai = IUSDai(usdai_);
        _stakedUsdai = IStakedUSDai(stakedUsdai_);
        _usdaiOAdapter = IOFT(usdaiOAdapter_);
        _stakedUsdaiOAdapter = IOFT(stakedUsdaiOAdapter_);
        _usdaiQueuedDepositor = IUSDaiQueuedDepositor(usdaiQueuedDepositor_);
    }

    /*------------------------------------------------------------------------*/
    /* Initialization */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Initialize the contract
     * @param admin Default admin address
     * @param oAdapters OAdapters to whitelist
     */
    function initialize(address admin, address[] memory oAdapters) external initializer {
        __ReentrancyGuard_init();
        __AccessControl_init();

        for (uint256 i = 0; i < oAdapters.length; i++) {
            _whitelistedOAdapters.add(oAdapters[i]);
        }

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /*------------------------------------------------------------------------*/
    /* Internal helpers */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Deposit the USDai
     * @dev sendParam.to must be an accessible account to receive tokens in the case of action failure
     * @param depositToken Deposit token
     * @param depositAmount Deposit token amount
     * @param data Additional compose data
     * @return success True if the deposit was successful, false otherwise
     */
    function _deposit(address depositToken, uint256 depositAmount, bytes memory data) internal returns (bool) {
        (uint256 usdaiAmountMinimum, bytes memory path, SendParam memory sendParam, uint256 nativeFee) =
            abi.decode(data, (uint256, bytes, SendParam, uint256));

        /* Get the destination address */
        address to = address(uint160(uint256(sendParam.to)));

        /* Approve the USDai contract to spend the deposit token */
        IERC20(depositToken).forceApprove(address(_usdai), depositAmount);

        try _usdai.deposit(depositToken, depositAmount, usdaiAmountMinimum, address(this), path) returns (
            uint256 usdaiAmount
        ) {
            /* Transfer the USDai to local destination */
            if (sendParam.dstEid == 0) {
                /* Transfer the USDai to recipient */
                _usdai.transfer(to, usdaiAmount);

                /* Emit the deposit event */
                emit ComposerDeposit(sendParam.dstEid, depositToken, to, depositAmount, usdaiAmount);
            } else {
                /* Update the sendParam with the USDai amount */
                sendParam.amountLD = usdaiAmount;

                /* Send the USDai to destination chain */
                try _usdaiOAdapter.send{value: nativeFee}(
                    sendParam, MessagingFee({nativeFee: nativeFee, lzTokenFee: 0}), payable(to)
                ) {
                    /* Emit the deposit event */
                    emit ComposerDeposit(sendParam.dstEid, depositToken, to, depositAmount, usdaiAmount);
                } catch (bytes memory reason) {
                    /* Transfer the usdai to owner */
                    _usdai.transfer(to, usdaiAmount);

                    /* Emit the failed action event */
                    emit ActionFailed("Send", reason);

                    return false;
                }
            }
        } catch (bytes memory reason) {
            /* Transfer the deposit token to owner */
            IERC20(depositToken).transfer(to, depositAmount);

            /* Refund the msg.value */
            (bool success,) = payable(to).call{value: msg.value}("");
            success;

            /* Emit the failed action event */
            emit ActionFailed("Deposit", reason);

            return false;
        }

        return true;
    }

    /**
     * @notice Deposit and stake the USDai
     * @dev sendParam.to must be an accessible account to receive tokens in the case of action failure
     * @param depositToken Deposit token
     * @param depositAmount Deposit token amount
     * @param data Additional compose data
     * @return success True if the deposit and stake was successful, false otherwise
     */
    function _depositAndStake(address depositToken, uint256 depositAmount, bytes memory data) internal returns (bool) {
        /* Decode the message */
        (
            uint256 usdaiAmountMinimum,
            bytes memory path,
            uint256 minShares,
            SendParam memory sendParam,
            uint256 nativeFee
        ) = abi.decode(data, (uint256, bytes, uint256, SendParam, uint256));

        /* Get the destination address */
        address to = address(uint160(uint256(sendParam.to)));

        /* Approve the USDai contract to spend the deposit token */
        IERC20(depositToken).forceApprove(address(_usdai), depositAmount);

        try _usdai.deposit(depositToken, depositAmount, usdaiAmountMinimum, address(this), path) returns (
            uint256 usdaiAmount
        ) {
            /* Approve the staked USDai contract to spend the USDai */
            _usdai.approve(address(_stakedUsdai), usdaiAmount);

            try _stakedUsdai.deposit(usdaiAmount, address(this), minShares) returns (uint256 susdaiAmount) {
                /* Transfer the staked USDai to local destination */
                if (sendParam.dstEid == 0) {
                    /* Transfer the staked USDai to recipient */
                    IERC20(address(_stakedUsdai)).transfer(to, susdaiAmount);

                    /* Emit the deposit and stake event */
                    emit ComposerDepositAndStake(
                        sendParam.dstEid, depositToken, to, depositAmount, usdaiAmount, susdaiAmount
                    );
                } else {
                    /* Update the sendParam with the staked USDai amount */
                    sendParam.amountLD = susdaiAmount;

                    /* Send the staked USDai back to source chain */
                    try _stakedUsdaiOAdapter.send{value: nativeFee}(
                        sendParam, MessagingFee({nativeFee: nativeFee, lzTokenFee: 0}), payable(to)
                    ) {
                        /* Emit the deposit and stake event */
                        emit ComposerDepositAndStake(
                            sendParam.dstEid, depositToken, to, depositAmount, usdaiAmount, susdaiAmount
                        );
                    } catch (bytes memory reason) {
                        /* Transfer the staked USDai to owner */
                        IERC20(address(_stakedUsdai)).transfer(to, susdaiAmount);

                        /* Emit the failed action event */
                        emit ActionFailed("Send", reason);

                        return false;
                    }
                }
            } catch (bytes memory reason) {
                /* Transfer the usdai token to owner */
                _usdai.transfer(to, usdaiAmount);

                /* Refund the msg.value */
                (bool success,) = payable(to).call{value: msg.value}("");
                success;

                /* Emit the failed action event */
                emit ActionFailed("Stake", reason);

                return false;
            }
        } catch (bytes memory reason) {
            /* Transfer the deposit token to owner */
            IERC20(depositToken).transfer(to, depositAmount);

            /* Refund the msg.value */
            (bool success,) = payable(to).call{value: msg.value}("");
            success;

            /* Emit the failed action event */
            emit ActionFailed("Deposit", reason);

            return false;
        }

        return true;
    }

    /**
     * @notice Deposit the deposit token into queue
     * @param depositToken Deposit token
     * @param depositAmount Deposit token amount
     * @param data Additional compose data
     * @return success True if the queue deposit was successful, false otherwise
     */
    function _queuedDeposit(address depositToken, uint256 depositAmount, bytes memory data) internal returns (bool) {
        /* Decode the message */
        (IUSDaiQueuedDepositor.QueueType queueType, address recipient, uint32 dstEid) =
            abi.decode(data, (IUSDaiQueuedDepositor.QueueType, address, uint32));

        /* Approve the queue depositor contract to spend the deposit token */
        IERC20(depositToken).forceApprove(address(_usdaiQueuedDepositor), depositAmount);

        /* Deposit the deposit token into queue depositor */
        try _usdaiQueuedDepositor.deposit(queueType, depositToken, depositAmount, recipient, dstEid) {
            /* Emit the queued deposit event */
            emit ComposerQueuedDeposit(queueType, depositToken, recipient, depositAmount);
        } catch (bytes memory reason) {
            /* Transfer the deposit token to owner */
            IERC20(depositToken).transfer(recipient, depositAmount);

            /* Emit the failed action event */
            emit ActionFailed("QueuedDeposit", reason);

            return false;
        }

        return true;
    }

    /*------------------------------------------------------------------------*/
    /* External API */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Compose a message to be sent to the destination chain
     * @param from Address of the sender
     * @param message Message
     */
    function lzCompose(
        address from,
        bytes32,
        bytes calldata message,
        address,
        bytes calldata
    ) external payable nonReentrant {
        /* Validate from address and endpoint */
        if (!_whitelistedOAdapters.contains(from) || msg.sender != _endpoint) revert InvalidAddress();

        /* Decode the message */
        uint256 amountLD = OFTComposeMsgCodec.amountLD(message);
        bytes memory composeMessage = OFTComposeMsgCodec.composeMsg(message);

        /* Decode the message */
        (ActionType actionType, bytes memory data) = abi.decode(composeMessage, (ActionType, bytes));

        /* Get the deposit token */
        address depositToken = IOFT(from).token();

        /* Decode the message based on the type */
        if (actionType == ActionType.Deposit) {
            _deposit(depositToken, amountLD, data);
        } else if (actionType == ActionType.DepositAndStake) {
            _depositAndStake(depositToken, amountLD, data);
        } else if (actionType == ActionType.QueuedDeposit) {
            _queuedDeposit(depositToken, amountLD, data);
        } else {
            revert UnknownAction();
        }
    }

    /**
     * @inheritdoc IOUSDaiUtility
     */
    function deposit(address depositToken, uint256 depositAmount, bytes memory data) external payable nonReentrant {
        /* Transfer the deposit token to the utility */
        IERC20(depositToken).transferFrom(msg.sender, address(this), depositAmount);

        /* Deposit the deposit token */
        if (!_deposit(depositToken, depositAmount, data)) revert DepositFailed();
    }

    /**
     * @inheritdoc IOUSDaiUtility
     */
    function depositAndStake(
        address depositToken,
        uint256 depositAmount,
        bytes memory data
    ) external payable nonReentrant {
        /* Transfer the deposit token to the utility */
        IERC20(depositToken).transferFrom(msg.sender, address(this), depositAmount);

        /* Deposit and stake */
        if (!_depositAndStake(depositToken, depositAmount, data)) revert DepositAndStakeFailed();
    }

    /**
     * @inheritdoc IOUSDaiUtility
     */
    function queuedDeposit(
        address depositToken,
        uint256 depositAmount,
        bytes memory data
    ) external payable nonReentrant {
        /* Transfer the deposit token to the utility */
        IERC20(depositToken).transferFrom(msg.sender, address(this), depositAmount);

        /* Queue deposit */
        if (!_queuedDeposit(depositToken, depositAmount, data)) revert QueueDepositFailed();
    }

    /**
     * @notice Receive ETH
     */
    receive() external payable {}

    /*------------------------------------------------------------------------*/
    /* Permissioned API */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IOUSDaiUtility
     */
    function addWhitelistedOAdapters(
        address[] memory oAdapters
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < oAdapters.length; i++) {
            _whitelistedOAdapters.add(oAdapters[i]);
        }

        /* Emit whitelisted OAdapters added event */
        emit WhitelistedOAdaptersAdded(oAdapters);
    }

    /**
     * @inheritdoc IOUSDaiUtility
     */
    function removeWhitelistedOAdapters(
        address[] memory oAdapters
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < oAdapters.length; i++) {
            _whitelistedOAdapters.remove(oAdapters[i]);
        }

        /* Emit whitelisted OAdapters removed event */
        emit WhitelistedOAdaptersRemoved(oAdapters);
    }

    /**
     * @inheritdoc IOUSDaiUtility
     */
    function rescue(address token, address to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        IERC20(token).transfer(to, amount);
    }
}
