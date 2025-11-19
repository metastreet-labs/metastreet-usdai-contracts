// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import {IPriceOracle} from "../interfaces/IPriceOracle.sol";
import {IUSDai} from "../interfaces/IUSDai.sol";

import {ILoanRouter} from "@usdai-loan-router-contracts/interfaces/ILoanRouter.sol";

import {LoanRouterPositionManager} from "./LoanRouterPositionManager.sol";

/**
 * @title Loan Router Position Manager Logic
 * @author MetaStreet Foundation
 */
library LoanRouterPositionManagerLogic {
    using EnumerableSet for EnumerableSet.AddressSet;

    /*------------------------------------------------------------------------*/
    /* Constants */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Fixed point scale
     */
    uint256 private constant FIXED_POINT_SCALE = 1e18;

    /**
     * @notice Basis points scale
     */
    uint256 private constant BASIS_POINTS_SCALE = 10_000;

    /*------------------------------------------------------------------------*/
    /* Errors */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Unsupported currency
     * @param currency Currency address
     */
    error UnsupportedCurrency(address currency);

    /**
     * @notice Invalid loan router
     */
    error InvalidCaller();

    /**
     * @notice Invalid lender
     */
    error InvalidLender();

    /*------------------------------------------------------------------------*/
    /* Internal helpers */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Validate hook context
     * @param loanTerms Loan terms
     * @param trancheIndex Tranche index
     * @param loanRouter Loan router
     */
    function _validateHookContext(
        ILoanRouter.LoanTerms calldata loanTerms,
        uint8 trancheIndex,
        address loanRouter
    ) internal view {
        /* Validate caller is loan router */
        if (msg.sender != loanRouter) revert InvalidCaller();

        /* Validate loan terms */
        if (loanTerms.trancheSpecs[trancheIndex].lender != address(this)) revert InvalidLender();
    }

    /**
     * @notice Update accrued interest and timestamp
     * @param accrual Accrual
     * @param oldAccrualRate Old accrual rate
     * @param timestamp Timestamp
     * @param lastRepaymentTimestamp Last repayment timestamp
     */
    function _accrue(
        LoanRouterPositionManager.Accrual storage accrual,
        uint256 oldAccrualRate,
        uint64 timestamp,
        uint64 lastRepaymentTimestamp
    ) internal {
        /* Accrue unscaled interest */
        accrual.accrued = accrual.accrued + accrual.rate * (block.timestamp - accrual.timestamp)
            - (oldAccrualRate * (timestamp - lastRepaymentTimestamp));

        /* Update timestamp */
        accrual.timestamp = uint64(block.timestamp);
    }

    /*
     * @notice Get value in USDai
     * @param priceOracle Price oracle
     * @param currencyToken Currency token address
     * @param amount Amount of currency token
     * @return Value in USDai
     */
    function _value(
        IUSDai usdai,
        IPriceOracle priceOracle_,
        address currencyToken,
        uint256 amount
    ) internal view returns (uint256) {
        /* If currency token is USDai, return amount */
        if (currencyToken == address(usdai)) return amount;

        /* Get price of currency token in terms of USDai */
        uint256 price = priceOracle_.price(currencyToken);
        return Math.mulDiv(amount, price, 10 ** IERC20Metadata(currencyToken).decimals());
    }

    /*------------------------------------------------------------------------*/
    /* Getter */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Get loan router balance
     * @param loansStorage Loans storage
     * @param usdai USDai
     * @param priceOracle Price oracle
     * @return Claimable loan balance
     * @return Pending loan balance
     * @return Accrued loan interest balance
     */
    function loanRouterBalance(
        LoanRouterPositionManager.Loans storage loansStorage,
        IUSDai usdai,
        IPriceOracle priceOracle
    ) external view returns (uint256, uint256, uint256) {
        uint256 totalRepaymentBalance;
        uint256 totalPendingBalance;
        uint256 totalAccruedBalance;
        for (uint256 i; i < loansStorage.currencyTokens.length(); i++) {
            /* Get currency token */
            address currencyToken = loansStorage.currencyTokens.at(i);

            /* Get repayment balance in terms of USDai */
            totalRepaymentBalance +=
                _value(usdai, priceOracle, currencyToken, loansStorage.repaymentBalances[currencyToken].repayment);

            /* Get pending balances in terms of USDai */
            totalPendingBalance +=
                _value(usdai, priceOracle, currencyToken, loansStorage.pendingBalances[currencyToken]);

            /* Get currency token accrual */
            LoanRouterPositionManager.Accrual storage accrual = loansStorage.interestAccruals[currencyToken];

            /* Compute unscaled accrued interest */
            uint256 accrued =
                (accrual.accrued + accrual.rate * (block.timestamp - accrual.timestamp)) / FIXED_POINT_SCALE;

            /* Get accrued value in terms of USDai */
            totalAccruedBalance += _value(usdai, priceOracle, currencyToken, accrued);
        }

        /* Return loan router balance */
        return (totalRepaymentBalance, totalPendingBalance, totalAccruedBalance);
    }

    /*------------------------------------------------------------------------*/
    /* Hook Logic */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Handle loan originated hook
     * @param depositTimelockStorage Deposit timelock storage
     * @param loansStorage Loans storage
     * @param loanTerms Loan terms
     * @param loanTermsHash Loan terms hash
     * @param trancheIndex Tranche index
     * @param usdai USDai
     * @param priceOracle Price oracle
     * @param loanRouter Loan router
     */
    function loanOriginated(
        LoanRouterPositionManager.DepositTimelock storage depositTimelockStorage,
        LoanRouterPositionManager.Loans storage loansStorage,
        ILoanRouter.LoanTerms calldata loanTerms,
        bytes32 loanTermsHash,
        uint8 trancheIndex,
        IUSDai usdai,
        IPriceOracle priceOracle,
        address loanRouter
    ) external {
        /* Validate hook context */
        _validateHookContext(loanTerms, trancheIndex, loanRouter);

        /* Validate currency token is either USDai, or supported by price oracle */
        if (loanTerms.currencyToken != address(usdai) && !priceOracle.supportedToken(loanTerms.currencyToken)) {
            revert UnsupportedCurrency(loanTerms.currencyToken);
        }

        /* Subtract deposited USDai amount from deposit timelock balance */
        depositTimelockStorage.balance -= depositTimelockStorage.amounts[loanTermsHash];

        /* Delete deposit timelock amount for loan terms hash */
        delete depositTimelockStorage.amounts[loanTermsHash];

        /* Compute scaled accrual rate */
        uint256 accrualRate = loanTerms.trancheSpecs[trancheIndex].rate * loanTerms.trancheSpecs[trancheIndex].amount;

        /* Register curency token */
        loansStorage.currencyTokens.add(loanTerms.currencyToken);

        /* Update loan in loans storage */
        loansStorage.loan[loanTermsHash] = LoanRouterPositionManager.Loan(
            accrualRate, loanTerms.trancheSpecs[trancheIndex].amount, uint64(block.timestamp), 0
        );

        /* Add loan balance to currency token balances storage */
        loansStorage.pendingBalances[loanTerms.currencyToken] += loanTerms.trancheSpecs[trancheIndex].amount;

        /* Get interest accrual */
        LoanRouterPositionManager.Accrual storage accrual = loansStorage.interestAccruals[loanTerms.currencyToken];

        /* Update accrued interest and timestamp */
        _accrue(accrual, 0, 0, 0);

        /* Update unscaled rate */
        accrual.rate += accrualRate;
    }

    /**
     * @notice Handle loan repayment hook
     * @param loansStorage Loans storage
     * @param loanTerms Loan terms
     * @param loanTermsHash Loan terms hash
     * @param trancheIndex Tranche index
     * @param loanBalance Loan balance
     * @param principal Principal amount
     * @param interest Interest amount
     * @param loanRouter Loan router
     */
    function loanRepayment(
        LoanRouterPositionManager.Loans storage loansStorage,
        ILoanRouter.LoanTerms calldata loanTerms,
        bytes32 loanTermsHash,
        uint8 trancheIndex,
        uint256 loanBalance,
        uint256 principal,
        uint256 interest,
        uint256 adminFeeRate,
        address loanRouter
    ) external {
        /* Validate hook context */
        _validateHookContext(loanTerms, trancheIndex, loanRouter);

        /* Get loan */
        LoanRouterPositionManager.Loan storage loan = loansStorage.loan[loanTermsHash];

        /* Compute admin fee amount */
        uint256 adminFee = interest * adminFeeRate / BASIS_POINTS_SCALE;

        /* Adjust for rounding losses and rounding gains */
        principal = loanBalance == 0 ? loan.pendingBalance : Math.min(loan.pendingBalance, principal);

        /* Update repayment balances */
        loansStorage.repaymentBalances[loanTerms.currencyToken].repayment += principal + interest - adminFee;
        loansStorage.repaymentBalances[loanTerms.currencyToken].adminFee += adminFee;

        /* Update total pending loan balances */
        loansStorage.pendingBalances[loanTerms.currencyToken] -= principal;

        /* Compute new loan balance */
        uint256 newLoanBalance = loan.pendingBalance - principal;

        /* Compute scaled new accrual rate */
        uint256 newAccrualRate = loanTerms.trancheSpecs[trancheIndex].rate * newLoanBalance;

        /* Get interest accrual */
        LoanRouterPositionManager.Accrual storage accrual = loansStorage.interestAccruals[loanTerms.currencyToken];

        /* Update accrued interest and timestamp */
        _accrue(accrual, loan.accrualRate, uint64(block.timestamp), loan.lastRepaymentTimestamp);

        /* Update unscaled rate */
        accrual.rate = accrual.rate + newAccrualRate - loan.accrualRate;

        /* Delete loan if fully repaid */
        if (loanBalance == 0) {
            delete loansStorage.loan[loanTermsHash];
        } else {
            /* Update loan */
            loan.accrualRate = newAccrualRate;
            loan.pendingBalance = newLoanBalance;
            loan.lastRepaymentTimestamp = uint64(block.timestamp);
        }
    }

    /**
     * @notice Handle loan liquidated hook
     * @param loansStorage Loans storage
     * @param loanTerms Loan terms
     * @param loanTermsHash Loan terms hash
     * @param trancheIndex Tranche index
     */
    function loanLiquidated(
        LoanRouterPositionManager.Loans storage loansStorage,
        ILoanRouter.LoanTerms calldata loanTerms,
        bytes32 loanTermsHash,
        uint8 trancheIndex,
        address loanRouter
    ) external {
        /* Validate hook context */
        _validateHookContext(loanTerms, trancheIndex, loanRouter);

        /* Get loan */
        LoanRouterPositionManager.Loan storage loan = loansStorage.loan[loanTermsHash];

        /* Get interest accrual */
        LoanRouterPositionManager.Accrual storage accrual = loansStorage.interestAccruals[loanTerms.currencyToken];

        /* Update accrued interest and timestamp */
        _accrue(accrual, 0, 0, 0);

        /* Update unscaled rate */
        accrual.rate -= loan.accrualRate;

        /* Update liquidation timestamp */
        loan.liquidationTimestamp = uint64(block.timestamp);
    }

    /**
     * @notice Handle loan collateral liquidated hook
     * @param loansStorage Loans storage
     * @param loanTerms Loan terms
     * @param loanTermsHash Loan terms hash
     * @param trancheIndex Tranche index
     * @param principal Principal amount
     * @param interest Interest amount
     * @param adminFeeRate Admin fee rate
     * @param loanRouter Loan router
     */
    function loanCollateralLiquidated(
        LoanRouterPositionManager.Loans storage loansStorage,
        ILoanRouter.LoanTerms calldata loanTerms,
        bytes32 loanTermsHash,
        uint8 trancheIndex,
        uint256 principal,
        uint256 interest,
        uint256 adminFeeRate,
        address loanRouter
    ) external {
        /* Validate hook context */
        _validateHookContext(loanTerms, trancheIndex, loanRouter);

        /* Get loan */
        LoanRouterPositionManager.Loan memory loan = loansStorage.loan[loanTermsHash];

        /* Compute admin fee amount */
        uint256 adminFee = interest * adminFeeRate / BASIS_POINTS_SCALE;

        /* Update repayment balances */
        loansStorage.repaymentBalances[loanTerms.currencyToken].repayment += principal + interest - adminFee;
        loansStorage.repaymentBalances[loanTerms.currencyToken].adminFee += adminFee;

        /* Subtract loan balance from pending balances storage */
        loansStorage.pendingBalances[loanTerms.currencyToken] -= loan.pendingBalance;

        /* Get interest accrual */
        LoanRouterPositionManager.Accrual storage accrual = loansStorage.interestAccruals[loanTerms.currencyToken];

        /* Update accrued interest and timestamp */
        _accrue(accrual, loan.accrualRate, loan.liquidationTimestamp, loan.lastRepaymentTimestamp);

        /* Delete loan */
        delete loansStorage.loan[loanTermsHash];
    }
}
