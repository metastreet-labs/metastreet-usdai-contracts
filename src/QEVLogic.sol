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
     * @notice Invalid count
     */
    error InvalidCount();

    /**
     * @notice Invalid redemption state
     */
    error InvalidRedemptionState();

    /*------------------------------------------------------------------------*/
    /* Events  */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Redemption updated
     * @param redemptionId Redemption ID
     * @param controller Controller
     * @param pendingShares New pending shares
     * @param bidAmount Bid amount
     */
    event RedemptionUpdated(
        uint256 indexed redemptionId, address indexed controller, uint256 pendingShares, uint256 bidAmount
    );

    /**
     * @notice Redemption created
     * @param redemptionId Redemption ID
     * @param controller Controller
     * @param pendingShares Pending shares
     * @param bidAmount Bid amount
     */
    event RedemptionCreated(
        uint256 indexed redemptionId, address indexed controller, uint256 pendingShares, uint256 bidAmount
    );

    /*------------------------------------------------------------------------*/
    /* Internal Helpers  */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Remove redemption from queue
     * @param redemptionState Redemption state
     * @param redemptionId Redemption ID
     */
    function _removeRedemption(
        StakedUSDaiStorage.RedemptionState storage redemptionState,
        uint256 redemptionId
    ) internal {
        /* Get redemption */
        IStakedUSDai.Redemption memory redemption = redemptionState.redemptions[redemptionId];

        /* Update tail */
        if (redemptionId == redemptionState.tail) redemptionState.tail = redemption.prev;

        /* Update previous redemption */
        if (redemption.prev != 0) redemptionState.redemptions[redemption.prev].next = redemption.next;

        /* Update next redemption */
        if (redemption.next != 0) redemptionState.redemptions[redemption.next].prev = redemption.prev;
    }

    /**
     * @notice Insert redemption into queue
     * @param redemptionState Redemption state
     * @param redemptionId Redemption ID
     * @param prev Previous redemption ID
     * @param next Next redemption ID
     */
    function _insertRedemption(
        StakedUSDaiStorage.RedemptionState storage redemptionState,
        uint256 redemptionId,
        uint256 prev,
        uint256 next
    ) internal {
        /* Get redemption */
        IStakedUSDai.Redemption storage redemption = redemptionState.redemptions[redemptionId];

        /* Link redemption prev and next */
        if (redemption.prev != prev) redemption.prev = prev;
        if (redemption.next != next) redemption.next = next;

        /* Link prev redemption to inserted redemption. */
        if (prev != 0) redemptionState.redemptions[prev].next = redemptionId;

        /* Link next redemption to inserted redemption. */
        if (next != 0) redemptionState.redemptions[next].prev = redemptionId;
    }

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
        uint64 auctionId,
        uint256 count
    ) external returns (uint256, uint256, address, bool) {
        /* Validate auction is settled */
        if (IQEVRegistry(qevRegistry).previousAuctionId() != auctionId) revert InvalidAuctionStatus();

        /* Validate count is not zero */
        if (count == 0) revert InvalidCount();

        /* Get auction */
        (uint256 bidCount, uint256 processedBidCount, uint256 processedRedemptionId) =
            IQEVRegistry(qevRegistry).auction(auctionId);

        /* Validate bid count is not zero and reordering is not completed */
        if (bidCount == 0 || processedBidCount == bidCount) revert InvalidCount();

        /* Validate head and tail are not 0 */
        if (redemptionState.head == 0 || redemptionState.tail == 0) revert InvalidRedemptionState();

        /* Get prev and next pointers */
        uint256 prev =
            processedRedemptionId == 0 ? redemptionState.redemptions[redemptionState.head].prev : processedRedemptionId;
        uint256 next =
            processedRedemptionId == 0 ? redemptionState.head : redemptionState.redemptions[processedRedemptionId].next;

        /* Get current redemption ID */
        uint256 redemptionId = redemptionState.index;

        /* Get admin fee rate and recipient */
        uint256 adminFeeRate = IQEVRegistry(qevRegistry).adminFeeRate();
        address adminFeeRecipient = IQEVRegistry(qevRegistry).adminFeeRecipient();

        /* Get bid */
        IQEVRegistry.Bid[] memory bids = IQEVRegistry(qevRegistry).bids(auctionId, processedBidCount, count);

        /* Process bids */
        uint256 totalBidAmount;
        for (uint256 i; i < bids.length; i++) {
            /* Get bid */
            IQEVRegistry.Bid memory bid = bids[i];

            /* Get redemption */
            IStakedUSDai.Redemption storage redemption = redemptionState.redemptions[bid.redemptionId];

            /* Skip if redemption is completely serviced */
            if (redemption.pendingShares == 0) continue;

            /* Get redemption shares */
            uint256 redemptionShares = Math.min(redemption.pendingShares, bid.redemptionShares);

            /* Get bid amount */
            uint256 bidAmount = Math.mulDiv(redemptionShares, bid.basisPoint, BASIS_POINT_SCALE);

            /* Get redemption ID */
            uint256 bidRedemptionId = bid.redemptionId;

            /* If redemption shares equals pending shares, reorder redemption. Else create new redemption */
            if (redemptionShares == redemption.pendingShares) {
                /* Subtract bid amount from redemption pending shares */
                redemption.pendingShares -= bidAmount;

                /* If next is not bid redemption ID, remove and insert redemption. Else forward pointer */
                if (next != bidRedemptionId) {
                    /* Remove redemption */
                    _removeRedemption(redemptionState, bidRedemptionId);

                    /* Insert redemption */
                    _insertRedemption(redemptionState, bidRedemptionId, prev, next);
                } else {
                    next = redemptionState.redemptions[bidRedemptionId].next;
                }

                /* Emit RedemptionUpdated */
                emit RedemptionUpdated(bidRedemptionId, redemption.controller, redemption.pendingShares, bidAmount);
            } else {
                /* Subtract redemption shares from redemption pending shares */
                redemption.pendingShares -= redemptionShares;

                /* Overwrite bid redemption ID */
                bidRedemptionId = ++redemptionId;

                /* Compute pending shares for new redemption */
                uint256 pendingShares = redemptionShares - bidAmount;

                /* Create new redemption */
                redemptionState.redemptions[bidRedemptionId] = IStakedUSDai.Redemption({
                    prev: prev,
                    next: next,
                    pendingShares: pendingShares,
                    redeemableShares: 0,
                    withdrawableAmount: 0,
                    controller: redemption.controller,
                    redemptionTimestamp: redemption.redemptionTimestamp
                });

                /* Add redemption ID */
                redemptionState.redemptionIds[redemption.controller].add(bidRedemptionId);

                /* Insert redemption */
                _insertRedemption(redemptionState, bidRedemptionId, prev, next);

                /* Emit RedemptionUpdated */
                emit RedemptionUpdated(bid.redemptionId, redemption.controller, redemption.pendingShares, 0);

                /* Emit RedemptionCreated */
                emit RedemptionCreated(bidRedemptionId, redemption.controller, pendingShares, bidAmount);
            }

            /* Update head with highest bid of auction */
            if (i == 0 && processedBidCount == 0) redemptionState.head = bidRedemptionId;

            /* Update prev pointer */
            prev = bidRedemptionId;

            /* Update total bid amount */
            totalBidAmount += bidAmount;

            /* Update last redemption ID */
            processedRedemptionId = bidRedemptionId;
        }

        /* Get total admin fee */
        uint256 totalAdminFee = Math.mulDiv(totalBidAmount, adminFeeRate, BASIS_POINT_SCALE);

        /* Get total pending shares burnt */
        uint256 totalPendingSharesBurnt = totalBidAmount - totalAdminFee;

        /* Update pending by subtracting total pending shares burnt */
        redemptionState.pending -= totalPendingSharesBurnt;

        /* Update redemption ID */
        redemptionState.index = redemptionId;

        /* Compute new processed bid index */
        processedBidCount += count;

        /* Set checkpoint after processing queue */
        IQEVRegistry(qevRegistry).processQueue(auctionId, processedBidCount, processedRedemptionId);

        return (totalPendingSharesBurnt, totalAdminFee, adminFeeRecipient, processedBidCount == bidCount);
    }
}
