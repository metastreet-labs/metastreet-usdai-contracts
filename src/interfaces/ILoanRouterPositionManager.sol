// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title Loan Router Position Manager Interface
 * @author MetaStreet Foundation
 */
interface ILoanRouterPositionManager {
    /*------------------------------------------------------------------------*/
    /* Errors */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Invalid timelock cancellation
     */
    error InvalidTimelockCancellation();

    /*------------------------------------------------------------------------*/
    /* Events */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Loan timelock deposited
     * @param loanTermsHash Loan terms hash
     * @param usdaiAmount USDai amount
     * @param expiration Expiration timestamp
     */
    event LoanTimelockDeposited(bytes32 indexed loanTermsHash, uint256 usdaiAmount, uint64 expiration);

    /**
     * @notice Loan timelock cancelled
     * @param loanTermsHash Loan terms hash
     * @param usdaiAmount USDai amount
     */
    event LoanTimelockCancelled(bytes32 indexed loanTermsHash, uint256 usdaiAmount);

    /**
     * @notice Loan repayment deposited
     * @param currencyToken Currency token
     * @param depositAmount Deposit amount
     * @param usdaiDepositAmount USDai deposit amount
     */
    event LoanRepaymentDeposited(
        address indexed currencyToken, uint256 depositAmount, uint256 usdaiDepositAmount
    );

    /**
     * @notice Admin fee transferred
     * @param currencyToken Currency token
     * @param adminFee Admin fee amount
     */
    event AdminFeeTransferred(address indexed currencyToken, uint256 adminFee);

    /*------------------------------------------------------------------------*/
    /* Getter */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Deposit timelock balance
     * @return Deposit timelock balance
     */
    function depositTimelockBalance() external view returns (uint256);

    /**
     * @notice Loan router balance
     * @return Repayment loan balance
     * @return Pending loan balance
     * @return Accrued loan interest balance
     */
    function loanRouterBalances() external view returns (uint256, uint256, uint256);

    /*------------------------------------------------------------------------*/
    /* Permissioned API */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Deposit loan timelock
     * @param loanTermsHash Loan terms hash
     * @param usdaiAmount USDai amount
     * @param expiration Expiration timestamp
     */
    function depositLoanTimelock(bytes32 loanTermsHash, uint256 usdaiAmount, uint64 expiration) external;

    /**
     * @notice Cancel loan timelock
     * @param loanTermsHash Loan terms hash
     */
    function cancelLoanTimelock(
        bytes32 loanTermsHash
    ) external;

    /**
     * @notice Deposit loan repayment
     * @param currencyToken Currency token
     * @param depositAmount Deposit amount
     * @param usdaiAmountMinimum Minimum USDai amount
     * @param data Swap data
     */
    function depositLoanRepayment(
        address currencyToken,
        uint256 depositAmount,
        uint256 usdaiAmountMinimum,
        bytes calldata data
    ) external;
}
