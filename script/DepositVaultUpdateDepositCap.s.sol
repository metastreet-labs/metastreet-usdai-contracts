// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.29;

import "forge-std/Script.sol";

import {DepositVault} from "src/misc/DepositVault.sol";

import {Deployer} from "./utils/Deployer.s.sol";

contract DepositVaultUpdateDepositCap is Deployer {
    function run(uint256 depositCap, bool resetCounter) public broadcast useDeployment {
        if (_deployment.depositVault == address(0)) revert MissingDependency();

        DepositVault depositVault = DepositVault(_deployment.depositVault);

        if (depositVault.hasRole(0x00, msg.sender)) {
            depositVault.updateDepositCap(depositCap, resetCounter);
        } else {
            console.log("\nCalldata");
            console.log("Target:   %s", address(depositVault));
            console.log("Calldata:");
            console.logBytes(abi.encodeWithSelector(DepositVault.updateDepositCap.selector, depositCap, resetCounter));
        }
    }
}
