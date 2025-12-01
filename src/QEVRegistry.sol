// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardTransientUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import "./interfaces/IQEVRegistry.sol";
import "./interfaces/IStakedUSDai.sol";

import "forge-std/console.sol";

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
     * @notice Maximum bid basis point
     */
    uint256 internal constant MAX_BASIS_POINT = 10_000;

    /**
     * @notice Bid EIP-712 typehash
     */
    bytes32 public constant BID_TYPEHASH = keccak256(
        "Bid(uint64 auctionId,uint256 redemptionId,uint256 redemptionShares,uint256 basisPoint,uint256 nonce)"
    );

    /**
     * @notice Queue processor role
     */
    bytes32 internal constant QUEUE_PROCESSOR_ADMIN_ROLE = keccak256("QUEUE_PROCESSOR_ADMIN_ROLE");

    /**
     * @notice Auction admin role
     */
    bytes32 internal constant AUCTION_ADMIN_ROLE = keccak256("AUCTION_ADMIN_ROLE");

    /**
     * @notice Auction storage location
     * @dev keccak256(abi.encode(uint256(keccak256("qevRegistry.auctions")) - 1)) & ~bytes32(uint256(0xff));
     */
    bytes32 private constant AUCTIONS_STORAGE_LOCATION =
        0x2300893e77ee547c2a2f3266e5f958206de4ae9c0af96661cba3ecd8cdcc1400;

    /*------------------------------------------------------------------------*/
    /* Immutable State */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Staked USDai address
     */
    IStakedUSDai internal immutable _susdai;

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
     * @param susdai_ Staked USDai address
     * @param adminFeeRate_ Admin fee rate
     * @param adminFeeRecipient_ Admin fee recipient
     */
    constructor(address susdai_, uint256 adminFeeRate_, address adminFeeRecipient_) {
        _disableInitializers();

        _susdai = IStakedUSDai(susdai_);
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
        _grantRole(QUEUE_PROCESSOR_ADMIN_ROLE, address(_susdai));
    }

    /*------------------------------------------------------------------------*/
    /* Modifiers */
    /*------------------------------------------------------------------------*/

    modifier validAuctionId(
        uint64 auctionId_
    ) {
        /* Get previous auction */
        uint64 previousAuctionId_ = _getAuctionStorage().previousAuctionId;

        /* Validate auction ID */
        if (auctionId_ >= block.timestamp || auctionId_ <= previousAuctionId_) revert InvalidAuctionId(auctionId_);

        /* Validate previous auction is fully reordered */
        Auction storage previousAuction_ = _getAuctionStorage().auctions[previousAuctionId_];

        /* Validate previous auction is reordered */
        if (previousAuction_.bidCount != previousAuction_.processedBidCount) revert InvalidAuctionStatus();

        _;
    }

    /*------------------------------------------------------------------------*/
    /* Internal */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Validate bid
     * @param auctionId_ Auction ID
     * @param auction_ Auction
     * @param signedBid Signed bid
     * @param prevBidBasisPoint Previous bid basis point
     * @param prevRedemptionId Previous redemption ID
     * @param index Index
     * @return Bid, isSkipped
     */
    function _validateBid(
        uint64 auctionId_,
        Auction storage auction_,
        SignedBid memory signedBid,
        uint256 prevBidBasisPoint,
        uint256 prevRedemptionId,
        uint256 index
    ) internal view returns (Bid memory, bool) {
        /* Get bid */
        Bid memory bid_ = signedBid.bid;

        /* Get redemption */
        (IStakedUSDai.Redemption memory redemption,) = _susdai.redemption(bid_.redemptionId);

        /* Recover transfer approval signer */
        address signer = ECDSA.recover(
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        BID_TYPEHASH,
                        bid_.auctionId,
                        bid_.redemptionId,
                        bid_.redemptionShares,
                        bid_.basisPoint,
                        bid_.nonce
                    )
                )
            ),
            signedBid.signature
        );

        /* If signer is not the controller, revert */
        if (signer != redemption.controller) revert InvalidSigner(index);

        /* Validate auction ID */
        if (bid_.auctionId != auctionId_) revert InvalidAuctionId(index);

        /* Validate redemption timestamp is smaller than auction ID */
        if (bid_.auctionId < redemption.redemptionTimestamp) revert InvalidAuctionId(index);

        /* Validate bid basis point is at least equal to previous bid basis point */
        if (bid_.basisPoint > prevBidBasisPoint) revert InvalidBasisPoint(index);

        /* Validate bid basis point is less than maximum basis point */
        if (bid_.basisPoint < MIN_BASIS_POINT || bid_.basisPoint > MAX_BASIS_POINT) revert InvalidBasisPoint(index);

        /* Validate redemption ID is less than previous redemption ID if basis point equals previous basis point */
        if (bid_.basisPoint == prevBidBasisPoint && bid_.redemptionId < prevRedemptionId) {
            revert InvalidRedemptionOrder(bid_.redemptionId);
        }

        /* Validate reorder amount is not zero */
        if (bid_.redemptionShares == 0) revert InvalidRedemptionShares(index);

        /* Validate bid is unique */
        if (auction_.bidIndices[bid_.redemptionId] != 0) revert DuplicateBid(index);

        /* Validate bid nonce */
        if (auction_.nonces[bid_.redemptionId] != bid_.nonce) revert InvalidNonce(index);

        return (bid_, redemption.pendingShares == 0);
    }

    /*------------------------------------------------------------------------*/
    /* Storage getters */
    /*------------------------------------------------------------------------*/

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
    function IMPLEMENTATION_VERSION() external pure returns (string memory) {
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
    function nextAuctionId() external view returns (uint64) {
        return IStakedUSDai(_susdai).redemptionTimestamp();
    }

    /**
     * @inheritdoc IQEVRegistry
     */
    function previousAuctionId() external view returns (uint64) {
        return _getAuctionStorage().previousAuctionId;
    }

    /**
     * @inheritdoc IQEVRegistry
     */
    function nonce(uint64 auctionId_, uint256 redemptionId_) external view returns (uint256) {
        return _getAuctionStorage().auctions[auctionId_].nonces[redemptionId_];
    }

    /**
     * @inheritdoc IQEVRegistry
     */
    function auction(
        uint64 auctionId_
    ) external view returns (uint256 bidCount, uint256 processedBidCount, uint256 processedRedemptionId) {
        /* Get auction storage */
        AuctionStorage storage auctionStorage = _getAuctionStorage();

        /* Get auction */
        Auction storage auction_ = auctionStorage.auctions[auctionId_];

        return (auction_.bidCount, auction_.processedBidCount, auction_.processedRedemptionId);
    }

    /**
     * @inheritdoc IQEVRegistry
     */
    function redemptionId(uint64 auctionId_, uint256 bidIndex) external view returns (uint256) {
        /* Validate bid index */
        if (bidIndex == 0) revert InvalidBidIndex();

        return _getAuctionStorage().auctions[auctionId_].bid[bidIndex].redemptionId;
    }

    /**
     * @inheritdoc IQEVRegistry
     */
    function bid(uint64 auctionId_, uint256 redemptionId_) external view returns (Bid memory) {
        /* Get bid index */
        uint256 bidIndex = _getAuctionStorage().auctions[auctionId_].bidIndices[redemptionId_];

        /* Validate bid */
        if (bidIndex == 0) revert InvalidBidIndex();

        return _getAuctionStorage().auctions[auctionId_].bid[bidIndex];
    }

    /**
     * @inheritdoc IQEVRegistry
     */
    function bids(uint64 auctionId_, uint256 offset, uint256 count) external view returns (Bid[] memory) {
        /* Clamp on count */
        count = Math.min(count, _getAuctionStorage().auctions[auctionId_].bidCount - offset);

        /* Create arrays */
        Bid[] memory bids_ = new Bid[](count);

        /* Get start index */
        uint256 startIndex = offset + 1;

        /* Fill array */
        for (uint256 i = startIndex; i < startIndex + count; i++) {
            bids_[i - startIndex] = _getAuctionStorage().auctions[auctionId_].bid[i];
        }

        return bids_;
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
    function incrementNonce(uint64 auctionId_, uint256 redemptionId_) external nonReentrant returns (uint256) {
        /* Validate auction ID is greater than current block timestamp */
        if (block.timestamp > auctionId_) revert InvalidTimestamp();

        /* Get redemption */
        (IStakedUSDai.Redemption memory redemption,) = _susdai.redemption(redemptionId_);

        /* Validate redemption controller is the caller */
        if (redemption.controller != msg.sender) revert InvalidCaller();

        /* Increment nonce */
        return ++_getAuctionStorage().auctions[auctionId_].nonces[redemptionId_];
    }

    /*------------------------------------------------------------------------*/
    /* Auction Admin API  */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IQEVRegistry
     */
    function postBids(
        uint64 auctionId_,
        SignedBid[] calldata signedBids
    ) external nonReentrant validAuctionId(auctionId_) onlyRole(AUCTION_ADMIN_ROLE) {
        /* Get current auction */
        Auction storage auction_ = _getAuctionStorage().auctions[auctionId_];

        /* Reveal bids */
        uint256 bidIndex = auction_.bidCount;
        uint256 prevBidBasisPoint = bidIndex == 0 ? type(uint256).max : auction_.bid[bidIndex].basisPoint;
        uint256 prevRedemptionId = bidIndex == 0 ? 0 : auction_.bid[bidIndex].redemptionId;
        for (uint256 i; i < signedBids.length; i++) {
            /* Validate bid */
            (Bid memory bid_, bool isSkipped) =
                _validateBid(auctionId_, auction_, signedBids[i], prevBidBasisPoint, prevRedemptionId, i);

            /* Skip bid if it is not included */
            if (isSkipped) continue;

            /* Set bid index */
            auction_.bidIndices[bid_.redemptionId] = ++bidIndex;

            /* Add bid */
            auction_.bid[bidIndex] = bid_;

            /* Update previous bid basis point and redemption ID */
            prevBidBasisPoint = bid_.basisPoint;
            prevRedemptionId = bid_.redemptionId;
        }

        /* Update bid index */
        auction_.bidCount = bidIndex;
    }

    /**
     * @inheritdoc IQEVRegistry
     */
    function settleAuction(
        uint64 auctionId_
    ) external nonReentrant onlyRole(AUCTION_ADMIN_ROLE) {
        /* Validate auction has bids */
        if (_getAuctionStorage().auctions[auctionId_].bidCount == 0) revert InvalidAuctionStatus();

        /* Validate auction ID is greater than previous auction ID */
        if (auctionId_ <= _getAuctionStorage().previousAuctionId) revert InvalidAuctionStatus();

        /* Get previous auction ID */
        _getAuctionStorage().previousAuctionId = auctionId_;

        /* Emit AuctionSettled */
        emit AuctionSettled(auctionId_);
    }

    /*------------------------------------------------------------------------*/
    /* Queue Processor API  */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IQEVRegistry
     */
    function processQueue(
        uint64 auctionId_,
        uint256 processedBidCount,
        uint256 processedRedemptionId
    ) external nonReentrant onlyRole(QUEUE_PROCESSOR_ADMIN_ROLE) {
        /* Get auction */
        Auction storage auction_ = _getAuctionStorage().auctions[auctionId_];

        /* Set auction reorder checkpoint */
        auction_.processedBidCount = processedBidCount;
        auction_.processedRedemptionId = processedRedemptionId;

        /* Emit AuctionCheckpointSet */
        emit AuctionCheckpointSet(auctionId_, processedBidCount, processedRedemptionId);
    }
}
