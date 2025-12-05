// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import {IPriceOracle} from "../interfaces/IPriceOracle.sol";
import {IUSDai} from "../interfaces/IUSDai.sol";

import {ILoanRouter} from "@metastreet-usdai-loan-router/interfaces/ILoanRouter.sol";

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

    /**
     * @notice Vesting duration (7 days)
     */
    uint256 private constant VESTING_DURATION = 7 * 86400;

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
     * @param interest Scaled interest amount (less admin fee)
     * @param oldAccrualRate Old accrual rate
     * @param timestamp Timestamp
     * @param lastRepaymentTimestamp Last repayment timestamp
     * @return vestInterest_ Unscaled interest amount for vesting
     */
    function _accrue(
        LoanRouterPositionManager.Accrual storage accrual,
        uint256 interest,
        uint256 oldAccrualRate,
        uint64 timestamp,
        uint64 lastRepaymentTimestamp
    ) internal returns (uint256 vestInterest_) {
        /* Compute scaled accrued value */
        uint256 accruedValue = oldAccrualRate * (timestamp - lastRepaymentTimestamp);

        /* Compute scaled interest amount for vesting */
        if (interest > accruedValue) vestInterest_ = (interest - accruedValue) / FIXED_POINT_SCALE;

        /* Accrue scaled interest */
        accrual.accrued = accrual.accrued + accrual.rate * (block.timestamp - accrual.timestamp) - accruedValue;

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

            /* Simulate vested interest */
            uint256 elapsed = block.timestamp - loansStorage.repaymentBalances[currencyToken].vest.timestamp;
            uint256 vested = elapsed >= VESTING_DURATION
                ? loansStorage.repaymentBalances[currencyToken].vest.amount
                : Math.mulDiv(loansStorage.repaymentBalances[currencyToken].vest.amount, elapsed, VESTING_DURATION);

            /* Get repayment balance in terms of USDai */
            totalRepaymentBalance += _value(
                usdai, priceOracle, currencyToken, loansStorage.repaymentBalances[currencyToken].repayment + vested
            );

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
    /* Vesting Logic */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Vest interest
     * @param repaymentBalances Repayment balances
     */
    function vestInterest(
        LoanRouterPositionManager.Repayment storage repaymentBalances
    ) public {
        /* If no amount to vest, return early */
        if (repaymentBalances.vest.amount == 0) return;

        /* Compute elapsed time */
        uint256 elapsed = block.timestamp - repaymentBalances.vest.timestamp;

        /* Compute vested amount */
        uint256 vested = elapsed >= VESTING_DURATION
            ? repaymentBalances.vest.amount
            : Math.mulDiv(repaymentBalances.vest.amount, elapsed, VESTING_DURATION);

        /* If vested amount is zero, return early */
        if (vested == 0) return;

        /* Update repayment */
        repaymentBalances.repayment += vested;

        /* Update vesting */
        repaymentBalances.vest.amount -= vested;
        repaymentBalances.vest.timestamp = uint64(block.timestamp);
    }

    /**
     * @notice Add vesting amount with blended schedule
     * @param repaymentBalances Repayment balances
     * @param newAmount New amount to add to vesting
     */
    function addVestingAmount(
        LoanRouterPositionManager.Repayment storage repaymentBalances,
        uint256 newAmount
    ) internal {
        /* If no existing vesting, start fresh */
        if (repaymentBalances.vest.amount == 0) {
            repaymentBalances.vest.amount = newAmount;
            repaymentBalances.vest.originalAmount = newAmount;
            repaymentBalances.vest.timestamp = uint64(block.timestamp);
            return;
        }

        /* Compute vested from original */
        uint256 vestedAmount = repaymentBalances.vest.originalAmount - repaymentBalances.vest.amount;

        /* Compute new original amount */
        uint256 newOriginal = repaymentBalances.vest.originalAmount + newAmount;

        /* Compute new effective elapsed time */
        uint256 effectiveElapsed = Math.mulDiv(vestedAmount, VESTING_DURATION, newOriginal);

        /* Update state */
        repaymentBalances.vest.amount += newAmount;
        repaymentBalances.vest.originalAmount = newOriginal;
        repaymentBalances.vest.timestamp = uint64(block.timestamp - effectiveElapsed);
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

        /* Update vesting interest */
        vestInterest(loansStorage.repaymentBalances[loanTerms.currencyToken]);

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
        _accrue(accrual, 0, 0, 0, 0);

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
     * @param repaymentDeadline Repayment deadline
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
        address loanRouter,
        uint64 repaymentDeadline
    ) external {
        /* Validate hook context */
        _validateHookContext(loanTerms, trancheIndex, loanRouter);

        /* Update vesting interest */
        vestInterest(loansStorage.repaymentBalances[loanTerms.currencyToken]);

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

        /* Compute seconds early if it is not prepayment */
        uint256 secondsEarly = block.timestamp > repaymentDeadline - loanTerms.repaymentInterval
            && block.timestamp < repaymentDeadline ? repaymentDeadline - block.timestamp : 0;

        /* Compute scaled new accrual rate */
        uint256 newAccrualRate = Math.mulDiv(
            loanTerms.trancheSpecs[trancheIndex].rate * newLoanBalance,
            loanTerms.repaymentInterval,
            loanTerms.repaymentInterval + secondsEarly
        );

        /* Get interest accrual */
        LoanRouterPositionManager.Accrual storage accrual = loansStorage.interestAccruals[loanTerms.currencyToken];

        /* Update accrued interest, timestamp, and calculate unscaled vesting interest */
        uint256 vestInterest_ = _accrue(
            accrual,
            (interest - adminFee) * FIXED_POINT_SCALE,
            loan.accrualRate,
            uint64(block.timestamp),
            loan.lastRepaymentTimestamp
        );

        /* Update unscaled vesting interest */
        if (vestInterest_ > 0) {
            loansStorage.repaymentBalances[loanTerms.currencyToken].repayment -= vestInterest_;
            addVestingAmount(loansStorage.repaymentBalances[loanTerms.currencyToken], vestInterest_);
        }

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

        /* Update vesting interest */
        vestInterest(loansStorage.repaymentBalances[loanTerms.currencyToken]);

        /* Get loan */
        LoanRouterPositionManager.Loan storage loan = loansStorage.loan[loanTermsHash];

        /* Get interest accrual */
        LoanRouterPositionManager.Accrual storage accrual = loansStorage.interestAccruals[loanTerms.currencyToken];

        /* Update accrued interest and timestamp */
        _accrue(accrual, 0, 0, 0, 0);

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

        /* Update vesting interest */
        vestInterest(loansStorage.repaymentBalances[loanTerms.currencyToken]);

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

        /* Update accrued interest, timestamp, and calculate unscaled vesting interest */
        uint256 vestInterest_ = _accrue(
            accrual,
            (interest - adminFee) * FIXED_POINT_SCALE,
            loan.accrualRate,
            loan.liquidationTimestamp,
            loan.lastRepaymentTimestamp
        );

        /* Update unscaled vesting interest */
        if (vestInterest_ > 0) {
            loansStorage.repaymentBalances[loanTerms.currencyToken].repayment -= vestInterest_;
            addVestingAmount(loansStorage.repaymentBalances[loanTerms.currencyToken], vestInterest_);
        }

        /* Delete loan */
        delete loansStorage.loan[loanTermsHash];
    }
}
