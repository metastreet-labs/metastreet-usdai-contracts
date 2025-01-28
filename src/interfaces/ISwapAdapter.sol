// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title Swap Adapter Interface
 * @author MetaStreet Foundation
 */
interface ISwapAdapter {
    /*------------------------------------------------------------------------*/
    /* Events */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Swapped in event
     * @param inputToken Input token
     * @param inputAmount Input amount
     * @param baseOutputAmount Base token output amount
     */
    event SwappedIn(address indexed inputToken, uint256 inputAmount, uint256 baseOutputAmount);

    /**
     * @notice Swapped out event
     * @param outputToken Output token
     * @param baseInputAmount Base token input amount
     * @param outputAmount Output amount
     */
    event SwappedOut(address indexed outputToken, uint256 baseInputAmount, uint256 outputAmount);

    /*------------------------------------------------------------------------*/
    /* Getter */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Base token
     * @return Base Token
     */
    function baseToken() external view returns (address);

    /*------------------------------------------------------------------------*/
    /* Permissioned API */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Swap in for base token
     * @param inputToken Input token
     * @param inputAmount Input amount
     * @param minBaseAmount Minimum base token amount
     * @param path Swap path
     * @return Base amount
     */
    function swapIn(
        address inputToken,
        uint256 inputAmount,
        uint256 minBaseAmount,
        bytes calldata path
    ) external returns (uint256);

    /**
     * @notice Swap out of base token
     * @param outputToken Output token
     * @param baseAmount Base token amount
     * @param minOutputAmount Minimum output amount
     * @param path Swap path
     * @return Output amount
     */
    function swapOut(
        address outputToken,
        uint256 baseAmount,
        uint256 minOutputAmount,
        bytes calldata path
    ) external returns (uint256);
}
