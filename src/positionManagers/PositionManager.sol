// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

/**
 * @title Base Position Manager
 * @author MetaStreet Foundation
 */
abstract contract PositionManager {
    /*------------------------------------------------------------------------*/
    /* Structures */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Asset valuation type
     */
    enum ValuationType {
        CONSERVATIVE,
        OPTIMISTIC
    }

    /*------------------------------------------------------------------------*/
    /* Errors */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Insufficient balance
     */
    error InsufficientBalance();

    /*------------------------------------------------------------------------*/
    /* Internal helpers */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Assets value
     * @return Assets value
     */
    function _assets(
        ValuationType valuationType
    ) internal view virtual returns (uint256);
}
