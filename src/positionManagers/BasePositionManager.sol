// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import "../StakedUSDaiStorage.sol";
import "./PositionManager.sol";

import "../interfaces/external/IWrappedMToken.sol";
import "../interfaces/IBasePositionManager.sol";

/**
 * @title Base Position Manager
 * @author MetaStreet Foundation
 */
abstract contract BasePositionManager is
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    PositionManager,
    StakedUSDaiStorage,
    IBasePositionManager
{
    /*------------------------------------------------------------------------*/
    /* Immutable state */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Wrapped M token
     */
    IWrappedMToken internal immutable _wrappedMToken;

    /**
     * @notice Admin fee rate
     */
    uint256 internal immutable _baseYieldAdminFeeRate;

    /*------------------------------------------------------------------------*/
    /* Constructor */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Constructor
     * @param wrappedMToken_ Wrapped M token
     * @param baseYieldAdminFeeRate_ Base yield admin fee rate
     */
    constructor(address wrappedMToken_, uint256 baseYieldAdminFeeRate_) {
        _wrappedMToken = IWrappedMToken(wrappedMToken_);
        _baseYieldAdminFeeRate = baseYieldAdminFeeRate_;
    }

    /*------------------------------------------------------------------------*/
    /* Internal helpers */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc PositionManager
     */
    function _assets(
        ValuationType
    ) internal view virtual override returns (uint256) {
        /* Scaled balance of wrapped M token */
        uint256 scaledBalance = _scale(_wrappedMToken.balanceOf(address(this)));

        /* Calculate admin fee */
        uint256 adminFee = ((scaledBalance + claimableBaseYield()) * _baseYieldAdminFeeRate) / BASIS_POINTS_SCALE;

        return scaledBalance + claimableBaseYield() - adminFee;
    }

    /**
     * @notice Scale factor
     * @return Scale factor
     */
    function _scaleFactor() internal view returns (uint256) {
        return 10 ** (18 - IERC20Metadata(address(_wrappedMToken)).decimals());
    }

    /**
     * @notice Helper function to scale up a value
     * @param value Value
     * @return Scaled value
     */
    function _scale(
        uint256 value
    ) internal view returns (uint256) {
        return value * _scaleFactor();
    }

    /**
     * @notice Helper function to scale down a value
     * @param value Value
     * @return Unscaled value
     */
    function _unscale(
        uint256 value
    ) internal view returns (uint256) {
        return value / _scaleFactor();
    }

    /*------------------------------------------------------------------------*/
    /* Getter */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IBasePositionManager
     */
    function claimableBaseYield() public view returns (uint256) {
        return _scale(_wrappedMToken.accruedYieldOf(address(this)) + _wrappedMToken.accruedYieldOf(address(_usdai)));
    }

    /**
     * @inheritdoc IBasePositionManager
     */
    function adminFeeRate() external view returns (uint256) {
        return _baseYieldAdminFeeRate;
    }

    /**
     * @inheritdoc IBasePositionManager
     */
    function adminFeeRecipient() external view returns (address) {
        return _adminFeeRecipient;
    }

    /*------------------------------------------------------------------------*/
    /* API */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IBasePositionManager
     */
    function claimBaseYield() external {
        _wrappedMToken.claimFor(address(_usdai));
        _wrappedMToken.claimFor(address(this));
    }

    /*------------------------------------------------------------------------*/
    /* Permissioned API */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IBasePositionManager
     */
    function depositBaseYield(
        uint256 usdaiAmount
    ) external onlyRole(STRATEGY_ADMIN_ROLE) nonReentrant returns (uint256, uint256) {
        /* Scale down the USDai amount */
        uint256 wrappedMAmount = _unscale(usdaiAmount);

        /* Validate balance */
        if (wrappedMAmount > _wrappedMToken.balanceOf(address(this))) {
            revert InsufficientBalance();
        }

        /* Approve wrapped M token to spend USDai */
        _wrappedMToken.approve(address(_usdai), wrappedMAmount);

        /* Deposit wrapped M token for USDai */
        uint256 usdaiAmount_ = _usdai.deposit(address(_wrappedMToken), wrappedMAmount, 0, address(this));

        /* Calculate admin fee */
        uint256 adminFee_ = (usdaiAmount_ * _baseYieldAdminFeeRate) / BASIS_POINTS_SCALE;

        /* Transfer admin fee to admin fee recipient */
        if (adminFee_ > 0) {
            _usdai.transfer(_adminFeeRecipient, adminFee_);

            /* Calculate amount less admin fee */
            usdaiAmount_ -= adminFee_;
        }

        /* Emit BaseYieldDeposited */
        emit BaseYieldDeposited(usdaiAmount_, adminFee_);

        return (usdaiAmount_, adminFee_);
    }
}
