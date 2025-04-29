// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.29;

import "forge-std/Script.sol";

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

import {OToken} from "src/omnichain/OToken.sol";

import {Deployer} from "./utils/Deployer.s.sol";

contract UpgradeOToken is Deployer {
    function run(
        address otoken
    ) public broadcast useDeployment returns (address) {
        // Deploy OToken implementation
        OToken otokenImpl = new OToken();
        console.log("OToken implementation", address(otokenImpl));

        /* Lookup proxy admin */
        address proxyAdmin = address(uint160(uint256(vm.load(otoken, ERC1967Utils.ADMIN_SLOT))));

        if (Ownable(proxyAdmin).owner() == msg.sender) {
            /* Upgrade Proxy */
            ProxyAdmin(proxyAdmin).upgradeAndCall(ITransparentUpgradeableProxy(otoken), address(otokenImpl), "");
            console.log("Upgraded proxy %s implementation to: %s\n", otoken, address(otokenImpl));
        } else {
            console.log("\nUpgrade calldata");
            console.log("Target:   %s", proxyAdmin);
            console.log("Calldata:");
            console.logBytes(
                abi.encodeWithSelector(
                    ProxyAdmin.upgradeAndCall.selector, ITransparentUpgradeableProxy(otoken), address(otokenImpl), ""
                )
            );
        }

        return address(otokenImpl);
    }
}
