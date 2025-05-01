// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.29;

import "forge-std/Script.sol";

import {ChainlinkPriceOracle} from "src/oracles/ChainlinkPriceOracle.sol";

import {Deployer} from "./utils/Deployer.s.sol";

contract PriceOracleAddPriceFeeds is Deployer {
    function run(address[] memory tokens, address[] memory priceFeeds) public broadcast useDeployment {
        if (_deployment.priceOracle == address(0)) revert MissingDependency();

        ChainlinkPriceOracle priceOracle = ChainlinkPriceOracle(_deployment.priceOracle);

        if (priceOracle.hasRole(0x00, msg.sender)) {
            priceOracle.addTokenPriceFeeds(tokens, priceFeeds);
        } else {
            console.log("\nCalldata");
            console.log("Target:   %s", address(priceOracle));
            console.log("Calldata:");
            console.logBytes(
                abi.encodeWithSelector(ChainlinkPriceOracle.addTokenPriceFeeds.selector, tokens, priceFeeds)
            );
        }
    }
}
