// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.29;

import "forge-std/Script.sol";

import {USDaiQueuedDepositor} from "src/queuedDepositor/USDaiQueuedDepositor.sol";

import {Deployer} from "./utils/Deployer.s.sol";

contract USDaiQueuedDepositorUpdateDepositEidWhitelist is Deployer {
    function run(uint32 srcEid, uint32 dstEid, bool whitelisted) public broadcast useDeployment {
        if (_deployment.usdaiQueuedDepositor == address(0)) revert MissingDependency();

        USDaiQueuedDepositor usdaiQueuedDepositor = USDaiQueuedDepositor(_deployment.usdaiQueuedDepositor);

        if (usdaiQueuedDepositor.hasRole(0x00, msg.sender)) {
            usdaiQueuedDepositor.updateDepositEidWhitelist(srcEid, dstEid, whitelisted);
        } else {
            console.log("\nCalldata");
            console.log("Target:   %s", address(usdaiQueuedDepositor));
            console.log("Calldata:");
            console.logBytes(
                abi.encodeWithSelector(
                    USDaiQueuedDepositor.updateDepositEidWhitelist.selector, srcEid, dstEid, whitelisted
                )
            );
        }
    }
}
