// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title Base Position Manager Interface
 * @author MetaStreet Foundation
 */
interface IBasePositionManager {
    /*------------------------------------------------------------------------*/
    /* Events */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Base yield deposited
     * @param usdaiAmount USDai amount
     */
    event BaseYieldDeposited(uint256 usdaiAmount);

    /*------------------------------------------------------------------------*/
    /* Getter */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Claimable base yield in USDai
     * @return Claimable base yield in USDai
     */
    function claimableBaseYield() external view returns (uint256);

    /*------------------------------------------------------------------------*/
    /* Permissioned API */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Claim base yield
     */
    function claimBaseYield() external;

    /**
     * @notice Deposit base yield
     * @param usdaiAmount USDai amount
     * @return USDai amount deposited
     */
    function depositBaseYield(
        uint256 usdaiAmount
    ) external returns (uint256);
}
