// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

/**
 * @title Mock Loan Router
 * @author MetaStreet Foundation
 */
contract MockLoanRouter {
    /*------------------------------------------------------------------------*/
    /* Getters */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Get deposit timelock
     * @return Deposit timelock address
     */
    function depositTimelock() external view returns (address) {
        return address(0);
    }
}
