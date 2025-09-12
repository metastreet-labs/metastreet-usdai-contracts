// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.29;

import "forge-std/Script.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {USDaiQueuedDepositor} from "src/queuedDepositor/USDaiQueuedDepositor.sol";
import {ReceiptToken} from "src/queuedDepositor/ReceiptToken.sol";

import {Deployer} from "./utils/Deployer.s.sol";

contract DeployUSDaiQueuedDepositor is Deployer {
    function run(
        address deployer,
        address multisig,
        address[] memory whitelistedTokens,
        uint256[] memory minAmounts
    ) public broadcast useDeployment returns (address) {
        // Deploy receipt token implementation
        ReceiptToken receiptTokenImpl = new ReceiptToken();
        console.log("ReceiptToken implementation", address(receiptTokenImpl));

        // Deploy USDaiQueuedDepositor implementation
        USDaiQueuedDepositor usdaiQueuedDepostiorImpl = new USDaiQueuedDepositor(
            _deployment.USDai,
            _deployment.stakedUSDai,
            _deployment.oAdapterUSDai,
            _deployment.oAdapterStakedUSDai,
            address(receiptTokenImpl),
            _deployment.oUSDaiUtility
        );
        console.log("USDaiQueuedDepositor implementation", address(usdaiQueuedDepostiorImpl));

        // Deploy USDaiQueuedDepositor proxy
        TransparentUpgradeableProxy usdaiQueuedDepositor = new TransparentUpgradeableProxy(
            address(usdaiQueuedDepostiorImpl),
            deployer,
            abi.encodeWithSelector(USDaiQueuedDepositor.initialize.selector, multisig, whitelistedTokens, minAmounts)
        );
        console.log("USDaiQueuedDepositor proxy", address(usdaiQueuedDepositor));

        _deployment.usdaiQueuedDepositor = address(usdaiQueuedDepositor);

        return (address(usdaiQueuedDepositor));
    }
}
