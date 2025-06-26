// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "./QEVBase.t.sol";
import "src/QEVLogic.sol";

/**
 * @title QEV Logic Tests
 * @notice Comprehensive tests for QEVLogic queue reordering and integrity
 * @dev Tests queue integrity across various states, partial processing, and multiple auction cycles
 */
contract QEVLogicTest is QEVBaseTest {
    /*------------------------------------------------------------------------*/
    /* Queue Integrity Tests - Empty Queue Scenarios */
    /*------------------------------------------------------------------------*/

    function test__QueueIntegrity_EmptyQueue_CannotReorderWithoutRedemptions() public {
        // Test: Reordering fails when queue is completely empty
        uint256 auctionId = startAuction();

        advanceAuctionTime(auctionId);

        // Now settle the auction after posting bids
        vm.prank(users.manager);
        qevRegistry.settleAuction();

        vm.expectRevert();
        vm.prank(users.manager);
        stakedUsdaiWithQEV.reorderRedemptions(auctionId, 1);
    }

    function test__QueueIntegrity_EmptyQueue_CannotReorderWithoutBids() public {
        // Test: Reordering fails when there are no bids in settled auction
        uint256 redemptionId = requestRedemption(user1, 100_000 ether);
        uint256 auctionId = qevRegistry.auctionId();

        advanceAuctionTime(auctionId);

        // Now settle the auction after posting bids
        vm.prank(users.manager);
        qevRegistry.settleAuction();

        vm.expectRevert();
        vm.prank(users.manager);
        stakedUsdaiWithQEV.reorderRedemptions(auctionId, 1);
    }

    /*------------------------------------------------------------------------*/
    /* Queue Integrity Tests - Basic Reordering */
    /*------------------------------------------------------------------------*/

    function test__QueueIntegrity_BasicReordering_SingleBidFullAmount() public {
        // Test: Single bid for full redemption amount maintains queue integrity
        uint256 redemptionId = requestRedemption(user1, 100_000 ether);
        uint256 auctionId = qevRegistry.auctionId();

        // Post bid for full amount
        IQEVRegistry.SignedBid[] memory signedBids = new IQEVRegistry.SignedBid[](1);
        signedBids[0] = createSignedBid(auctionId, redemptionId, 100_000 ether, 1000, user1PrivateKey);

        advanceAuctionTime(auctionId);

        vm.prank(users.manager);
        qevRegistry.postBids(signedBids);

        // Now settle the auction after posting bids
        vm.prank(users.manager);
        qevRegistry.settleAuction();

        // Verify initial queue state
        uint256[] memory initialOrder = new uint256[](1);
        initialOrder[0] = redemptionId;
        assertQueueIntegrity(initialOrder);

        // Execute reordering
        vm.prank(users.manager);
        (uint256 pendingSharesBurnt, uint256 adminFee) = stakedUsdaiWithQEV.reorderRedemptions(auctionId, 1);

        // Verify queue integrity maintained (redemption moves to head)
        assertQueueIntegrity(initialOrder);

        // Verify shares were burnt correctly (1% of 10k = 100 burnt)
        assertEq(pendingSharesBurnt, 9_900 ether, "Should burn 99% of bid amount");
        assertEq(adminFee, 100 ether, "Should collect 1% admin fee");

        // Verify redemption was updated
        (IStakedUSDai.Redemption memory redemption,) = stakedUsdaiWithQEV.redemption(redemptionId);
        assertEq(redemption.pendingShares, 90_000 ether, "Pending shares reduced by bid amount");
    }

    function test__QueueIntegrity_BasicReordering_SingleBidPartialAmount() public {
        // Test: Single bid for partial redemption amount creates new redemption and maintains integrity
        uint256 redemptionId = requestRedemption(user1, 100_000 ether);
        uint256 auctionId = qevRegistry.auctionId();

        // Post bid for partial amount
        IQEVRegistry.SignedBid[] memory signedBids = new IQEVRegistry.SignedBid[](1);
        signedBids[0] = createSignedBid(auctionId, redemptionId, 60_000 ether, 2000, user1PrivateKey);

        advanceAuctionTime(auctionId);

        vm.prank(users.manager);
        qevRegistry.postBids(signedBids);

        // Now settle the auction after posting bids
        vm.prank(users.manager);
        qevRegistry.settleAuction();

        // Execute reordering
        vm.prank(users.manager);
        (uint256 pendingSharesBurnt, uint256 adminFee) = stakedUsdaiWithQEV.reorderRedemptions(auctionId, 1);

        // Verify new redemption was created (index incremented to 2)
        (, uint256 head, uint256 tail,,) = getQueueState();
        assertEq(head, 2, "New redemption should be at head");
        assertEq(tail, 1, "Original redemption should be at tail");

        // Verify queue integrity with new structure
        uint256[] memory expectedOrder = new uint256[](2);
        expectedOrder[0] = 2; // New prioritized redemption
        expectedOrder[1] = 1; // Original redemption with reduced amount
        assertQueueIntegrity(expectedOrder);

        // Verify redemption amounts
        (IStakedUSDai.Redemption memory originalRedemption,) = stakedUsdaiWithQEV.redemption(1);
        (IStakedUSDai.Redemption memory newRedemption,) = stakedUsdaiWithQEV.redemption(2);

        assertEq(originalRedemption.pendingShares, 40_000 ether, "Original redemption reduced by bid amount");
        assertEq(newRedemption.pendingShares, 48_000 ether, "New redemption = bid amount - admin fee"); // 60k - 12k fee
            // = 48k

        // Verify burn amounts (20% of 60k = 12k)
        assertEq(pendingSharesBurnt, 11_880 ether, "Should burn 99% of bid amount");
        assertEq(adminFee, 120 ether, "Should collect 1% admin fee");
    }

    function test__QueueIntegrity_BasicReordering_MultipleBidsFromSameRedemption() public {
        // Test: Cannot have multiple bids from same redemption in single auction
        uint256 redemptionId = requestRedemption(user1, 100_000 ether);
        uint256 auctionId = qevRegistry.auctionId();

        // Post first bid
        IQEVRegistry.SignedBid[] memory firstBid = new IQEVRegistry.SignedBid[](2);
        firstBid[0] = createSignedBid(auctionId, redemptionId, 50_000 ether, 2000, user1PrivateKey);
        firstBid[1] = createSignedBid(auctionId, redemptionId, 50_000 ether, 1000, user1PrivateKey);

        advanceAuctionTime(auctionId);

        vm.expectRevert(abi.encodeWithSelector(IQEVRegistry.DuplicateBid.selector, 1));
        vm.prank(users.manager);
        qevRegistry.postBids(firstBid);
    }

    /*------------------------------------------------------------------------*/
    /* Queue Integrity Tests - Multiple Redemptions */
    /*------------------------------------------------------------------------*/

    function test__QueueIntegrity_MultipleRedemptions_AllBidsProcessed() public {
        // Test: Multiple redemptions with bids are reordered correctly maintaining queue integrity
        uint256 redemptionId1 = requestRedemption(user1, 100_000 ether);
        uint256 redemptionId2 = requestRedemption(user2, 150_000 ether);
        uint256 redemptionId3 = requestRedemption(user3, 80_000 ether);
        uint256 auctionId = qevRegistry.auctionId();

        // Verify initial queue order (FIFO)
        uint256[] memory initialOrder = new uint256[](3);
        initialOrder[0] = 1; // user1 first
        initialOrder[1] = 2; // user2 second
        initialOrder[2] = 3; // user3 third
        assertQueueIntegrity(initialOrder);

        // Post bids with different priorities
        IQEVRegistry.SignedBid[] memory signedBids = new IQEVRegistry.SignedBid[](3);
        signedBids[0] = createSignedBid(auctionId, redemptionId3, 80_000 ether, 5000, user3PrivateKey); // 50% - highest
        signedBids[1] = createSignedBid(auctionId, redemptionId1, 100_000 ether, 3000, user1PrivateKey); // 30% - middle
        signedBids[2] = createSignedBid(auctionId, redemptionId2, 150_000 ether, 1000, user2PrivateKey); // 10% - lowest

        advanceAuctionTime(auctionId);

        vm.prank(users.manager);
        qevRegistry.postBids(signedBids);

        // Now settle the auction after posting bids
        vm.prank(users.manager);
        qevRegistry.settleAuction();

        // Execute reordering
        vm.prank(users.manager);
        stakedUsdaiWithQEV.reorderRedemptions(auctionId, 3);

        // Verify new queue order (ordered by bid basis point)
        uint256[] memory reorderedQueue = new uint256[](3);
        reorderedQueue[0] = 3; // user3 (50% bid) - highest priority
        reorderedQueue[1] = 1; // user1 (30% bid) - middle priority
        reorderedQueue[2] = 2; // user2 (10% bid) - lowest priority
        assertQueueIntegrity(reorderedQueue);

        // Verify all redemptions were updated with reduced pending shares
        (IStakedUSDai.Redemption memory redemption1,) = stakedUsdaiWithQEV.redemption(1);
        (IStakedUSDai.Redemption memory redemption2,) = stakedUsdaiWithQEV.redemption(2);
        (IStakedUSDai.Redemption memory redemption3,) = stakedUsdaiWithQEV.redemption(3);

        assertEq(redemption1.pendingShares, 70_000 ether, "User1 pending reduced by bid"); // 100k - 30k bid
        assertEq(redemption2.pendingShares, 135_000 ether, "User2 pending reduced by bid"); // 150k - 15k bid
        assertEq(redemption3.pendingShares, 40_000 ether, "User3 pending reduced by bid"); // 80k - 40k bid
    }

    function test__QueueIntegrity_MultipleRedemptions_MixedBidsAndNonBids() public {
        // Test: Queue with some redemptions having bids and others not maintains integrity
        uint256 redemptionId1 = requestRedemption(user1, 100_000 ether);
        uint256 redemptionId2 = requestRedemption(user2, 150_000 ether); // No bid
        uint256 redemptionId3 = requestRedemption(user3, 80_000 ether);
        uint256 auctionId = qevRegistry.auctionId();

        // Post bids only for user1 and user3
        IQEVRegistry.SignedBid[] memory signedBids = new IQEVRegistry.SignedBid[](2);
        signedBids[0] = createSignedBid(auctionId, redemptionId3, 50_000 ether, 4000, user3PrivateKey); // 40%
        signedBids[1] = createSignedBid(auctionId, redemptionId1, 75_000 ether, 2000, user1PrivateKey); // 20%

        advanceAuctionTime(auctionId);

        vm.prank(users.manager);
        qevRegistry.postBids(signedBids);

        // Now settle the auction after posting bids
        vm.prank(users.manager);
        qevRegistry.settleAuction();

        // Execute reordering
        vm.prank(users.manager);
        stakedUsdaiWithQEV.reorderRedemptions(auctionId, 2);

        // Verify queue order: bid redemptions move to front, non-bid stays in original position
        uint256[] memory expectedOrder = new uint256[](5);
        expectedOrder[0] = 4; // user3's new prioritized redemption (40% bid) - highest priority
        expectedOrder[1] = 5; // user1's new prioritized redemption (20% bid) - middle priority
        expectedOrder[2] = 1; // user1's remaining original redemption
        expectedOrder[3] = 2; // user2's original redemption (no bid) - remains in original position
        expectedOrder[4] = 3; // user3's remaining original redemption
        assertQueueIntegrity(expectedOrder);

        // Verify only bid redemptions were modified
        (IStakedUSDai.Redemption memory redemption1,) = stakedUsdaiWithQEV.redemption(1);
        (IStakedUSDai.Redemption memory redemption2,) = stakedUsdaiWithQEV.redemption(2);
        (IStakedUSDai.Redemption memory redemption3,) = stakedUsdaiWithQEV.redemption(3);

        assertEq(redemption1.pendingShares, 25_000 ether, "User1 pending reduced by bid");
        assertEq(redemption2.pendingShares, 150_000 ether, "User2 pending unchanged (no bid)");
        assertEq(redemption3.pendingShares, 30_000 ether, "User3 pending reduced by bid");
    }

    /*------------------------------------------------------------------------*/
    /* Queue Integrity Tests - Partial Processing */
    /*------------------------------------------------------------------------*/

    function test__QueueIntegrity_PartialProcessing_MultipleCallsForSameAuction() public {
        // Test: Processing bids in multiple calls maintains queue integrity
        uint256[] memory redemptionIds = new uint256[](6);
        for (uint256 i = 0; i < 6; i++) {
            redemptionIds[i] = requestRedemption(i < 2 ? user1 : (i < 4 ? user2 : user3), 100_000 ether);
        }

        uint256 auctionId = qevRegistry.auctionId();

        // Post bids for all redemptions in order of basis points (highest to lowest)
        IQEVRegistry.SignedBid[] memory signedBids = new IQEVRegistry.SignedBid[](6);
        signedBids[0] = createSignedBid(auctionId, redemptionIds[0], 50_000 ether, 6000, user1PrivateKey); // 60%
        signedBids[1] = createSignedBid(auctionId, redemptionIds[1], 50_000 ether, 5000, user1PrivateKey); // 50%
        signedBids[2] = createSignedBid(auctionId, redemptionIds[2], 50_000 ether, 4000, user2PrivateKey); // 40%
        signedBids[3] = createSignedBid(auctionId, redemptionIds[3], 50_000 ether, 3000, user2PrivateKey); // 30%
        signedBids[4] = createSignedBid(auctionId, redemptionIds[4], 50_000 ether, 2000, user3PrivateKey); // 20%
        signedBids[5] = createSignedBid(auctionId, redemptionIds[5], 50_000 ether, 1000, user3PrivateKey); // 10%

        advanceAuctionTime(auctionId);

        vm.prank(users.manager);
        qevRegistry.postBids(signedBids);

        // Now settle the auction after posting bids
        vm.prank(users.manager);
        qevRegistry.settleAuction();

        // Process in multiple batches
        vm.prank(users.manager);
        stakedUsdaiWithQEV.reorderRedemptions(auctionId, 3); // First 3 bids

        vm.prank(users.manager);
        stakedUsdaiWithQEV.reorderRedemptions(auctionId, 2); // Next 2 bids

        vm.prank(users.manager);
        stakedUsdaiWithQEV.reorderRedemptions(auctionId, 1); // Last bid

        // Verify final queue integrity
        uint256[] memory expectedOrder = new uint256[](12);
        expectedOrder[0] = 7; // redemptionId 1's new prioritized redemption (60% bid)
        expectedOrder[1] = 8; // redemptionId 2's new prioritized redemption (50% bid)
        expectedOrder[2] = 9; // redemptionId 3's new prioritized redemption (40% bid)
        expectedOrder[3] = 10; // redemptionId 4's new prioritized redemption (30% bid)
        expectedOrder[4] = 11; // redemptionId 5's new prioritized redemption (20% bid)
        expectedOrder[5] = 12; // redemptionId 6's new prioritized redemption (10% bid)
        expectedOrder[6] = 1; // redemptionId 1's remaining original redemption
        expectedOrder[7] = 2; // redemptionId 2's remaining original redemption
        expectedOrder[8] = 3; // redemptionId 3's remaining original redemption
        expectedOrder[9] = 4; // redemptionId 4's remaining original redemption
        expectedOrder[10] = 5; // redemptionId 5's remaining original redemption
        expectedOrder[11] = 6; // redemptionId 6's remaining original redemption
        assertQueueIntegrity(expectedOrder);

        // Verify auction processing is complete
        (uint256 bidCount, uint256 processedBidCount,,,) = qevRegistry.auction(auctionId);
        assertEq(processedBidCount, bidCount, "All bids should be processed");
    }

    function test__QueueIntegrity_PartialProcessing_PartiallyProcessedRedemptions() public {
        // Test: Redemptions that are partially processed maintain correct state
        uint256 redemptionId = requestRedemption(user1, 100_000 ether);
        uint256 auctionId = qevRegistry.auctionId();

        // Create bid for partial amount
        IQEVRegistry.SignedBid[] memory signedBids = new IQEVRegistry.SignedBid[](1);
        signedBids[0] = createSignedBid(auctionId, redemptionId, 60_000 ether, 3000, user1PrivateKey);

        advanceAuctionTime(auctionId);

        vm.prank(users.manager);
        qevRegistry.postBids(signedBids);

        // Now settle the auction after posting bids
        vm.prank(users.manager);
        qevRegistry.settleAuction();

        // Partially service some redemptions before reordering
        vm.prank(users.manager);
        stakedUsdaiWithQEV.serviceRedemptions(20_000 ether);

        // Execute reordering
        vm.prank(users.manager);
        stakedUsdaiWithQEV.reorderRedemptions(auctionId, 1);

        // Verify queue integrity maintained with partially serviced redemption
        uint256[] memory expectedOrder = new uint256[](2);
        expectedOrder[0] = 2; // New prioritized redemption
        expectedOrder[1] = 1; // Original redemption (partially serviced)
        assertQueueIntegrity(expectedOrder);

        // Verify redemption states
        (IStakedUSDai.Redemption memory originalRedemption,) = stakedUsdaiWithQEV.redemption(1);
        (IStakedUSDai.Redemption memory newRedemption,) = stakedUsdaiWithQEV.redemption(2);

        assertLt(originalRedemption.pendingShares, 100_000 ether, "Original redemption should be partially processed");
        assertGt(newRedemption.pendingShares, 0, "New redemption should have pending shares");
    }

    /*------------------------------------------------------------------------*/
    /* Queue Integrity Tests - Multiple Auction Cycles */
    /*------------------------------------------------------------------------*/

    function test__QueueIntegrity_MultipleAuctions_SequentialAuctionProcessing() public {
        // Test: Multiple auction cycles maintain queue integrity across settlements

        // First auction cycle
        uint256 redemptionId1 = requestRedemption(user1, 100_000 ether);
        uint256 redemptionId2 = requestRedemption(user2, 80_000 ether);

        uint256 auction1Id = qevRegistry.auctionId();

        IQEVRegistry.SignedBid[] memory bids1 = new IQEVRegistry.SignedBid[](1);
        bids1[0] = createSignedBid(auction1Id, redemptionId2, 50_000 ether, 2000, user2PrivateKey);

        advanceAuctionTime(auction1Id);

        vm.prank(users.manager);
        qevRegistry.postBids(bids1);

        // Now settle the auction after posting bids
        vm.prank(users.manager);
        qevRegistry.settleAuction();

        vm.prank(users.manager);
        stakedUsdaiWithQEV.reorderRedemptions(auction1Id, 1);

        // Verify queue after first auction
        uint256[] memory expectedOrder1 = new uint256[](3);
        expectedOrder1[0] = 3; // user2's new prioritized redemption
        expectedOrder1[1] = 1; // user1's original redemption
        expectedOrder1[2] = 2; // user2's remaining redemption
        assertQueueIntegrity(expectedOrder1);

        // Second auction cycle - add more redemptions
        uint256 redemptionId4 = requestRedemption(user3, 120_000 ether);

        uint256 auction2Id = qevRegistry.auctionId();

        IQEVRegistry.SignedBid[] memory bids2 = new IQEVRegistry.SignedBid[](2);
        bids2[0] = createSignedBid(auction2Id, redemptionId1, 75_000 ether, 4000, user1PrivateKey);
        bids2[1] = createSignedBid(auction2Id, redemptionId4, 60_000 ether, 1500, user3PrivateKey);

        advanceAuctionTime(auction2Id);

        vm.prank(users.manager);
        qevRegistry.postBids(bids2);

        // Now settle the auction after posting bids
        vm.prank(users.manager);
        qevRegistry.settleAuction();

        vm.prank(users.manager);
        stakedUsdaiWithQEV.reorderRedemptions(auction2Id, 2);

        // Verify queue integrity maintained across multiple auctions
        (, uint256 head, uint256 tail,,) = getQueueState();
        assertGt(head, 0, "Queue should have head");
        assertGt(tail, 0, "Queue should have tail");

        // Verify no redemptions are lost or duplicated
        uint256 redemptionCount = 0;
        uint256 current = head;
        while (current != 0) {
            redemptionCount++;
            (IStakedUSDai.Redemption memory redemption,) = stakedUsdaiWithQEV.redemption(current);
            current = redemption.next;

            // Prevent infinite loops
            if (redemptionCount > 10) break;
        }

        assertGe(redemptionCount, 4, "Should have at least 4 redemptions in queue");
    }

    /*------------------------------------------------------------------------*/
    /* Queue Integrity Tests - Edge Cases */
    /*------------------------------------------------------------------------*/

    function test__QueueIntegrity_EdgeCases_RedemptionCompletelyServiced() public {
        // Test: Completely serviced redemptions are skipped during reordering
        uint256 redemptionId1 = requestRedemption(user1, 50_000 ether);
        uint256 redemptionId2 = requestRedemption(user2, 100_000 ether);
        uint256 auctionId = qevRegistry.auctionId();

        // Service first redemption completely
        vm.prank(users.manager);
        stakedUsdaiWithQEV.serviceRedemptions(50_000 ether);

        // Post bid for the serviced redemption
        IQEVRegistry.SignedBid[] memory signedBids = new IQEVRegistry.SignedBid[](1);
        signedBids[0] = createSignedBid(auctionId, redemptionId1, 25_000 ether, 2000, user1PrivateKey);

        advanceAuctionTime(auctionId);

        vm.prank(users.manager);
        qevRegistry.postBids(signedBids);

        // Now settle the auction after posting bids
        vm.prank(users.manager);
        qevRegistry.settleAuction();

        vm.expectRevert(abi.encodeWithSelector(QEVLogic.InvalidBidIndex.selector));
        vm.prank(users.manager);
        stakedUsdaiWithQEV.reorderRedemptions(auctionId, 1);

        (uint256 bidCount,,,,) = qevRegistry.auction(auctionId);
        assertEq(bidCount, 0, "Bid count should be 0");
    }

    function test__QueueIntegrity_EdgeCases_BidAmountExceedsRedemptionShares() public {
        // Test: Bid amount larger than available shares is clamped correctly
        uint256 redemptionId = requestRedemption(user1, 50_000 ether);
        uint256 auctionId = qevRegistry.auctionId();

        // Post bid for more than available shares
        IQEVRegistry.SignedBid[] memory signedBids = new IQEVRegistry.SignedBid[](1);
        signedBids[0] = createSignedBid(auctionId, redemptionId, 100_000 ether, 2000, user1PrivateKey);

        advanceAuctionTime(auctionId);

        vm.prank(users.manager);
        qevRegistry.postBids(signedBids);

        // Now settle the auction after posting bids
        vm.prank(users.manager);
        qevRegistry.settleAuction();

        // Execute reordering
        vm.prank(users.manager);
        stakedUsdaiWithQEV.reorderRedemptions(auctionId, 1);

        // Verify the bid was clamped to available shares
        (IStakedUSDai.Redemption memory redemption,) = stakedUsdaiWithQEV.redemption(1);
        assertEq(redemption.pendingShares, 40_000 ether, "Should clamp to available shares"); // 50k - 10k bid = 40k
    }

    function test__QueueIntegrity_EdgeCases_VaryingRedemptionAmounts() public {
        // Test: Queue integrity with redemptions of widely varying amounts
        uint256[] memory amounts = new uint256[](5);
        amounts[0] = 1 ether; // Very small
        amounts[1] = 1_000_000 ether; // Very large
        amounts[2] = 50_000 ether; // Medium
        amounts[3] = 10 ether; // Small
        amounts[4] = 500_000 ether; // Large

        uint256[] memory redemptionIds = new uint256[](5);
        for (uint256 i = 0; i < 5; i++) {
            redemptionIds[i] = requestRedemption(user1, amounts[i]);
        }

        uint256 auctionId = qevRegistry.auctionId();

        // Post bids for varying amounts
        // Create bids in descending order (highest to lowest basis points)
        IQEVRegistry.SignedBid[] memory signedBids = new IQEVRegistry.SignedBid[](5);
        for (uint256 i = 0; i < 5; i++) {
            uint256 bidAmount = amounts[i] / 2; // Bid for half the shares
            uint256 basisPoint = 1400 - i * 100; // Descending: 1400, 1300, 1200, 1100, 1000
            signedBids[i] = createSignedBid(auctionId, redemptionIds[i], bidAmount, basisPoint, user1PrivateKey);
        }

        advanceAuctionTime(auctionId);

        vm.prank(users.manager);
        qevRegistry.postBids(signedBids);

        // Now settle the auction after posting bids
        vm.prank(users.manager);
        qevRegistry.settleAuction();

        // Execute reordering
        vm.prank(users.manager);
        stakedUsdaiWithQEV.reorderRedemptions(auctionId, 5);

        // Verify queue integrity regardless of varying amounts
        (, uint256 head, uint256 tail,,) = getQueueState();
        assertGt(head, 0, "Queue should have head");
        assertGt(tail, 0, "Queue should have tail");

        // Count redemptions in queue
        uint256 redemptionCount = 0;
        uint256 current = head;
        while (current != 0 && redemptionCount < 20) {
            // Safety check
            redemptionCount++;
            (IStakedUSDai.Redemption memory redemption,) = stakedUsdaiWithQEV.redemption(current);
            current = redemption.next;
        }

        assertGe(redemptionCount, 5, "Should maintain all redemption entries");
    }

    /*------------------------------------------------------------------------*/
    /* Integration with Service Redemptions */
    /*------------------------------------------------------------------------*/

    function test__Integration_ReorderThenService_CorrectProcessingOrder() public {
        // Test: After reordering, serviceRedemptions processes in correct priority order
        uint256 redemptionId1 = requestRedemption(user1, 100_000 ether);
        uint256 redemptionId2 = requestRedemption(user2, 150_000 ether);
        uint256 redemptionId3 = requestRedemption(user3, 80_000 ether);
        uint256 auctionId = qevRegistry.auctionId();

        // Post bids (user3 pays most, should be first)
        IQEVRegistry.SignedBid[] memory signedBids = new IQEVRegistry.SignedBid[](2);
        signedBids[0] = createSignedBid(auctionId, redemptionId3, 50_000 ether, 5000, user3PrivateKey); // 50%
        signedBids[1] = createSignedBid(auctionId, redemptionId1, 80_000 ether, 2000, user1PrivateKey); // 20%

        advanceAuctionTime(auctionId);

        vm.prank(users.manager);
        qevRegistry.postBids(signedBids);

        // Now settle the auction after posting bids
        vm.prank(users.manager);
        qevRegistry.settleAuction();

        // Execute reordering
        vm.prank(users.manager);
        stakedUsdaiWithQEV.reorderRedemptions(auctionId, 2);

        // Service limited amount to verify processing order
        vm.prank(users.manager);
        uint256 amountProcessed = stakedUsdaiWithQEV.serviceRedemptions(25_000 ether);

        // Verify user3's redemption (highest bidder) was serviced first
        (IStakedUSDai.Redemption memory redemption3,) = stakedUsdaiWithQEV.redemption(4);
        assertLt(redemption3.pendingShares, 30_000 ether, "User3 redemption should be partially serviced");

        // User2 should be unaffected (didn't bid)
        (IStakedUSDai.Redemption memory redemption2,) = stakedUsdaiWithQEV.redemption(2);
        assertEq(redemption2.pendingShares, 150_000 ether, "User2 redemption should be unchanged");
    }
}
