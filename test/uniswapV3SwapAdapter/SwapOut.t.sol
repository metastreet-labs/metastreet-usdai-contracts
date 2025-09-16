// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import {BaseTest} from "../Base.t.sol";
import {TestERC20} from "../tokens/TestERC20.sol";
import {UniswapV3SwapAdapter} from "src/swapAdapters/UniswapV3SwapAdapter.sol";

contract SwapAdapterSwapOutTest is BaseTest {
    function testFuzz__SwapAdapterSwapOut(
        uint256 amount
    ) public {
        vm.assume(amount > 0);
        vm.assume(amount <= 10_000_000 ether);

        // Transfer some test USD from the deployer to USDai
        vm.prank(users.deployer);
        /// forge-lint: disable-next-line
        usd.transfer(address(usdai), amount);

        // USDai approves the swap adapter to spend its USD
        vm.prank(address(usdai));
        usd.approve(address(uniswapV3SwapAdapter), amount);

        // USDai swaps in 100 USD for wrapped M
        vm.prank(address(usdai));
        uint256 mAmount = uniswapV3SwapAdapter.swapIn(address(usd), amount, 0, "");

        vm.assume(mAmount > 0);

        // Assert USDai's wrapped M balance increased by mAmount
        assertEq(WRAPPED_M_TOKEN.balanceOf(address(usdai)), mAmount);

        // USDai approves the swap adapter to spend its wrapped M
        vm.prank(address(usdai));
        WRAPPED_M_TOKEN.approve(address(uniswapV3SwapAdapter), mAmount);

        // USDai swaps out mAmount of wrapped M for USD
        vm.prank(address(usdai));
        uint256 usdAmount = uniswapV3SwapAdapter.swapOut(address(usd), mAmount, 0, "");

        // Assert USDai's wrapped M balance decreased by mAmount
        assertEq(WRAPPED_M_TOKEN.balanceOf(address(usdai)), 0);

        // Assert USDai's USD balance increased by usdAmount
        assertEq(usd.balanceOf(address(usdai)), usdAmount);
    }

    function test__SwapAdapterSwapOut_RevertWhen_NonWhitelistedToken() public {
        // Deploy a non-whitelisted token
        vm.prank(address(usdai));
        TestERC20 nonWhitelistedToken = new TestERC20("Non Whitelisted", "NWT", 18, 100 ether);

        // Transfer some test USD from the deployer to USDai
        vm.prank(users.deployer);
        /// forge-lint: disable-next-line
        usd.transfer(address(usdai), 100 ether);

        // USDai approves the swap adapter to spend its USD
        vm.prank(address(usdai));
        usd.approve(address(uniswapV3SwapAdapter), 100 ether);

        // USDai swaps in 100 USD for wrapped M
        vm.prank(address(usdai));
        uint256 mAmount = uniswapV3SwapAdapter.swapIn(address(usd), 100 ether, 0, "");

        // USDai approves the swap adapter to spend its wrapped M
        vm.prank(address(usdai));
        WRAPPED_M_TOKEN.approve(address(uniswapV3SwapAdapter), mAmount);

        // USDai swaps out mAmount of wrapped M for USD
        vm.prank(address(usdai));
        vm.expectRevert(abi.encodeWithSelector(UniswapV3SwapAdapter.InvalidToken.selector));
        uniswapV3SwapAdapter.swapOut(address(nonWhitelistedToken), mAmount, 0, "");
    }

    function testFuzz__SwapAdapterSwapOut_Multihop(
        uint256 amount
    ) public {
        vm.assume(amount > 1 ether);
        vm.assume(amount <= 10_000_000 ether);

        // Add USD2 to whitelist
        address[] memory whitelistedTokens = new address[](1);
        whitelistedTokens[0] = address(usd2);
        vm.prank(users.deployer);
        uniswapV3SwapAdapter.setWhitelistedTokens(whitelistedTokens);

        // Transfer some test USD from the deployer to USDai
        vm.prank(users.deployer);
        /// forge-lint: disable-next-line
        usd.transfer(address(usdai), amount);

        // USDai approves the swap adapter to spend its USD
        vm.prank(address(usdai));
        usd.approve(address(uniswapV3SwapAdapter), amount);

        // USDai swaps in USD for wrapped M
        vm.prank(address(usdai));
        uint256 mAmount = uniswapV3SwapAdapter.swapIn(address(usd), amount, 0, "");

        vm.assume(mAmount > 0);

        // USDai approves the swap adapter to spend its wrapped M
        vm.prank(address(usdai));
        WRAPPED_M_TOKEN.approve(address(uniswapV3SwapAdapter), mAmount);

        // Encode path for wrapped M -> USD -> USD2
        bytes memory path = abi.encodePacked(
            address(WRAPPED_M_TOKEN),
            uint24(100), // 0.01% fee
            address(usd),
            uint24(100), // 0.01% fee
            address(usd2)
        );

        // USDai swaps out wrapped M for USD2 via USD
        vm.prank(address(usdai));
        uint256 usd2Amount = uniswapV3SwapAdapter.swapOut(address(usd2), mAmount, 0, path);

        // Assert usd2Amount is greater than 0
        assertGt(usd2Amount, 0);

        // Assert USDai's wrapped M balance decreased by mAmount
        assertEq(WRAPPED_M_TOKEN.balanceOf(address(usdai)), 0);

        // Assert USDai's USD2 balance increased by usd2Amount
        assertEq(usd2.balanceOf(address(usdai)), usd2Amount);
    }
}
