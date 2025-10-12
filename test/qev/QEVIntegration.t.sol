// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "./QEVBase.t.sol";

/**
 * @title QEV Integration Tests
 * @notice Comprehensive end-to-end integration tests for the complete QEV system
 * @dev Tests realistic workflows, complex scenarios, and edge cases in full system context
 */
contract QEVIntegrationTest is QEVBaseTest {
    /*------------------------------------------------------------------------*/
    /* End-to-End Workflow Tests */
    /*------------------------------------------------------------------------*/

    function test__EndToEnd_CompleteUserJourney_DepositRedeemBidReorderWithdraw() public {
        // Test: Complete user journey from deposit to final withdrawal via QEV

        // === SETUP PHASE ===
        // Users deposit and build positions
        vm.startPrank(user1);
        uint256 user1Shares = stakedUsdaiWithQEV.balanceOf(user1);
        vm.stopPrank();

        vm.startPrank(user2);
        uint256 user2Shares = stakedUsdaiWithQEV.balanceOf(user2);
        vm.stopPrank();

        assertGt(user1Shares, 0, "User1 should have shares from setup");
        assertGt(user2Shares, 0, "User2 should have shares from setup");

        // === REDEMPTION PHASE ===
        // Both users request redemptions
        uint256 redemptionId1 = requestRedemption(user1, 300_000 ether);
        uint256 redemptionId2 = requestRedemption(user2, 400_000 ether);

        // Verify initial queue order (FIFO)
        uint256[] memory initialOrder = new uint256[](2);
        initialOrder[0] = 1;
        initialOrder[1] = 2;
        assertQueueIntegrity(initialOrder);

        // === AUCTION PHASE ===
        uint256 auctionId = qevRegistry.auctionId();

        // User2 bids to jump ahead of user1 (pays 25% fee)
        IQEVRegistry.SignedBid[] memory signedBids = new IQEVRegistry.SignedBid[](1);
        signedBids[0] = createSignedBid(auctionId, redemptionId2, 200_000 ether, 2500, user2PrivateKey);

        // Advance time to end auction period
        advanceAuctionTime(auctionId);

        // Capture NAV before postBids
        uint256 navBefore = stakedUsdaiWithQEV.nav();

        vm.prank(users.manager);
        qevRegistry.postBids(signedBids);

        // Now settle the auction after posting bids
        vm.prank(users.manager);
        qevRegistry.settleAuction();

        // === REORDERING PHASE ===
        vm.prank(users.manager);
        (uint256 pendingSharesBurnt, uint256 adminFee) = stakedUsdaiWithQEV.reorderRedemptions(auctionId, 1);

        // Verify NAV consistency after postBids
        uint256 navAfter = stakedUsdaiWithQEV.nav();
        assertEq(navAfter, navBefore, "NAV should remain consistent after QEV operations");

        // Verify economics: 25% of 200k = 50k bid amount, 1% admin fee = 5k, burnt = 45k
        assertEq(adminFee, 500 ether, "Admin fee should be 1% of bid amount");
        assertEq(pendingSharesBurnt, 49_500 ether, "Should burn 99% of bid amount");

        // Verify user2 jumped ahead with new prioritized redemption
        uint256[] memory reorderedQueue = new uint256[](3);
        reorderedQueue[0] = 3; // User2's new prioritized redemption
        reorderedQueue[1] = 1; // User1's original redemption
        reorderedQueue[2] = 2; // User2's remaining redemption
        assertQueueIntegrity(reorderedQueue);

        // === SERVICE PHASE ===
        // Service redemptions in priority order
        vm.prank(users.manager);
        uint256 amountServiced = stakedUsdaiWithQEV.serviceRedemptions(150_000 ether);

        assertGt(amountServiced, 0, "Should service some redemptions");

        // Advance past timelock
        skipTime(TIMELOCK + 1);

        // === WITHDRAWAL PHASE ===
        // User2 should be able to withdraw first (paid for priority)
        uint256 user2WithdrawableAmount = stakedUsdaiWithQEV.maxWithdraw(user2);
        assertGt(user2WithdrawableAmount, 0, "User2 should have withdrawable amount");

        uint256 maxRedeem = stakedUsdaiWithQEV.maxRedeem(user2);

        vm.prank(user2);
        uint256 withdrawn = stakedUsdaiWithQEV.withdraw(user2WithdrawableAmount, user2, user2);
        assertEq(withdrawn, maxRedeem, "Should withdraw full amount");

        // Verify user1 still waiting (didn't pay for priority)
        uint256 user1WithdrawableAmount = stakedUsdaiWithQEV.maxWithdraw(user1);
        assertEq(user1WithdrawableAmount, 0, "User1 should still be waiting");
    }

    function test__EndToEnd_MultipleAuctionCycles_ComplexReordering() public {
        // Test: Multiple auction cycles with increasing complexity

        // === CYCLE 1: Simple reordering ===
        uint256 redemptionId1 = requestRedemption(user1, 100_000 ether);
        uint256 redemptionId2 = requestRedemption(user2, 150_000 ether);

        uint256 auction1Id = qevRegistry.auctionId();

        IQEVRegistry.SignedBid[] memory bids1 = new IQEVRegistry.SignedBid[](1);
        bids1[0] = createSignedBid(auction1Id, redemptionId2, 100_000 ether, 3000, user2PrivateKey);

        // Advance time to end auction period
        advanceAuctionTime(auction1Id);

        vm.prank(users.manager);
        qevRegistry.postBids(bids1);

        // Now settle the auction after posting bids
        vm.prank(users.manager);
        qevRegistry.settleAuction();

        vm.prank(users.manager);
        stakedUsdaiWithQEV.reorderRedemptions(auction1Id, 1);

        // === CYCLE 2: Add more participants ===
        uint256 redemptionId4 = requestRedemption(user3, 200_000 ether);
        uint256 redemptionId5 = requestRedemption(user1, 120_000 ether); // User1 makes another redemption

        uint256 auction2Id = qevRegistry.auctionId();

        IQEVRegistry.SignedBid[] memory bids2 = new IQEVRegistry.SignedBid[](3);
        bids2[0] = createSignedBid(auction2Id, redemptionId1, 50_000 ether, 5000, user1PrivateKey); // User1 bids on old
            // redemption
        bids2[1] = createSignedBid(auction2Id, redemptionId4, 150_000 ether, 4000, user3PrivateKey); // User3 bids
        bids2[2] = createSignedBid(auction2Id, redemptionId5, 80_000 ether, 2000, user1PrivateKey); // User1 bids on new
            // redemption

        // Advance time to end auction period
        advanceAuctionTime(auction2Id);

        vm.prank(users.manager);
        qevRegistry.postBids(bids2);

        // Now settle the auction after posting bids
        vm.prank(users.manager);
        qevRegistry.settleAuction();

        vm.prank(users.manager);
        stakedUsdaiWithQEV.reorderRedemptions(auction2Id, 3);

        // === CYCLE 3: Service and continue ===
        vm.prank(users.manager);
        stakedUsdaiWithQEV.serviceRedemptions(100_000 ether);

        uint256 redemptionId6 = requestRedemption(user2, 80_000 ether);

        uint256 auction3Id = qevRegistry.auctionId();

        IQEVRegistry.SignedBid[] memory bids3 = new IQEVRegistry.SignedBid[](1);
        bids3[0] = createSignedBid(auction3Id, redemptionId6, 40_000 ether, 6000, user2PrivateKey);

        // Advance time to end auction period
        advanceAuctionTime(auction3Id);

        vm.prank(users.manager);
        qevRegistry.postBids(bids3);

        // Now settle the auction after posting bids
        vm.prank(users.manager);
        qevRegistry.settleAuction();

        vm.prank(users.manager);
        stakedUsdaiWithQEV.reorderRedemptions(auction3Id, 1);

        // Verify system integrity across multiple cycles
        (, uint256 head, uint256 tail, uint256 pending,) = getQueueState();
        assertGt(head, 0, "Queue should have head after multiple cycles");
        assertGt(tail, 0, "Queue should have tail after multiple cycles");
        assertGt(pending, 0, "Should have pending shares");

        // Verify queue structure is maintained
        uint256 redemptionCount = 0;
        uint256 current = head;
        while (current != 0) {
            redemptionCount++;
            (IStakedUSDai.Redemption memory redemption,) = stakedUsdaiWithQEV.redemption(current);
            assertGt(redemption.pendingShares, 0, "All queued redemptions should have pending shares");
            current = redemption.next;
        }

        assertGe(redemptionCount, 3, "Should have multiple redemptions queued");
    }

    /*------------------------------------------------------------------------*/
    /* Stress Testing and Gas Optimization */
    /*------------------------------------------------------------------------*/

    function test__StressTesting_LargeNumberOfRedemptions_BatchProcessing() public {
        // Test: System handles large number of redemptions efficiently

        uint256 numRedemptions = 10;
        uint256[] memory redemptionIds = new uint256[](numRedemptions);

        // Create many redemptions from different users
        for (uint256 i = 0; i < numRedemptions; i++) {
            address user = i % 3 == 0 ? user1 : (i % 3 == 1 ? user2 : user3);
            redemptionIds[i] = requestRedemption(user, 50_000 ether + i * 10_000 ether);
        }

        uint256 auctionId = qevRegistry.auctionId();

        // Create bids for most redemptions
        uint256 numBids = 7;
        IQEVRegistry.SignedBid[] memory signedBids = new IQEVRegistry.SignedBid[](numBids);

        for (uint256 i = 0; i < numBids; i++) {
            uint256 redemptionId = redemptionIds[i];
            uint256 privateKey = i % 3 == 0 ? user1PrivateKey : (i % 3 == 1 ? user2PrivateKey : user3PrivateKey);
            uint256 basisPoint = 5000 - i * 500; // Decreasing basis points
            uint256 bidAmount = 30_000 ether + i * 5_000 ether;

            signedBids[i] = createSignedBid(auctionId, redemptionId, bidAmount, basisPoint, privateKey);
        }

        // Advance time to end auction period
        advanceAuctionTime(auctionId);

        // Capture NAV before postBids
        uint256 navBefore = stakedUsdaiWithQEV.nav();

        // Post bids in batches (simulating gas constraints)
        uint256 batchSize = 3;
        for (uint256 i = 0; i < numBids; i += batchSize) {
            uint256 endIndex = i + batchSize > numBids ? numBids : i + batchSize;
            uint256 currentBatchSize = endIndex - i;

            IQEVRegistry.SignedBid[] memory batch = new IQEVRegistry.SignedBid[](currentBatchSize);
            for (uint256 j = 0; j < currentBatchSize; j++) {
                batch[j] = signedBids[i + j];
            }

            vm.prank(users.manager);
            qevRegistry.postBids(batch);
        }

        // Now settle the auction after posting all bids
        vm.prank(users.manager);
        qevRegistry.settleAuction();

        // Process reordering in batches
        uint256 reorderBatchSize = 2;
        uint256 processedBids = 0;

        while (processedBids < numBids) {
            uint256 remainingBids = numBids - processedBids;
            uint256 currentBatch = remainingBids > reorderBatchSize ? reorderBatchSize : remainingBids;

            vm.prank(users.manager);
            stakedUsdaiWithQEV.reorderRedemptions(auctionId, currentBatch);

            processedBids += currentBatch;
        }

        // Verify final state integrity
        (uint256 bidCount, uint256 processedBidCount,,,) = qevRegistry.auction(auctionId);
        assertEq(processedBidCount, bidCount, "All bids should be processed");

        // Verify queue integrity
        (, uint256 head, uint256 tail,,) = getQueueState();
        assertGt(head, 0, "Queue should have head");
        assertGt(tail, 0, "Queue should have tail");

        // Verify NAV consistency after all operations
        uint256 navAfter = stakedUsdaiWithQEV.nav();
        assertEq(navAfter, navBefore, "NAV should remain consistent after QEV operations");
    }

    /*------------------------------------------------------------------------*/
    /* Economic Incentive Testing */
    /*------------------------------------------------------------------------*/

    function test__Economics_BidPricing_OptimalBidStrategy() public {
        // Test: Economic incentives work correctly for different bid strategies

        uint256 redemptionId1 = requestRedemption(user1, 1_000_000 ether);
        uint256 redemptionId2 = requestRedemption(user2, 1_000_000 ether);
        uint256 redemptionId3 = requestRedemption(user3, 1_000_000 ether);

        // Verify queue order
        uint256[] memory expectedOrder1 = new uint256[](3);
        expectedOrder1[0] = 1; // User1's remaining original redemption
        expectedOrder1[1] = 2; // User2's remaining original redemption
        expectedOrder1[2] = 3; // User3's remaining original redemption
        assertQueueIntegrity(expectedOrder1);

        uint256 auctionId = qevRegistry.auctionId();

        IQEVRegistry.SignedBid[] memory signedBids = new IQEVRegistry.SignedBid[](3);
        signedBids[0] = createSignedBid(auctionId, redemptionId3, 500_000 ether, 5000, user3PrivateKey);
        signedBids[1] = createSignedBid(auctionId, redemptionId2, 500_000 ether, 2500, user2PrivateKey);
        signedBids[2] = createSignedBid(auctionId, redemptionId1, 500_000 ether, 500, user1PrivateKey);

        // Advance time to end auction period
        advanceAuctionTime(auctionId);

        // Capture NAV before postBids
        uint256 navBefore = stakedUsdaiWithQEV.nav();

        vm.prank(users.manager);
        qevRegistry.postBids(signedBids);

        // Now settle the auction after posting bids
        vm.prank(users.manager);
        qevRegistry.settleAuction();

        // Track balances before reordering
        uint256 adminBalanceBefore = stakedUsdaiWithQEV.balanceOf(users.admin);

        vm.prank(users.manager);
        (uint256 totalPendingSharesBurnt, uint256 totalAdminFee) = stakedUsdaiWithQEV.reorderRedemptions(auctionId, 3);

        // Verify queue order reflects bid priority
        uint256[] memory expectedOrder2 = new uint256[](6);
        expectedOrder2[0] = 4; // User3's new redemption (50% bid)
        expectedOrder2[1] = 5; // User2's new redemption (25% bid)
        expectedOrder2[2] = 6; // User1's new redemption (5% bid)
        expectedOrder2[3] = 1; // User1's remaining original redemption
        expectedOrder2[4] = 2; // User2's remaining original redemption
        expectedOrder2[5] = 3; // User3's remaining original redemption
        assertQueueIntegrity(expectedOrder2);

        // Verify NAV consistency after reordering
        uint256 navAfter = stakedUsdaiWithQEV.nav();
        assertEq(navAfter, navBefore, "NAV should remain consistent after QEV operations");

        // Verify economic outcomes
        uint256 expectedTotalBidAmount = 25_000 ether + 125_000 ether + 250_000 ether; // 5% + 25% + 50% of 500k each
        uint256 expectedAdminFee = expectedTotalBidAmount * ADMIN_FEE_RATE / 10_000; // 1% admin fee
        uint256 expectedBurnt = expectedTotalBidAmount - expectedAdminFee; // 90% burnt

        assertEq(totalAdminFee, expectedAdminFee, "Admin fee should match calculation");
        assertEq(totalPendingSharesBurnt, expectedBurnt, "Burnt amount should match calculation");

        // Verify admin received fee shares
        uint256 adminBalanceAfter = stakedUsdaiWithQEV.balanceOf(users.admin);
        assertEq(adminBalanceAfter - adminBalanceBefore, totalAdminFee, "Admin should receive fee shares");

        // Service redemptions to verify priority worked
        vm.prank(users.manager);
        stakedUsdaiWithQEV.serviceRedemptions(200_000 ether);

        // User3 (highest bidder) should be serviced first
        (IStakedUSDai.Redemption memory user3Redemption,) = stakedUsdaiWithQEV.redemption(4);
        assertLt(user3Redemption.pendingShares, 250_000 ether, "User3 should be partially serviced");

        // User1 (lowest bidder) should be unaffected
        (IStakedUSDai.Redemption memory user1Redemption,) = stakedUsdaiWithQEV.redemption(6);
        assertEq(user1Redemption.pendingShares, 475_000 ether, "User1 should be unaffected"); // 500k - 25k bid = 475k
    }

    /*------------------------------------------------------------------------*/
    /* Error Recovery and Edge Cases */
    /*------------------------------------------------------------------------*/

    function test__ErrorRecovery_PartialAuctionFailure_SystemContinuity() public {
        // Test: System continues operating correctly after partial auction failures

        uint256 redemptionId1 = requestRedemption(user1, 100_000 ether);
        uint256 redemptionId2 = requestRedemption(user2, 150_000 ether);

        uint256 auctionId = qevRegistry.auctionId();

        // Post some valid bids
        IQEVRegistry.SignedBid[] memory validBids = new IQEVRegistry.SignedBid[](1);
        validBids[0] = createSignedBid(auctionId, redemptionId1, 50_000 ether, 2000, user1PrivateKey);

        // Advance time to end auction period
        advanceAuctionTime(auctionId);

        // Capture NAV before postBids
        uint256 navBefore = stakedUsdaiWithQEV.nav();

        vm.prank(users.manager);
        qevRegistry.postBids(validBids);

        // Now settle the auction after posting bids
        vm.prank(users.manager);
        qevRegistry.settleAuction();

        // Process partial batch
        vm.prank(users.manager);
        stakedUsdaiWithQEV.reorderRedemptions(auctionId, 1);

        // Start new auction cycle - system should continue normally
        uint256 redemptionId3 = requestRedemption(user3, 200_000 ether);

        uint256 auction2Id = qevRegistry.auctionId();
        assertEq(auction2Id, auctionId + 1, "Next auction should start normally");

        IQEVRegistry.SignedBid[] memory newBids = new IQEVRegistry.SignedBid[](1);
        newBids[0] = createSignedBid(auction2Id, redemptionId3, 100_000 ether, 3000, user3PrivateKey);

        // Advance time to end auction period
        advanceAuctionTime(auction2Id);

        // Capture NAV before postBids
        uint256 navBefore2 = stakedUsdaiWithQEV.nav();

        vm.prank(users.manager);
        qevRegistry.postBids(newBids);

        // Now settle the auction after posting bids
        vm.prank(users.manager);
        qevRegistry.settleAuction();

        vm.prank(users.manager);
        stakedUsdaiWithQEV.reorderRedemptions(auction2Id, 1);

        // Verify system integrity maintained
        (, uint256 head, uint256 tail,,) = getQueueState();
        assertGt(head, 0, "System should continue operating");
        assertGt(tail, 0, "Queue should be maintained");

        // Verify NAV consistency after all operations
        uint256 navAfter = stakedUsdaiWithQEV.nav();
        assertEq(navAfter, navBefore2, "NAV should remain consistent after QEV operations");
    }

    function test__EdgeCases_SimultaneousServiceAndReorder_StateConsistency() public {
        // Test: System maintains consistency when servicing and reordering happen close together

        uint256 redemptionId1 = requestRedemption(user1, 200_000 ether);
        uint256 redemptionId2 = requestRedemption(user2, 300_000 ether);

        // Service some redemptions first
        vm.prank(users.manager);
        stakedUsdaiWithQEV.serviceRedemptions(100_000 ether);

        uint256 auctionId = qevRegistry.auctionId();

        // Post bid for partially serviced redemption
        IQEVRegistry.SignedBid[] memory signedBids = new IQEVRegistry.SignedBid[](1);
        signedBids[0] = createSignedBid(auctionId, redemptionId1, 80_000 ether, 2500, user1PrivateKey);

        // Advance time to end auction period
        advanceAuctionTime(auctionId);

        vm.prank(users.manager);
        qevRegistry.postBids(signedBids);

        // Now settle the auction after posting bids
        vm.prank(users.manager);
        qevRegistry.settleAuction();

        // Service more redemptions right before reordering
        vm.prank(users.manager);
        stakedUsdaiWithQEV.serviceRedemptions(50_000 ether);

        // Capture NAV before postBids
        uint256 navBefore = stakedUsdaiWithQEV.nav();

        // Execute reordering
        vm.prank(users.manager);
        stakedUsdaiWithQEV.reorderRedemptions(auctionId, 1);

        // Verify NAV consistency after reordering
        uint256 navAfter = stakedUsdaiWithQEV.nav();
        assertEq(navAfter, navBefore, "NAV should remain consistent after QEV operations");

        // Verify state consistency
        (, uint256 head, uint256 tail, uint256 pending, uint256 redemptionBalance) = getQueueState();

        assertGt(head, 0, "Queue should have head");
        assertGt(tail, 0, "Queue should have tail");
        assertGt(pending, 0, "Should have pending shares");
        assertGt(redemptionBalance, 0, "Should have redemption balance from servicing");

        // Verify queue integrity
        uint256 redemptionCount = 0;
        uint256 current = head;
        while (current != 0 && redemptionCount < 10) {
            redemptionCount++;
            (IStakedUSDai.Redemption memory redemption,) = stakedUsdaiWithQEV.redemption(current);
            current = redemption.next;
        }

        assertGe(redemptionCount, 1, "Should have redemptions in queue");
    }
}
