// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {ISwapRouter02, IV3SwapRouter} from "../../src/interfaces/external/ISwapRouter02.sol";

import {ISwapAdapter} from "../interfaces/ISwapAdapter.sol";

/**
 * @title Uniswap V3 Swap Adapter
 * @author MetaStreet Foundation
 */
contract UniswapV3SwapAdapter is ISwapAdapter, AccessControl {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    /*------------------------------------------------------------------------*/
    /* Constants */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Implementation version
     */
    string public constant IMPLEMENTATION_VERSION = "1.0";

    /**
     * @notice Implementation name
     */
    string public constant IMPLEMENTATION_NAME = "Uniswap V3 Swap Adapter";

    /**
     * @notice USD.ai role for access control
     */
    bytes32 internal constant USDAI_ROLE = keccak256("USDAI_ROLE");

    /**
     * @notice Fee for Uniswap V3 swap router (0.01%)
     */
    uint24 internal constant UNISWAP_V3_FEE = 100;

    /**
     * @notice Path address size
     */
    uint256 internal constant PATH_ADDR_SIZE = 20;

    /**
     * @notice Path fee size
     */
    uint256 internal constant PATH_FEE_SIZE = 3;

    /**
     * @notice Path next offset
     */
    uint256 internal constant PATH_NEXT_OFFSET = PATH_ADDR_SIZE + PATH_FEE_SIZE;

    /*------------------------------------------------------------------------*/
    /* Errors */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Invalid token
     */
    error InvalidToken();

    /**
     * @notice Invalid amount
     */
    error InvalidAmount();

    /**
     * @notice Invalid path
     */
    error InvalidPath();

    /**
     * @notice Invalid path format
     */
    error InvalidPathFormat();

    /*------------------------------------------------------------------------*/
    /* Immutable state */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Base token
     */
    IERC20 internal immutable _baseToken;

    /**
     * @notice Swap router
     */
    ISwapRouter02 internal immutable _swapRouter;

    /*------------------------------------------------------------------------*/
    /* State */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Whitelisted tokens
     */
    EnumerableSet.AddressSet internal _whitelistedTokens;

    /*------------------------------------------------------------------------*/
    /* Constructor */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Uniswap V3 Swap Adapter Constructor
     * @param baseToken_ Base token
     * @param swapRouter_ Swap router
     */
    constructor(address baseToken_, address swapRouter_) {
        _baseToken = IERC20(baseToken_);
        _swapRouter = ISwapRouter02(swapRouter_);

        /* Grant roles */
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /*------------------------------------------------------------------------*/
    /* Modifiers */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Non-zero uint
     * @param value Value
     */
    modifier nonZeroUint(
        uint256 value
    ) {
        if (value == 0) revert InvalidAmount();
        _;
    }

    /**
     * @notice Whitelisted token
     * @param value Value
     */
    modifier whitelistedToken(
        address value
    ) {
        if (!_whitelistedTokens.contains(value)) revert InvalidToken();
        _;
    }

    /**
     * @notice Valid swap in path
     * @param tokenInput Input token
     * @param path Path
     */
    modifier validSwapInPath(address tokenInput, bytes calldata path) {
        if (path.length != 0) {
            /* Decode input and output tokens */
            (address tokenInput_, address tokenOutput) = _decodeInputAndOutputTokens(path);

            /* Validate input and output tokens */
            if (tokenInput_ != tokenInput || tokenOutput != address(_baseToken)) {
                revert InvalidPath();
            }
        }
        _;
    }

    /**
     * @notice Valid swap out path
     * @param tokenOutput Output token
     * @param path Path
     */
    modifier validSwapOutPath(address tokenOutput, bytes calldata path) {
        if (path.length != 0) {
            /* Decode input and output tokens */
            (address tokenInput, address tokenOutput_) = _decodeInputAndOutputTokens(path);

            /* Validate input and output tokens */
            if (tokenInput != address(_baseToken) || tokenOutput_ != tokenOutput) {
                revert InvalidPath();
            }
        }

        _;
    }

    /*------------------------------------------------------------------------*/
    /* Getters */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc ISwapAdapter
     */
    function baseToken() external view returns (address) {
        return address(_baseToken);
    }

    /**
     * @notice Whitelisted tokens
     * @return Whitelisted tokens
     */
    function whitelistedTokens() external view returns (address[] memory) {
        return _whitelistedTokens.values();
    }

    /*------------------------------------------------------------------------*/
    /* Helpers */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Decode input and output tokens
     * @param path Swap path
     * @return tokenInput Input token
     * @return tokenOutput Output token
     */
    function _decodeInputAndOutputTokens(
        bytes calldata path
    ) internal pure returns (address, address) {
        /* Validate path format */
        if (
            (path.length < PATH_ADDR_SIZE + PATH_FEE_SIZE + PATH_ADDR_SIZE)
                || ((path.length - PATH_ADDR_SIZE) % PATH_NEXT_OFFSET != 0)
        ) {
            revert InvalidPathFormat();
        }

        /* Get input token */
        address tokenInput = address(bytes20(path[:PATH_ADDR_SIZE]));

        /* Calculate position of output token */
        uint256 numHops = (path.length - PATH_ADDR_SIZE) / PATH_NEXT_OFFSET;
        uint256 outputTokenIndex = numHops * PATH_NEXT_OFFSET;

        /* Get output token */
        address tokenOutput = address(bytes20(path[outputTokenIndex:outputTokenIndex + PATH_ADDR_SIZE]));

        return (tokenInput, tokenOutput);
    }

    /*------------------------------------------------------------------------*/
    /* API */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc ISwapAdapter
     */
    function swapIn(
        address inputToken,
        uint256 inputAmount,
        uint256 minBaseAmount,
        bytes calldata path
    )
        external
        onlyRole(USDAI_ROLE)
        nonZeroUint(inputAmount)
        whitelistedToken(inputToken)
        validSwapInPath(inputToken, path)
        returns (uint256)
    {
        /* Transfer token input from sender to this contract */
        IERC20(inputToken).safeTransferFrom(msg.sender, address(this), inputAmount);

        /* Approve the router to spend token input */
        IERC20(inputToken).forceApprove(address(_swapRouter), inputAmount);

        /* Swap token input for base token */
        uint256 baseAmount;
        if (path.length == 0) {
            /* Define swap params */
            IV3SwapRouter.ExactInputSingleParams memory params = IV3SwapRouter.ExactInputSingleParams({
                tokenIn: address(inputToken),
                tokenOut: address(_baseToken),
                fee: UNISWAP_V3_FEE,
                recipient: msg.sender,
                amountIn: inputAmount,
                amountOutMinimum: minBaseAmount,
                sqrtPriceLimitX96: 0
            });

            /* Swap input token for base token */
            baseAmount = _swapRouter.exactInputSingle(params);
        } else {
            /* Define swap params */
            IV3SwapRouter.ExactInputParams memory params = IV3SwapRouter.ExactInputParams({
                path: path,
                recipient: msg.sender,
                amountIn: inputAmount,
                amountOutMinimum: minBaseAmount
            });

            /* Swap input token for base token */
            baseAmount = _swapRouter.exactInput(params);
        }

        /* Emit SwappedIn event */
        emit SwappedIn(inputToken, inputAmount, baseAmount);

        return baseAmount;
    }

    /**
     * @inheritdoc ISwapAdapter
     */
    function swapOut(
        address outputToken,
        uint256 baseAmount,
        uint256 minOutputAmount,
        bytes calldata path
    )
        external
        onlyRole(USDAI_ROLE)
        nonZeroUint(baseAmount)
        whitelistedToken(outputToken)
        validSwapOutPath(outputToken, path)
        returns (uint256)
    {
        /* Transfer token input from sender to this contract */
        _baseToken.safeTransferFrom(msg.sender, address(this), baseAmount);

        /* Approve the router to spend base token */
        _baseToken.forceApprove(address(_swapRouter), baseAmount);

        /* Swap base token for token output */
        uint256 outputAmount;
        if (path.length == 0) {
            /* Define swap params */
            IV3SwapRouter.ExactInputSingleParams memory params = IV3SwapRouter.ExactInputSingleParams({
                tokenIn: address(_baseToken),
                tokenOut: address(outputToken),
                fee: UNISWAP_V3_FEE,
                recipient: msg.sender,
                amountIn: baseAmount,
                amountOutMinimum: minOutputAmount,
                sqrtPriceLimitX96: 0
            });

            /* Swap base token for token output */
            outputAmount = _swapRouter.exactInputSingle(params);
        } else {
            /* Define swap params */
            IV3SwapRouter.ExactInputParams memory params = IV3SwapRouter.ExactInputParams({
                path: path,
                recipient: msg.sender,
                amountIn: baseAmount,
                amountOutMinimum: minOutputAmount
            });

            /* Swap base token for token output */
            outputAmount = _swapRouter.exactInput(params);
        }

        /* Emit SwappedOut event */
        emit SwappedOut(outputToken, baseAmount, outputAmount);

        return outputAmount;
    }

    /*------------------------------------------------------------------------*/
    /* Admin API */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Set whitelisted tokens
     * @param whitelistedTokens_ Whitelisted tokens
     */
    function setWhitelistedTokens(
        address[] memory whitelistedTokens_
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i; i < whitelistedTokens_.length; i++) {
            if (whitelistedTokens_[i] == address(0)) revert InvalidToken();

            _whitelistedTokens.add(whitelistedTokens_[i]);
        }
    }

    /**
     * @notice Remove whitelisted tokens
     * @param whitelistedTokens_ Whitelisted tokens
     */
    function removeWhitelistedTokens(
        address[] memory whitelistedTokens_
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i; i < whitelistedTokens_.length; i++) {
            if (whitelistedTokens_[i] == address(0)) revert InvalidToken();

            _whitelistedTokens.remove(whitelistedTokens_[i]);
        }
    }
}
