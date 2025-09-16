// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import {BaseTest} from "../Base.t.sol";
import {ChainlinkPriceOracle} from "../../src/oracles/ChainlinkPriceOracle.sol";
import {AggregatorV3Interface} from "../../src/interfaces/external/IAggregatorV3Interface.sol";
import {IPriceOracle} from "../../src/interfaces/IPriceOracle.sol";

contract ChainlinkPriceOracleTest is BaseTest {
    // Mainnet addresses
    address constant WETH_ETHEREUM = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant WETH_ETHEREUM_PRICE_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419; // WETH_ETHEREUM/USD
    address constant USDC_ETHEREUM = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant USDC_ETHEREUM_PRICE_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6; // USDC_ETHEREUM/USD
    address constant DAI_ETHEREUM = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant DAI_ETHEREUM_PRICE_FEED = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9; // DAI_ETHEREUM/USD

    ChainlinkPriceOracle public oracle;

    function setUp() public override {
        vm.createSelectFork(vm.envString("ETHEREUM_RPC_URL"));
        vm.rollFork(22244554);

        // Create arrays for constructor
        address[] memory tokens = new address[](3);
        tokens[0] = USDC_ETHEREUM;
        tokens[1] = DAI_ETHEREUM;
        tokens[2] = WETH_ETHEREUM;

        address[] memory priceFeeds = new address[](3);
        priceFeeds[0] = USDC_ETHEREUM_PRICE_FEED;
        priceFeeds[1] = DAI_ETHEREUM_PRICE_FEED;
        priceFeeds[2] = WETH_ETHEREUM_PRICE_FEED;

        // Deploy oracle
        oracle = new ChainlinkPriceOracle(M_NAV_PRICE_FEED, tokens, priceFeeds);
    }

    function test__Price_WETH_ETHEREUM() public view {
        // Get WETH_ETHEREUM price in terms of USDai
        uint256 price = oracle.price(WETH_ETHEREUM);

        (, int256 answer,,,) = AggregatorV3Interface(WETH_ETHEREUM_PRICE_FEED).latestRoundData();

        assertEq(price, uint256(answer) * 10 ** 10);
    }

    function test__Price_USDC_ETHEREUM() public view {
        // Get USDC_ETHEREUM price in terms of USDai
        uint256 price = oracle.price(USDC_ETHEREUM);

        (, int256 answer,,,) = AggregatorV3Interface(USDC_ETHEREUM_PRICE_FEED).latestRoundData();

        assertEq(price, uint256(answer) * 10 ** 10);
    }

    function test__Price_DAI_ETHEREUM() public view {
        // Get DAI_ETHEREUM price in terms of USDai
        uint256 price = oracle.price(DAI_ETHEREUM);

        (, int256 answer,,,) = AggregatorV3Interface(DAI_ETHEREUM_PRICE_FEED).latestRoundData();

        assertEq(price, uint256(answer) * 10 ** 10);
    }

    function test__Price_RevertWhen_UnsupportedToken() public {
        // Create a random token address
        address randomToken = address(0x123);

        // Should revert when trying to get price for unsupported token
        vm.expectRevert(abi.encodeWithSelector(IPriceOracle.UnsupportedToken.selector, randomToken));
        oracle.price(randomToken);
    }

    function test__RemoveTokenPriceFeeds() public {
        address[] memory tokens = new address[](1);
        tokens[0] = USDC_ETHEREUM;

        // Remove USDC_ETHEREUM price feed
        oracle.removeTokenPriceFeeds(tokens);

        // Should revert when trying to get price for unsupported token
        vm.expectRevert(abi.encodeWithSelector(IPriceOracle.UnsupportedToken.selector, USDC_ETHEREUM));
        oracle.price(USDC_ETHEREUM);
    }
}
