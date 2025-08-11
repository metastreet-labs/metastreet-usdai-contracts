// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "../Base.t.sol";

contract StakedUSDaiServiceRedemptionsTest is BaseTest {
    uint256 internal initialBalance;
    address internal constant RANDOM_ADDRESS = address(0xdead);

    function setUp() public override {
        super.setUp();

        // User approves USDai to spend their USD
        vm.startPrank(users.normalUser1);
        usd.approve(address(usdai), 10_000_000 ether);

        // User deposits USD into USDai
        initialBalance = usdai.deposit(address(usd), 10_000_000 ether, 0, users.normalUser1);

        // User deposits USDai into StakedUSDai
        usdai.approve(address(stakedUsdai), initialBalance);
        stakedUsdai.deposit(initialBalance, users.normalUser1);

        vm.stopPrank();
    }

    function testFuzz__ServiceRedemptions_WithYield(uint256[5] memory redemptionShares, uint256 yieldAmount) public {
        // Bound redemption amounts to reasonable values
        uint256 totalRedemptions;
        for (uint256 i = 0; i < redemptionShares.length; i++) {
            redemptionShares[i] = bound(redemptionShares[i], 1 ether, 1_000_000 ether);
            totalRedemptions += redemptionShares[i];
        }
        vm.assume(totalRedemptions <= initialBalance);

        // Request multiple redemptions
        vm.startPrank(users.normalUser1);
        for (uint256 i = 0; i < redemptionShares.length; i++) {
            stakedUsdai.requestRedeem(redemptionShares[i], users.normalUser1, users.normalUser1);
        }
        vm.stopPrank();

        // Simulate yield deposit
        yieldAmount = bound(yieldAmount, 1 ether, 10_000 ether);
        simulateYieldDeposit(yieldAmount);

        // Service redemptions in chunks
        uint256 remainingRedemptions = totalRedemptions;
        while (remainingRedemptions > 0) {
            uint256 chunk = remainingRedemptions > 100_000 ether ? 100_000 ether : remainingRedemptions;

            vm.prank(users.manager);
            uint256 processed = stakedUsdai.serviceRedemptions(chunk);

            assertGt(processed, 0, "Should process some redemptions");
            remainingRedemptions -= chunk;
        }

        // Warp past timelock
        vm.warp(block.timestamp + stakedUsdai.timelock() + 1);

        // Verify all redemptions can be redeemed
        vm.startPrank(users.normalUser1);
        for (uint256 i = 0; i < redemptionShares.length; i++) {
            uint256 redeemableAmount = stakedUsdai.redeem(redemptionShares[i], users.normalUser1, users.normalUser1);
            assertGt(redeemableAmount, 0, "Should receive assets");
        }
        vm.stopPrank();

        // Get redemption state info
        (uint256 index, uint256 head, uint256 tail, uint256 pending, uint256 redemptionBalance) =
            stakedUsdai.redemptionQueueInfo();

        // Assert redemption state info
        assertEq(index, 5, "Redemption index should be 5");
        assertEq(head, 0, "Redemption head should be 0");
        assertEq(tail, 5, "Redemption tail should be 5");
        assertEq(pending, 0, "Redemption pending should be 0");
        assertEq(redemptionBalance, 0, "Redemption balance should be total amount");
    }

    function testFuzz__ServiceRedemptions_WithAssetReduction(
        uint256[5] memory redemptionShares,
        uint256 reductionAmount
    ) public {
        // Bound redemption amounts to reasonable values
        uint256 totalRedemptions;
        for (uint256 i = 0; i < redemptionShares.length; i++) {
            redemptionShares[i] = bound(redemptionShares[i], 1 ether, 1_000_000 ether);
            totalRedemptions += redemptionShares[i];
        }
        vm.assume(totalRedemptions <= initialBalance);

        // Request multiple redemptions
        vm.startPrank(users.normalUser1);
        for (uint256 i = 0; i < redemptionShares.length; i++) {
            stakedUsdai.requestRedeem(redemptionShares[i], users.normalUser1, users.normalUser1);
        }
        vm.stopPrank();

        // Simulate asset reduction by transferring out USDai
        reductionAmount = bound(reductionAmount, 0, initialBalance - totalRedemptions);
        vm.startPrank(address(stakedUsdai));
        usdai.transfer(RANDOM_ADDRESS, reductionAmount);
        vm.stopPrank();

        // Service redemptions in chunks
        uint256 remainingRedemptions = totalRedemptions;
        while (remainingRedemptions > 0) {
            uint256 chunk = remainingRedemptions > 100_000 ether ? 100_000 ether : remainingRedemptions;

            vm.prank(users.manager);
            uint256 processed = stakedUsdai.serviceRedemptions(chunk);

            assertGt(processed, 0, "Should process some redemptions");
            remainingRedemptions -= chunk;
        }

        // Warp past timelock
        vm.warp(block.timestamp + stakedUsdai.timelock() + 1);

        // Verify all redemptions can be redeemed
        vm.startPrank(users.normalUser1);
        for (uint256 i = 0; i < redemptionShares.length; i++) {
            uint256 redeemableAmount = stakedUsdai.redeem(redemptionShares[i], users.normalUser1, users.normalUser1);
            assertGt(redeemableAmount, 0, "Should receive assets");
        }
        vm.stopPrank();

        // Get redemption state info
        (uint256 index, uint256 head, uint256 tail, uint256 pending, uint256 redemptionBalance) =
            stakedUsdai.redemptionQueueInfo();

        // Assert redemption state info
        assertEq(index, 5, "Redemption index should be 5");
        assertEq(head, 0, "Redemption head should be 0");
        assertEq(tail, 5, "Redemption tail should be 5");
        assertEq(pending, 0, "Redemption pending should be 0");
        assertEq(redemptionBalance, 0, "Redemption balance should be total amount");
    }

    function test__ServiceRedemptions_RevertWhen_InvalidAmount() public {
        // Try to service redemption with zero amount
        vm.startPrank(users.manager);
        vm.expectRevert(IStakedUSDai.InvalidAmount.selector);
        stakedUsdai.serviceRedemptions(0);
        vm.stopPrank();
    }

    function test__ServiceRedemptions_RevertWhen_NotManager() public {
        // Try to service redemption as non-manager
        vm.startPrank(users.normalUser1);
        vm.expectRevert();
        stakedUsdai.serviceRedemptions(1 ether);
        vm.stopPrank();
    }

    function test__ServiceRedemptions_RevertWhen_InvalidRedemptionState() public {
        // Try to service more shares than pending
        vm.startPrank(users.manager);
        vm.expectRevert(IStakedUSDai.InvalidRedemptionState.selector);
        stakedUsdai.serviceRedemptions(1 ether);
        vm.stopPrank();
    }

    function test__ServiceRedemptions_InterweavedRequestsAndServices() public {
        uint256[] memory amounts = new uint256[](5);
        amounts[0] = 100_000 ether;
        amounts[1] = 200_000 ether;
        amounts[2] = 300_000 ether;
        amounts[3] = 400_000 ether;
        amounts[4] = 500_000 ether;

        // First two redemption requests
        vm.startPrank(users.normalUser1);
        stakedUsdai.requestRedeem(amounts[0], users.normalUser1, users.normalUser1);
        stakedUsdai.requestRedeem(amounts[1], users.normalUser1, users.normalUser1);
        vm.stopPrank();

        // First service redemption (100k)
        vm.prank(users.manager);
        uint256 processed1 = stakedUsdai.serviceRedemptions(100_000 ether);
        assertEq(processed1 > 0, true, "Should process first redemption");

        // Check state after first service
        (uint256 index1, uint256 head1, uint256 tail1, uint256 pending1, uint256 redemptionBalance1) =
            stakedUsdai.redemptionQueueInfo();
        assertEq(index1, 2, "Index should be 2");
        assertEq(head1, 2, "Head should point to second redemption");
        assertEq(tail1, 2, "Tail should be 2");
        assertEq(pending1, 200_000 ether, "Pending should be second redemption amount");
        assertEq(redemptionBalance1, processed1, "Should have redemption balance");

        // Two more redemption requests
        vm.startPrank(users.normalUser1);
        stakedUsdai.requestRedeem(amounts[2], users.normalUser1, users.normalUser1);
        stakedUsdai.requestRedeem(amounts[3], users.normalUser1, users.normalUser1);
        vm.stopPrank();

        // Second service redemption (350k)
        vm.prank(users.manager);
        uint256 processed2 = stakedUsdai.serviceRedemptions(350_000 ether);
        assertEq(processed2 > 0, true, "Should process second batch");

        // Check state after second service
        (uint256 index2, uint256 head2, uint256 tail2, uint256 pending2, uint256 redemptionBalance2) =
            stakedUsdai.redemptionQueueInfo();
        assertEq(index2, 4, "Index should be 4");
        assertEq(head2, 3, "Head should point to third redemption");
        assertEq(tail2, 4, "Tail should be 4");
        assertEq(pending2, 550_000 ether, "Pending should be the sum of processed redemptions");
        assertGt(redemptionBalance2, redemptionBalance1, "Redemption balance should increase");

        // Final redemption request
        vm.startPrank(users.normalUser1);
        stakedUsdai.requestRedeem(amounts[4], users.normalUser1, users.normalUser1);
        vm.stopPrank();

        // Third service redemption (600k)
        vm.prank(users.manager);
        uint256 processed3 = stakedUsdai.serviceRedemptions(600_000 ether);
        assertEq(processed3 > 0, true, "Should process third batch");

        // Check final state
        (uint256 index3, uint256 head3, uint256 tail3, uint256 pending3, uint256 redemptionBalance3) =
            stakedUsdai.redemptionQueueInfo();
        assertEq(index3, 5, "Index should be 5");
        assertEq(head3, 5, "Head should point to fifth redemption");
        assertEq(tail3, 5, "Tail should be 5");
        assertEq(pending3, 450_000 ether, "Should have remaining pending amount");
        assertGt(redemptionBalance3, redemptionBalance2, "Redemption balance should increase");

        // Warp past timelock
        vm.warp(block.timestamp + stakedUsdai.timelock() + 1);

        // Verify serviced redemptions can be redeemed
        vm.startPrank(users.normalUser1);
        stakedUsdai.redeem(1_050_000 ether, users.normalUser1, users.normalUser1);
        vm.stopPrank();

        // Get controller redemptions IDs
        uint256[] memory redemptionIds = stakedUsdai.redemptionIds(address(users.normalUser1));
        uint256 totalPendingShares;
        for (uint256 i; i < redemptionIds.length; i++) {
            (IStakedUSDai.Redemption memory redemption,) = stakedUsdai.redemption(redemptionIds[i]);
            totalPendingShares += redemption.pendingShares;
            assertEq(redemption.redeemableShares, 0, "Should have 0 redeemable shares");
        }
        assertEq(totalPendingShares, 450_000 ether, "Should have remaining pending amount");
    }
}
