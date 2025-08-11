// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "./QEVBase.t.sol";

/**
 * @title QEV Registry Tests
 * @notice Comprehensive tests for QEVRegistry auction logic and bid validation
 * @dev Tests auction lifecycle, bid posting, signature verification, and error conditions
 */
contract QEVRegistryTest is QEVBaseTest {
    /*------------------------------------------------------------------------*/
    /* Basic Auction Lifecycle Tests */
    /*------------------------------------------------------------------------*/

    function test__AuctionBasicLifecycle_InitialAuctionSetup() public {
        // Test: Verify initial auction state is correct
        uint256 auctionId = qevRegistry.auctionId();
        assertEq(auctionId, 0, "Initial auction ID should be 0");

        (
            uint256 bidCount,
            uint256 processedBidCount,
            uint256 processedRedemptionId,
            uint64 auctionStart,
            uint64 auctionEnd
        ) = qevRegistry.auction(0);

        assertEq(bidCount, 0, "Initial bid count should be 0");
        assertEq(processedBidCount, 0, "Initial processed bid index should be 0");
        assertEq(processedRedemptionId, 0, "Initial last redemption ID should be 0");
        assertGt(auctionEnd, auctionStart, "Auction end should be after start");
        assertEq(auctionEnd - auctionStart, DEFAULT_AUCTION_DURATION, "Auction duration should match default");
    }

    function test__AuctionBasicLifecycle_SettleEmptyAuction() public {
        // Test: Settle auction with no bids creates next auction
        uint256 initialAuctionId = qevRegistry.auctionId();

        // Skip to end of auction
        skipTime(DEFAULT_AUCTION_DURATION + 1);

        vm.expectEmit(true, true, false, true);
        emit IQEVRegistry.AuctionSettled(initialAuctionId, block.timestamp);

        vm.prank(users.manager);
        qevRegistry.settleAuction();

        uint256 newAuctionId = qevRegistry.auctionId();
        assertEq(newAuctionId, initialAuctionId + 1, "New auction should be created");

        uint64 settlementTimestamp = qevRegistry.settlementTimestamp(initialAuctionId);
        assertEq(settlementTimestamp, block.timestamp, "Settlement timestamp should be set");
    }

    function test__AuctionBasicLifecycle_CannotSettleBeforeEnd() public {
        // Test: Cannot settle auction before it ends
        vm.expectRevert(IQEVRegistry.InvalidTimestamp.selector);
        vm.prank(users.manager);
        qevRegistry.settleAuction();
    }

    function test__AuctionBasicLifecycle_SetAuctionDuration() public {
        // Test: Admin can set auction duration
        uint64 newDuration = 2 hours;

        vm.expectEmit(true, false, false, true);
        emit IQEVRegistry.AuctionDurationSet(newDuration);

        vm.prank(users.deployer);
        qevRegistry.setAuctionDuration(newDuration);

        // Verify new duration applies to next auction
        (,,, uint64 auctionStart, uint64 auctionEnd) = qevRegistry.auction(0);
        assertEq(auctionEnd - auctionStart, newDuration, "New duration should be applied");
    }

    /*------------------------------------------------------------------------*/
    /* Bid Posting and Validation Tests */
    /*------------------------------------------------------------------------*/

    function test__BidValidation_SingleValidBid() public {
        // Test: Post single valid bid during auction
        uint256 redemptionId = requestRedemption(user1, 100_000 ether);
        uint256 auctionId = qevRegistry.auctionId();

        IQEVRegistry.SignedBid[] memory signedBids = new IQEVRegistry.SignedBid[](1);
        signedBids[0] = createSignedBid(auctionId, redemptionId, 50_000 ether, 1000, user1PrivateKey);

        advanceAuctionTime(auctionId);

        vm.prank(users.manager);
        qevRegistry.postBids(signedBids);

        // Now settle the auction after posting bids
        vm.prank(users.manager);
        qevRegistry.settleAuction();

        // Verify bid was posted
        (uint256 bidCount,,,,) = qevRegistry.auction(auctionId);
        assertEq(bidCount, 1, "Bid count should be 1");

        IQEVRegistry.Bid memory retrievedBid = qevRegistry.bid(auctionId, redemptionId);
        assertEq(retrievedBid.redemptionId, redemptionId, "Redemption ID should match");
        assertEq(retrievedBid.basisPoint, 1000, "Basis point should match");
        assertEq(retrievedBid.redemptionShares, 50_000 ether, "Redemption amount should match");
    }

    function test__BidValidation_MultipleBidsOrderedByBasisPoint() public {
        // Test: Multiple bids are correctly ordered by basis point (descending) and timestamp (ascending)
        uint256 redemptionId1 = requestRedemption(user1, 100_000 ether);
        uint256 redemptionId2 = requestRedemption(user2, 100_000 ether);
        uint256 redemptionId3 = requestRedemption(user3, 100_000 ether);
        uint256 auctionId = qevRegistry.auctionId();

        IQEVRegistry.SignedBid[] memory signedBids = new IQEVRegistry.SignedBid[](3);
        signedBids[0] = createSignedBid(auctionId, redemptionId1, 50_000 ether, 5000, user1PrivateKey); // 50%
        signedBids[1] = createSignedBid(auctionId, redemptionId2, 60_000 ether, 3000, user2PrivateKey); // 30%
        signedBids[2] = createSignedBid(auctionId, redemptionId3, 40_000 ether, 1000, user3PrivateKey); // 10%

        advanceAuctionTime(auctionId);

        vm.prank(users.manager);
        qevRegistry.postBids(signedBids);

        // Verify ordering by basis point (descending)
        IQEVRegistry.Bid[] memory retrievedBids = qevRegistry.bids(auctionId, 0, 3);
        assertEq(retrievedBids[0].basisPoint, 5000, "First bid should have highest basis point");
        assertEq(retrievedBids[1].basisPoint, 3000, "Second bid should have middle basis point");
        assertEq(retrievedBids[2].basisPoint, 1000, "Third bid should have lowest basis point");
    }

    function test__BidValidation_InvalidSignature() public {
        // Test: Bid with invalid signature is rejected
        uint256 redemptionId = requestRedemption(user1, 100_000 ether);
        uint256 auctionId = qevRegistry.auctionId();

        IQEVRegistry.SignedBid[] memory signedBids = new IQEVRegistry.SignedBid[](1);
        signedBids[0] = createSignedBid(auctionId, redemptionId, 50_000 ether, 1000, user2PrivateKey);

        advanceAuctionTime(auctionId);

        vm.expectRevert(abi.encodeWithSelector(IQEVRegistry.InvalidSigner.selector, 0));
        vm.prank(users.manager);
        qevRegistry.postBids(signedBids);
    }

    function test__BidValidation_WrongAuctionId() public {
        // Test: Bid with wrong auction ID is rejected
        uint256 redemptionId = requestRedemption(user1, 100_000 ether);
        uint256 auctionId = qevRegistry.auctionId();

        IQEVRegistry.SignedBid[] memory signedBids = new IQEVRegistry.SignedBid[](1);
        signedBids[0] = createSignedBid(auctionId + 1, redemptionId, 50_000 ether, 1000, user1PrivateKey);

        advanceAuctionTime(auctionId);

        vm.expectRevert(abi.encodeWithSelector(IQEVRegistry.InvalidAuctionId.selector, 0));
        vm.prank(users.manager);
        qevRegistry.postBids(signedBids);
    }

    function test__BidValidation_BasisPointTooLow() public {
        // Test: Bid with basis point below minimum is rejected
        uint256 redemptionId = requestRedemption(user1, 100_000 ether);
        uint256 auctionId = qevRegistry.auctionId();

        IQEVRegistry.SignedBid[] memory signedBids = new IQEVRegistry.SignedBid[](1);
        signedBids[0] = createSignedBid(auctionId, redemptionId, 50_000 ether, 5, user1PrivateKey); // Below min of 10

        advanceAuctionTime(auctionId);

        vm.expectRevert(abi.encodeWithSelector(IQEVRegistry.InvalidBidBasisPoint.selector, 0));
        vm.prank(users.manager);
        qevRegistry.postBids(signedBids);
    }

    function test__BidValidation_BasisPointTooHigh() public {
        // Test: Bid with basis point above maximum is rejected
        uint256 redemptionId = requestRedemption(user1, 100_000 ether);
        uint256 auctionId = qevRegistry.auctionId();

        IQEVRegistry.SignedBid[] memory signedBids = new IQEVRegistry.SignedBid[](1);
        signedBids[0] = createSignedBid(auctionId, redemptionId, 50_000 ether, 10_001, user1PrivateKey); // Above max of
            // 10,000

        advanceAuctionTime(auctionId);

        vm.expectRevert(abi.encodeWithSelector(IQEVRegistry.InvalidBidBasisPoint.selector, 0));
        vm.prank(users.manager);
        qevRegistry.postBids(signedBids);
    }

    function test__BidValidation_ZeroRedemptionAmount() public {
        // Test: Bid with zero redemption amount is rejected
        uint256 redemptionId = requestRedemption(user1, 100_000 ether);
        uint256 auctionId = qevRegistry.auctionId();

        IQEVRegistry.SignedBid[] memory signedBids = new IQEVRegistry.SignedBid[](1);
        signedBids[0] = createSignedBid(auctionId, redemptionId, 0, 1000, user1PrivateKey);

        advanceAuctionTime(auctionId);

        vm.expectRevert(abi.encodeWithSelector(IQEVRegistry.InvalidRedemptionShares.selector, 0));
        vm.prank(users.manager);
        qevRegistry.postBids(signedBids);
    }

    function test__BidValidation_DuplicateBid() public {
        // Test: Duplicate bids from same redemption ID are rejected
        uint256 redemptionId = requestRedemption(user1, 100_000 ether);
        uint256 auctionId = qevRegistry.auctionId();

        // Post first bid
        IQEVRegistry.SignedBid[] memory firstBid = new IQEVRegistry.SignedBid[](1);
        firstBid[0] = createSignedBid(auctionId, redemptionId, 50_000 ether, 2000, user1PrivateKey);

        advanceAuctionTime(auctionId);

        vm.prank(users.manager);
        qevRegistry.postBids(firstBid);

        // Try to post second bid for same redemption
        IQEVRegistry.SignedBid[] memory secondBid = new IQEVRegistry.SignedBid[](1);
        secondBid[0] = createSignedBid(auctionId, redemptionId, 30_000 ether, 1000, user1PrivateKey);

        vm.expectRevert(abi.encodeWithSelector(IQEVRegistry.DuplicateBid.selector, 0));
        vm.prank(users.manager);
        qevRegistry.postBids(secondBid);
    }

    function test__BidValidation_InvalidNonce() public {
        // Test: Bid with incorrect nonce is rejected
        uint256 redemptionId = requestRedemption(user1, 100_000 ether);
        uint256 auctionId = qevRegistry.auctionId();

        // Manually create bid with wrong nonce
        IQEVRegistry.Bid memory bid = IQEVRegistry.Bid({
            auctionId: auctionId,
            redemptionId: redemptionId,
            redemptionShares: 50_000 ether,
            basisPoint: 1000,
            nonce: 999, // Wrong nonce
            timestamp: uint64(block.timestamp)
        });

        bytes memory signature = signBid(bid, user1PrivateKey);

        IQEVRegistry.SignedBid[] memory signedBids = new IQEVRegistry.SignedBid[](1);
        signedBids[0] = IQEVRegistry.SignedBid({bid: bid, signature: signature});

        advanceAuctionTime(auctionId);

        vm.expectRevert(abi.encodeWithSelector(IQEVRegistry.InvalidNonce.selector, 0));
        vm.prank(users.manager);
        qevRegistry.postBids(signedBids);
    }

    /*------------------------------------------------------------------------*/
    /* Multiple Bid Batch Tests */
    /*------------------------------------------------------------------------*/

    function test__MultipleBatches_PostBidsInMultipleBatches() public {
        // Test: Post bids in multiple batches to simulate gas constraints
        uint256[] memory redemptionIds = new uint256[](6);
        for (uint256 i = 0; i < 6; i++) {
            redemptionIds[i] = requestRedemption(i < 2 ? user1 : (i < 4 ? user2 : user3), 100_000 ether);
        }

        uint256 auctionId = qevRegistry.auctionId();

        // First batch: 3 bids
        IQEVRegistry.SignedBid[] memory batch1 = new IQEVRegistry.SignedBid[](3);
        batch1[0] = createSignedBid(auctionId, redemptionIds[0], 50_000 ether, 5000, user1PrivateKey);
        batch1[1] = createSignedBid(auctionId, redemptionIds[1], 60_000 ether, 4000, user1PrivateKey);
        batch1[2] = createSignedBid(auctionId, redemptionIds[2], 40_000 ether, 3000, user2PrivateKey);

        advanceAuctionTime(auctionId);

        vm.prank(users.manager);
        qevRegistry.postBids(batch1);

        // Second batch: 3 more bids
        IQEVRegistry.SignedBid[] memory batch2 = new IQEVRegistry.SignedBid[](3);
        batch2[0] = createSignedBid(auctionId, redemptionIds[3], 70_000 ether, 2000, user2PrivateKey);
        batch2[1] = createSignedBid(auctionId, redemptionIds[4], 30_000 ether, 1500, user3PrivateKey);
        batch2[2] = createSignedBid(auctionId, redemptionIds[5], 80_000 ether, 1000, user3PrivateKey);

        vm.prank(users.manager);
        qevRegistry.postBids(batch2);

        // Verify all bids are properly ordered
        (uint256 bidCount,,,,) = qevRegistry.auction(auctionId);
        assertEq(bidCount, 6, "Total bid count should be 6");

        IQEVRegistry.Bid[] memory allBids = qevRegistry.bids(auctionId, 0, 6);
        assertEq(allBids[0].basisPoint, 5000, "First bid should have highest basis point");
        assertEq(allBids[5].basisPoint, 1000, "Last bid should have lowest basis point");

        // Verify all basis points are in descending order
        for (uint256 i = 0; i < allBids.length - 1; i++) {
            assertGe(allBids[i].basisPoint, allBids[i + 1].basisPoint, "Bids should be in descending order");
        }
    }

    /*------------------------------------------------------------------------*/
    /* Nonce Management Tests */
    /*------------------------------------------------------------------------*/

    function test__NonceManagement_IncrementNonceDuringAuction() public {
        // Test: User can increment nonce during active auction
        uint256 redemptionId = requestRedemption(user1, 100_000 ether);
        uint256 auctionId = qevRegistry.auctionId();

        uint256 initialNonce = qevRegistry.nonce(auctionId, redemptionId);
        assertEq(initialNonce, 0, "Initial nonce should be 0");

        vm.prank(user1);
        uint256 newNonce = qevRegistry.incrementNonce(auctionId, redemptionId);

        assertEq(newNonce, 1, "New nonce should be 1");
        assertEq(qevRegistry.nonce(auctionId, redemptionId), 1, "Stored nonce should be updated");
    }

    function test__NonceManagement_CannotIncrementAfterAuctionEnd() public {
        // Test: Cannot increment nonce after auction ends
        uint256 redemptionId = requestRedemption(user1, 100_000 ether);
        uint256 auctionId = qevRegistry.auctionId();

        // End auction
        skipTime(DEFAULT_AUCTION_DURATION + 1);

        vm.expectRevert(IQEVRegistry.InvalidTimestamp.selector);
        vm.prank(user1);
        qevRegistry.incrementNonce(auctionId, redemptionId);
    }

    function test__NonceManagement_OnlyControllerCanIncrementNonce() public {
        // Test: Only redemption controller can increment nonce
        uint256 redemptionId = requestRedemption(user1, 100_000 ether);
        uint256 auctionId = qevRegistry.auctionId();

        vm.expectRevert(IQEVRegistry.InvalidCaller.selector);
        vm.prank(user2);
        qevRegistry.incrementNonce(auctionId, redemptionId);
    }

    /*------------------------------------------------------------------------*/
    /* Edge Cases and Error Conditions */
    /*------------------------------------------------------------------------*/

    function test__EdgeCases_PostBidsBeforeAuctionEnds() public {
        // Test: Cannot post bids after auction ends
        uint256 redemptionId = requestRedemption(user1, 100_000 ether);
        uint256 auctionId = qevRegistry.auctionId();

        IQEVRegistry.SignedBid[] memory signedBids = new IQEVRegistry.SignedBid[](1);
        signedBids[0] = createSignedBid(auctionId, redemptionId, 50_000 ether, 1000, user1PrivateKey);

        vm.expectRevert(IQEVRegistry.InvalidTimestamp.selector);
        vm.prank(users.manager);
        qevRegistry.postBids(signedBids);
    }

    function test__EdgeCases_PostBidsDuringActiveAuction() public {
        // Test: Cannot post bids during active auction (before it ends)
        uint256 redemptionId = requestRedemption(user1, 100_000 ether);
        uint256 auctionId = qevRegistry.auctionId();

        // Try to post bids during active auction (before it ends)
        IQEVRegistry.SignedBid[] memory signedBids = new IQEVRegistry.SignedBid[](1);
        signedBids[0] = createSignedBid(auctionId, redemptionId, 50_000 ether, 1000, user1PrivateKey);

        vm.expectRevert(IQEVRegistry.InvalidTimestamp.selector);
        vm.prank(users.manager);
        qevRegistry.postBids(signedBids);
    }

    function test__EdgeCases_BidTimestampOutsideAuctionWindow() public {
        // Test: Bid with timestamp outside auction window is rejected
        uint256 redemptionId = requestRedemption(user1, 100_000 ether);
        uint256 auctionId = qevRegistry.auctionId();

        // Create bid with future timestamp
        IQEVRegistry.Bid memory bid = IQEVRegistry.Bid({
            auctionId: auctionId,
            redemptionId: redemptionId,
            redemptionShares: 50_000 ether,
            basisPoint: 1000,
            nonce: 0,
            timestamp: uint64(block.timestamp + DEFAULT_AUCTION_DURATION + 1)
        });

        bytes memory signature = signBid(bid, user1PrivateKey);

        IQEVRegistry.SignedBid[] memory signedBids = new IQEVRegistry.SignedBid[](1);
        signedBids[0] = IQEVRegistry.SignedBid({bid: bid, signature: signature});

        advanceAuctionTime(auctionId);

        vm.expectRevert(abi.encodeWithSelector(IQEVRegistry.InvalidBidTimestamp.selector, 0));
        vm.prank(users.manager);
        qevRegistry.postBids(signedBids);
    }

    function test__EdgeCases_RetrieveBidsWithOffsetAndCount() public {
        // Test: Retrieve bids with different offset and count parameters
        uint256[] memory redemptionIds = new uint256[](5);
        for (uint256 i = 0; i < 5; i++) {
            redemptionIds[i] = requestRedemption(user1, 100_000 ether);
        }

        uint256 auctionId = qevRegistry.auctionId();

        IQEVRegistry.SignedBid[] memory signedBids = new IQEVRegistry.SignedBid[](5);
        for (uint256 i = 0; i < 5; i++) {
            signedBids[i] = createSignedBid(auctionId, redemptionIds[i], 50_000 ether, 5000 - i * 1000, user1PrivateKey);
        }

        advanceAuctionTime(auctionId);

        vm.prank(users.manager);
        qevRegistry.postBids(signedBids);

        // Test different retrieval patterns
        IQEVRegistry.Bid[] memory firstThree = qevRegistry.bids(auctionId, 0, 3);
        assertEq(firstThree.length, 3, "Should return 3 bids");
        assertEq(firstThree[0].basisPoint, 5000, "First bid should have highest basis point");

        IQEVRegistry.Bid[] memory lastTwo = qevRegistry.bids(auctionId, 3, 2);
        assertEq(lastTwo.length, 2, "Should return 2 bids");
        assertEq(lastTwo[0].basisPoint, 2000, "Fourth bid should have correct basis point");

        IQEVRegistry.Bid[] memory beyondRange = qevRegistry.bids(auctionId, 3, 10);
        assertEq(beyondRange.length, 2, "Should clamp to available bids");
    }

    /*------------------------------------------------------------------------*/
    /* Access Control Tests */
    /*------------------------------------------------------------------------*/

    function test__AccessControl_OnlyAuctionAdminCanPostBids() public {
        // Test: Only auction admin can post bids
        uint256 redemptionId = requestRedemption(user1, 100_000 ether);
        uint256 auctionId = qevRegistry.auctionId();

        IQEVRegistry.SignedBid[] memory signedBids = new IQEVRegistry.SignedBid[](1);
        signedBids[0] = createSignedBid(auctionId, redemptionId, 50_000 ether, 1000, user1PrivateKey);

        advanceAuctionTime(auctionId);

        vm.expectRevert();
        vm.prank(user1);
        qevRegistry.postBids(signedBids);
    }

    function test__AccessControl_OnlyAuctionAdminCanSettleAuction() public {
        // Test: Only auction admin can settle auction
        skipTime(DEFAULT_AUCTION_DURATION + 1);

        vm.expectRevert();
        vm.prank(user1);
        qevRegistry.settleAuction();
    }

    function test__AccessControl_OnlyDefaultAdminCanSetDuration() public {
        // Test: Only default admin can set auction duration
        vm.expectRevert();
        vm.prank(user1);
        qevRegistry.setAuctionDuration(2 hours);
    }
}
