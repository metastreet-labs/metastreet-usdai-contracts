// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.29;

import "forge-std/Script.sol";

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

import {IUSDai} from "src/interfaces/IUSDai.sol";
import {StakedUSDai} from "src/StakedUSDai.sol";
import {Deployer} from "./utils/Deployer.s.sol";

contract UpgradeStakedUSDai is Deployer {
    function run() public broadcast useDeployment returns (address) {
        // Deploy StakedUSDai implemetation
        StakedUSDai stakedUSDaiImpl =
            new StakedUSDai(_deployment.USDai, IUSDai(_deployment.USDai).baseToken(), _deployment.priceOracle);
        console.log("StakedUSDai implementation", address(stakedUSDaiImpl));

        /* Lookup proxy admin */
        address proxyAdmin = address(uint160(uint256(vm.load(_deployment.stakedUSDai, ERC1967Utils.ADMIN_SLOT))));

        if (Ownable(proxyAdmin).owner() == msg.sender) {
            /* Upgrade Proxy */
            ProxyAdmin(proxyAdmin).upgradeAndCall(
                ITransparentUpgradeableProxy(_deployment.stakedUSDai), address(stakedUSDaiImpl), ""
            );
            console.log("Upgraded proxy %s implementation to: %s\n", _deployment.USDai, address(stakedUSDaiImpl));
        } else {
            console.log("\nUpgrade calldata");
            console.log("Target:   %s", proxyAdmin);
            console.log("Calldata:");
            console.logBytes(
                abi.encodeWithSelector(
                    ProxyAdmin.upgradeAndCall.selector,
                    ITransparentUpgradeableProxy(_deployment.stakedUSDai),
                    address(stakedUSDaiImpl),
                    ""
                )
            );
        }

        return address(stakedUSDaiImpl);
    }
}
