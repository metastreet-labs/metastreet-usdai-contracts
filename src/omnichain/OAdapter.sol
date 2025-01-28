// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFTCore.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/utils/RateLimiter.sol";

import "../interfaces/IMintable.sol";

/**
 * @title Omnichain Adapter
 * @author MetaStreet Foundation
 */
contract OAdapter is OFTCore, RateLimiter {
    /*------------------------------------------------------------------------*/
    /* Immutable state */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Token
     */
    IMintable internal immutable _token;

    /*------------------------------------------------------------------------*/
    /* Constructor */
    /*------------------------------------------------------------------------*/

    /**
     * @dev Mintable adapter contructor
     * @param token_ The address of the wrapped token
     * @param lzEndpoint_ The LayerZero endpoint address
     * @param delegate_ The delegate address
     * @param rateLimitConfigs_ The rate limit configs
     */
    constructor(
        address token_,
        address lzEndpoint_,
        RateLimitConfig[] memory rateLimitConfigs_,
        address delegate_
    ) OFTCore(IERC20Metadata(token_).decimals(), lzEndpoint_, delegate_) Ownable(delegate_) {
        /* Set token */
        _token = IMintable(token_);

        /* Set rate limits */
        _setRateLimits(rateLimitConfigs_);
    }

    /*------------------------------------------------------------------------*/
    /* Overrides */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc OFTCore
     */
    function _debit(
        address _from,
        uint256 _amountLD,
        uint256 _minAmountLD,
        uint32 _dstEid
    ) internal override returns (uint256 amountSentLD, uint256 amountReceivedLD) {
        (amountSentLD, amountReceivedLD) = _debitView(_amountLD, _minAmountLD, _dstEid);
        _checkAndUpdateRateLimit(_dstEid, amountSentLD);
        _token.burn(_from, amountSentLD);
    }

    /**
     * @inheritdoc OFTCore
     */
    function _credit(
        address _to,
        uint256 _amountLD,
        uint32 /*_srcEid*/
    ) internal override returns (uint256 amountReceivedLD) {
        _token.mint(_to, _amountLD);
        return _amountLD;
    }

    /*------------------------------------------------------------------------*/
    /* Getters */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IOFT
     */
    function token() public view override returns (address) {
        return address(_token);
    }

    /**
     * @inheritdoc IOFT
     */
    function approvalRequired() external pure returns (bool) {
        return false;
    }

    /*------------------------------------------------------------------------*/
    /* Admin API */
    /*------------------------------------------------------------------------*/

    /**
     * @dev Sets the rate limits based on RateLimitConfig array. Only callable by the owner.
     * @param _rateLimitConfigs An array of RateLimitConfig structures defining the rate limits.
     */
    function setRateLimits(
        RateLimitConfig[] calldata _rateLimitConfigs
    ) external onlyOwner {
        _setRateLimits(_rateLimitConfigs);
    }
}
