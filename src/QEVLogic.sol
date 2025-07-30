// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import "./StakedUSDaiStorage.sol";

import "./interfaces/IStakedUSDai.sol";
import "./interfaces/IQEVRegistry.sol";

/**
 * @title QEV Logic
 * @author MetaStreet Foundation
 */
library QEVLogic {
    using EnumerableSet for EnumerableSet.UintSet;

    /*------------------------------------------------------------------------*/
    /* Constants */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Bid EIP-712 typehash
     */
    bytes32 public constant BID_TYPEHASH =
        keccak256("Bid(uint256 auctionId,uint256 redemptionId,uint256 feeRate,uint256 timestamp,uint256 nonce)");

    /**
     * @notice Basis point scale
     */
    uint256 internal constant BASIS_POINT_SCALE = 10_000;

    /*------------------------------------------------------------------------*/
    /* Errors  */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Invalid auction status
     */
    error InvalidAuctionStatus();

    /**
     * @notice Invalid bid index
     */
    error InvalidBidIndex();

    /**
     * @notice Invalid redemption state
     */
    error InvalidRedemptionState();

    /*------------------------------------------------------------------------*/
    /* Helpers  */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Process QEV
     * @param redemptionState Redemption state
     * @param qevRegistry QEV registry
     * @param auctionId Auction ID
     * @param count Count of redemptions to reorder
     * @return totalPendingSharesBurnt Total pending shares burnt
     * @return totalAdminFee Total admin fee
     * @return adminFeeRecipient Admin fee recipient
     * @return isReordered True if reordering is completed
     */
    function _reorderRedemptions(
        StakedUSDaiStorage.RedemptionState storage redemptionState,
        address qevRegistry,
        uint256 auctionId,
        uint256 count
    ) external returns (uint256, uint256, address, bool) {
        /* Get auction */
        (uint256 bidIndex, uint256 reorderHead, IQEVRegistry.AuctionStatus status) =
            IQEVRegistry(qevRegistry).auction(auctionId);

        /* Validate auction bids are revealed */
        if (status != IQEVRegistry.AuctionStatus.Revealed) revert InvalidAuctionStatus();

        /* Validate bid count is not zero and reordering is not completed */
        if (bidIndex == 0 || reorderHead == bidIndex) revert InvalidBidIndex();

        /* Validate head is not 0 */
        if (redemptionState.head == 0) revert InvalidRedemptionState();

        /* Get incision point */
        uint256 next = reorderHead == 0
            ? redemptionState.head
            : redemptionState.redemptions[IQEVRegistry(qevRegistry).redemptionId(auctionId, reorderHead)].next;
        uint256 prev = reorderHead == 0
            ? redemptionState.redemptions[redemptionState.head].prev
            : IQEVRegistry(qevRegistry).redemptionId(auctionId, reorderHead);

        /* Get admin fee rate and recipient */
        uint256 adminFeeRate = IQEVRegistry(qevRegistry).adminFeeRate();
        address adminFeeRecipient = IQEVRegistry(qevRegistry).adminFeeRecipient();

        /* Get bid records */
        IQEVRegistry.BidRecord[] memory bidRecords = IQEVRegistry(qevRegistry).bidRecords(auctionId, reorderHead, count);

        /* Process bids */
        uint256 totalBidAmount;
        uint256 totalAdminFee;
        for (uint256 i; i < bidRecords.length; i++) {
            /* Get bid */
            IQEVRegistry.Bid memory bid = bidRecords[i].bid;

            /* Get redemption */
            IStakedUSDai.Redemption storage redemption = redemptionState.redemptions[bid.redemptionId];

            /* Skip if redemption is completely serviced */
            if (redemption.pendingShares == 0) continue;

            /* If current redemption is next, update next pointer. Else extract redemption */
            if (next == bid.redemptionId) {
                /* Update next */
                next = redemptionState.redemptions[bid.redemptionId].next;
            } else {
                /* Extract redemption */
                _extractRedemption(redemptionState, redemption);

                /* Insert redemption */
                redemption.prev = prev;
                redemption.next = next;

                /* Link next redemption to inserted redemption */
                redemptionState.redemptions[next].prev = bid.redemptionId;
            }

            /* Get bid amount */
            uint256 bidAmount = Math.mulDiv(redemption.pendingShares, bid.basisPoint, BASIS_POINT_SCALE);

            /* Update pending shares */
            redemption.pendingShares -= bidAmount;

            /* Update head */
            if (i == 0 && reorderHead == 0) redemptionState.head = bid.redemptionId;

            /* Update previous redemptions */
            prev = bid.redemptionId;

            /* Update total bid amount */
            totalBidAmount += bidAmount;

            /* Update total admin fee */
            totalAdminFee += Math.mulDiv(bidAmount, adminFeeRate, BASIS_POINT_SCALE);
        }

        /* Get total pending shares burnt */
        uint256 totalPendingSharesBurnt = totalBidAmount - totalAdminFee;

        /* Update pending by subtracting total pending shares burnt */
        redemptionState.pending -= totalPendingSharesBurnt;

        /* Set new reorder head */
        IQEVRegistry(qevRegistry).setReorderHead(auctionId, reorderHead + count);

        return (totalPendingSharesBurnt, totalAdminFee, adminFeeRecipient, reorderHead + count == bidIndex);
    }

    /**
     * @notice Extract redemption from queue
     * @dev This function removes a redemption from the queue and controller's redemption IDs
     * @dev Does not remove the redemption from the redemptions mapping
     * @param redemptionState Redemption state
     * @param redemptionId Request ID
     */
    function _extractRedemption(
        StakedUSDaiStorage.RedemptionState storage redemptionState,
        IStakedUSDai.Redemption memory redemption
    ) internal {
        /* Update previous redemption */
        if (redemption.prev != 0) redemptionState.redemptions[redemption.prev].next = redemption.next;

        /* Update next redemption */
        if (redemption.next != 0) redemptionState.redemptions[redemption.next].prev = redemption.prev;
    }
}
