// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.29;

import "forge-std/Script.sol";

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

import {DepositVault} from "src/misc/DepositVault.sol";

import {Deployer} from "./utils/Deployer.s.sol";

contract UpgradeDepositVault is Deployer {
    function run(
        address depositToken,
        uint256 depositAmountMinimum,
        uint32 dstEid
    ) public broadcast useDeployment returns (address) {
        // Deploy DepositVault implementation
        DepositVault depositVaultImpl = new DepositVault(depositToken, depositAmountMinimum, dstEid);
        console.log("DepositVault implementation", address(depositVaultImpl));

        /* Lookup proxy admin */
        address proxyAdmin = address(uint160(uint256(vm.load(_deployment.depositVault, ERC1967Utils.ADMIN_SLOT))));

        if (Ownable(proxyAdmin).owner() == msg.sender) {
            /* Upgrade Proxy */
            ProxyAdmin(proxyAdmin).upgradeAndCall(
                ITransparentUpgradeableProxy(_deployment.depositVault), address(depositVaultImpl), ""
            );
            console.log(
                "Upgraded proxy %s implementation to: %s\n", _deployment.depositVault, address(depositVaultImpl)
            );
        } else {
            console.log("\nUpgrade calldata");
            console.log("Target:   %s", proxyAdmin);
            console.log("Calldata:");
            console.logBytes(
                abi.encodeWithSelector(
                    ProxyAdmin.upgradeAndCall.selector,
                    ITransparentUpgradeableProxy(_deployment.depositVault),
                    address(depositVaultImpl),
                    ""
                )
            );
        }

        return address(depositVaultImpl);
    }
}
