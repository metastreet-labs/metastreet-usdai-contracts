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
import {IOUSDaiUtility} from "src/interfaces/IOUSDaiUtility.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract USDaiQueuedDepositTest is OmnichainBaseTest {
    using OptionsBuilder for bytes;

    function setUp() public override {
        super.setUp();

        AccessControl(address(usdtHomeToken)).grantRole(usdtHomeToken.BRIDGE_ADMIN_ROLE(), address(this));
        usdtHomeToken.mint(user, 20_000_000 ether);
    }

    function testFuzz__USDaiQueuedLocalDeposit(
        uint256 amount
    ) public {
        vm.assume(amount >= 1_000_000 ether);
        vm.assume(amount <= 10_000_000 ether);

        // User approves USDai to spend their USD
        vm.startPrank(user);
        usdtHomeToken.approve(address(usdaiQueuedDepositor), amount * 2);

        // User deposits into USDai queued depositor
        uint256 queueIndex1 = usdaiQueuedDepositor.deposit(
            IUSDaiQueuedDepositor.QueueType.Deposit, address(usdtHomeToken), amount, user, 0
        );

        IUSDaiQueuedDepositor.QueueItem memory queueItem1 =
            usdaiQueuedDepositor.queueItem(IUSDaiQueuedDepositor.QueueType.Deposit, address(usdtHomeToken), queueIndex1);
        assertEq(queueItem1.pendingDeposit, amount);
        assertEq(queueItem1.dstEid, 0);
        assertEq(queueItem1.depositor, user);
        assertEq(queueItem1.recipient, user);

        (uint256 head1, uint256 pending1, IUSDaiQueuedDepositor.QueueItem[] memory queueItems1) =
            usdaiQueuedDepositor.queueInfo(IUSDaiQueuedDepositor.QueueType.Deposit, address(usdtHomeToken), 0, 100);
        assertEq(head1, 0);
        assertEq(pending1, amount);
        assertEq(queueItems1.length, 1);

        // User deposits into USDai queued depositor
        uint256 queueIndex2 = usdaiQueuedDepositor.deposit(
            IUSDaiQueuedDepositor.QueueType.Deposit, address(usdtHomeToken), amount, user, 0
        );

        IUSDaiQueuedDepositor.QueueItem memory queueItem2 =
            usdaiQueuedDepositor.queueItem(IUSDaiQueuedDepositor.QueueType.Deposit, address(usdtHomeToken), queueIndex2);
        assertEq(queueItem2.pendingDeposit, amount);
        assertEq(queueItem2.dstEid, 0);
        assertEq(queueItem2.depositor, user);
        assertEq(queueItem2.recipient, user);

        (uint256 head2, uint256 pending2, IUSDaiQueuedDepositor.QueueItem[] memory queueItems2) =
            usdaiQueuedDepositor.queueInfo(IUSDaiQueuedDepositor.QueueType.Deposit, address(usdtHomeToken), 0, 100);
        assertEq(head2, 0);
        assertEq(pending2, amount * 2);
        assertEq(queueItems2.length, 2);

        // Verify that the queued USDai was minted to the user
        assertEq(IERC20(queuedUSDaiToken).balanceOf(user), amount * 2);

        vm.stopPrank();
    }

    function testFuzz__USDaiQueuedLocalDeposit_6Decimals(
        uint256 amount
    ) public {
        vm.assume(amount >= 1_000_000 * 1e6);
        vm.assume(amount <= 10_000_000 * 1e6);

        // User approves USDai to spend their USD
        vm.startPrank(user);
        usdtHomeToken6Decimals.approve(address(usdaiQueuedDepositor), amount * 2);

        // User deposits into USDai queued depositor
        uint256 queueIndex1 = usdaiQueuedDepositor.deposit(
            IUSDaiQueuedDepositor.QueueType.Deposit, address(usdtHomeToken6Decimals), amount, user, 0
        );

        IUSDaiQueuedDepositor.QueueItem memory queueItem1 = usdaiQueuedDepositor.queueItem(
            IUSDaiQueuedDepositor.QueueType.Deposit, address(usdtHomeToken6Decimals), queueIndex1
        );
        assertEq(queueItem1.pendingDeposit, amount);
        assertEq(queueItem1.dstEid, 0);
        assertEq(queueItem1.depositor, user);
        assertEq(queueItem1.recipient, user);

        (uint256 head1, uint256 pending1, IUSDaiQueuedDepositor.QueueItem[] memory queueItems1) = usdaiQueuedDepositor
            .queueInfo(IUSDaiQueuedDepositor.QueueType.Deposit, address(usdtHomeToken6Decimals), 0, 100);
        assertEq(head1, 0);
        assertEq(pending1, amount);
        assertEq(queueItems1.length, 1);

        // User deposits into USDai queued depositor
        uint256 queueIndex2 = usdaiQueuedDepositor.deposit(
            IUSDaiQueuedDepositor.QueueType.Deposit, address(usdtHomeToken6Decimals), amount, user, 0
        );

        IUSDaiQueuedDepositor.QueueItem memory queueItem2 = usdaiQueuedDepositor.queueItem(
            IUSDaiQueuedDepositor.QueueType.Deposit, address(usdtHomeToken6Decimals), queueIndex2
        );
        assertEq(queueItem2.pendingDeposit, amount);
        assertEq(queueItem2.dstEid, 0);
        assertEq(queueItem2.depositor, user);
        assertEq(queueItem2.recipient, user);

        (uint256 head2, uint256 pending2, IUSDaiQueuedDepositor.QueueItem[] memory queueItems2) = usdaiQueuedDepositor
            .queueInfo(IUSDaiQueuedDepositor.QueueType.Deposit, address(usdtHomeToken6Decimals), 0, 100);
        assertEq(head2, 0);
        assertEq(pending2, amount * 2);
        assertEq(queueItems2.length, 2);

        // Verify that the queued USDai was minted to the user
        assertEq(IERC20(queuedUSDaiToken).balanceOf(user), amount * 2 * 1e12);

        vm.stopPrank();
    }

    function testFuzz__USDaiQueuedLocalDepositAndStake(
        uint256 amount
    ) public {
        vm.assume(amount >= 1_000_000 ether);
        vm.assume(amount <= 10_000_000 ether);

        // User approves USDai to spend their USD
        vm.startPrank(user);
        usdtHomeToken.approve(address(usdaiQueuedDepositor), amount * 2);

        // User deposits into USDai queued depositor
        uint256 queueIndex1 = usdaiQueuedDepositor.deposit(
            IUSDaiQueuedDepositor.QueueType.DepositAndStake, address(usdtHomeToken), amount, user, 0
        );

        IUSDaiQueuedDepositor.QueueItem memory queueItem1 = usdaiQueuedDepositor.queueItem(
            IUSDaiQueuedDepositor.QueueType.DepositAndStake, address(usdtHomeToken), queueIndex1
        );
        assertEq(queueItem1.pendingDeposit, amount);
        assertEq(queueItem1.dstEid, 0);
        assertEq(queueItem1.depositor, user);
        assertEq(queueItem1.recipient, user);

        (uint256 head1, uint256 pending1, IUSDaiQueuedDepositor.QueueItem[] memory queueItems1) = usdaiQueuedDepositor
            .queueInfo(IUSDaiQueuedDepositor.QueueType.DepositAndStake, address(usdtHomeToken), 0, 100);
        assertEq(head1, 0);
        assertEq(pending1, amount);
        assertEq(queueItems1.length, 1);

        // User deposits into USDai queued depositor
        uint256 queueIndex2 = usdaiQueuedDepositor.deposit(
            IUSDaiQueuedDepositor.QueueType.DepositAndStake, address(usdtHomeToken), amount, user, 0
        );

        IUSDaiQueuedDepositor.QueueItem memory queueItem2 = usdaiQueuedDepositor.queueItem(
            IUSDaiQueuedDepositor.QueueType.DepositAndStake, address(usdtHomeToken), queueIndex2
        );
        assertEq(queueItem2.pendingDeposit, amount);
        assertEq(queueItem2.dstEid, 0);
        assertEq(queueItem2.depositor, user);
        assertEq(queueItem2.recipient, user);

        (uint256 head2, uint256 pending2, IUSDaiQueuedDepositor.QueueItem[] memory queueItems2) = usdaiQueuedDepositor
            .queueInfo(IUSDaiQueuedDepositor.QueueType.DepositAndStake, address(usdtHomeToken), 0, 100);
        assertEq(head2, 0);
        assertEq(pending2, amount * 2);
        assertEq(queueItems2.length, 2);

        // Verify that the queued USDai was minted to the user
        assertEq(IERC20(queuedStakedUSDaiToken).balanceOf(user), amount * 2);

        vm.stopPrank();
    }

    function testFuzz__USDaiQueuedLocalDepositAndStake_6Decimals(
        uint256 amount
    ) public {
        vm.assume(amount >= 1_000_000 * 1e6);
        vm.assume(amount <= 10_000_000 * 1e6);

        // User approves USDai to spend their USD
        vm.startPrank(user);
        usdtHomeToken6Decimals.approve(address(usdaiQueuedDepositor), amount * 2);

        // User deposits into USDai queued depositor
        uint256 queueIndex1 = usdaiQueuedDepositor.deposit(
            IUSDaiQueuedDepositor.QueueType.DepositAndStake, address(usdtHomeToken6Decimals), amount, user, 0
        );

        IUSDaiQueuedDepositor.QueueItem memory queueItem1 = usdaiQueuedDepositor.queueItem(
            IUSDaiQueuedDepositor.QueueType.DepositAndStake, address(usdtHomeToken6Decimals), queueIndex1
        );
        assertEq(queueItem1.pendingDeposit, amount);
        assertEq(queueItem1.dstEid, 0);
        assertEq(queueItem1.depositor, user);
        assertEq(queueItem1.recipient, user);

        (uint256 head1, uint256 pending1, IUSDaiQueuedDepositor.QueueItem[] memory queueItems1) = usdaiQueuedDepositor
            .queueInfo(IUSDaiQueuedDepositor.QueueType.DepositAndStake, address(usdtHomeToken6Decimals), 0, 100);
        assertEq(head1, 0);
        assertEq(pending1, amount);
        assertEq(queueItems1.length, 1);

        // User deposits into USDai queued depositor
        uint256 queueIndex2 = usdaiQueuedDepositor.deposit(
            IUSDaiQueuedDepositor.QueueType.DepositAndStake, address(usdtHomeToken6Decimals), amount, user, 0
        );

        IUSDaiQueuedDepositor.QueueItem memory queueItem2 = usdaiQueuedDepositor.queueItem(
            IUSDaiQueuedDepositor.QueueType.DepositAndStake, address(usdtHomeToken6Decimals), queueIndex2
        );
        assertEq(queueItem2.pendingDeposit, amount);
        assertEq(queueItem2.dstEid, 0);
        assertEq(queueItem2.depositor, user);
        assertEq(queueItem2.recipient, user);

        (uint256 head2, uint256 pending2, IUSDaiQueuedDepositor.QueueItem[] memory queueItems2) = usdaiQueuedDepositor
            .queueInfo(IUSDaiQueuedDepositor.QueueType.DepositAndStake, address(usdtHomeToken6Decimals), 0, 100);
        assertEq(head2, 0);
        assertEq(pending2, amount * 2);
        assertEq(queueItems2.length, 2);

        // Verify that the queued USDai was minted to the user
        assertEq(IERC20(queuedStakedUSDaiToken).balanceOf(user), amount * 2 * 1e12);

        vm.stopPrank();
    }

    function testFuzz__USDaiQueuedOmnichainDeposit(
        uint256 amount
    ) public {
        vm.assume(amount >= 1_000_000 ether);
        vm.assume(amount <= 10_000_000 ether);

        bytes memory receiveOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);

        // Compose message for deposit on home chain
        bytes memory suffix = abi.encode(IUSDaiQueuedDepositor.QueueType.Deposit, user, usdtAwayEid);
        bytes memory composeMsg = abi.encode(IOUSDaiUtility.ActionType.QueuedDeposit, suffix);

        // LZ composer option
        bytes memory composerOptions = receiveOptions.addExecutorLzComposeOption(0, 1_050_000, uint128(0));

        // Send param for USD away to USD home
        SendParam memory usdtSendParam = SendParam({
            dstEid: usdtHomeEid,
            to: addressToBytes32(address(oUsdaiUtility)),
            amountLD: amount,
            minAmountLD: (amount / 10 ** 12) * 10 ** 12,
            extraOptions: composerOptions,
            composeMsg: composeMsg,
            oftCmd: ""
        });

        // Quote the fee for sending USD from away to home
        (,, OFTReceipt memory receipt) = usdtAwayOAdapter.quoteOFT(usdtSendParam);
        usdtSendParam.minAmountLD = receipt.amountReceivedLD;

        // Compose message for USD away to USD home
        MessagingFee memory fee = usdtAwayOAdapter.quoteSend(usdtSendParam, false);

        vm.startPrank(user);

        // Send the USD
        (MessagingReceipt memory msgReceipt, OFTReceipt memory oftReceipt) =
            usdtAwayOAdapter.send{value: fee.nativeFee}(usdtSendParam, fee, payable(address(this)));

        // Verify that the packets were correctly sent to the destination chain
        verifyPackets(usdtHomeEid, addressToBytes32(address(usdtHomeOAdapter)));

        // Recreate the compose message for the composer receiver
        bytes memory composerMsg_ = OFTComposeMsgCodec.encode(
            msgReceipt.nonce,
            usdtAwayEid,
            oftReceipt.amountReceivedLD,
            abi.encodePacked(addressToBytes32(user), composeMsg)
        );

        // Execute the compose message
        this.lzCompose(
            usdtHomeEid,
            address(usdtHomeOAdapter),
            composerOptions,
            msgReceipt.guid,
            address(oUsdaiUtility),
            composerMsg_
        );

        IUSDaiQueuedDepositor.QueueItem memory queueItem =
            usdaiQueuedDepositor.queueItem(IUSDaiQueuedDepositor.QueueType.Deposit, address(usdtHomeToken), 0);
        assertEq(queueItem.pendingDeposit, usdtSendParam.minAmountLD);
        assertEq(queueItem.dstEid, usdtAwayEid);
        assertEq(queueItem.depositor, address(oUsdaiUtility));
        assertEq(queueItem.recipient, user);

        // Verify that the queued USDai was minted to the user
        assertEq(IERC20(queuedUSDaiToken).balanceOf(user), usdtSendParam.minAmountLD);

        vm.stopPrank();
    }

    function test__USDaiQueuedDeposit_RevertWhen_InvalidAmount() public {
        // Local
        vm.startPrank(user);
        usdtHomeToken.approve(address(usdaiQueuedDepositor), 100);
        vm.expectRevert(IUSDaiQueuedDepositor.InvalidAmount.selector);
        usdaiQueuedDepositor.deposit(IUSDaiQueuedDepositor.QueueType.Deposit, address(usdtHomeToken), 100, user, 0);
        vm.stopPrank();
    }

    function test__USDaiQueuedDeposit_RevertWhen_InvalidDepositToken() public {
        vm.startPrank(user);
        vm.expectRevert(IUSDaiQueuedDepositor.InvalidToken.selector);
        usdaiQueuedDepositor.deposit(IUSDaiQueuedDepositor.QueueType.Deposit, address(usdai), 100, user, 0);
        vm.stopPrank();
    }

    function test__USDaiQueuedDeposit_RevertWhen_TransferringReceiptToken() public {
        uint256 amount = 1_000_000 ether;

        // User approves USDai to spend their USD
        vm.startPrank(user);
        usdtHomeToken.approve(address(usdaiQueuedDepositor), amount);

        // User deposits into USDai queued depositor
        usdaiQueuedDepositor.deposit(IUSDaiQueuedDepositor.QueueType.Deposit, address(usdtHomeToken), amount, user, 0);

        vm.expectRevert();
        IERC20(queuedUSDaiToken).transfer(address(usdaiQueuedDepositor), amount);

        vm.stopPrank();
    }

    function test__USDaiQueuedDeposit_RevertWhen_DepositCapExceeded() public {
        usdaiQueuedDepositor.updateDepositCap(10_000_000 * 1e18, false);

        (uint256 cap, uint256 counter) = usdaiQueuedDepositor.depositCapInfo();

        assertEq(cap, 10_000_000 * 1e18);
        assertEq(counter, 0);

        vm.startPrank(user);
        usdtHomeToken.approve(address(usdaiQueuedDepositor), cap + 1);
        vm.expectRevert(IUSDaiQueuedDepositor.InvalidAmount.selector);
        usdaiQueuedDepositor.deposit(IUSDaiQueuedDepositor.QueueType.Deposit, address(usdtHomeToken), cap + 1, user, 0);
        vm.stopPrank();

        usdaiQueuedDepositor.updateDepositCap(cap + 1, false);

        vm.startPrank(user);
        usdaiQueuedDepositor.deposit(IUSDaiQueuedDepositor.QueueType.Deposit, address(usdtHomeToken), cap + 1, user, 0);
        vm.stopPrank();

        (, counter) = usdaiQueuedDepositor.depositCapInfo();
        assertEq(counter, cap + 1);
    }
}
