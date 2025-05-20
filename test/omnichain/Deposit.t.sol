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

contract OUSDaiUtilityDepositTest is OmnichainBaseTest {
    using OptionsBuilder for bytes;

    // Test deposit of USD
    function test__OUSDaiUtilityDepositUsd() public {
        vm.startPrank(user);

        // LZ receive option
        bytes memory receiveOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(500_000, 0);

        // Send param for USDAI away to USDAI home
        SendParam memory usdaiSendParam = SendParam(
            usdaiAwayEid,
            addressToBytes32(user),
            initialBalance, // will be set later
            (initialBalance / 10 ** 12) * 10 ** 12,
            receiveOptions,
            "",
            ""
        );

        // Quote the fee for sending USDAI from home to away
        MessagingFee memory fee = usdaiHomeOAdapter.quoteSend(usdaiSendParam, false);

        // Compose message for USDAI away to USDAI home
        bytes memory suffix = abi.encode(initialBalance, "", usdaiSendParam, fee.nativeFee);
        bytes memory composeMsg = abi.encode(OUSDaiUtility.ActionType.Deposit, suffix);

        // LZ composer option
        bytes memory composerOptions = receiveOptions.addExecutorLzComposeOption(0, 800_000, uint128(fee.nativeFee));

        // Send param for USD away to USD home
        SendParam memory usdtSendParam = SendParam({
            dstEid: usdtHomeEid,
            to: addressToBytes32(address(oUsdaiUtility)),
            amountLD: initialBalance,
            minAmountLD: initialBalance,
            extraOptions: composerOptions,
            composeMsg: composeMsg,
            oftCmd: ""
        });

        // Quote the fee for sending USD from away to home
        (,, OFTReceipt memory receipt) = usdtAwayOAdapter.quoteOFT(usdtSendParam);
        usdtSendParam.minAmountLD = receipt.amountReceivedLD;

        // Compose message for USD away to USD home
        fee = usdtAwayOAdapter.quoteSend(usdtSendParam, false);

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

        // Verify that the packets were correctly sent to the destination chain
        verifyPackets(usdaiAwayEid, addressToBytes32(address(usdaiAwayOAdapter)));

        // Assert that the USDAI away token was minted to the user
        assertEq(usdaiAwayToken.balanceOf(user), initialBalance);

        vm.stopPrank();
    }

    function test__OUSDaiUtilityDepositUsd_InvalidDeposit() public {
        vm.startPrank(user);

        // LZ receive option
        bytes memory receiveOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(500_000, 0);

        // Send param for USDAI away to USDAI home
        SendParam memory usdaiSendParam = SendParam(
            usdaiAwayEid,
            addressToBytes32(user),
            initialBalance, // will be set later
            (initialBalance / 10 ** 12) * 10 ** 12,
            receiveOptions,
            "",
            ""
        );

        // Quote the fee for sending USDAI from home to away
        MessagingFee memory fee = usdaiHomeOAdapter.quoteSend(usdaiSendParam, false);

        // Compose message for USDAI away to USDAI home
        bytes memory suffix = abi.encode(initialBalance * 2, "", usdaiSendParam, fee.nativeFee);
        bytes memory composeMsg = abi.encode(OUSDaiUtility.ActionType.Deposit, suffix);

        // LZ composer option
        bytes memory composerOptions = receiveOptions.addExecutorLzComposeOption(0, 800_000, uint128(fee.nativeFee));

        // Send param for USD away to USD home
        SendParam memory usdtSendParam = SendParam({
            dstEid: usdtHomeEid,
            to: addressToBytes32(address(oUsdaiUtility)),
            amountLD: initialBalance,
            minAmountLD: initialBalance,
            extraOptions: composerOptions,
            composeMsg: composeMsg,
            oftCmd: ""
        });

        // Quote the fee for sending USD from away to home
        (,, OFTReceipt memory receipt) = usdtAwayOAdapter.quoteOFT(usdtSendParam);
        usdtSendParam.minAmountLD = receipt.amountReceivedLD;

        // Compose message for USD away to USD home
        fee = usdtAwayOAdapter.quoteSend(usdtSendParam, false);

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

        assertEq(usdtHomeToken.balanceOf(address(user)), initialBalance);

        vm.stopPrank();
    }

    function test__OUSDaiUtilityDepositUsd_InvalidSend() public {
        vm.startPrank(user);

        // LZ receive option
        bytes memory receiveOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(500_000, 0);

        // Send param for USDAI away to USDAI home
        SendParam memory usdaiSendParam = SendParam(
            usdaiAwayEid,
            addressToBytes32(user),
            initialBalance, // will be set later
            (initialBalance / 10 ** 12) * 10 ** 12,
            receiveOptions,
            "",
            ""
        );

        // Quote the fee for sending USDAI from home to away
        MessagingFee memory fee = usdaiHomeOAdapter.quoteSend(usdaiSendParam, false);

        // Compose message for USDAI away to USDAI home
        bytes memory suffix = abi.encode(initialBalance, "", usdaiSendParam, 0);
        bytes memory composeMsg = abi.encode(OUSDaiUtility.ActionType.Deposit, suffix);

        // LZ composer option
        bytes memory composerOptions = receiveOptions.addExecutorLzComposeOption(0, 800_000, uint128(fee.nativeFee));

        // Send param for USD away to USD home
        SendParam memory usdtSendParam = SendParam({
            dstEid: usdtHomeEid,
            to: addressToBytes32(address(oUsdaiUtility)),
            amountLD: initialBalance,
            minAmountLD: initialBalance,
            extraOptions: composerOptions,
            composeMsg: composeMsg,
            oftCmd: ""
        });

        // Quote the fee for sending USD from away to home
        (,, OFTReceipt memory receipt) = usdtAwayOAdapter.quoteOFT(usdtSendParam);
        usdtSendParam.minAmountLD = receipt.amountReceivedLD;

        // Compose message for USD away to USD home
        fee = usdtAwayOAdapter.quoteSend(usdtSendParam, false);

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

        // Assert that the USD was not sent to the composer receiver
        assertEq(usdai.balanceOf(address(user)), initialBalance);

        vm.stopPrank();
    }
}
