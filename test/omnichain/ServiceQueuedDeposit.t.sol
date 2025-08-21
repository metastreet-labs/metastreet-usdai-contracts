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

import {IOUSDaiUtility} from "src/interfaces/IOUSDaiUtility.sol";
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
        usdtHomeToken.approve(address(usdaiQueuedDepositor), amount * 4);

        // User deposits into USDai queued depositor
        uint256 queueIndex1 = usdaiQueuedDepositor.deposit(
            IUSDaiQueuedDepositor.QueueType.Deposit, address(usdtHomeToken), amount, user, 0
        );

        vm.stopPrank();

        usdaiQueuedDepositor.service(
            IUSDaiQueuedDepositor.QueueType.Deposit, abi.encode(address(usdtHomeToken), 1, 0, 0, "")
        );

        IUSDaiQueuedDepositor.QueueItem memory queueItem1 =
            usdaiQueuedDepositor.queueItem(IUSDaiQueuedDepositor.QueueType.Deposit, address(usdtHomeToken), queueIndex1);
        assertEq(queueItem1.pendingDeposit, 0);
        assertEq(queueItem1.dstEid, 0);
        assertEq(queueItem1.depositor, user);
        assertEq(queueItem1.recipient, user);

        (uint256 head1, uint256 pending1, IUSDaiQueuedDepositor.QueueItem[] memory queueItems1) =
            usdaiQueuedDepositor.queueInfo(IUSDaiQueuedDepositor.QueueType.Deposit, address(usdtHomeToken), 0, 100);
        assertEq(head1, 1);
        assertEq(pending1, 0);
        assertEq(queueItems1.length, 1);

        assertEq(usdai.balanceOf(user), amount);

        vm.startPrank(user);

        // User deposits into USDai queued depositor
        uint256 queueIndex2 = usdaiQueuedDepositor.deposit(
            IUSDaiQueuedDepositor.QueueType.Deposit, address(usdtHomeToken), 1_000_000 ether, user, 0
        );

        vm.stopPrank();

        usdaiQueuedDepositor.service(
            IUSDaiQueuedDepositor.QueueType.Deposit, abi.encode(address(usdtHomeToken), 1, 0, 0, "")
        );

        IUSDaiQueuedDepositor.QueueItem memory queueItem2 =
            usdaiQueuedDepositor.queueItem(IUSDaiQueuedDepositor.QueueType.Deposit, address(usdtHomeToken), queueIndex2);
        assertEq(queueItem2.pendingDeposit, 0);
        assertEq(queueItem2.dstEid, 0);
        assertEq(queueItem2.depositor, user);
        assertEq(queueItem2.recipient, user);

        (uint256 head2, uint256 pending2, IUSDaiQueuedDepositor.QueueItem[] memory queueItems2) =
            usdaiQueuedDepositor.queueInfo(IUSDaiQueuedDepositor.QueueType.Deposit, address(usdtHomeToken), 0, 100);
        assertEq(head2, 2);
        assertEq(pending2, 0);
        assertEq(queueItems2.length, 2);

        vm.expectRevert(IUSDaiQueuedDepositor.InvalidQueueState.selector);
        usdaiQueuedDepositor.service(
            IUSDaiQueuedDepositor.QueueType.Deposit, abi.encode(address(usdtHomeToken), 1, 0, 0, "")
        );

        assertEq(usdai.balanceOf(user), amount * 2);

        vm.startPrank(user);

        // User deposits into USDai queued depositor
        usdaiQueuedDepositor.deposit(
            IUSDaiQueuedDepositor.QueueType.Deposit, address(usdtHomeToken), 1_000_000 ether, user, 0
        );

        // User deposits into USDai queued depositor
        usdaiQueuedDepositor.deposit(
            IUSDaiQueuedDepositor.QueueType.Deposit, address(usdtHomeToken), 1_000_000 ether, user, 0
        );

        vm.stopPrank();

        usdaiQueuedDepositor.service(
            IUSDaiQueuedDepositor.QueueType.Deposit, abi.encode(address(usdtHomeToken), 3, 0, 10, "")
        );

        assertEq(usdai.balanceOf(user), 4_000_000 ether);
        assertEq(IERC20(queuedUSDaiToken).balanceOf(user), 0);
    }

    function test__USDaiServiceQueuedLocalDeposit_With_MaxServiceAmount() public {
        uint256 amount = 1_000_000 ether;

        // User approves USDai to spend their USD
        vm.startPrank(user);
        usdtHomeToken.approve(address(usdaiQueuedDepositor), amount * 4);

        // User deposits into USDai queued depositor
        uint256 queueIndex1 = usdaiQueuedDepositor.deposit(
            IUSDaiQueuedDepositor.QueueType.Deposit, address(usdtHomeToken), amount, user, 0
        );

        vm.stopPrank();

        usdaiQueuedDepositor.service(
            IUSDaiQueuedDepositor.QueueType.Deposit, abi.encode(address(usdtHomeToken), 1, 500_000 ether, 0, "")
        );

        IUSDaiQueuedDepositor.QueueItem memory queueItem1 =
            usdaiQueuedDepositor.queueItem(IUSDaiQueuedDepositor.QueueType.Deposit, address(usdtHomeToken), queueIndex1);
        assertEq(queueItem1.pendingDeposit, 500_000 ether);
        assertEq(queueItem1.dstEid, 0);
        assertEq(queueItem1.depositor, user);
        assertEq(queueItem1.recipient, user);

        (uint256 head1, uint256 pending1, IUSDaiQueuedDepositor.QueueItem[] memory queueItems1) =
            usdaiQueuedDepositor.queueInfo(IUSDaiQueuedDepositor.QueueType.Deposit, address(usdtHomeToken), 0, 100);
        assertEq(head1, 0);
        assertEq(pending1, 500_000 ether);
        assertEq(queueItems1.length, 1);

        assertEq(usdai.balanceOf(user), 500_000 ether);

        vm.startPrank(user);

        // User deposits into USDai queued depositor
        uint256 queueIndex2 = usdaiQueuedDepositor.deposit(
            IUSDaiQueuedDepositor.QueueType.Deposit, address(usdtHomeToken), 1_000_000 ether, user, 0
        );

        vm.stopPrank();

        usdaiQueuedDepositor.service(
            IUSDaiQueuedDepositor.QueueType.Deposit, abi.encode(address(usdtHomeToken), 1, 500_000 ether, 0, "")
        );

        IUSDaiQueuedDepositor.QueueItem memory queueItem2 =
            usdaiQueuedDepositor.queueItem(IUSDaiQueuedDepositor.QueueType.Deposit, address(usdtHomeToken), queueIndex2);
        assertEq(queueItem2.pendingDeposit, 1_000_000 ether);
        assertEq(queueItem2.dstEid, 0);
        assertEq(queueItem2.depositor, user);
        assertEq(queueItem2.recipient, user);

        (uint256 head2, uint256 pending2, IUSDaiQueuedDepositor.QueueItem[] memory queueItems2) =
            usdaiQueuedDepositor.queueInfo(IUSDaiQueuedDepositor.QueueType.Deposit, address(usdtHomeToken), 0, 100);
        assertEq(head2, 1);
        assertEq(pending2, 1_000_000 ether);
        assertEq(queueItems2.length, 2);

        usdaiQueuedDepositor.service(
            IUSDaiQueuedDepositor.QueueType.Deposit, abi.encode(address(usdtHomeToken), 1, 200_000 ether, 0, "")
        );

        queueItem2 =
            usdaiQueuedDepositor.queueItem(IUSDaiQueuedDepositor.QueueType.Deposit, address(usdtHomeToken), queueIndex2);
        assertEq(queueItem2.pendingDeposit, 800_000 ether);
        assertEq(queueItem2.dstEid, 0);
        assertEq(queueItem2.depositor, user);
        assertEq(queueItem2.recipient, user);

        (head2, pending2, queueItems2) =
            usdaiQueuedDepositor.queueInfo(IUSDaiQueuedDepositor.QueueType.Deposit, address(usdtHomeToken), 0, 100);
        assertEq(head2, 1);
        assertEq(pending2, 800_000 ether);
        assertEq(queueItems2.length, 2);
    }

    function test__USDaiServiceQueuedLocalDeposit_6Decimals() public {
        uint256 amount = 1_000_000 * 1e6;

        // User approves USDai to spend their USD
        vm.startPrank(user);
        usdtHomeToken6Decimals.approve(address(usdaiQueuedDepositor), amount * 4);

        // User deposits into USDai queued depositor
        uint256 queueIndex1 = usdaiQueuedDepositor.deposit(
            IUSDaiQueuedDepositor.QueueType.Deposit, address(usdtHomeToken6Decimals), amount, user, 0
        );

        vm.stopPrank();

        usdaiQueuedDepositor.service(
            IUSDaiQueuedDepositor.QueueType.Deposit, abi.encode(address(usdtHomeToken6Decimals), 1, 0, 0, "")
        );

        IUSDaiQueuedDepositor.QueueItem memory queueItem1 = usdaiQueuedDepositor.queueItem(
            IUSDaiQueuedDepositor.QueueType.Deposit, address(usdtHomeToken6Decimals), queueIndex1
        );
        assertEq(queueItem1.pendingDeposit, 0);
        assertEq(queueItem1.dstEid, 0);
        assertEq(queueItem1.depositor, user);
        assertEq(queueItem1.recipient, user);

        (uint256 head1, uint256 pending1, IUSDaiQueuedDepositor.QueueItem[] memory queueItems1) = usdaiQueuedDepositor
            .queueInfo(IUSDaiQueuedDepositor.QueueType.Deposit, address(usdtHomeToken6Decimals), 0, 100);
        assertEq(head1, 1);
        assertEq(pending1, 0);
        assertEq(queueItems1.length, 1);

        assertEq(usdai.balanceOf(user), 1_000_000 ether);

        vm.startPrank(user);

        // User deposits into USDai queued depositor
        uint256 queueIndex2 = usdaiQueuedDepositor.deposit(
            IUSDaiQueuedDepositor.QueueType.Deposit, address(usdtHomeToken6Decimals), amount, user, 0
        );

        vm.stopPrank();

        usdaiQueuedDepositor.service(
            IUSDaiQueuedDepositor.QueueType.Deposit, abi.encode(address(usdtHomeToken6Decimals), 1, 0, 0, "")
        );

        IUSDaiQueuedDepositor.QueueItem memory queueItem2 = usdaiQueuedDepositor.queueItem(
            IUSDaiQueuedDepositor.QueueType.Deposit, address(usdtHomeToken6Decimals), queueIndex2
        );
        assertEq(queueItem2.pendingDeposit, 0);
        assertEq(queueItem2.dstEid, 0);
        assertEq(queueItem2.depositor, user);
        assertEq(queueItem2.recipient, user);

        (uint256 head2, uint256 pending2, IUSDaiQueuedDepositor.QueueItem[] memory queueItems2) = usdaiQueuedDepositor
            .queueInfo(IUSDaiQueuedDepositor.QueueType.Deposit, address(usdtHomeToken6Decimals), 0, 100);
        assertEq(head2, 2);
        assertEq(pending2, 0);
        assertEq(queueItems2.length, 2);

        vm.expectRevert(IUSDaiQueuedDepositor.InvalidQueueState.selector);
        usdaiQueuedDepositor.service(
            IUSDaiQueuedDepositor.QueueType.Deposit, abi.encode(address(usdtHomeToken6Decimals), 1, 0, 0, "")
        );

        assertEq(usdai.balanceOf(user), 2_000_000 ether);

        vm.startPrank(user);

        // User deposits into USDai queued depositor
        usdaiQueuedDepositor.deposit(
            IUSDaiQueuedDepositor.QueueType.Deposit, address(usdtHomeToken6Decimals), amount, user, 0
        );

        // User deposits into USDai queued depositor
        usdaiQueuedDepositor.deposit(
            IUSDaiQueuedDepositor.QueueType.Deposit, address(usdtHomeToken6Decimals), amount, user, 0
        );

        vm.stopPrank();

        usdaiQueuedDepositor.service(
            IUSDaiQueuedDepositor.QueueType.Deposit, abi.encode(address(usdtHomeToken6Decimals), 3, 0, 10, "")
        );

        assertEq(usdai.balanceOf(user), 4_000_000 ether);
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
            IUSDaiQueuedDepositor.QueueType.Deposit, abi.encode(address(usdtHomeToken), 1, 0, 0, "")
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

        uint256 depositSharePrice1 = stakedUsdai.depositSharePrice() + 1;

        usdaiQueuedDepositor.service(
            IUSDaiQueuedDepositor.QueueType.DepositAndStake,
            abi.encode(address(usdtHomeToken), 1, 0, 0, "", depositSharePrice1)
        );

        IUSDaiQueuedDepositor.QueueItem memory queueItem1 = usdaiQueuedDepositor.queueItem(
            IUSDaiQueuedDepositor.QueueType.DepositAndStake, address(usdtHomeToken), queueIndex1
        );
        assertEq(queueItem1.pendingDeposit, 0);
        assertEq(queueItem1.dstEid, 0);
        assertEq(queueItem1.depositor, user);
        assertEq(queueItem1.recipient, user);

        (uint256 head1, uint256 pending1, IUSDaiQueuedDepositor.QueueItem[] memory queueItems1) = usdaiQueuedDepositor
            .queueInfo(IUSDaiQueuedDepositor.QueueType.DepositAndStake, address(usdtHomeToken), 0, 100);
        assertEq(head1, 1);
        assertEq(pending1, 0);
        assertEq(queueItems1.length, 1);

        assertEq(IERC20(address(stakedUsdai)).balanceOf(user), 1_000_000 ether - 1e6);

        vm.startPrank(user);

        // User deposits into USDai queued depositor
        uint256 queueIndex2 = usdaiQueuedDepositor.deposit(
            IUSDaiQueuedDepositor.QueueType.DepositAndStake, address(usdtHomeToken), 1_000_000 ether, user, 0
        );

        vm.stopPrank();

        // Get the deposit share price and min shares
        uint256 depositSharePrice2 = stakedUsdai.depositSharePrice();

        usdaiQueuedDepositor.service(
            IUSDaiQueuedDepositor.QueueType.DepositAndStake,
            abi.encode(address(usdtHomeToken), 1, 0, 0, "", depositSharePrice2)
        );

        IUSDaiQueuedDepositor.QueueItem memory queueItem2 = usdaiQueuedDepositor.queueItem(
            IUSDaiQueuedDepositor.QueueType.DepositAndStake, address(usdtHomeToken), queueIndex2
        );
        assertEq(queueItem2.pendingDeposit, 0);
        assertEq(queueItem2.dstEid, 0);
        assertEq(queueItem2.depositor, user);
        assertEq(queueItem2.recipient, user);

        (uint256 head2, uint256 pending2, IUSDaiQueuedDepositor.QueueItem[] memory queueItems2) = usdaiQueuedDepositor
            .queueInfo(IUSDaiQueuedDepositor.QueueType.DepositAndStake, address(usdtHomeToken), 0, 100);
        assertEq(head2, 2);
        assertEq(pending2, 0);
        assertEq(queueItems2.length, 2);

        uint256 depositSharePrice3 = stakedUsdai.depositSharePrice();
        vm.expectRevert(IUSDaiQueuedDepositor.InvalidQueueState.selector);
        usdaiQueuedDepositor.service(
            IUSDaiQueuedDepositor.QueueType.DepositAndStake,
            abi.encode(address(usdtHomeToken), 3, 0, 0, "", depositSharePrice3)
        );

        (uint256 head3, uint256 pending3, IUSDaiQueuedDepositor.QueueItem[] memory queueItems3) = usdaiQueuedDepositor
            .queueInfo(IUSDaiQueuedDepositor.QueueType.DepositAndStake, address(usdtHomeToken), 0, 100);
        assertEq(head3, 2);
        assertEq(pending3, 0);
        assertEq(queueItems3.length, 2);

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

        uint256 depositSharePrice4 = stakedUsdai.depositSharePrice();

        usdaiQueuedDepositor.service(
            IUSDaiQueuedDepositor.QueueType.DepositAndStake,
            abi.encode(address(usdtHomeToken), 1, 0, 0, "", depositSharePrice4)
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
            IUSDaiQueuedDepositor.QueueType.Deposit, abi.encode(address(usdtHomeToken), 1, 0, 0, "")
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

        uint256 depositSharePrice = stakedUsdai.depositSharePrice() + 1;

        usdaiQueuedDepositor.service(
            IUSDaiQueuedDepositor.QueueType.DepositAndStake,
            abi.encode(address(usdtHomeToken), 1, 0, 0, "", depositSharePrice)
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
        oUsdaiUtility.localCompose(
            IOUSDaiUtility.ActionType.QueuedDeposit, address(usdtHomeToken), initialBalance, data
        );

        // Assert that the USDAI home token was minted to the user
        assertEq(usdtHomeToken.balanceOf(address(usdaiQueuedDepositor)), initialBalance);

        vm.stopPrank();

        // Service the deposit
        usdaiQueuedDepositor.service(
            IUSDaiQueuedDepositor.QueueType.Deposit, abi.encode(address(usdtHomeToken), 1, 0, 0, "")
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
        oUsdaiUtility.localCompose(
            IOUSDaiUtility.ActionType.QueuedDeposit, address(usdtHomeToken), initialBalance, data
        );

        vm.stopPrank();

        // Deal some ETH to the USDai queued depositor to cover the native fee
        vm.deal(address(usdaiQueuedDepositor), 100 ether);

        // Service the deposit
        usdaiQueuedDepositor.service(
            IUSDaiQueuedDepositor.QueueType.Deposit, abi.encode(address(usdtHomeToken), 1, 0, 0, "")
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

        uint256 depositSharePrice = stakedUsdai.depositSharePrice() + 1;

        vm.expectRevert(IUSDaiQueuedDepositor.InsufficientBalance.selector);
        usdaiQueuedDepositor.service(
            IUSDaiQueuedDepositor.QueueType.DepositAndStake,
            abi.encode(address(usdtHomeToken), 1, 0, 0, "", depositSharePrice)
        );
    }

    function test__USDaiServiceQueuedOmnichainDepositAndStake_RevertWhen_InvalidSharePrice() public {
        uint256 amount = 1_000_000 ether;

        // User approves USDai to spend their USD
        vm.startPrank(user);
        usdtHomeToken.approve(address(usdaiQueuedDepositor), amount);

        // User deposits into USDai queued depositor
        usdaiQueuedDepositor.deposit(
            IUSDaiQueuedDepositor.QueueType.DepositAndStake, address(usdtHomeToken), amount, user, 0
        );

        vm.stopPrank();

        uint256 depositSharePrice = stakedUsdai.depositSharePrice() + 1;

        vm.expectRevert(IUSDaiQueuedDepositor.InvalidSharePrice.selector);
        usdaiQueuedDepositor.service(
            IUSDaiQueuedDepositor.QueueType.DepositAndStake,
            abi.encode(address(usdtHomeToken), 1, 0, 0, "", depositSharePrice - 1)
        );
    }
}
