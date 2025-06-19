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
        bytes memory composeMsg = abi.encode(OUSDaiUtility.ActionType.QueuedDeposit, suffix);

        // LZ composer option
        bytes memory composerOptions = receiveOptions.addExecutorLzComposeOption(0, 500_000, uint128(0));

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

        vm.stopPrank();
    }

    function test__USDaiQueuedDeposit_RevertWhen_InvalidAmount() public {
        // Local
        vm.startPrank(user);
        vm.expectRevert(IUSDaiQueuedDepositor.InvalidAmount.selector);
        usdaiQueuedDepositor.deposit(IUSDaiQueuedDepositor.QueueType.Deposit, address(usdtHomeToken), 100, user, 0);
        vm.stopPrank();

        // Omnichain
        bytes memory receiveOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);

        // Compose message for deposit on home chain
        bytes memory suffix = abi.encode(IUSDaiQueuedDepositor.QueueType.Deposit, user, usdtAwayEid);
        bytes memory composeMsg = abi.encode(OUSDaiUtility.ActionType.QueuedDeposit, suffix);

        // LZ composer option
        bytes memory composerOptions = receiveOptions.addExecutorLzComposeOption(0, 500_000, uint128(0));

        // Send param for USD away to USD home
        SendParam memory usdtSendParam = SendParam({
            dstEid: usdtHomeEid,
            to: addressToBytes32(address(oUsdaiUtility)),
            amountLD: 1e12,
            minAmountLD: 1e12,
            extraOptions: composerOptions,
            composeMsg: composeMsg,
            oftCmd: ""
        });

        // Quote the fee for sending USD from away to home
        (,, OFTReceipt memory receipt) = usdtAwayOAdapter.quoteOFT(usdtSendParam);
        usdtSendParam.minAmountLD = receipt.amountReceivedLD;

        // Compose message for USD away to USD home
        MessagingFee memory fee = usdtAwayOAdapter.quoteSend(usdtSendParam, false);

        // Get initial balance
        uint256 initialBalance = usdtHomeToken.balanceOf(user);

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

        // Verify that the USD was not deposited due to revert
        assertEq(usdtHomeToken.balanceOf(user), initialBalance + 1e12);
    }

    function test__USDaiQueuedDeposit_RevertWhen_InvalidDepositToken() public {
        vm.startPrank(user);
        vm.expectRevert(IUSDaiQueuedDepositor.InvalidToken.selector);
        usdaiQueuedDepositor.deposit(IUSDaiQueuedDepositor.QueueType.Deposit, address(usdai), 100, user, 0);
        vm.stopPrank();
    }
}
