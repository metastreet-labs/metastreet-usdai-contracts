// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.29;

import "forge-std/Script.sol";

import {UniswapV3SwapAdapter} from "src/swapAdapters/UniswapV3SwapAdapter.sol";
import {Deployer} from "./utils/Deployer.s.sol";

contract SwapAdapterSetTokenWhitelist is Deployer {
    function run(
        address[] memory tokens
    ) public broadcast useDeployment {
        if (_deployment.swapAdapter == address(0)) revert MissingDependency();

        UniswapV3SwapAdapter swapAdapter = UniswapV3SwapAdapter(_deployment.swapAdapter);

        if (swapAdapter.hasRole(0x00, msg.sender)) {
            swapAdapter.setWhitelistedTokens(tokens);
        } else {
            console.log("\nCalldata");
            console.log("Target:   %s", address(swapAdapter));
            console.log("Calldata:");
            console.logBytes(abi.encodeWithSelector(UniswapV3SwapAdapter.setWhitelistedTokens.selector, tokens));
        }
    }
}
