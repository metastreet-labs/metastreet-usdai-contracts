// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "@openzeppelin/contracts/proxy/Proxy.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "src/interfaces/IUSDaiQueuedDepositor.sol";

/**
 * @title Receipt Token Proxy
 * @author MetaStreet Foundation
 */
contract ReceiptTokenProxy is Proxy {
    /*------------------------------------------------------------------------*/
    /* Constants */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Beacon address (i.e.USDaiQueuedDepositor)
     */
    address internal immutable _beacon;

    /*------------------------------------------------------------------------*/
    /* Constructor */
    /*------------------------------------------------------------------------*/

    /**
     * @notice ReceiptTokenProxy constructor
     *
     * @dev Set the USDaiQueuedDepositor address as beacon
     *      and initializes the storage of the Proxy
     *
     * @param beacon_ Beacon address
     * @param implementation Implementation address
     * @param data Initialization data
     */
    constructor(address beacon_, address implementation, bytes memory data) {
        _beacon = beacon_;
        Address.functionDelegateCall(implementation, data);
    }

    /*------------------------------------------------------------------------*/
    /* Overrides */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Get implementation address
     *
     * @dev Overrides Proxy._implementation()
     *
     * @return Implementation address
     */
    function _implementation() internal view virtual override returns (address) {
        return IUSDaiQueuedDepositor(_beacon).receiptTokenImplementation();
    }
}
