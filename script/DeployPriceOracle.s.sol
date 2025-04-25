// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.29;

import "forge-std/Script.sol";

import {ChainlinkPriceOracle} from "src/oracles/ChainlinkPriceOracle.sol";

import {Deployer} from "./utils/Deployer.s.sol";

contract DeployPriceOracle is Deployer {
    function run(
        address mNavPriceFeed,
        address[] memory tokens,
        address[] memory priceFeeds
    ) public broadcast useDeployment returns (address) {
        // Deploy ChainlinkPriceOracle
        ChainlinkPriceOracle priceOracle = new ChainlinkPriceOracle(mNavPriceFeed, tokens, priceFeeds);
        console.log("ChainlinkPriceOracle", address(priceOracle));

        // Log deployment
        _deployment.priceOracle = address(priceOracle);

        return (address(priceOracle));
    }
}
