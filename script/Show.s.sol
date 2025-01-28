// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.29;

import "forge-std/Script.sol";

import {Deployer} from "./utils/Deployer.s.sol";

contract Show is Deployer {
    function run() public {
        console.log("Printing deployments\n");
        console.log("Network: %s\n", _chainIdToNetwork[block.chainid]);

        /* Deserialize */
        _deserialize();

        console.log("USDai:               %s", _deployment.USDai);
        console.log("StakedUSDai:         %s", _deployment.stakedUSDai);
        console.log("WrappedMSwapAdapter: %s", _deployment.wrappedMSwapAdapter);

        console.log("Printing deployments completed");
    }
}
