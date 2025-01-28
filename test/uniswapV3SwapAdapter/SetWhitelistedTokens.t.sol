// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "../Base.t.sol";

contract SwapAdapterSetWhitelistedTokensTest is BaseTest {
    function test__SwapAdapterSetWhitelistedTokens() public {
        // Define the whitelisted tokens
        address[] memory whitelistedTokens = new address[](2);
        whitelistedTokens[0] = address(usd);
        whitelistedTokens[1] = address(0x1234567890123456789012345678901234567890);

        // Set the whitelisted tokens as the deployer
        vm.prank(users.deployer);
        uniswapV3SwapAdapter.setWhitelistedTokens(whitelistedTokens);

        // Get the updated whitelisted tokens
        address[] memory updatedWhitelistedTokens = uniswapV3SwapAdapter.whitelistedTokens();

        // Assert the whitelisted tokens were updated correctly (including WETH & USDT)
        assertEq(updatedWhitelistedTokens.length, 4);
        bool found;
        for (uint256 i; i < updatedWhitelistedTokens.length; i++) {
            if (updatedWhitelistedTokens[i] == 0x1234567890123456789012345678901234567890) {
                found = true;
            }
        }
        assertEq(found, true);
    }

    function test__SwapAdapterRemoveWhitelistedTokens() public {
        // Define the whitelisted tokens
        address[] memory whitelistedTokens = new address[](2);
        whitelistedTokens[0] = address(usd);
        whitelistedTokens[1] = address(0x1234567890123456789012345678901234567890);

        // Set the whitelisted tokens as the deployer
        vm.prank(users.deployer);
        uniswapV3SwapAdapter.setWhitelistedTokens(whitelistedTokens);

        // Assert the whitelisted tokens were added correctly
        assertEq(uniswapV3SwapAdapter.whitelistedTokens().length, 4);

        // Remove the whitelisted tokens as the deployer
        vm.prank(users.deployer);
        uniswapV3SwapAdapter.removeWhitelistedTokens(whitelistedTokens);

        // Get the updated whitelisted tokens
        address[] memory updatedWhitelistedTokens = uniswapV3SwapAdapter.whitelistedTokens();

        // Assert the whitelisted tokens were removed correctly
        assertEq(updatedWhitelistedTokens.length, 2);
    }
}
