// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title Price Oracle Interface
 * @author MetaStreet Foundation
 */
interface IPriceOracle {
    /*------------------------------------------------------------------------*/
    /* Errors */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Invalid address
     */
    error InvalidAddress();

    /**
     * @notice Invalid length
     */
    error InvalidLength();

    /**
     * @notice Invalid price
     */
    error InvalidPrice();

    /**
     * @notice Unsupported token
     * @param token Token
     */
    error UnsupportedToken(address token);

    /*------------------------------------------------------------------------*/
    /* Getters */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Check if token is supported
     * @param token Token
     * @return True if token is supported, false otherwise
     */
    function supportedToken(
        address token
    ) external view returns (bool);

    /**
     * @notice Get price of token in terms of USDai
     * @param token Token
     */
    function price(
        address token
    ) external view returns (uint256);
}
