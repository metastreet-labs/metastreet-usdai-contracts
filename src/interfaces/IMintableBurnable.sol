// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title Mintable Burnable Interface
 * @author MetaStreet Foundation
 */
interface IMintableBurnable {
    /*------------------------------------------------------------------------*/
    /* Minter API */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Mint
     * @param to Account
     * @param amount Amount
     */
    function mint(address to, uint256 amount) external;

    /**
     * @notice Burn
     * @param from Account
     * @param amount Amount
     */
    function burn(address from, uint256 amount) external;
}
