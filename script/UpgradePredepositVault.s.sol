// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.29;

import "forge-std/Script.sol";

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

import {PredepositVault} from "src/omnichain/PredepositVault.sol";

import {Deployer} from "./utils/Deployer.s.sol";

contract UpgradePredepositVault is Deployer {
    function run(
        address predepositVault,
        address depositToken,
        uint256 depositAmountMinimum
    ) public broadcast useDeployment returns (address) {
        // Deploy PredepositVault implementation
        PredepositVault predepositVaultImpl = new PredepositVault(depositToken, depositAmountMinimum);
        console.log("PredepositVault implementation", address(predepositVaultImpl));

        /* Lookup proxy admin */
        address proxyAdmin = address(uint160(uint256(vm.load(predepositVault, ERC1967Utils.ADMIN_SLOT))));

        if (Ownable(proxyAdmin).owner() == msg.sender) {
            /* Upgrade Proxy */
            ProxyAdmin(proxyAdmin).upgradeAndCall(
                ITransparentUpgradeableProxy(predepositVault), address(predepositVaultImpl), ""
            );
            console.log("Upgraded proxy %s implementation to: %s\n", predepositVault, address(predepositVaultImpl));
        } else {
            console.log("\nUpgrade calldata");
            console.log("Target:   %s", proxyAdmin);
            console.log("Calldata:");
            console.logBytes(
                abi.encodeWithSelector(
                    ProxyAdmin.upgradeAndCall.selector,
                    ITransparentUpgradeableProxy(predepositVault),
                    address(predepositVaultImpl),
                    ""
                )
            );
        }

        return address(predepositVaultImpl);
    }
}
