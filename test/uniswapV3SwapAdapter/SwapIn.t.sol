// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import {BaseTest} from "../Base.t.sol";
import {TestERC20} from "../tokens/TestERC20.sol";
import {UniswapV3SwapAdapter} from "src/swapAdapters/UniswapV3SwapAdapter.sol";

contract SwapAdapterSwapInTest is BaseTest {
    function testFuzz__SwapAdapterSwapIn(
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

        // Assert USDai's wrapped M balance increased by mAmount
        assertEq(WRAPPED_M_TOKEN.balanceOf(address(usdai)), mAmount);

        // Assert USDai's USD balance decreased by 100
        assertEq(usd.balanceOf(address(usdai)), 0);
    }

    function test__SwapAdapterSwapIn_RevertWhen_NonWhitelistedToken() public {
        // Deploy a non-whitelisted token
        vm.prank(address(usdai));
        TestERC20 nonWhitelistedToken = new TestERC20("Non Whitelisted", "NWT", 18, 100 ether);

        // USDai approves the swap adapter to spend the non-whitelisted tokens
        vm.prank(address(usdai));
        nonWhitelistedToken.approve(address(uniswapV3SwapAdapter), 100 ether);

        // Attempt to swap in the non-whitelisted tokens, expecting a revert
        vm.prank(address(usdai));
        vm.expectRevert(abi.encodeWithSelector(UniswapV3SwapAdapter.InvalidToken.selector));
        uniswapV3SwapAdapter.swapIn(address(nonWhitelistedToken), 100 ether, 0, "");
    }

    function test__SwapAdapterSwapIn_RevertWhen_InsufficientUSDai() public {
        uint256 amount = 100 ether;

        // Transfer some test USD from the deployer to USDai
        vm.prank(users.deployer);
        /// forge-lint: disable-next-line
        usd.transfer(address(usdai), amount);

        // USDai approves the swap adapter to spend its USD
        vm.prank(address(usdai));
        usd.approve(address(uniswapV3SwapAdapter), amount);

        // USDai swaps in 100 USD for wrapped M
        vm.prank(address(usdai));
        vm.expectRevert();
        uniswapV3SwapAdapter.swapIn(address(usd), amount, amount, "");
    }

    function testFuzz__SwapAdapterSwapIn_Multihop(
        uint256 amount
    ) public {
        vm.assume(amount > 1 ether);
        vm.assume(amount <= 10_000_000 ether);

        // Add USD2 to whitelist
        address[] memory whitelistedTokens = new address[](1);
        whitelistedTokens[0] = address(usd2);
        vm.prank(users.deployer);
        uniswapV3SwapAdapter.setWhitelistedTokens(whitelistedTokens);

        // Transfer some test USD2 from the deployer to USDai
        vm.prank(users.deployer);
        /// forge-lint: disable-next-line
        usd2.transfer(address(usdai), amount);

        // USDai approves the swap adapter to spend its USD2
        vm.prank(address(usdai));
        usd2.approve(address(uniswapV3SwapAdapter), amount);

        // Encode path for USD2 -> USD -> wrapped M
        bytes memory path = abi.encodePacked(
            address(usd2),
            uint24(100), // 0.01% fee
            address(usd),
            uint24(100), // 0.01% fee
            address(WRAPPED_M_TOKEN)
        );

        // USDai swaps in USD2 for wrapped M via USD
        vm.prank(address(usdai));
        uint256 mAmount = uniswapV3SwapAdapter.swapIn(address(usd2), amount, 0, path);

        // Assert mAmount is greater than 0
        assertGt(mAmount, 0);

        // Assert USDai's wrapped M balance increased by mAmount
        assertEq(WRAPPED_M_TOKEN.balanceOf(address(usdai)), mAmount);

        // Assert USDai's USD2 balance decreased by amount
        assertEq(usd2.balanceOf(address(usdai)), 0);
    }
}
