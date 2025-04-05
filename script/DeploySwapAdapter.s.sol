// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.29;

import "forge-std/Script.sol";

import {UniswapV3SwapAdapter} from "src/swapAdapters/UniswapV3SwapAdapter.sol";

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import {Deployer} from "./utils/Deployer.s.sol";

contract DeploySwapAdapter is Deployer {
    function run(
        address wrappedMToken,
        address swapRouter,
        address[] memory tokens
    ) public broadcast useDeployment returns (address) {
        // Deploy UniswapV3SwapAdapter
        UniswapV3SwapAdapter swapAdapter = new UniswapV3SwapAdapter(wrappedMToken, swapRouter);
        console.log("UniswapV3SwapAdapter", address(swapAdapter));

        // Set tokens whitelist
        swapAdapter.setWhitelistedTokens(tokens);

        // Grant role to USDAI
        AccessControl(address(swapAdapter)).grantRole(keccak256("USDAI_ROLE"), address(_deployment.USDai));

        // Log deployment
        _deployment.swapAdapter = address(swapAdapter);

        return (address(swapAdapter));
    }
}
