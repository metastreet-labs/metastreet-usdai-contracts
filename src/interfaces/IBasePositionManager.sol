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
     * @param depositedAmount Deposited USDai amount
     * @param adminFee Admin fee
     */
    event BaseYieldDeposited(uint256 depositedAmount, uint256 adminFee);

    /*------------------------------------------------------------------------*/
    /* Getter */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Claimable base yield in USDai
     * @return Claimable base yield in USDai
     */
    function claimableBaseYield() external view returns (uint256);

    /**
     * @notice Admin fee rate
     * @return Admin fee rate
     */
    function adminFeeRate() external view returns (uint256);

    /**
     * @notice Admin fee recipient
     * @return Admin fee recipient
     */
    function adminFeeRecipient() external view returns (address);

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
     * @return Deposited USDai amount
     * @return Admin fee
     */
    function depositBaseYield(
        uint256 usdaiAmount
    ) external returns (uint256, uint256);
}
