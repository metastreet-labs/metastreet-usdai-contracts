// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.29;

import "forge-std/Script.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {UniswapV3SwapAdapter} from "src/swapAdapters/UniswapV3SwapAdapter.sol";
import {ChainlinkPriceOracle} from "src/oracles/ChainlinkPriceOracle.sol";
import {USDai} from "src/USDai.sol";
import {StakedUSDai} from "src/StakedUSDai.sol";
import {QEVRegistry} from "src/QEVRegistry.sol";
import {Deployer} from "./utils/Deployer.s.sol";

contract DeployTestEnvironment is Deployer {
    function run(
        address wrappedMToken,
        address swapRouter,
        address mNavPriceFeed,
        address[] calldata tokens,
        address[] calldata priceFeeds,
        uint64 timelock
    ) public broadcast useDeployment returns (address, address, address, address, address) {
        // Deploy UniswapV3SwapAdapter
        UniswapV3SwapAdapter swapAdapter = new UniswapV3SwapAdapter(wrappedMToken, swapRouter, tokens);
        console.log("UniswapV3SwapAdapter", address(swapAdapter));

        // Deploy ChainlinkPriceOracle
        ChainlinkPriceOracle priceOracle = new ChainlinkPriceOracle(mNavPriceFeed, tokens, priceFeeds);
        console.log("ChainlinkPriceOracle", address(priceOracle));

        // Deploy USDai implemetation
        USDai USDaiImpl = new USDai(address(swapAdapter));
        console.log("USDai implementation", address(USDaiImpl));

        // Deploy USDai proxy
        TransparentUpgradeableProxy USDai_ = new TransparentUpgradeableProxy(
            address(USDaiImpl), msg.sender, abi.encodeWithSignature("initialize(address)", msg.sender)
        );
        console.log("USDai proxy", address(USDai_));

        // Deploy QEVRegistry implemetation
        QEVRegistry qevRegistry = new QEVRegistry(address(0), 100, msg.sender, uint64(block.timestamp));
        console.log("QEVRegistry", address(qevRegistry));

        // Deploy QEVRegistry proxy
        TransparentUpgradeableProxy qevRegistry_ =
            new TransparentUpgradeableProxy(address(qevRegistry), msg.sender, abi.encodeWithSignature("initialize()"));
        console.log("QEVRegistry proxy", address(qevRegistry_));

        // Deploy StakedUSDai
        StakedUSDai stakedUSDaiImpl = new StakedUSDai(
            address(USDai_), address(qevRegistry_), wrappedMToken, 100, msg.sender, address(priceOracle)
        );
        console.log("StakedUSDai implementation", address(stakedUSDaiImpl));

        // Deploy StakedUSDai proxy
        TransparentUpgradeableProxy stakedUSDai = new TransparentUpgradeableProxy(
            address(stakedUSDaiImpl),
            msg.sender,
            abi.encodeWithSignature("initialize(address,uint64)", msg.sender, timelock)
        );
        console.log("StakedUSDai proxy", address(stakedUSDai));

        // Grant roles
        IAccessControl(address(swapAdapter)).grantRole(keccak256("USDAI_ROLE"), address(USDai_));

        // Log deployment
        _deployment.swapAdapter = address(swapAdapter);
        _deployment.priceOracle = address(priceOracle);
        _deployment.USDai = address(USDai_);
        _deployment.stakedUSDai = address(stakedUSDai);
        _deployment.qevRegistry = address(qevRegistry_);

        return
            (address(swapAdapter), address(priceOracle), address(USDai_), address(stakedUSDai), address(qevRegistry_));
    }
}
