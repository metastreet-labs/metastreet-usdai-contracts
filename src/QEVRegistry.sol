// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardTransientUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import "./interfaces/IQEVRegistry.sol";
import "./interfaces/IStakedUSDai.sol";

/**
 * @title QEV Registry
 * @author MetaStreet Foundation
 */
contract QEVRegistry is
    ReentrancyGuardTransientUpgradeable,
    EIP712Upgradeable,
    AccessControlUpgradeable,
    IQEVRegistry
{
    /*------------------------------------------------------------------------*/
    /* Constants */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Minimum bid basis point
     */
    uint256 internal constant MIN_BASIS_POINT = 10;

    /**
     * @notice Bid EIP-712 typehash
     */
    bytes32 public constant BID_TYPEHASH =
        keccak256("Bid(uint256 auctionId,uint256 redemptionId,uint256 basisPoint,uint64 nonce)");

    /**
     * @notice Set head role
     */
    bytes32 internal constant SET_HEAD_ADMIN_ROLE = keccak256("SET_HEAD_ADMIN_ROLE");

    /**
     * @notice Staked USDai storage location
     * @dev keccak256(abi.encode(uint256(keccak256("qevRegistry.susdai")) - 1)) & ~bytes32(uint256(0xff));
     */
    bytes32 private constant SUSDAI_STORAGE_LOCATION =
        0x0000000000000000000000000000000000000000000000000000000000000000;

    /**
     * @notice Auction storage location
     * @dev keccak256(abi.encode(uint256(keccak256("qevRegistry.auctions")) - 1)) & ~bytes32(uint256(0xff));
     */
    bytes32 private constant AUCTIONS_STORAGE_LOCATION =
        0x0000000000000000000000000000000000000000000000000000000000000000;

    /*------------------------------------------------------------------------*/
    /* Immutable State */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Admin fee rate
     */
    uint256 internal immutable _adminFeeRate;

    /**
     * @notice Admin fee recipient
     */
    address internal immutable _adminFeeRecipient;

    /*------------------------------------------------------------------------*/
    /* Constructor */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Constructor
     * @param adminFeeRate_ Admin fee rate
     * @param adminFeeRecipient_ Admin fee recipient
     */
    constructor(uint256 adminFeeRate_, address adminFeeRecipient_) {
        _disableInitializers();

        _adminFeeRate = adminFeeRate_;
        _adminFeeRecipient = adminFeeRecipient_;
    }

    /*------------------------------------------------------------------------*/
    /* Initializer */
    /*------------------------------------------------------------------------*/

    function initialize() external initializer {
        __ReentrancyGuardTransient_init();
        __EIP712_init("QEVRegistry", DOMAIN_VERSION());
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /*------------------------------------------------------------------------*/
    /* Internal */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Validate bid
     * @param auctionId_ Auction ID
     * @param auction_ Auction
     * @param signedBid Signed bid
     * @param timestamp Timestamp
     * @param prevBidBasisPoint Previous bid basis point
     * @param prevTimestamp Previous timestamp
     * @param index Index
     * @return Bid
     */
    function _validateBid(
        uint256 auctionId_,
        Auction storage auction_,
        SignedBid memory signedBid,
        uint64 timestamp,
        uint256 prevBidBasisPoint,
        uint64 prevTimestamp,
        uint256 index
    ) internal view returns (Bid memory) {
        /* Get bid */
        Bid memory bid = signedBid.bid;

        /* Get redemption */
        (IStakedUSDai.Redemption memory redemption,) = _getStakedUSDaiStorage().susdai.redemption(bid.redemptionId);

        /* Recover transfer approval signer */
        address signer = ECDSA.recover(
            _hashTypedDataV4(
                keccak256(abi.encode(BID_TYPEHASH, bid.auctionId, bid.redemptionId, bid.basisPoint, bid.nonce))
            ),
            signedBid.signature
        );

        /* If signer is not the controller, revert */
        if (signer != redemption.controller) revert InvalidSigner(index);

        /* Validate auction ID */
        if (bid.auctionId != auctionId_) revert InvalidAuctionId(index);

        /* Validate bid basis point is at least equal to previous bid basis point */
        if (bid.basisPoint > prevBidBasisPoint || bid.basisPoint < MIN_BASIS_POINT) revert InvalidBidBasisPoint(index);

        /* Validate timestamp is at least equal to previous timestamp if basis point equals previous basis point */
        if (bid.basisPoint == prevBidBasisPoint && prevTimestamp > timestamp) revert InvalidTimestamp(index);

        /* Validate redemption is not serviced */
        if (redemption.pendingShares == 0) revert InvalidRedemptionStatus(index);

        /* Validate bid is unique */
        if (auction_.bidIndices[bid.redemptionId] != 0) revert DuplicatedBid(index);

        /* Validate bid nonce */
        if (auction_.bidRecords[bid.redemptionId].nonce != bid.nonce) revert InvalidNonce(index);

        return bid;
    }

    /*------------------------------------------------------------------------*/
    /* Storage getters */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Get reference to staked USDai storage
     * @return $ Reference to staked USDai storage
     */
    function _getStakedUSDaiStorage() internal pure returns (StakedUSDaiStorage storage $) {
        assembly {
            $.slot := SUSDAI_STORAGE_LOCATION
        }
    }

    /**
     * @notice Get reference to ERC-7201 auction storage
     * @return $ Reference to auction storage
     */
    function _getAuctionStorage() internal pure returns (AuctionStorage storage $) {
        assembly {
            $.slot := AUCTIONS_STORAGE_LOCATION
        }
    }

    /*------------------------------------------------------------------------*/
    /* Getters */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Get price oracle implementation version
     * @return Price oracle implementation version
     */
    function IMPLEMENTATION_VERSION() public pure returns (string memory) {
        return "1.0";
    }

    /**
     * @notice Get signing domain version
     * @return Signing domain version
     */
    function DOMAIN_VERSION() public pure returns (string memory) {
        return "1.0";
    }

    /**
     * @inheritdoc IQEVRegistry
     */
    function auctionId() public view returns (uint256) {
        return _getAuctionStorage().auctionId;
    }

    /**
     * @inheritdoc IQEVRegistry
     */
    function nonce(uint256 auctionId_, uint256 redemptionId_) public view returns (uint256) {
        return _getAuctionStorage().auctions[auctionId_].bidRecords[redemptionId_].nonce;
    }

    /**
     * @inheritdoc IQEVRegistry
     */
    function auction(
        uint256 auctionId_
    ) public view returns (uint256 bidIndex, uint256 head, AuctionStatus status) {
        Auction storage auction_ = _getAuctionStorage().auctions[auctionId_];

        return (auction_.bidIndex, auction_.head, auction_.status);
    }

    /**
     * @inheritdoc IQEVRegistry
     */
    function redemptionId(uint256 auctionId_, uint256 bidIndex) public view returns (uint256) {
        /* Validate bid index */
        if (bidIndex == 0) revert InvalidBidIndex();

        return _getAuctionStorage().auctions[auctionId_].bidRecords[bidIndex].bid.redemptionId;
    }

    /**
     * @inheritdoc IQEVRegistry
     */
    function bidRecord(uint256 auctionId_, uint256 redemptionId_) public view returns (BidRecord memory) {
        /* Get bid index */
        uint256 bidIndex = _getAuctionStorage().auctions[auctionId_].bidIndices[redemptionId_];

        /* Validate bid */
        if (bidIndex == 0) revert InvalidBidIndex();

        return _getAuctionStorage().auctions[auctionId_].bidRecords[bidIndex];
    }

    /**
     * @inheritdoc IQEVRegistry
     */
    function bidRecords(uint256 auctionId_, uint256 offset, uint256 count) public view returns (BidRecord[] memory) {
        /* Clamp on count */
        count = Math.min(count, _getAuctionStorage().auctions[auctionId_].bidIndex - offset);

        /* Create arrays */
        BidRecord[] memory bidRecords_ = new BidRecord[](count);

        /* Get start index */
        uint256 startIndex = offset + 1;

        /* Fill array */
        for (uint256 i = startIndex; i <= startIndex + count; i++) {
            bidRecords_[i - startIndex] = _getAuctionStorage().auctions[auctionId_].bidRecords[i];
        }

        return bidRecords_;
    }

    /**
     * @inheritdoc IQEVRegistry
     */
    function adminFeeRate() external view returns (uint256) {
        return _adminFeeRate;
    }

    /**
     * @inheritdoc IQEVRegistry
     */
    function adminFeeRecipient() external view returns (address) {
        return _adminFeeRecipient;
    }

    /*------------------------------------------------------------------------*/
    /* Public API  */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IQEVRegistry
     */
    function incrementNonce(uint256 auctionId_, uint256 redemptionId_) external nonReentrant returns (uint256) {
        /* Validate staked USDai is set */
        if (address(_getStakedUSDaiStorage().susdai) == address(0)) revert InvalidAddress();

        /* Validate auction status */
        if (_getAuctionStorage().auctions[auctionId_].status != AuctionStatus.Opened) revert InvalidStatus();

        /* Get redemption */
        (IStakedUSDai.Redemption memory redemption,) = _getStakedUSDaiStorage().susdai.redemption(redemptionId_);

        /* Validate redemption controller is the caller */
        if (redemption.controller != msg.sender) revert InvalidCaller();

        /* Increment nonce */
        return ++_getAuctionStorage().auctions[auctionId_].bidRecords[redemptionId_].nonce;
    }

    /*------------------------------------------------------------------------*/
    /* Permissioned API  */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IQEVRegistry
     */
    function postBids(
        SignedBid[] calldata signedBids,
        uint64[] calldata timestamps
    ) external nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        /* Validate staked USDai is set */
        if (address(_getStakedUSDaiStorage().susdai) == address(0)) revert InvalidAddress();

        /* Validate length */
        if (signedBids.length != timestamps.length) revert InvalidLength();

        /* Get current auction ID */
        uint256 auctionId_ = auctionId();

        /* Get current auction */
        Auction storage auction_ = _getAuctionStorage().auctions[auctionId_];

        /* Validate auction status */
        if (auction_.status != AuctionStatus.Closed) revert InvalidStatus();

        /* Reveal bids */
        uint256 bidIndex = auction_.bidIndex;
        uint256 prevBidBasisPoint = bidIndex == 0 ? type(uint256).max : auction_.bidRecords[bidIndex].bid.basisPoint;
        uint64 prevTimestamp = bidIndex == 0 ? type(uint64).max : auction_.bidRecords[bidIndex].timestamp;
        for (uint256 i; i < signedBids.length; i++) {
            /* Validate bid */
            Bid memory bid =
                _validateBid(auctionId_, auction_, signedBids[i], timestamps[i], prevBidBasisPoint, prevTimestamp, i);

            /* Set bid index */
            auction_.bidIndices[bid.redemptionId] = ++bidIndex;

            /* Add bid record. Note: Bid nonce is validated in _validateBid */
            auction_.bidRecords[bidIndex] = BidRecord({bid: bid, nonce: bid.nonce, timestamp: timestamps[i]});

            /* Update previous bid basis point and timestamp */
            prevBidBasisPoint = bid.basisPoint;
            prevTimestamp = timestamps[i];
        }

        /* Update bid index */
        auction_.bidIndex = bidIndex;
    }

    /**
     * @inheritdoc IQEVRegistry
     */
    function setClosed(
        uint256 auctionId_
    ) external nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_getAuctionStorage().auctions[auctionId_].status != AuctionStatus.Opened) revert InvalidStatus();

        /* Set auction closed */
        _getAuctionStorage().auctions[auctionId_].status = AuctionStatus.Closed;

        /* Emit AuctionClosed */
        emit AuctionClosed(auctionId_);
    }

    /**
     * @inheritdoc IQEVRegistry
     */
    function setRevealed(
        uint256 auctionId_
    ) external nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_getAuctionStorage().auctions[auctionId_].status != AuctionStatus.Closed) revert InvalidStatus();

        /* Set auction revealed */
        _getAuctionStorage().auctions[auctionId_].status = AuctionStatus.Revealed;

        /* Emit AuctionBidsRevealed */
        emit AuctionBidsRevealed(auctionId_);
    }

    /**
     * @inheritdoc IQEVRegistry
     */
    function setReordered(
        uint256 auctionId_
    ) external nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        /* Get auction */
        Auction storage auction_ = _getAuctionStorage().auctions[auctionId_];

        /* Validate auction status and reordering is completed */
        if (auction_.status != AuctionStatus.Revealed || auction_.head != auction_.bidIndex) revert InvalidStatus();

        /* Set auction reordered */
        _getAuctionStorage().auctions[auctionId_].status = AuctionStatus.Reordered;

        /* Increment auction ID */
        ++_getAuctionStorage().auctionId;

        /* Emit AuctionQueueReordered */
        emit AuctionQueueReordered(auctionId_);
    }

    /**
     * @inheritdoc IQEVRegistry
     */
    function setReorderHead(
        uint256 auctionId_,
        uint256 reorderHead
    ) external nonReentrant onlyRole(SET_HEAD_ADMIN_ROLE) {
        /* Get auction */
        Auction storage auction_ = _getAuctionStorage().auctions[auctionId_];

        /* Set auction head */
        auction_.head = reorderHead;

        /* Emit AuctionReorderHeadSet */
        emit AuctionReorderHeadSet(auctionId_, reorderHead);
    }

    /**
     * @inheritdoc IQEVRegistry
     * @param susdai_ Staked USDai address
     */
    function setStakedUSDai(
        address susdai_
    ) external nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        /* Validate staked USDai address */
        if (susdai_ == address(0)) revert InvalidAddress();

        /* Set staked USDai */
        _getStakedUSDaiStorage().susdai = IStakedUSDai(susdai_);

        /* Grant set head admin role */
        _grantRole(SET_HEAD_ADMIN_ROLE, susdai_);
    }
}
