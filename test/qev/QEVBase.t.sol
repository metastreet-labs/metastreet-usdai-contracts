// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "../Base.t.sol";
import {QEVRegistry} from "src/QEVRegistry.sol";
import {IQEVRegistry} from "src/interfaces/IQEVRegistry.sol";
import {StakedUSDai} from "src/StakedUSDai.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import {IStakedUSDai} from "src/interfaces/IStakedUSDai.sol";

/**
 * @title QEV Base Test Setup
 * @notice Extended base test class with QEV registry setup and utilities
 * @dev Provides signature generation, auction management, and queue inspection helpers
 */
abstract contract QEVBaseTest is BaseTest {
    using ECDSA for bytes32;

    /*------------------------------------------------------------------------*/
    /* Constants */
    /*------------------------------------------------------------------------*/

    /// Bid typehash for EIP-712
    bytes32 internal constant BID_TYPEHASH = keccak256(
        "Bid(uint64 auctionId,uint256 redemptionId,uint256 redemptionShares,uint256 basisPoint,uint256 nonce)"
    );

    /// Admin fee rate (1%)
    uint256 internal constant ADMIN_FEE_RATE = 100;

    /*------------------------------------------------------------------------*/
    /* State Variables */
    /*------------------------------------------------------------------------*/

    // EIP-712 domain separator
    bytes32 internal domainSeparator;

    // Test user private keys for signing
    uint256 internal user1PrivateKey = 0x1;
    uint256 internal user2PrivateKey = 0x2;
    uint256 internal user3PrivateKey = 0x3;

    address internal user1 = vm.addr(user1PrivateKey);
    address internal user2 = vm.addr(user2PrivateKey);
    address internal user3 = vm.addr(user3PrivateKey);

    /*------------------------------------------------------------------------*/
    /* Setup */
    /*------------------------------------------------------------------------*/

    function setUp() public virtual override {
        super.setUp();
        setDomainSeparator();
        fundTestUsers();
    }

    /*------------------------------------------------------------------------*/
    /* QEV Deployment */
    /*------------------------------------------------------------------------*/

    function setDomainSeparator() internal {
        // Calculate domain separator
        domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("QEVRegistry"),
                keccak256("1.0"),
                block.chainid,
                address(qevRegistry)
            )
        );
    }

    function fundTestUsers() internal {
        // Fund test users with USD
        vm.startPrank(users.deployer);
        usd.transfer(user1, 10_000_000 ether);
        usd.transfer(user2, 10_000_000 ether);
        usd.transfer(user3, 10_000_000 ether);
        vm.stopPrank();

        // Convert USD to USDai for test users
        address[3] memory testUsers = [user1, user2, user3];
        for (uint256 i = 0; i < testUsers.length; i++) {
            vm.startPrank(testUsers[i]);
            usd.approve(address(usdai), type(uint256).max);
            uint256 usdaiBalance = usdai.deposit(address(usd), 1_000_000 ether, 0, testUsers[i]);
            usdai.approve(address(stakedUsdai), type(uint256).max);
            stakedUsdai.deposit(usdaiBalance, testUsers[i]);
            vm.stopPrank();
        }
    }

    /*------------------------------------------------------------------------*/
    /* Signature Utilities */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Generate EIP-712 signature for a bid
     * @param bid Bid to sign
     * @param privateKey Private key to sign with
     * @return signature EIP-712 signature
     */
    function signBid(IQEVRegistry.Bid memory bid, uint256 privateKey) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(
            abi.encode(BID_TYPEHASH, bid.auctionId, bid.redemptionId, bid.redemptionShares, bid.basisPoint, bid.nonce)
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    /**
     * @notice Create a signed bid
     * @dev IMPORTANT: When posting multiple bids, they must be ordered by basis points
     *      from highest to lowest. Use timestamp for tie-breaking if basis points are equal.
     * @param auctionId Auction ID
     * @param redemptionId Redemption ID
     * @param redemptionShares Amount to reorder
     * @param basisPoint Basis point bid
     * @param privateKey Private key to sign with
     * @return signedBid Signed bid
     */
    function createSignedBid(
        uint64 auctionId,
        uint256 redemptionId,
        uint256 redemptionShares,
        uint256 basisPoint,
        uint256 privateKey
    ) internal view returns (IQEVRegistry.SignedBid memory) {
        uint256 nonce = qevRegistry.nonce(auctionId, redemptionId);

        IQEVRegistry.Bid memory bid = IQEVRegistry.Bid({
            auctionId: auctionId,
            redemptionId: redemptionId,
            redemptionShares: redemptionShares,
            basisPoint: basisPoint,
            nonce: nonce
        });

        bytes memory signature = signBid(bid, privateKey);

        return IQEVRegistry.SignedBid({bid: bid, signature: signature});
    }

    /**
     * @notice Sort bids by basis points (highest to lowest) with redemption ID tie-breaking
     * @dev Bids must be posted in descending order by basis points
     * @param signedBids Array of signed bids to sort
     * @return sortedBids Properly sorted array
     */
    function sortBids(
        IQEVRegistry.SignedBid[] memory signedBids
    ) internal pure returns (IQEVRegistry.SignedBid[] memory) {
        uint256 length = signedBids.length;
        if (length <= 1) return signedBids;

        // Simple bubble sort (fine for test arrays)
        for (uint256 i = 0; i < length - 1; i++) {
            for (uint256 j = 0; j < length - i - 1; j++) {
                bool shouldSwap = false;

                // Primary sort: higher basis points first
                if (signedBids[j].bid.basisPoint < signedBids[j + 1].bid.basisPoint) {
                    shouldSwap = true;
                }
                // Tie-breaking: earlier redemption ID first (if basis points equal)
                else if (
                    signedBids[j].bid.basisPoint == signedBids[j + 1].bid.basisPoint
                        && signedBids[j].bid.redemptionId > signedBids[j + 1].bid.redemptionId
                ) {
                    shouldSwap = true;
                }

                if (shouldSwap) {
                    IQEVRegistry.SignedBid memory temp = signedBids[j];
                    signedBids[j] = signedBids[j + 1];
                    signedBids[j + 1] = temp;
                }
            }
        }

        return signedBids;
    }

    /**
     * @notice Post bids with automatic sorting
     * @param signedBids Array of signed bids (will be sorted automatically)
     */
    function postSortedBids(
        IQEVRegistry.SignedBid[] memory signedBids
    ) internal {
        IQEVRegistry.SignedBid[] memory sortedBids = sortBids(signedBids);

        // Get the upcoming auction ID
        uint64 auctionId = qevRegistry.nextAuctionId();

        advanceAuctionTime(auctionId);

        vm.prank(users.manager);
        qevRegistry.postBids(auctionId, sortedBids);
    }

    /*------------------------------------------------------------------------*/
    /* Auction Utilities */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Advance time to auction time
     * @param auctionId Auction ID to advance time for
     */
    function advanceAuctionTime(
        uint64 auctionId
    ) internal {
        vm.warp(auctionId + 1);
    }

    /*------------------------------------------------------------------------*/
    /* Redemption Utilities */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Request redemption for a user
     * @param user User address
     * @param shares Amount of shares to redeem
     * @return redemptionId Redemption ID
     */
    function requestRedemption(address user, uint256 shares) internal returns (uint256) {
        vm.prank(user);
        return stakedUsdai.requestRedeem(shares, user, user);
    }

    /**
     * @notice Get redemption queue state
     * @return index Current redemption index
     * @return head Head of queue
     * @return tail Tail of queue
     * @return pending Total pending shares
     * @return redemptionBalance Total redemption balance
     */
    function getQueueState() internal view returns (uint256, uint256, uint256, uint256, uint256) {
        return stakedUsdai.redemptionQueueInfo();
    }

    /**
     * @notice Assert queue integrity by checking linked list structure
     * @param expectedOrder Array of redemption IDs in expected queue order
     */
    function assertQueueIntegrity(
        uint256[] memory expectedOrder
    ) internal view {
        (, uint256 head, uint256 tail,,) = getQueueState();

        if (expectedOrder.length == 0) {
            assertEq(head, 0, "Queue head should be 0 for empty queue");
            assertEq(tail, 0, "Queue tail should be 0 for empty queue");
            return;
        }

        // Check head and tail
        assertEq(head, expectedOrder[0], "Queue head mismatch");
        assertEq(tail, expectedOrder[expectedOrder.length - 1], "Queue tail mismatch");

        // Check forward links
        for (uint256 i = 0; i < expectedOrder.length; i++) {
            (IStakedUSDai.Redemption memory redemption,) = stakedUsdai.redemption(expectedOrder[i]);

            if (i == 0) {
                assertEq(redemption.prev, 0, "First redemption should have no prev");
            } else {
                assertEq(redemption.prev, expectedOrder[i - 1], "Incorrect prev link");
            }

            if (i == expectedOrder.length - 1) {
                assertEq(redemption.next, 0, "Last redemption should have no next");
            } else {
                assertEq(redemption.next, expectedOrder[i + 1], "Incorrect next link");
            }
        }
    }

    /*------------------------------------------------------------------------*/
    /* Test Utilities */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Skip to next block and update timestamp
     */
    function skipBlock() internal {
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 12);
    }

    /**
     * @notice Skip forward by specified time
     * @param time Time to skip in seconds
     */
    function skipTime(
        uint256 time
    ) internal {
        vm.warp(block.timestamp + time);
    }
}
