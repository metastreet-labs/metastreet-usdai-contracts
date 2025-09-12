// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.29;

import "forge-std/Script.sol";

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

import {USDaiQueuedDepositor} from "src/queuedDepositor/USDaiQueuedDepositor.sol";
import {ReceiptToken} from "src/queuedDepositor/ReceiptToken.sol";

import {Deployer} from "./utils/Deployer.s.sol";

contract UpgradeUSDaiQueuedDepositor is Deployer {
    function run() public broadcast useDeployment returns (address) {
        // Deploy receipt token implementation
        ReceiptToken receiptTokenImpl = new ReceiptToken();
        console.log("ReceiptToken implementation", address(receiptTokenImpl));

        // Deploy USDaiQueuedDepositor implementation
        USDaiQueuedDepositor usdaiQueuedDepositorImpl = new USDaiQueuedDepositor(
            _deployment.USDai,
            _deployment.stakedUSDai,
            _deployment.oAdapterUSDai,
            _deployment.oAdapterStakedUSDai,
            address(receiptTokenImpl),
            _deployment.oUSDaiUtility
        );
        console.log("USDaiQueuedDepositor implementation", address(usdaiQueuedDepositorImpl));

        /* Lookup proxy admin */
        address proxyAdmin =
            address(uint160(uint256(vm.load(_deployment.usdaiQueuedDepositor, ERC1967Utils.ADMIN_SLOT))));

        if (Ownable(proxyAdmin).owner() == msg.sender) {
            /* Upgrade Proxy */
            ProxyAdmin(proxyAdmin).upgradeAndCall(
                ITransparentUpgradeableProxy(_deployment.usdaiQueuedDepositor), address(usdaiQueuedDepositorImpl), ""
            );
            console.log(
                "Upgraded proxy %s implementation to: %s\n",
                _deployment.usdaiQueuedDepositor,
                address(usdaiQueuedDepositorImpl)
            );
        } else {
            console.log("\nUpgrade calldata");
            console.log("Target:   %s", proxyAdmin);
            console.log("Calldata:");
            console.logBytes(
                abi.encodeWithSelector(
                    ProxyAdmin.upgradeAndCall.selector,
                    ITransparentUpgradeableProxy(_deployment.usdaiQueuedDepositor),
                    address(usdaiQueuedDepositorImpl),
                    ""
                )
            );
        }

        return address(usdaiQueuedDepositorImpl);
    }
}
