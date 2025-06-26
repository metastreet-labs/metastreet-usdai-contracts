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
     * @notice Bid
     * @param auctionId Auction ID
     * @param redemptionId Redemption ID
     * @param reorderAmount Reorder amount
     * @param basisPoint Bid basis point
     * @param nonce Nonce
     * @param timestamp Submission timestamp
     */
    struct Bid {
        uint256 auctionId;
        uint256 redemptionId;
        uint256 reorderAmount;
        uint256 basisPoint;
        uint256 nonce;
        uint64 timestamp;
    }

    /**
     * @notice Signed bid
     * @param bid Bid
     * @param signature Signature
     */
    struct SignedBid {
        Bid bid;
        bytes signature;
    }

    /**
     * @notice Auction
     * @param bidIndex Bid index (a.k.a. bid count)
     * @param reorderBidIndex Reorder bid index
     * @param lastRedemptionId Last redemption ID
     * @param nonces Mapping of redemption ID to nonce
     * @param bidIndices Mapping of redemption ID to bid index
     * @param bid Mapping of bid index to bid
     */
    struct Auction {
        uint256 bidIndex;
        uint256 reorderBidIndex;
        uint256 lastRedemptionId;
        mapping(uint256 => uint256) nonces;
        mapping(uint256 => uint256) bidIndices;
        mapping(uint256 => Bid) bid;
    }

    /**
     * @custom:storage-location erc7201:qevRegistry.auctions
     */
    struct AuctionStorage {
        uint256 id;
        uint64 genesisTimestamp;
        uint64 duration;
        mapping(uint256 => uint64) settlementTimestamps;
        mapping(uint256 => Auction) auctions;
    }

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
     * @notice Invalid caller
     */
    error InvalidCaller();

    /**
     * @notice Invalid timestamp
     */
    error InvalidTimestamp();

    /**
     * @notice Invalid start time
     */
    error InvalidStartTime();

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
     * @notice Invalid bid timestamp
     * @param id Index of the signed bid
     */
    error InvalidBidTimestamp(uint256 id);

    /**
     * @notice Invalid reorder amount
     * @param id Index of the signed bid
     */
    error InvalidReorderAmount(uint256 id);

    /**
     * @notice Invalid bid basis point
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
     * @notice Auction genesis timestamp set
     * @param timestamp Genesis timestamp
     */
    event GenesisTimestampSet(uint64 timestamp);

    /**
     * @notice Auction duration set
     * @param duration Auction duration
     */
    event AuctionDurationSet(uint256 duration);

    /**
     * @notice Auction settled
     * @param auctionId Auction ID
     * @param timestamp Settlement timestamp
     */
    event AuctionSettled(uint256 auctionId, uint256 timestamp);

    /**
     * @notice Auction reorder checkpoint set
     * @param auctionId Auction ID
     * @param reorderBidIndex Reorder bid index
     * @param lastRedemptionId Last redemption ID
     */
    event AuctionCheckpointSet(uint256 auctionId, uint256 reorderBidIndex, uint256 lastRedemptionId);

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
     * @return reorderBidIndex Reorder bid index
     * @return lastRedemptionId Last redemption ID
     * @return auctionStart Auction start time
     * @return auctionEnd Auction end time
     */
    function auction(
        uint256 auctionId
    )
        external
        view
        returns (
            uint256 bidIndex,
            uint256 reorderBidIndex,
            uint256 lastRedemptionId,
            uint64 auctionStart,
            uint64 auctionEnd
        );

    /**
     * @notice Get redemption ID
     * @param auctionId Auction ID
     * @param bidIndex Bid index
     * @return Redemption ID
     */
    function redemptionId(uint256 auctionId, uint256 bidIndex) external view returns (uint256);

    /**
     * @notice Get bid
     * @param auctionId Auction ID
     * @param redemptionId Redemption ID
     * @return bid Bid
     */
    function bid(uint256 auctionId, uint256 redemptionId) external view returns (Bid memory);

    /**
     * @notice Get bids
     * @param auctionId Auction ID
     * @param offset Offset
     * @param count Count
     * @return bids Bids
     */
    function bids(uint256 auctionId, uint256 offset, uint256 count) external view returns (Bid[] memory);

    /**
     * @notice Get settlement timestamp
     * @param auctionId Auction ID
     * @return Settlement timestamp
     */
    function settlementTimestamp(
        uint256 auctionId
    ) external view returns (uint64);

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
     */
    function postBids(
        SignedBid[] calldata signedBids
    ) external;

    /**
     * @notice Settle auction
     */
    function settleAuction() external;

    /**
     * @notice Set genesis timestamp
     * @param timestamp Genesis timestamp
     */
    function setGenesisTimestamp(
        uint64 timestamp
    ) external;

    /**
     * @notice Set auction duration
     * @param duration Auction duration
     */
    function setAuctionDuration(
        uint64 duration
    ) external;

    /**
     * @notice Set reorder checkpoint
     * @param auctionId Auction ID
     * @param reorderBidIndex Reorder bid index
     * @param lastRedemptionId Last redemption ID
     */
    function setCheckpoint(uint256 auctionId, uint256 reorderBidIndex, uint256 lastRedemptionId) external;
}
