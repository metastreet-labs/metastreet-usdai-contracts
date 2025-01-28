// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.29;

import "forge-std/Script.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {WrappedMSwapAdapter} from "src/swapAdapters/WrappedMSwapAdapter.sol";
import {USDai} from "src/USDai.sol";
import {StakedUSDai} from "src/StakedUSDai.sol";
import {Deployer} from "./utils/Deployer.s.sol";

contract Deploy is Deployer {
    function run(
        address wrappedMToken,
        address swapRouter,
        uint64 timelock
    ) public returns (address, address, address) {
        // Deploy WrappedMSwapAdapter
        WrappedMSwapAdapter swapAdapter = new WrappedMSwapAdapter(wrappedMToken, swapRouter);
        console.log("WrappedMSwapAdapter", address(swapAdapter));

        // Deploy USDai implemetation
        USDai USDaiImpl = new USDai(address(swapAdapter));
        console.log("USDai implementation", address(USDaiImpl));

        // Deploy USDai proxy
        TransparentUpgradeableProxy USDai_ =
            new TransparentUpgradeableProxy(address(USDaiImpl), msg.sender, abi.encodeWithSignature("initialize()"));
        console.log("USDai proxy", address(USDai_));

        // Deploy StakedUSDai
        StakedUSDai stakedUSDaiImpl = new StakedUSDai(address(USDai_));
        console.log("StakedUSDai implementation", address(stakedUSDaiImpl));

        // Deploy StakedUSDai proxy
        TransparentUpgradeableProxy stakedUSDai = new TransparentUpgradeableProxy(
            address(stakedUSDaiImpl), msg.sender, abi.encodeWithSignature("initialize(uint64)", timelock)
        );
        console.log("StakedUSDai proxy", address(stakedUSDai));

        // Grant roles
        IAccessControl(address(swapAdapter)).grantRole(keccak256("USDAI_ROLE"), address(USDai_));

        // Log deployment
        _deployment.wrappedMSwapAdapter = address(swapAdapter);
        _deployment.USDai = address(USDai_);
        _deployment.stakedUSDai = address(stakedUSDai);

        return (address(swapAdapter), address(USDai_), address(stakedUSDai));
    }
}
