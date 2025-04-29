// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.29;

import "forge-std/Script.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {OAdapter} from "src/omnichain/OAdapter.sol";

import {Deployer} from "./utils/Deployer.s.sol";

contract DeployOAdapter is Deployer {
    function run(address token, address lzEndpoint) public broadcast useDeployment returns (address) {
        // Deploy OAdapter
        OAdapter adapter = new OAdapter(token, lzEndpoint, msg.sender);
        console.log("OAdapter", address(adapter));

        if (token == _deployment.USDai) {
            _deployment.oAdapterUSDai = address(adapter);
        } else if (token == _deployment.stakedUSDai) {
            _deployment.oAdapterStakedUSDai = address(adapter);
        }

        return (address(adapter));
    }
}
