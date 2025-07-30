// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IStakedUSDai} from "./IStakedUSDai.sol";

/**
 * @title QEV Registry Interface
 * @author MetaStreet Foundation
 */
interface IQEVRegistry {
    /*------------------------------------------------------------------------*/
    /* Structures */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Auction status
     * @param Active Auction is active
     * @param Closed Auction is closed
     * @param Revealed Bids are revealed
     * @param ServiceCompleted Service is completed
     */
    enum AuctionStatus {
        Opened,
        Closed,
        Revealed,
        Reordered
    }

    /**
     * @notice Bid
     * @param auctionId Auction ID
     * @param redemptionId Redemption ID
     * @param basisPoint Bid basis point
     * @param nonce Nonce
     */
    struct Bid {
        uint256 auctionId;
        uint256 redemptionId;
        uint256 basisPoint;
        uint256 nonce;
    }

    /**
     * @notice Signed bid with submission timestamp
     * @param bid Bid
     * @param timestamp Submission timestamp
     * @param signature Signature
     */
    struct SignedBid {
        Bid bid;
        uint64 timestamp;
        bytes signature;
    }

    /**
     * @notice Bid record
     * @param bid Bid
     * @param nonce Nonce
     * @param timestamp Submission timestamp
     */
    struct BidRecord {
        Bid bid;
        uint256 nonce;
        uint64 timestamp;
    }

    /**
     * @notice Auction
     * @param bidIndex Bid index
     * @param head Head index for reordering
     * @param status Auction status
     * @param bidIndices Mapping of redemption ID to bid index
     * @param bidRecords Mapping of bid index to bid record
     */
    struct Auction {
        uint256 bidIndex;
        uint256 head;
        AuctionStatus status;
        mapping(uint256 => uint256) bidIndices;
        mapping(uint256 => BidRecord) bidRecords;
    }

    /**
     * @custom:storage-location erc7201:qevRegistry.susdai
     * @param susdai Staked USDai
     */
    struct StakedUSDaiStorage {
        IStakedUSDai susdai;
    }

    /**
     * @custom:storage-location erc7201:qevRegistry.auctions
     */
    struct AuctionStorage {
        uint256 auctionId;
        mapping(uint256 => Auction) auctions;
    }

    /*------------------------------------------------------------------------*/
    /* Errors  */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Invalid address
     */
    error InvalidAddress();

    /**
     * @notice Invalid status
     */
    error InvalidStatus();

    /**
     * @notice Invalid length
     */
    error InvalidLength();

    /**
     * @notice Invalid bid index
     */
    error InvalidBidIndex();

    /**
     * @notice Invalid caller
     */
    error InvalidCaller();

    /**
     * @notice Invalid auction ID
     * @param id Index of the signed bid
     */
    error InvalidAuctionId(uint256 id);

    /**
     * @notice Invalid signer
     * @param id Index of the bid record
     */
    error InvalidSigner(uint256 id);

    /**
     * @notice Invalid nonce
     * @param id Index of the bid record
     */
    error InvalidNonce(uint256 id);

    /**
     * @notice Invalid timestamp
     * @param id Index of the signed bid
     */
    error InvalidTimestamp(uint256 id);

    /**
     * @notice Invalid bid amount
     * @param id Index of the signed bid
     */
    error InvalidBidBasisPoint(uint256 id);

    /**
     * @notice Duplicated bid
     * @param id Index of the signed bid
     */
    error DuplicatedBid(uint256 id);

    /**
     * @notice Invalid redemption status
     * @param id Index of the signed bid
     */
    error InvalidRedemptionStatus(uint256 id);

    /*------------------------------------------------------------------------*/
    /* Events */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Auction closed
     * @param auctionId Auction ID
     */
    event AuctionClosed(uint256 auctionId);

    /**
     * @notice Auction bids revealed
     * @param auctionId Auction ID
     */
    event AuctionBidsRevealed(uint256 auctionId);

    /**
     * @notice Auction queue reordered
     * @param auctionId Auction ID
     */
    event AuctionQueueReordered(uint256 auctionId);

    /**
     * @notice Auction reorder head set
     * @param auctionId Auction ID
     * @param reorderHead Reorder head index
     */
    event AuctionReorderHeadSet(uint256 auctionId, uint256 reorderHead);

    /*------------------------------------------------------------------------*/
    /* Getters */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Get auction ID
     * @return auctionId Auction ID
     */
    function auctionId() external view returns (uint256);

    /**
     * @notice Get nonce
     * @param auctionId Auction ID
     * @param redemptionId Redemption ID
     * @return nonce Nonce
     */
    function nonce(uint256 auctionId, uint256 redemptionId) external view returns (uint256);

    /**
     * @notice Get auction
     * @param auctionId Auction ID
     * @return bidIndex Bid index
     * @return reorderHead Head index for reordering
     * @return status Auction status
     */
    function auction(
        uint256 auctionId
    ) external view returns (uint256 bidIndex, uint256 reorderHead, AuctionStatus status);

    /**
     * @notice Get redemption ID
     * @param auctionId Auction ID
     * @param index Index
     * @return Redemption ID
     */
    function redemptionId(uint256 auctionId, uint256 index) external view returns (uint256);

    /**
     * @notice Get bid record
     * @param auctionId Auction ID
     * @param redemptionId Redemption ID
     * @return bidRecord Bid record
     */
    function bidRecord(uint256 auctionId, uint256 redemptionId) external view returns (BidRecord memory);

    /**
     * @notice Get bid records
     * @param auctionId Auction ID
     * @param offset Offset
     * @param count Count
     * @return bidRecords Bid records
     */
    function bidRecords(uint256 auctionId, uint256 offset, uint256 count) external view returns (BidRecord[] memory);

    /**
     * @notice Get admin fee rate
     * @return adminFeeRate Admin fee rate
     */
    function adminFeeRate() external view returns (uint256);

    /**
     * @notice Get admin fee recipient
     * @return adminFeeRecipient Admin fee recipient
     */
    function adminFeeRecipient() external view returns (address);

    /*------------------------------------------------------------------------*/
    /* Public API */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Increment nonce
     * @param auctionId Auction ID
     * @param redemptionId Redemption ID
     * @return nonce Nonce
     */
    function incrementNonce(uint256 auctionId, uint256 redemptionId) external returns (uint256);

    /*------------------------------------------------------------------------*/
    /* Permissioned API */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Post bids
     * @param signedBids Signed bids
     * @param timestamps Timestamps
     */
    function postBids(SignedBid[] calldata signedBids, uint64[] calldata timestamps) external;

    /**
     * @notice Set auction closed and increment auction ID
     * @param auctionId Auction ID
     */
    function setClosed(
        uint256 auctionId
    ) external;

    /**
     * @notice Set auction bids revealed
     * @param auctionId Auction ID
     */
    function setRevealed(
        uint256 auctionId
    ) external;

    /**
     * @notice Set auction reordered
     * @param auctionId Auction ID
     */
    function setReordered(
        uint256 auctionId
    ) external;

    /**
     * @notice Set reorder head
     * @param auctionId Auction ID
     * @param reorderHead Reorder head index
     */
    function setReorderHead(uint256 auctionId, uint256 reorderHead) external;

    /**
     * @notice Set staked USDai
     * @param susdai Staked USDai
     */
    function setStakedUSDai(
        address susdai
    ) external;
}
