// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ILoanRouter} from "@metastreet-usdai-loan-router/interfaces/ILoanRouter.sol";

/**
 * @title Loan Router Position Manager Interface
 * @author MetaStreet Foundation
 */
interface ILoanRouterPositionManager {
    /*------------------------------------------------------------------------*/
    /* Errors */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Invalid deposit timelock
     */
    error InvalidDepositTimelock();

    /**
     * @notice Invalid deposit
     */
    error InvalidDeposit();

    /**
     * @notice Invalid loan router
     */
    error InvalidLoanRouter();

    /**
     * @notice Invalid lender
     */
    error InvalidLender();

    /*------------------------------------------------------------------------*/
    /* Events */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Funds deposited
     * @param loanTermsHash Loan terms hash
     * @param usdaiAmount USDai amount
     * @param expiration Expiration timestamp
     */
    event DepositFunds(bytes32 indexed loanTermsHash, uint256 usdaiAmount, uint64 expiration);

    /**
     * @notice Loan deposit cancelled
     * @param loanTermsHash Loan terms hash
     * @param usdaiAmount USDai amount
     */
    event LoanDepositCancelled(bytes32 indexed loanTermsHash, uint256 usdaiAmount);

    /**
     * @notice Loan repayment deposited
     * @param currencyToken Currency token
     * @param currencyTokenAmount Currency token amount
     * @param usdaiAmount USDai amount
     * @param adminFee Admin fee
     */
    event LoanRepaymentDeposited(
        address indexed currencyToken, uint256 currencyTokenAmount, uint256 usdaiAmount, uint256 adminFee
    );

    /*------------------------------------------------------------------------*/
    /* Getter */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Deposit timelock balance
     * @return Deposit timelock balance
     */
    function depositTimelockBalance() external view returns (uint256);

    /**
     * @notice Claimable loan repayment
     * @return Claimable loan repayment
     */
    function claimableLoanRepayment() external view returns (uint256);

    /**
     * @notice Pending loan balance
     * @return Pending loan balance
     */
    function pendingLoanBalance() external view returns (uint256);

    /**
     * @notice Accrued loan interest
     * @return Accrued loan interest
     */
    function accruedLoanInterest() external view returns (uint256);

    /*------------------------------------------------------------------------*/
    /* Permissioned API */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Deposit funds
     * @param loanTerms Loan terms
     * @param usdaiAmount USDai amount
     * @param expiration Expiration timestamp
     */
    function depositFunds(ILoanRouter.LoanTerms calldata loanTerms, uint256 usdaiAmount, uint64 expiration) external;

    /**
     * @notice Cancel deposit
     * @param loanTerms Loan terms
     * @return USDai amount
     */
    function cancelDeposit(
        ILoanRouter.LoanTerms calldata loanTerms
    ) external returns (uint256);

    /**
     * @notice Deposit loan repayment
     * @param currencyToken Currency token
     * @param currencyTokenAmount Currency token amount
     * @param usdaiAmountMinimum USDai amount minimum
     * @param data Data
     * @return USDai amount
     */
    function depositLoanRepayment(
        address currencyToken,
        uint256 currencyTokenAmount,
        uint256 usdaiAmountMinimum,
        bytes calldata data
    ) external returns (uint256);
}
