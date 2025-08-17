// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.29;

import "forge-std/Script.sol";

import {USDaiQueuedDepositor} from "src/queuedDepositor/USDaiQueuedDepositor.sol";

import {Deployer} from "./utils/Deployer.s.sol";

contract USDaiQueuedDepositorUpdateDepositCap is Deployer {
    function run(uint256 depositCap, bool resetCounter) public broadcast useDeployment {
        if (_deployment.usdaiQueuedDepositor == address(0)) revert MissingDependency();

        USDaiQueuedDepositor usdaiQueuedDepositor = USDaiQueuedDepositor(_deployment.usdaiQueuedDepositor);

        if (usdaiQueuedDepositor.hasRole(0x00, msg.sender)) {
            usdaiQueuedDepositor.updateDepositCap(depositCap, resetCounter);
        } else {
            console.log("\nCalldata");
            console.log("Target:   %s", address(usdaiQueuedDepositor));
            console.log("Calldata:");
            console.logBytes(
                abi.encodeWithSelector(USDaiQueuedDepositor.updateDepositCap.selector, depositCap, resetCounter)
            );
        }
    }
}
