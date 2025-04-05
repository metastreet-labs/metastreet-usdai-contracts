// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.29;

import "forge-std/Script.sol";

import {AggregatorV3Interface} from "src/interfaces/external/IAggregatorV3Interface.sol";

import {Deployer} from "./utils/Deployer.s.sol";

contract TestMNAVPriceFeed is AggregatorV3Interface {
    function decimals() external pure returns (uint8) {
        return 8;
    }

    function description() external pure returns (string memory) {
        return "Test M NAV";
    }

    function version() external pure returns (uint256) {
        return 6;
    }

    function getRoundData(
        uint80
    ) external pure returns (uint80, int256, uint256, uint256, uint80) {
        revert("Not Implemented");
    }

    function latestRoundData()
        external
        pure
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        roundId = 18446744073709551766;
        answer = 103815096;
        startedAt = 1744372905;
        updatedAt = 1744372919;
        answeredInRound = 18446744073709551766;
    }
}

contract DeployTestMNAVPriceFeed is Deployer {
    function run() public broadcast useDeployment returns (address) {
        // Deploy TestMNAVPriceFeed
        TestMNAVPriceFeed priceFeed = new TestMNAVPriceFeed();
        console.log("TestMNAVPriceFeed", address(priceFeed));

        return (address(priceFeed));
    }
}
