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
     * @notice Maximum bid basis point
     */
    uint256 internal constant MAX_BASIS_POINT = 10_000;

    /**
     * @notice Bid EIP-712 typehash
     */
    bytes32 public constant BID_TYPEHASH = keccak256(
        "Bid(uint256 auctionId,uint256 redemptionId,uint256 reorderAmount,uint256 basisPoint,uint256 nonce,uint64 timestamp)"
    );

    /**
     * @notice Checkpoint role
     */
    bytes32 internal constant CHECKPOINT_ADMIN_ROLE = keccak256("CHECKPOINT_ADMIN_ROLE");

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
        _grantRole(CHECKPOINT_ADMIN_ROLE, address(_susdai));
    }

    /*------------------------------------------------------------------------*/
    /* Modifiers */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Validate previous auction is reordered
     */
    modifier previousAuctionReordered() {
        /* Get auction ID */
        uint256 auctionId_ = auctionId();

        /* If auction ID is 0, skip validation */
        if (auctionId_ == 0) _;

        /* Get auction */
        Auction storage auction_ = _getAuctionStorage().auctions[auctionId_ - 1];

        /* Validate previous auction is reordered */
        if (auction_.bidIndex != auction_.reorderBidIndex) revert InvalidAuctionStatus();

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
     * @param prevTimestamp Previous timestamp
     * @param auctionStart Auction start time
     * @param auctionEnd Auction end time
     * @param index Index
     * @return Bid
     */
    function _validateBid(
        uint256 auctionId_,
        Auction storage auction_,
        SignedBid memory signedBid,
        uint256 prevBidBasisPoint,
        uint64 prevTimestamp,
        uint64 auctionStart,
        uint64 auctionEnd,
        uint256 index
    ) internal view returns (Bid memory) {
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
                        bid_.reorderAmount,
                        bid_.basisPoint,
                        bid_.nonce,
                        bid_.timestamp
                    )
                )
            ),
            signedBid.signature
        );

        /* If signer is not the controller, revert */
        if (signer != redemption.controller) revert InvalidSigner(index);

        /* Validate auction ID */
        if (bid_.auctionId != auctionId_) revert InvalidAuctionId(index);

        /* Validate bid basis point is at least equal to previous bid basis point */
        if (bid_.basisPoint > prevBidBasisPoint) revert InvalidBidBasisPoint(index);

        /* Validate bid basis point is less than maximum basis point */
        if (bid_.basisPoint < MIN_BASIS_POINT || bid_.basisPoint > MAX_BASIS_POINT) revert InvalidBidBasisPoint(index);

        /* Validate bid timestamp is valid */
        if (bid_.timestamp < auctionStart || bid_.timestamp >= auctionEnd) revert InvalidBidTimestamp(index);

        /* Validate timestamp is at least equal to previous timestamp if basis point equals previous basis point */
        if (bid_.basisPoint == prevBidBasisPoint && prevTimestamp > bid_.timestamp) revert InvalidBidTimestamp(index);

        /* Validate redemption is not serviced */
        if (redemption.pendingShares == 0) revert InvalidRedemptionStatus(index);

        /* Validate reorder amount is not zero */
        if (bid_.reorderAmount == 0) revert InvalidReorderAmount(index);

        /* Validate bid is unique */
        if (auction_.bidIndices[bid_.redemptionId] != 0) revert DuplicatedBid(index);

        /* Validate bid nonce */
        if (auction_.nonces[bid_.redemptionId] != bid_.nonce) revert InvalidNonce(index);

        return bid_;
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
        return _getAuctionStorage().id;
    }

    /**
     * @inheritdoc IQEVRegistry
     */
    function nonce(uint256 auctionId_, uint256 redemptionId_) public view returns (uint256) {
        return _getAuctionStorage().auctions[auctionId_].nonces[redemptionId_];
    }

    /**
     * @inheritdoc IQEVRegistry
     */
    function auction(
        uint256 auctionId_
    )
        public
        view
        returns (
            uint256 bidIndex,
            uint256 reorderBidIndex,
            uint256 lastRedemptionId,
            uint64 auctionStart,
            uint64 auctionEnd
        )
    {
        /* Get auction storage */
        AuctionStorage storage auctionStorage = _getAuctionStorage();

        /* Get auction */
        Auction storage auction_ = auctionStorage.auctions[auctionId_];

        /* Get start time */
        uint64 startTime =
            auctionId_ == 0 ? auctionStorage.genesisTimestamp : auctionStorage.settlementTimestamps[auctionId_ - 1];

        /* Validate start time */
        if (startTime == 0) revert InvalidStartTime();

        return (
            auction_.bidIndex,
            auction_.reorderBidIndex,
            auction_.lastRedemptionId,
            startTime,
            startTime + auctionStorage.duration
        );
    }

    /**
     * @inheritdoc IQEVRegistry
     */
    function redemptionId(uint256 auctionId_, uint256 bidIndex) public view returns (uint256) {
        /* Validate bid index */
        if (bidIndex == 0) revert InvalidBidIndex();

        return _getAuctionStorage().auctions[auctionId_].bid[bidIndex].redemptionId;
    }

    /**
     * @inheritdoc IQEVRegistry
     */
    function bid(uint256 auctionId_, uint256 redemptionId_) public view returns (Bid memory) {
        /* Get bid index */
        uint256 bidIndex = _getAuctionStorage().auctions[auctionId_].bidIndices[redemptionId_];

        /* Validate bid */
        if (bidIndex == 0) revert InvalidBidIndex();

        return _getAuctionStorage().auctions[auctionId_].bid[bidIndex];
    }

    /**
     * @inheritdoc IQEVRegistry
     */
    function bids(uint256 auctionId_, uint256 offset, uint256 count) public view returns (Bid[] memory) {
        /* Clamp on count */
        count = Math.min(count, _getAuctionStorage().auctions[auctionId_].bidIndex - offset);

        /* Create arrays */
        Bid[] memory bids_ = new Bid[](count);

        /* Get start index */
        uint256 startIndex = offset + 1;

        /* Fill array */
        for (uint256 i = startIndex; i <= startIndex + count; i++) {
            bids_[i - startIndex] = _getAuctionStorage().auctions[auctionId_].bid[i];
        }

        return bids_;
    }

    /**
     * @inheritdoc IQEVRegistry
     */
    function settlementTimestamp(
        uint256 auctionId_
    ) public view returns (uint64) {
        return _getAuctionStorage().settlementTimestamps[auctionId_];
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
        /* Get auction end time. Reverts if genesis timestamp is not set */
        (,,,, uint64 auctionEnd) = auction(auctionId_);

        /* Validate auction has not ended */
        if (auctionEnd <= block.timestamp) revert InvalidTimestamp();

        /* Get redemption */
        (IStakedUSDai.Redemption memory redemption,) = _susdai.redemption(redemptionId_);

        /* Validate redemption controller is the caller */
        if (redemption.controller != msg.sender) revert InvalidCaller();

        /* Increment nonce */
        return ++_getAuctionStorage().auctions[auctionId_].nonces[redemptionId_];
    }

    /*------------------------------------------------------------------------*/
    /* Permissioned API  */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IQEVRegistry
     */
    function postBids(
        SignedBid[] calldata signedBids
    ) external nonReentrant previousAuctionReordered onlyRole(DEFAULT_ADMIN_ROLE) {
        /* Get current auction ID */
        uint256 auctionId_ = auctionId();

        /* Get current auction end time. Reverts if genesis timestamp is not set */
        (,,, uint64 auctionStart, uint64 auctionEnd) = auction(auctionId_);

        /* Validate auction ended */
        if (auctionEnd < block.timestamp) revert InvalidTimestamp();

        /* Get current auction */
        Auction storage auction_ = _getAuctionStorage().auctions[auctionId_];

        /* Reveal bids */
        uint256 bidIndex = auction_.bidIndex;
        uint256 prevBidBasisPoint = bidIndex == 0 ? type(uint256).max : auction_.bid[bidIndex].basisPoint;
        uint64 prevTimestamp = bidIndex == 0 ? 0 : auction_.bid[bidIndex].timestamp;
        for (uint256 i; i < signedBids.length; i++) {
            /* Validate bid */
            Bid memory bid_ = _validateBid(
                auctionId_, auction_, signedBids[i], prevBidBasisPoint, prevTimestamp, auctionStart, auctionEnd, i
            );

            /* Set bid index */
            auction_.bidIndices[bid_.redemptionId] = ++bidIndex;

            /* Add bid */
            auction_.bid[bidIndex] = bid_;

            /* Update previous bid basis point and timestamp */
            prevBidBasisPoint = bid_.basisPoint;
            prevTimestamp = bid_.timestamp;
        }

        /* Update bid index */
        auction_.bidIndex = bidIndex;
    }

    /**
     * @inheritdoc IQEVRegistry
     */
    function settleAuction() external nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        /* Get current auction ID */
        uint256 auctionId_ = auctionId();

        /* Get current auction end. Reverts if genesis timestamp is not set */
        (,,,, uint64 auctionEnd) = auction(auctionId_);

        /* Validate auction ended */
        if (auctionEnd < block.timestamp) revert InvalidTimestamp();

        /* Set auction duration */
        _getAuctionStorage().settlementTimestamps[auctionId_] = uint64(block.timestamp);

        /* Increment auction ID */
        _getAuctionStorage().id++;

        /* Emit AuctionSettled */
        emit AuctionSettled(auctionId_, block.timestamp);
    }

    /**
     * @inheritdoc IQEVRegistry
     */
    function setGenesisTimestamp(
        uint64 timestamp
    ) external nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        /* Validate genesis timestamp is not set and timestamp is not 0 */
        if (_getAuctionStorage().genesisTimestamp != 0 || timestamp == 0) revert InvalidTimestamp();

        /* Set genesis timestamp */
        _getAuctionStorage().genesisTimestamp = timestamp;

        /* Emit GenesisTimestampSet */
        emit GenesisTimestampSet(timestamp);
    }

    /**
     * @inheritdoc IQEVRegistry
     */
    function setAuctionDuration(
        uint64 duration
    ) external nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        /* Get current auction start time. Reverts if genesis timestamp is not set */
        (,,, uint64 auctionStart,) = auction(_getAuctionStorage().id);

        /* Validate auction duration is not too short */
        if (auctionStart + duration < block.timestamp) revert InvalidTimestamp();

        /* Set auction duration */
        _getAuctionStorage().duration = duration;

        /* Emit AuctionDurationSet */
        emit AuctionDurationSet(duration);
    }

    /**
     * @inheritdoc IQEVRegistry
     */
    function setCheckpoint(
        uint256 auctionId_,
        uint256 reorderBidIndex,
        uint256 lastRedemptionId
    ) external nonReentrant onlyRole(CHECKPOINT_ADMIN_ROLE) {
        /* Get auction */
        Auction storage auction_ = _getAuctionStorage().auctions[auctionId_];

        /* Set auction reorder checkpoint */
        auction_.reorderBidIndex = reorderBidIndex;
        auction_.lastRedemptionId = lastRedemptionId;

        /* Emit AuctionCheckpointSet */
        emit AuctionCheckpointSet(auctionId_, reorderBidIndex, lastRedemptionId);
    }
}
