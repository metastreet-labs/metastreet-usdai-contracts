// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title Base Position Manager Interface
 * @author MetaStreet Foundation
 */
interface IBasePositionManager {
    /*------------------------------------------------------------------------*/
    /* Errors */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Invalid rate
     */
    error InvalidRate();

    /*------------------------------------------------------------------------*/
    /* Events */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Base yield deposited
     * @param usdaiAmount USDai amount
     * @param adminFee Admin fee in USDai
     */
    event BaseYieldDeposited(uint256 usdaiAmount, uint256 adminFee);

    /**
     * @notice Admin fee rate set
     * @param rate Admin fee rate
     */
    event AdminFeeRateSet(uint256 rate);

    /**
     * @notice Admin fee withdrawn
     * @param to Address to withdraw to
     * @param amount Amount to withdraw
     */
    event AdminFeeWithdrawn(address to, uint256 amount);

    /*------------------------------------------------------------------------*/
    /* Getter */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Claimable base yield in USDai
     * @return Claimable base yield in USDai
     */
    function claimableBaseYield() external view returns (uint256);

    /**
     * @notice Admin fee balance and rate
     * @return Admin fee balance
     * @return Admin fee rate
     */
    function adminFee() external view returns (uint256, uint256);

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
     * @return USDai amount
     * @return Admin fee in USDai
     */
    function depositBaseYield(
        uint256 usdaiAmount
    ) external returns (uint256, uint256);

    /**
     * @notice Set admin fee rate
     * @param rate Admin fee rate
     */
    function setAdminFeeRate(
        uint256 rate
    ) external;

    /**
     * @notice Withdraw admin fee
     * @param to Address to withdraw to
     * @param amount Amount to withdraw
     */
    function withdrawAdminFee(address to, uint256 amount) external;
}
