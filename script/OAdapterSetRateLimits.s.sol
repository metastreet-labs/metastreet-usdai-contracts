// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.29;

import "forge-std/Script.sol";

import {RateLimiter} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/utils/RateLimiter.sol";

import {OAdapter} from "src/omnichain/OAdapter.sol";

import {Deployer} from "./utils/Deployer.s.sol";

contract OAdapterSetRateLimits is Deployer {
    function run(address oadapterAddress, uint32[] memory dstEids, uint256 limit, uint256 window) public broadcast {
        OAdapter oadapter = OAdapter(oadapterAddress);

        RateLimiter.RateLimitConfig[] memory rateLimitConfigs = new RateLimiter.RateLimitConfig[](dstEids.length);
        for (uint256 i; i < dstEids.length; i++) {
            rateLimitConfigs[i] = RateLimiter.RateLimitConfig(dstEids[i], limit, window);
        }

        if (oadapter.owner() == msg.sender) {
            oadapter.setRateLimits(rateLimitConfigs);
        } else {
            console.log("\nCalldata");
            console.log("Target:   %s", address(oadapter));
            console.log("Calldata:");
            console.logBytes(abi.encodeWithSelector(OAdapter.setRateLimits.selector, rateLimitConfigs));
        }
    }
}
