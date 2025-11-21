// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.29;

import "forge-std/Script.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {UniswapV3SwapAdapter} from "src/swapAdapters/UniswapV3SwapAdapter.sol";
import {ChainlinkPriceOracle} from "src/oracles/ChainlinkPriceOracle.sol";
import {USDai} from "src/USDai.sol";
import {StakedUSDai} from "src/StakedUSDai.sol";

import {Deployer} from "./utils/Deployer.s.sol";

interface IWrappedMToken {
    /**
     * @notice Starts earning for `account` if allowed by TTG
     * @param account The account to start earning for
     */
    function startEarningFor(
        address account
    ) external;
}

contract DeployProductionEnvironment is Deployer {
    // Create3 Deterministic Addresses
    address internal constant USDAI_ADDRESS = 0x0A1a1A107E45b7Ced86833863f482BC5f4ed82EF;
    address internal constant STAKED_USDAI_ADDRESS = 0x0B2b2B2076d95dda7817e785989fE353fe955ef9;

    // Loan router and deposit timelock addresses
    address internal constant LOAN_ROUTER_ADDRESS = address(0);
    address internal constant DEPOSIT_TIMELOCK_ADDRESS = address(0);

    function run(
        address wrappedMToken,
        address swapRouter,
        address mNavPriceFeed,
        address[] calldata tokens,
        address[] calldata priceFeeds,
        address multisig
    ) public broadcast useDeployment {
        // Deploy UniswapV3SwapAdapter
        UniswapV3SwapAdapter swapAdapter = new UniswapV3SwapAdapter(wrappedMToken, swapRouter, tokens);
        console.log("UniswapV3SwapAdapter", address(swapAdapter));

        // Grant USDAI role
        IAccessControl(address(swapAdapter)).grantRole(keccak256("USDAI_ROLE"), address(USDAI_ADDRESS));

        // Transfer swap adapter admin role
        IAccessControl(address(swapAdapter)).grantRole(0x00, multisig);
        IAccessControl(address(swapAdapter)).revokeRole(0x00, msg.sender);

        // Deploy ChainlinkPriceOracle
        ChainlinkPriceOracle priceOracle = new ChainlinkPriceOracle(mNavPriceFeed, tokens, priceFeeds);
        console.log("ChainlinkPriceOracle", address(priceOracle));

        // Transfer price oracle admin
        IAccessControl(address(priceOracle)).grantRole(0x00, multisig);
        IAccessControl(address(priceOracle)).revokeRole(0x00, msg.sender);

        // Deploy USDai implemetation
        USDai USDaiImpl = new USDai(address(swapAdapter));
        console.log("USDai implementation", address(USDaiImpl));

        // Deploy StakedUSDai
        StakedUSDai stakedUSDaiImpl = new StakedUSDai(
            USDAI_ADDRESS,
            wrappedMToken,
            100,
            multisig,
            address(priceOracle),
            LOAN_ROUTER_ADDRESS,
            DEPOSIT_TIMELOCK_ADDRESS,
            100,
            uint64(block.timestamp)
        );
        console.log("StakedUSDai implementation", address(stakedUSDaiImpl));

        // Enable M emissions
        IWrappedMToken(wrappedMToken).startEarningFor(USDAI_ADDRESS);
        IWrappedMToken(wrappedMToken).startEarningFor(STAKED_USDAI_ADDRESS);

        // Log deployment
        _deployment.genesisTimestamp = uint64(block.timestamp);
        _deployment.swapAdapter = address(swapAdapter);
        _deployment.priceOracle = address(priceOracle);
        _deployment.USDai = USDAI_ADDRESS;
        _deployment.stakedUSDai = STAKED_USDAI_ADDRESS;
    }
}
