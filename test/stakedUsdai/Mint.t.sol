// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "../Base.t.sol";

contract StakedUSDaiMintTest is BaseTest {
    uint256 internal initialBalance;

    function setUp() public override {
        super.setUp();

        // User approves USDai to spend their USD
        vm.startPrank(users.normalUser1);
        usd.approve(address(usdai), 10_000_000 ether);

        // User deposits USD into USDai
        initialBalance = usdai.deposit(address(usd), 10_000_000 ether, 0, users.normalUser1);

        vm.stopPrank();
    }

    function testFuzz__StakedUSDaiMint(
        uint256 shares
    ) public {
        vm.assume(shares > 1e6);
        vm.assume(shares <= initialBalance - 1e6);

        uint256 initialAssets = stakedUsdai.totalAssets();

        // Calculate expected assets needed
        uint256 expectedAssets = stakedUsdai.convertToAssets(shares);
        uint256 previewMint = stakedUsdai.previewMint(shares);

        // Assert preview mint matches expected assets
        assertEq(previewMint, expectedAssets);

        // User approves StakedUSDai to spend their USDai
        vm.startPrank(users.normalUser1);
        usdai.approve(address(stakedUsdai), expectedAssets);

        // User mints StakedUSDai shares
        stakedUsdai.mint(shares, users.normalUser1);

        // Assert user's StakedUSDai balance is shares
        assertEq(stakedUsdai.balanceOf(users.normalUser1), shares, "Shares mismatch");

        // Assert user's USDai balance decreased by expected assets
        assertEq(usdai.balanceOf(users.normalUser1), initialBalance - expectedAssets, "USDai balance mismatch");

        // Assert total assets increased
        assertEq(stakedUsdai.totalAssets(), initialAssets + expectedAssets, "Total assets mismatch");

        vm.stopPrank();
    }

    function testFuzz__StakedUSDaiMint_SharePriceConsistencyMultipleMints(
        uint256[5] memory depositAmounts
    ) public {
        // First make a proper initial deposit to get past LOCKED_SHARES
        vm.startPrank(users.normalUser1);
        usd.approve(address(usdai), 1_000_000 ether);
        usdai.deposit(address(usd), 1_000_000 ether, 0, users.normalUser1);
        uint256 sharesToMint = 1_000_000 ether - 1e6;
        uint256 expectedAssets = stakedUsdai.convertToAssets(sharesToMint);
        usdai.approve(address(stakedUsdai), expectedAssets);
        stakedUsdai.mint(sharesToMint, users.normalUser1);
        vm.stopPrank();

        // Track share prices for each deposit
        uint256[] memory sharePrices = new uint256[](depositAmounts.length);

        // Make multiple deposits with different amounts
        for (uint256 i = 0; i < depositAmounts.length; i++) {
            // Bound deposit amount to reasonable range
            depositAmounts[i] = bound(depositAmounts[i], 1 ether, 1_000_000 ether);

            vm.startPrank(users.normalUser2);
            usd.approve(address(usdai), depositAmounts[i]);
            uint256 usdaiBalance = usdai.deposit(address(usd), depositAmounts[i], 0, users.normalUser2);

            uint256 shares = stakedUsdai.convertToShares(usdaiBalance);
            usdai.approve(address(stakedUsdai), usdaiBalance);
            uint256 assets = stakedUsdai.mint(shares, users.normalUser2);
            vm.stopPrank();

            // Calculate and store share price
            sharePrices[i] = (assets * 1e18) / shares;

            // If not first deposit, verify share price is consistent
            if (i > 1) {
                uint256 priceDiff = sharePrices[i] > sharePrices[i - 1]
                    ? sharePrices[i] - sharePrices[i - 1]
                    : sharePrices[i - 1] - sharePrices[i];
                assertLt(priceDiff, 1, "Share prices should remain consistent");
            }
        }
    }

    function test__StakedUSDaiMint_RevertWhen_ZeroShares() public {
        vm.startPrank(users.normalUser1);
        vm.expectRevert(IStakedUSDai.InvalidAmount.selector);
        stakedUsdai.mint(0, users.normalUser1);
        vm.stopPrank();
    }

    function test__StakedUSDaiMint_RevertWhen_InvalidAmount() public {
        vm.startPrank(users.normalUser1);
        vm.expectRevert(IStakedUSDai.InvalidAmount.selector);
        stakedUsdai.mint(0, users.normalUser1, 1);
        vm.stopPrank();
    }

    function test__StakedUSDaiMint_RevertWhen_ZeroAddress() public {
        vm.startPrank(users.normalUser1);
        vm.expectRevert(IStakedUSDai.InvalidAddress.selector);
        stakedUsdai.mint(1 ether, address(0));
        vm.stopPrank();
    }

    function test__StakedUSDaiMint_RevertWhen_Blacklisted() public {
        vm.prank(users.deployer);
        stakedUsdai.setBlacklist(users.normalUser1, true);

        vm.startPrank(users.normalUser1);
        vm.expectRevert(abi.encodeWithSelector(IStakedUSDai.BlacklistedAddress.selector, users.normalUser1));
        stakedUsdai.mint(1 ether, users.normalUser1);
        vm.stopPrank();
    }

    function test__StakedUSDaiMint_RevertWhen_Paused() public {
        // Pause contract
        vm.prank(users.deployer);
        stakedUsdai.pause();

        vm.startPrank(users.normalUser1);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        stakedUsdai.mint(1 ether, users.normalUser1);
        vm.stopPrank();
    }
}
