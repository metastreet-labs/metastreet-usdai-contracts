// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {console} from "forge-std/console.sol";

import {OmnichainBaseTest} from "./Base.t.sol";

import {OptionsBuilder} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import {
    IOFT,
    SendParam,
    MessagingFee,
    OFTReceipt,
    MessagingReceipt
} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFTCore.sol";
import {OFTComposeMsgCodec} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/libs/OFTComposeMsgCodec.sol";

import {OUSDaiUtility} from "src/omnichain/OUSDaiUtility.sol";

import {IUSDaiQueuedDepositor} from "src/interfaces/IUSDaiQueuedDepositor.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract USDaiServiceQueuedDepositTest is OmnichainBaseTest {
    using OptionsBuilder for bytes;

    function setUp() public override {
        super.setUp();

        AccessControl(address(usdtHomeToken)).grantRole(usdtHomeToken.BRIDGE_ADMIN_ROLE(), address(this));
        usdtHomeToken.mint(user, 20_000_000 ether);
    }

    function test__USDaiServiceQueuedLocalDeposit() public {
        uint256 amount = 1_000_000 ether;

        // User approves USDai to spend their USD
        vm.startPrank(user);
        usdtHomeToken.approve(address(usdaiQueuedDepositor), amount * 3);

        // User deposits into USDai queued depositor
        uint256 queueIndex1 = usdaiQueuedDepositor.deposit(
            IUSDaiQueuedDepositor.QueueType.Deposit, address(usdtHomeToken), amount, user, 0
        );

        vm.stopPrank();

        usdaiQueuedDepositor.service(
            IUSDaiQueuedDepositor.QueueType.Deposit,
            abi.encode(address(usdtHomeToken), 500_000 ether, 500_000 ether, "")
        );

        IUSDaiQueuedDepositor.QueueItem memory queueItem1 =
            usdaiQueuedDepositor.queueItem(IUSDaiQueuedDepositor.QueueType.Deposit, address(usdtHomeToken), queueIndex1);
        assertEq(queueItem1.pendingDeposit, amount - 500_000 ether);
        assertEq(queueItem1.dstEid, 0);
        assertEq(queueItem1.depositor, user);
        assertEq(queueItem1.recipient, user);

        (uint256 head1, uint256 pending1, IUSDaiQueuedDepositor.QueueItem[] memory queueItems1) =
            usdaiQueuedDepositor.queueInfo(IUSDaiQueuedDepositor.QueueType.Deposit, address(usdtHomeToken), 0, 100);
        assertEq(head1, 0);
        assertEq(pending1, amount - 500_000 ether);
        assertEq(queueItems1.length, 1);

        assertEq(usdai.balanceOf(user), 500_000 ether);

        vm.startPrank(user);

        // User deposits into USDai queued depositor
        uint256 queueIndex2 = usdaiQueuedDepositor.deposit(
            IUSDaiQueuedDepositor.QueueType.Deposit, address(usdtHomeToken), 1_000_000 ether, user, 0
        );

        vm.stopPrank();

        usdaiQueuedDepositor.service(
            IUSDaiQueuedDepositor.QueueType.Deposit,
            abi.encode(address(usdtHomeToken), 1_000_000 ether, 1_000_000 ether, "")
        );

        IUSDaiQueuedDepositor.QueueItem memory queueItem2 =
            usdaiQueuedDepositor.queueItem(IUSDaiQueuedDepositor.QueueType.Deposit, address(usdtHomeToken), queueIndex2);
        assertEq(queueItem2.pendingDeposit, 500_000 ether);
        assertEq(queueItem2.dstEid, 0);
        assertEq(queueItem2.depositor, user);
        assertEq(queueItem2.recipient, user);

        (uint256 head2, uint256 pending2, IUSDaiQueuedDepositor.QueueItem[] memory queueItems2) =
            usdaiQueuedDepositor.queueInfo(IUSDaiQueuedDepositor.QueueType.Deposit, address(usdtHomeToken), 0, 100);
        assertEq(head2, 1);
        assertEq(pending2, 500_000 ether);
        assertEq(queueItems2.length, 2);

        usdaiQueuedDepositor.service(
            IUSDaiQueuedDepositor.QueueType.Deposit,
            abi.encode(address(usdtHomeToken), 500_000 ether, 500_000 ether, "")
        );

        (uint256 head3, uint256 pending3, IUSDaiQueuedDepositor.QueueItem[] memory queueItems3) =
            usdaiQueuedDepositor.queueInfo(IUSDaiQueuedDepositor.QueueType.Deposit, address(usdtHomeToken), 0, 100);
        assertEq(head3, 2);
        assertEq(pending3, 0);
        assertEq(queueItems3.length, 2);

        assertEq(usdai.balanceOf(user), 2_000_000 ether);

        vm.expectRevert();
        usdaiQueuedDepositor.service(
            IUSDaiQueuedDepositor.QueueType.Deposit, abi.encode(address(usdtHomeToken), 100, 100, "")
        );

        vm.startPrank(user);

        // User deposits into USDai queued depositor
        uint256 queueIndex3 = usdaiQueuedDepositor.deposit(
            IUSDaiQueuedDepositor.QueueType.Deposit, address(usdtHomeToken), 1_000_000 ether, user, 0
        );

        vm.stopPrank();

        IUSDaiQueuedDepositor.QueueItem memory queueItem4 =
            usdaiQueuedDepositor.queueItem(IUSDaiQueuedDepositor.QueueType.Deposit, address(usdtHomeToken), queueIndex3);
        assertEq(queueItem4.pendingDeposit, 1_000_000 ether);
        assertEq(queueItem4.dstEid, 0);
        assertEq(queueItem4.depositor, user);
        assertEq(queueItem4.recipient, user);

        (uint256 head4, uint256 pending4, IUSDaiQueuedDepositor.QueueItem[] memory queueItems4) =
            usdaiQueuedDepositor.queueInfo(IUSDaiQueuedDepositor.QueueType.Deposit, address(usdtHomeToken), 0, 100);
        assertEq(head4, 2);
        assertEq(pending4, 1_000_000 ether);
        assertEq(queueItems4.length, 3);

        assertEq(usdai.balanceOf(user), 2_000_000 ether);

        usdaiQueuedDepositor.service(
            IUSDaiQueuedDepositor.QueueType.Deposit,
            abi.encode(address(usdtHomeToken), 1_000_000 ether, 1_000_000 ether, "")
        );

        assertEq(usdai.balanceOf(user), 3_000_000 ether);
        assertEq(IERC20(queuedUSDaiToken).balanceOf(user), 0);
    }

    function test__USDaiServiceQueuedLocalDeposit_WithBlacklistedAccount() public {
        uint256 amount = 1_000_000 ether;

        // User approves USDai to spend their USD
        vm.startPrank(user);
        usdtHomeToken.approve(address(usdaiQueuedDepositor), amount * 2);

        // User deposits into USDai queued depositor
        usdaiQueuedDepositor.deposit(IUSDaiQueuedDepositor.QueueType.Deposit, address(usdtHomeToken), amount, user, 0);

        // User deposits into USDai queued depositor
        usdaiQueuedDepositor.deposit(
            IUSDaiQueuedDepositor.QueueType.Deposit, address(usdtHomeToken), amount, blacklistedUser, 0
        );

        vm.stopPrank();

        usdaiQueuedDepositor.service(
            IUSDaiQueuedDepositor.QueueType.Deposit,
            abi.encode(address(usdtHomeToken), 1_000_000 ether, 1_000_000 ether, "")
        );

        assertEq(usdai.balanceOf(user), 1_000_000 ether);
        assertEq(usdai.balanceOf(blacklistedUser), 0);
    }

    function test__USDaiServiceQueuedLocalDepositAndStake() public {
        uint256 amount = 1_000_000 ether;

        // User approves USDai to spend their USD
        vm.startPrank(user);
        usdtHomeToken.approve(address(usdaiQueuedDepositor), amount * 3);

        // User deposits into USDai queued depositor
        uint256 queueIndex1 = usdaiQueuedDepositor.deposit(
            IUSDaiQueuedDepositor.QueueType.DepositAndStake, address(usdtHomeToken), amount, user, 0
        );

        vm.stopPrank();

        usdaiQueuedDepositor.service(
            IUSDaiQueuedDepositor.QueueType.DepositAndStake,
            abi.encode(address(usdtHomeToken), 500_000 ether, 500_000 ether, "", 500_000 ether - 1e6)
        );

        IUSDaiQueuedDepositor.QueueItem memory queueItem1 = usdaiQueuedDepositor.queueItem(
            IUSDaiQueuedDepositor.QueueType.DepositAndStake, address(usdtHomeToken), queueIndex1
        );
        assertEq(queueItem1.pendingDeposit, amount - 500_000 ether);
        assertEq(queueItem1.dstEid, 0);
        assertEq(queueItem1.depositor, user);
        assertEq(queueItem1.recipient, user);

        (uint256 head1, uint256 pending1, IUSDaiQueuedDepositor.QueueItem[] memory queueItems1) = usdaiQueuedDepositor
            .queueInfo(IUSDaiQueuedDepositor.QueueType.DepositAndStake, address(usdtHomeToken), 0, 100);
        assertEq(head1, 0);
        assertEq(pending1, amount - 500_000 ether);
        assertEq(queueItems1.length, 1);

        assertEq(IERC20(address(stakedUsdai)).balanceOf(user), 500_000 ether - 1e6);

        vm.startPrank(user);

        // User deposits into USDai queued depositor
        uint256 queueIndex2 = usdaiQueuedDepositor.deposit(
            IUSDaiQueuedDepositor.QueueType.DepositAndStake, address(usdtHomeToken), 1_000_000 ether, user, 0
        );

        vm.stopPrank();

        // Get the deposit share price and min shares
        uint256 depositSharePrice1 = stakedUsdai.depositSharePrice();
        uint256 minShares1 = 1_000_000 ether * 1e18 / depositSharePrice1;

        usdaiQueuedDepositor.service(
            IUSDaiQueuedDepositor.QueueType.DepositAndStake,
            abi.encode(address(usdtHomeToken), 1_000_000 ether, 1_000_000 ether, "", minShares1)
        );

        IUSDaiQueuedDepositor.QueueItem memory queueItem2 = usdaiQueuedDepositor.queueItem(
            IUSDaiQueuedDepositor.QueueType.DepositAndStake, address(usdtHomeToken), queueIndex2
        );
        assertEq(queueItem2.pendingDeposit, 500_000 ether);
        assertEq(queueItem2.dstEid, 0);
        assertEq(queueItem2.depositor, user);
        assertEq(queueItem2.recipient, user);

        (uint256 head2, uint256 pending2, IUSDaiQueuedDepositor.QueueItem[] memory queueItems2) = usdaiQueuedDepositor
            .queueInfo(IUSDaiQueuedDepositor.QueueType.DepositAndStake, address(usdtHomeToken), 0, 100);
        assertEq(head2, 1);
        assertEq(pending2, 500_000 ether);
        assertEq(queueItems2.length, 2);

        uint256 depositSharePrice2 = stakedUsdai.depositSharePrice();
        uint256 minShares2 = 500_000 ether * 1e18 / depositSharePrice2;

        usdaiQueuedDepositor.service(
            IUSDaiQueuedDepositor.QueueType.DepositAndStake,
            abi.encode(address(usdtHomeToken), 500_000 ether, 500_000 ether, "", minShares2)
        );

        (uint256 head3, uint256 pending3, IUSDaiQueuedDepositor.QueueItem[] memory queueItems3) = usdaiQueuedDepositor
            .queueInfo(IUSDaiQueuedDepositor.QueueType.DepositAndStake, address(usdtHomeToken), 0, 100);
        assertEq(head3, 2);
        assertEq(pending3, 0);
        assertEq(queueItems3.length, 2);

        assertEq(IERC20(address(stakedUsdai)).balanceOf(user), 500_000 ether - 1e6 + minShares1 + minShares2);

        vm.startPrank(user);

        // User deposits into USDai queued depositor
        uint256 queueIndex3 = usdaiQueuedDepositor.deposit(
            IUSDaiQueuedDepositor.QueueType.DepositAndStake, address(usdtHomeToken), 1_000_000 ether, user, 0
        );

        vm.stopPrank();

        IUSDaiQueuedDepositor.QueueItem memory queueItem4 = usdaiQueuedDepositor.queueItem(
            IUSDaiQueuedDepositor.QueueType.DepositAndStake, address(usdtHomeToken), queueIndex3
        );
        assertEq(queueItem4.pendingDeposit, 1_000_000 ether);
        assertEq(queueItem4.dstEid, 0);
        assertEq(queueItem4.depositor, user);
        assertEq(queueItem4.recipient, user);

        (uint256 head4, uint256 pending4, IUSDaiQueuedDepositor.QueueItem[] memory queueItems4) = usdaiQueuedDepositor
            .queueInfo(IUSDaiQueuedDepositor.QueueType.DepositAndStake, address(usdtHomeToken), 0, 100);
        assertEq(head4, 2);
        assertEq(pending4, 1_000_000 ether);
        assertEq(queueItems4.length, 3);

        assertEq(IERC20(address(stakedUsdai)).balanceOf(user), 500_000 ether - 1e6 + minShares1 + minShares2);

        uint256 depositSharePrice3 = stakedUsdai.depositSharePrice();
        uint256 minShares3 = 1_000_000 ether * 1e18 / depositSharePrice3;

        usdaiQueuedDepositor.service(
            IUSDaiQueuedDepositor.QueueType.DepositAndStake,
            abi.encode(address(usdtHomeToken), 1_000_000 ether, 1_000_000 ether, "", minShares3)
        );

        assertEq(
            IERC20(address(stakedUsdai)).balanceOf(user), 500_000 ether - 1e6 + minShares1 + minShares2 + minShares3
        );
        assertEq(IERC20(queuedStakedUSDaiToken).balanceOf(user), 0);
    }

    function test__USDaiServiceQueuedOmnichainDeposit() public {
        uint256 amount = 1_000_000 ether;

        // User approves USDai to spend their USD
        vm.startPrank(user);
        usdtHomeToken.approve(address(usdaiQueuedDepositor), amount);

        // User deposits into USDai queued depositor
        usdaiQueuedDepositor.deposit(
            IUSDaiQueuedDepositor.QueueType.Deposit, address(usdtHomeToken), amount, user, usdaiAwayEid
        );

        vm.stopPrank();

        // Deal some ETH to the USDai queued depositor to cover the native fee
        vm.deal(address(usdaiQueuedDepositor), 100 ether);

        usdaiQueuedDepositor.service(
            IUSDaiQueuedDepositor.QueueType.Deposit, abi.encode(address(usdtHomeToken), amount, amount, "")
        );

        // Verify that the packets were correctly sent to the destination chain.
        // @param _dstEid The endpoint ID of the destination chain.
        // @param _dstAddress The OApp address on the destination chain.
        verifyPackets(usdaiAwayEid, addressToBytes32(address(usdaiAwayOAdapter)));

        assertEq(usdaiAwayToken.balanceOf(user), amount);
    }

    function test__USDaiServiceQueuedOmnichainDepositAndStake() public {
        uint256 amount = 1_000_000 ether;

        // User approves USDai to spend their USD
        vm.startPrank(user);
        usdtHomeToken.approve(address(usdaiQueuedDepositor), amount);

        // User deposits into USDai queued depositor
        usdaiQueuedDepositor.deposit(
            IUSDaiQueuedDepositor.QueueType.DepositAndStake, address(usdtHomeToken), amount, user, stakedUsdaiAwayEid
        );

        vm.stopPrank();

        // Deal some ETH to the USDai queued depositor to cover the native fee
        vm.deal(address(usdaiQueuedDepositor), 100 ether);

        usdaiQueuedDepositor.service(
            IUSDaiQueuedDepositor.QueueType.DepositAndStake,
            abi.encode(address(usdtHomeToken), amount, amount, "", amount - 1e6)
        );

        // Verify that the packets were correctly sent to the destination chain.
        // @param _dstEid The endpoint ID of the destination chain.
        // @param _dstAddress The OApp address on the destination chain.
        verifyPackets(stakedUsdaiAwayEid, addressToBytes32(address(stakedUsdaiAwayOAdapter)));

        uint256 amountWithoutDust = (amount - 1e6) / 1e12 * 1e12;

        assertEq(IERC20(address(stakedUsdaiAwayToken)).balanceOf(user), amountWithoutDust);
    }

    function test__USDaiServiceQueuedOmnichainDeposit_LocalSource_LocalDestination() public {
        vm.startPrank(user);

        // Data
        bytes memory data = abi.encode(IUSDaiQueuedDepositor.QueueType.Deposit, user, 0);

        // Approve the USDAI utility to spend the USD
        usdtHomeToken.approve(address(oUsdaiUtility), initialBalance);

        // Deposit the USD
        oUsdaiUtility.queuedDeposit(address(usdtHomeToken), initialBalance, data);

        // Assert that the USDAI home token was minted to the user
        assertEq(usdtHomeToken.balanceOf(address(usdaiQueuedDepositor)), initialBalance);

        vm.stopPrank();

        // Service the deposit
        usdaiQueuedDepositor.service(
            IUSDaiQueuedDepositor.QueueType.Deposit,
            abi.encode(address(usdtHomeToken), initialBalance, initialBalance, "", initialBalance - 1e6)
        );

        // Assert that the USDAI home token was minted to the user
        assertEq(usdai.balanceOf(user), initialBalance);

        // Assert that the USDT home token was burned
        assertEq(usdtHomeToken.balanceOf(address(usdaiQueuedDepositor)), 0);
    }

    function test__USDaiServiceQueuedOmnichainDeposit_LocalSource_ForeignDestination() public {
        vm.startPrank(user);

        // Data
        bytes memory data = abi.encode(IUSDaiQueuedDepositor.QueueType.Deposit, user, usdaiAwayEid);

        // Approve the USDAI utility to spend the USD
        usdtHomeToken.approve(address(oUsdaiUtility), initialBalance);

        // Deposit the USD
        oUsdaiUtility.queuedDeposit(address(usdtHomeToken), initialBalance, data);

        vm.stopPrank();

        // Deal some ETH to the USDai queued depositor to cover the native fee
        vm.deal(address(usdaiQueuedDepositor), 100 ether);

        // Service the deposit
        usdaiQueuedDepositor.service(
            IUSDaiQueuedDepositor.QueueType.Deposit,
            abi.encode(address(usdtHomeToken), initialBalance, initialBalance, "", initialBalance - 1e6)
        );

        // Verify that the packets were correctly sent to the destination chain
        verifyPackets(usdaiAwayEid, addressToBytes32(address(usdaiAwayOAdapter)));

        // Assert that the USDAI away token was minted to the user
        assertEq(usdaiAwayToken.balanceOf(user), initialBalance);

        vm.stopPrank();
    }

    function test__USDaiServiceQueuedOmnichainDepositAndStake_RevertWhen_InsufficientBalance() public {
        uint256 amount = 1_000_000 ether;

        // User approves USDai to spend their USD
        vm.startPrank(user);
        usdtHomeToken.approve(address(usdaiQueuedDepositor), amount);

        // User deposits into USDai queued depositor
        usdaiQueuedDepositor.deposit(
            IUSDaiQueuedDepositor.QueueType.DepositAndStake, address(usdtHomeToken), amount, user, stakedUsdaiAwayEid
        );

        vm.stopPrank();

        vm.expectRevert(IUSDaiQueuedDepositor.InsufficientBalance.selector);
        usdaiQueuedDepositor.service(
            IUSDaiQueuedDepositor.QueueType.DepositAndStake,
            abi.encode(address(usdtHomeToken), amount, amount, "", amount - 1e6)
        );
    }
}
