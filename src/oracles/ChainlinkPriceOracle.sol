// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "../interfaces/external/IAggregatorV3Interface.sol";
import "../interfaces/IPriceOracle.sol";

/**
 * @title Chainlink Price Oracle
 * @author MetaStreet Foundation
 */
contract ChainlinkPriceOracle is IPriceOracle, AccessControl {
    using EnumerableSet for EnumerableSet.AddressSet;

    /*------------------------------------------------------------------------*/
    /* Constants */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Implementation version
     */
    string public constant IMPLEMENTATION_VERSION = "1.0";

    /**
     * @notice Implementation name
     */
    string public constant IMPLEMENTATION_NAME = "Chainlink Price Oracle";

    /**
     * @notice USDai decimals
     */
    uint8 internal constant USDAI_DECIMALS = 18;

    /**
     * @notice USDai scaling factor
     */
    int256 internal constant USDAI_SCALING_FACTOR = int256(10 ** USDAI_DECIMALS);

    /**
     * @notice M price ceiling (8 token decimals)
     */
    int256 internal constant M_PRICE_CEILING = int256(10 ** 8);

    /*------------------------------------------------------------------------*/
    /* Errors */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Invalid decimals
     */
    error InvalidDecimals();

    /*------------------------------------------------------------------------*/
    /* Events */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Token price feed added
     * @param token Token
     * @param priceFeed Price feed
     */
    event TokenPriceFeedAdded(address indexed token, address indexed priceFeed);

    /**
     * @notice Token price feed removed
     * @param token Token
     */
    event TokenPriceFeedRemoved(address indexed token);

    /*------------------------------------------------------------------------*/
    /* Structures */
    /*------------------------------------------------------------------------*/

    struct TokenPriceFeed {
        address token;
        address priceFeed;
    }

    /*------------------------------------------------------------------------*/
    /* Immutable state */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Scale factor
     */
    int256 internal immutable _scaleFactor;

    /**
     * @notice M NAV price feed
     */
    AggregatorV3Interface internal immutable _mNavPriceFeed;

    /**
     * @notice M decimals
     */
    uint8 internal immutable _mDecimals;

    /**
     * @notice M NAV price feed decimals
     */
    uint8 internal immutable _mNavDecimals;

    /*------------------------------------------------------------------------*/
    /* State */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Tokens
     */
    EnumerableSet.AddressSet internal _tokens;

    /**
     * @notice Token price feeds
     */
    mapping(address => AggregatorV3Interface) internal _priceFeeds;

    /*------------------------------------------------------------------------*/
    /* Constructor */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Chainlink Price Oracle constructor
     * @param mNavPriceFeed_ M NAV price feed
     * @param tokens_ Tokens
     * @param priceFeeds_ Price feeds
     */
    constructor(address mNavPriceFeed_, address[] memory tokens_, address[] memory priceFeeds_) {
        /* Validate price feeds */
        if (mNavPriceFeed_ == address(0)) {
            revert InvalidAddress();
        }

        /* Set M NAV price feed */
        _mNavPriceFeed = AggregatorV3Interface(mNavPriceFeed_);

        /* Set M NAV price feed decimals */
        _mNavDecimals = _mNavPriceFeed.decimals();

        /* Validate M NAV price feed decimals */
        if (_mNavDecimals != 8) revert InvalidDecimals();

        /* Add token price feeds */
        _addTokenPriceFeeds(tokens_, priceFeeds_);

        /* Grant roles */
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /*------------------------------------------------------------------------*/
    /* Getters */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Get address of M NAV price feed
     * @return M NAV price feed
     */
    function mNavPriceFeed() external view returns (address) {
        return address(_mNavPriceFeed);
    }

    /**
     * @inheritdoc IPriceOracle
     */
    function supportedToken(
        address token_
    ) public view returns (bool) {
        return _tokens.contains(token_) && address(_priceFeeds[token_]) != address(0);
    }

    /**
     * @notice Get tokens
     * @return Tokens
     */
    function supportedTokens() external view returns (address[] memory) {
        return _tokens.values();
    }

    /**
     * @notice Get address of price feeds
     * @return Price feeds
     */
    function priceFeeds() external view returns (TokenPriceFeed[] memory) {
        /* Initialize price feeds */
        TokenPriceFeed[] memory feeds = new TokenPriceFeed[](_tokens.length());

        /* Get price feeds */
        for (uint256 i = 0; i < _tokens.length(); i++) {
            address token_ = _tokens.at(i);
            feeds[i] = TokenPriceFeed({token: token_, priceFeed: address(_priceFeeds[token_])});
        }

        return feeds;
    }

    /*------------------------------------------------------------------------*/
    /* Internal helpers */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Add token price feeds
     * @param tokens_ Tokens
     * @param priceFeeds_ Price feeds
     */
    function _addTokenPriceFeeds(address[] memory tokens_, address[] memory priceFeeds_) internal {
        /* Validate tokens and price feeds */
        if (tokens_.length != priceFeeds_.length) {
            revert InvalidLength();
        }

        /* Set token price feeds */
        for (uint256 i = 0; i < tokens_.length; i++) {
            /* Validate token */
            if (tokens_[i] == address(0) || priceFeeds_[i] == address(0)) revert InvalidAddress();

            /* Validate price feed decimals */
            if (AggregatorV3Interface(priceFeeds_[i]).decimals() > 18) revert InvalidDecimals();

            /* Validate token price feed is not already set */
            if (address(_priceFeeds[tokens_[i]]) != address(0)) revert InvalidAddress();

            /* Add token */
            _tokens.add(tokens_[i]);

            /* Set token price feed */
            _priceFeeds[tokens_[i]] = AggregatorV3Interface(priceFeeds_[i]);

            /* Emit event */
            emit TokenPriceFeedAdded(tokens_[i], priceFeeds_[i]);
        }
    }

    /**
     * @notice Remove token price feeds
     * @param tokens_ Tokens
     */
    function _removeTokenPriceFeed(
        address[] memory tokens_
    ) internal {
        /* Set token price feeds */
        for (uint256 i = 0; i < tokens_.length; i++) {
            /* Validate token */
            if (tokens_[i] == address(0)) revert InvalidAddress();

            /* Validate token is currently supported */
            if (!_tokens.contains(tokens_[i])) revert InvalidAddress();

            /* Remove token */
            _tokens.remove(tokens_[i]);

            /* Set token price feed */
            delete _priceFeeds[tokens_[i]];

            /* Emit event */
            emit TokenPriceFeedRemoved(tokens_[i]);
        }
    }

    /**
     * @notice Get derived price
     * @param token_ Token
     * @return Derived price
     */
    function _getDerivedPrice(
        address token_
    ) internal view returns (int256) {
        /* Get token price feed */
        AggregatorV3Interface tokenPriceFeed = _priceFeeds[token_];

        /* Get token price */
        (, int256 tokenPrice,,,) = tokenPriceFeed.latestRoundData();
        uint8 tokenDecimals = tokenPriceFeed.decimals();
        tokenPrice = _scalePrice(tokenPrice, tokenDecimals);

        /* Get M NAV price with 10 ** _mNavDecimals as ceiling */
        (, int256 mNavPrice,,,) = _mNavPriceFeed.latestRoundData();
        mNavPrice = _scalePrice(mNavPrice < M_PRICE_CEILING ? mNavPrice : M_PRICE_CEILING, _mNavDecimals);

        return (tokenPrice * USDAI_SCALING_FACTOR) / mNavPrice;
    }

    /**
     * @notice Scale price
     * @param price_ Price to scale
     * @param priceDecimals Decimals of the price
     * @return Scaled price
     */
    function _scalePrice(int256 price_, uint8 priceDecimals) internal pure returns (int256) {
        return price_ * int256(10 ** uint256(USDAI_DECIMALS - priceDecimals));
    }

    /*------------------------------------------------------------------------*/
    /* Public API */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IPriceOracle
     */
    function price(
        address token_
    ) external view returns (uint256) {
        /* Validate token is supported */
        if (!supportedToken(token_)) revert UnsupportedToken(token_);

        /* Get price of token in terms of M token */
        int256 price_ = _getDerivedPrice(token_);

        /* Validate price is non-zero and non-negative */
        if (price_ <= 0) revert InvalidPrice();

        /* Return price scaled up by scale factor */
        return uint256(price_);
    }

    /*------------------------------------------------------------------------*/
    /* Admin API */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Add token price feed
     * @param tokens_ Tokens
     * @param priceFeeds_ Price feeds
     */
    function addTokenPriceFeeds(
        address[] memory tokens_,
        address[] memory priceFeeds_
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _addTokenPriceFeeds(tokens_, priceFeeds_);
    }

    /**
     * @notice Remove token price feeds
     * @param tokens_ Tokens
     */
    function removeTokenPriceFeeds(
        address[] memory tokens_
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _removeTokenPriceFeed(tokens_);
    }
}
