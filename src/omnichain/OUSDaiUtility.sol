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

import "../interfaces/IUSDai.sol";
import "../interfaces/IStakedUSDai.sol";

/**
 * @title Omnichain Utility
 * @author MetaStreet Foundation
 */
contract OUSDaiUtility is ILayerZeroComposer, ReentrancyGuardUpgradeable, AccessControlUpgradeable {
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
    /* Structures */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Action type
     */
    enum ActionType {
        Deposit,
        DepositAndStake
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
        address stakedUsdaiOAdapter_
    ) {
        _disableInitializers();

        _endpoint = endpoint_;
        _usdai = IUSDai(usdai_);
        _stakedUsdai = IStakedUSDai(stakedUsdai_);
        _usdaiOAdapter = IOFT(usdaiOAdapter_);
        _stakedUsdaiOAdapter = IOFT(stakedUsdaiOAdapter_);
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
     */
    function _deposit(address depositToken, uint256 depositAmount, bytes memory data) internal {
        (uint256 usdaiAmountMinimum, bytes memory path, SendParam memory sendParam, uint256 nativeFee) =
            abi.decode(data, (uint256, bytes, SendParam, uint256));

        /* Get the destination address */
        address to = address(uint160(uint256(sendParam.to)));

        /* Approve the USDai contract to spend the deposit token */
        IERC20(depositToken).forceApprove(address(_usdai), depositAmount);

        try _usdai.deposit(depositToken, depositAmount, usdaiAmountMinimum, address(this), path) returns (
            uint256 usdaiAmount
        ) {
            /* Update the sendParam with the USDai amount */
            sendParam.amountLD = usdaiAmount;

            /* Send the USDai back to source chain */
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
            }
        } catch (bytes memory reason) {
            /* Transfer the deposit token to owner */
            IERC20(depositToken).transfer(to, depositAmount);

            /* Refund the msg.value */
            (bool success,) = payable(to).call{value: msg.value}("");
            success;

            /* Emit the failed action event */
            emit ActionFailed("Deposit", reason);
        }
    }

    /**
     * @notice Deposit and stake the USDai
     * @dev sendParam.to must be an accessible account to receive tokens in the case of action failure
     * @param depositToken Deposit token
     * @param depositAmount Deposit token amount
     * @param data Additional compose data
     */
    function _depositAndStake(address depositToken, uint256 depositAmount, bytes memory data) internal {
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
                }
            } catch (bytes memory reason) {
                /* Transfer the usdai token to owner */
                _usdai.transfer(to, usdaiAmount);

                /* Refund the msg.value */
                (bool success,) = payable(to).call{value: msg.value}("");
                success;

                /* Emit the failed action event */
                emit ActionFailed("Stake", reason);
            }
        } catch (bytes memory reason) {
            /* Transfer the deposit token to owner */
            IERC20(depositToken).transfer(to, depositAmount);

            /* Refund the msg.value */
            (bool success,) = payable(to).call{value: msg.value}("");
            success;

            /* Emit the failed action event */
            emit ActionFailed("Deposit", reason);
        }
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
        } else {
            revert UnknownAction();
        }
    }

    /**
     * @notice Receive ETH
     */
    receive() external payable {}

    /*------------------------------------------------------------------------*/
    /* Permissioned API */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Add whitelisted OAdapters
     * @param oAdapters OAdapters to whitelist
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
     * @notice Remove whitelisted OAdapters
     * @param oAdapters OAdapters to remove
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
     * @notice Rescue tokens
     * @param token Token to rescue
     * @param to Destination address
     * @param amount Amount of tokens to rescue
     */
    function rescue(address token, address to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        IERC20(token).transfer(to, amount);
    }
}
