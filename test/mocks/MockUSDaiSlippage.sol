// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockUSDai} from "./MockUSDai.sol";

/**
 * @title Mock USDai with Custom Slippage
 * @author MetaStreet Foundation
 */
contract MockUSDaiSlippage is MockUSDai {
    uint256 internal immutable _SLIPPAGE_RATE;

    constructor(
        uint256 slippageRate_
    ) {
        _SLIPPAGE_RATE = slippageRate_;
    }

    /**
     * @notice Override _deposit to return specific amount
     * @param depositToken Deposit token
     * @param depositAmount Deposit amount
     * @param usdaiAmountMinimum USDai amount minimum
     * @param recipient Recipient address
     * @return USDai amount
     */
    function _deposit(
        address depositToken,
        uint256 depositAmount,
        uint256 usdaiAmountMinimum,
        address recipient,
        bytes calldata
    )
        internal
        override
        nonZeroUint(depositAmount)
        nonZeroUint(usdaiAmountMinimum)
        nonZeroAddress(recipient)
        returns (uint256)
    {
        /* Transfer token in from sender to this contract */
        IERC20(depositToken).transferFrom(msg.sender, address(this), depositAmount);

        /* Return specific amount */
        uint256 slippage = (depositAmount * _SLIPPAGE_RATE) / 1e18;
        uint256 usdaiAmount = depositAmount - slippage - 1;

        /* Check that the USDai amount is greater than the minimum */
        if (usdaiAmount < usdaiAmountMinimum) revert InvalidAmount();

        /* Mint to the recipient */
        _mint(recipient, usdaiAmount);

        /* Emit deposited event */
        emit Deposited(msg.sender, recipient, depositToken, depositAmount, usdaiAmountMinimum);

        return usdaiAmount;
    }
}
