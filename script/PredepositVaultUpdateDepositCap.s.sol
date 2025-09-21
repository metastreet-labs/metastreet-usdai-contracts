// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.29;

import "forge-std/Script.sol";

import {PredepositVault} from "src/omnichain/PredepositVault.sol";

import {Deployer} from "./utils/Deployer.s.sol";

contract PredepositVaultUpdateDepositCap is Deployer {
    function run(address predepositVault_, uint256 depositCap, bool resetCounter) public broadcast useDeployment {
        PredepositVault predepositVault = PredepositVault(predepositVault_);

        if (predepositVault.hasRole(0x00, msg.sender)) {
            predepositVault.updateDepositCap(depositCap, resetCounter);
        } else {
            console.log("\nCalldata");
            console.log("Target:   %s", address(predepositVault));
            console.log("Calldata:");
            console.logBytes(
                abi.encodeWithSelector(PredepositVault.updateDepositCap.selector, depositCap, resetCounter)
            );
        }
    }
}
