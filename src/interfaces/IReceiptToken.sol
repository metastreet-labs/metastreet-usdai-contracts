// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title Queued Depositor Receipt Token Interface
 * @author MetaStreet Foundation
 */
interface IReceiptToken {
    /*------------------------------------------------------------------------*/
    /* USDai Receipt Token API */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Mint receipt token
     * @param to Account
     * @param amount Amount to mint
     */
    function mint(address to, uint256 amount) external;

    /**
     * @notice Burn receipt token
     * @param from Account
     * @param amount Amount to burn
     */
    function burn(address from, uint256 amount) external;
}
