// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import {PositionManager} from "./PositionManager.sol";

import {IPriceOracle} from "../interfaces/IPriceOracle.sol";
import {ILoanRouterPositionManager} from "../interfaces/ILoanRouterPositionManager.sol";

import {ILoanRouter} from "@metastreet-usdai-loan-router/interfaces/ILoanRouter.sol";
import {IUSDai} from "../USDai.sol";

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

    /*------------------------------------------------------------------------*/
    /* Getter */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Get claimable loan repayment
     * @param currencyTokensStorage Currency tokens storage
     * @param priceOracle Price oracle
     * @return Total claimable repayment
     */
    function claimableLoanRepayment(
        LoanRouterPositionManager.CurrencyTokens storage currencyTokensStorage,
        IPriceOracle priceOracle
    ) external view returns (uint256) {
        uint256 totalClaimableRepayment;
        for (uint256 i; i < currencyTokensStorage.currencyTokens.length(); i++) {
            /* Get currency token */
            address currencyToken = currencyTokensStorage.currencyTokens.at(i);

            /* Get claimable repayment amounts in terms of USDai */
            totalClaimableRepayment +=
                _value(priceOracle, currencyToken, IERC20(currencyToken).balanceOf(address(this)));
        }

        /* Return total claimable repayment amounts in terms of USDai */
        return totalClaimableRepayment;
    }

    /**
     * @notice Get pending loan balance
     * @param currencyTokensStorage Currency tokens storage
     * @param loansStorage Loans storage
     * @param priceOracle Price oracle
     * @return Total pending balance
     */
    function pendingLoanBalance(
        LoanRouterPositionManager.CurrencyTokens storage currencyTokensStorage,
        LoanRouterPositionManager.Loans storage loansStorage,
        IPriceOracle priceOracle
    ) external view returns (uint256) {
        uint256 totalPendingBalance;
        for (uint256 i; i < currencyTokensStorage.currencyTokens.length(); i++) {
            /* Get currency token */
            address currencyToken = currencyTokensStorage.currencyTokens.at(i);

            /* Get pending balances in terms of USDai */
            totalPendingBalance += _value(priceOracle, currencyToken, loansStorage.pendingBalances[currencyToken]);
        }

        /* Return total pending balances in terms of USDai */
        return totalPendingBalance;
    }

    /**
     * @notice Get accrued loan interest
     * @param currencyTokensStorage Currency tokens storage
     * @param loansStorage Loans storage
     * @param priceOracle Price oracle
     * @return Total accrued interest
     */
    function accruedLoanInterest(
        LoanRouterPositionManager.CurrencyTokens storage currencyTokensStorage,
        LoanRouterPositionManager.Loans storage loansStorage,
        IPriceOracle priceOracle
    ) external view returns (uint256) {
        /* Compute total accrued interest */
        uint256 totalAccrued;
        for (uint256 i; i < currencyTokensStorage.currencyTokens.length(); i++) {
            /* Get currency token */
            address currencyToken = currencyTokensStorage.currencyTokens.at(i);

            /* Get currency token accrual */
            LoanRouterPositionManager.Accrual storage accrual = loansStorage.interestAccruals[currencyToken];

            /* Compute unscaled accrued interest */
            uint256 accrued =
                (accrual.accrued + accrual.rate * (block.timestamp - accrual.timestamp)) / FIXED_POINT_SCALE;

            /* Get accrued value in terms of USDai */
            totalAccrued += _value(priceOracle, currencyToken, accrued);
        }

        /* Return total accrued interest in terms of USDai */
        return totalAccrued;
    }

    /**
     * @notice Validate deposit funds
     * @param usdai USDai
     * @param depositTimelock Deposit timelock
     * @param priceOracle Price oracle
     * @param loanRouter Loan router
     * @param loanTerms Loan terms
     * @param depositTimelockStorage Deposit timelock storage
     * @param redemptionBalance Redemption balance
     * @param usdaiAmount USDai amount
     * @return Loan terms hash
     */
    function validateDepositFunds(
        IUSDai usdai,
        address depositTimelock,
        IPriceOracle priceOracle,
        address loanRouter,
        ILoanRouter.LoanTerms calldata loanTerms,
        LoanRouterPositionManager.DepositTimelock storage depositTimelockStorage,
        uint256 redemptionBalance,
        uint256 usdaiAmount
    ) external view returns (bytes32) {
        /* Validate pool currency token is supported in price oracle */
        if (!priceOracle.supportedToken(loanTerms.currencyToken)) {
            revert PositionManager.UnsupportedCurrency(loanTerms.currencyToken);
        }

        /* Validate currency token is not USDai and not USDai base token */
        if (loanTerms.currencyToken == address(usdai) || loanTerms.currencyToken == IUSDai(usdai).baseToken()) {
            revert PositionManager.UnsupportedCurrency(loanTerms.currencyToken);
        }

        /* Validate deposit timelock */
        if (loanTerms.depositTimelock != depositTimelock) revert ILoanRouterPositionManager.InvalidDepositTimelock();

        /* Get USDai balance */
        uint256 usdaiBalance = usdai.balanceOf(address(this)) - redemptionBalance;

        /* Validate USDai balance */
        if (usdaiAmount > usdaiBalance) revert PositionManager.InsufficientBalance();

        /* Create loan terms hash */
        bytes32 loanTermsHash = ILoanRouter(loanRouter).loanTermsHash(loanTerms);

        /* Validate not already deposited */
        if (depositTimelockStorage.amounts[loanTermsHash] != 0) revert ILoanRouterPositionManager.InvalidDeposit();

        return loanTermsHash;
    }

    /**
     * @notice Prorated loan balance
     * @param loanTerms Loan terms
     * @param loanBalance Loan balance
     * @param trancheIndex Tranche index
     * @return Prorated loan balance
     */
    function proratedLoanBalance(
        ILoanRouter.LoanTerms calldata loanTerms,
        uint256 loanBalance,
        uint256 trancheIndex
    ) internal pure returns (uint256) {
        /* Compute original total principal */
        uint256 originalPrincipal;
        for (uint256 i; i < loanTerms.trancheSpecs.length; i++) {
            originalPrincipal += loanTerms.trancheSpecs[i].amount;
        }

        /* Compute prorated loan balance */
        return Math.mulDiv(loanBalance, loanTerms.trancheSpecs[trancheIndex].amount, originalPrincipal);
    }

    /**
     * @notice Accrue interest
     * @param loansStorage Loans storage
     * @param currencyToken Currency token
     * @param oldAccrualRate Old accrual rate
     * @param newAccrualRate New accrual rate
     * @param lastRepaymentTimestamp Last repayment timestamp
     * @param accrualType Accrual type
     */
    function accrue(
        LoanRouterPositionManager.Loans storage loansStorage,
        address currencyToken,
        uint256 oldAccrualRate,
        uint256 newAccrualRate,
        uint64 lastRepaymentTimestamp,
        LoanRouterPositionManager.AccrualType accrualType
    ) internal {
        /* Get interest accrual */
        LoanRouterPositionManager.Accrual storage accrual = loansStorage.interestAccruals[currencyToken];

        /* Accrue unscaled interest */
        accrual.accrued = accrual.accrued + accrual.rate * (block.timestamp - accrual.timestamp)
            - (
                accrualType == LoanRouterPositionManager.AccrualType.Liquidated
                    ? 0
                    : (oldAccrualRate * (block.timestamp - lastRepaymentTimestamp))
            );

        /* Update timestamp */
        accrual.timestamp = uint64(block.timestamp);

        /* Update unscaled rate with a clamp to prevent underflow */
        accrual.rate = LoanRouterPositionManager.AccrualType.CollateralLiquidated == accrualType
            ? accrual.rate
            : accrual.rate + newAccrualRate < oldAccrualRate ? 0 : accrual.rate + newAccrualRate - oldAccrualRate;
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
     */
    function loanOriginated(
        LoanRouterPositionManager.DepositTimelock storage depositTimelockStorage,
        LoanRouterPositionManager.Loans storage loansStorage,
        ILoanRouter.LoanTerms calldata loanTerms,
        bytes32 loanTermsHash,
        uint8 trancheIndex
    ) external {
        /* Subtract deposited USDai amount from deposit timelock balance */
        depositTimelockStorage.balance -= depositTimelockStorage.amounts[loanTermsHash];

        /* Delete deposit timelock amount for loan terms hash */
        delete depositTimelockStorage.amounts[loanTermsHash];

        /* Compute scaled accrual rate */
        uint256 accrualRate = loanTerms.trancheSpecs[trancheIndex].rate * loanTerms.trancheSpecs[trancheIndex].amount;

        /* Update loan in loans storage */
        loansStorage.loan[loanTermsHash] = LoanRouterPositionManager.Loan(
            accrualRate, loanTerms.trancheSpecs[trancheIndex].amount, uint64(block.timestamp)
        );

        /* Add loan balance to currency token balances storage */
        loansStorage.pendingBalances[loanTerms.currencyToken] += loanTerms.trancheSpecs[trancheIndex].amount;

        /* Accrue interest */
        accrue(
            loansStorage,
            loanTerms.currencyToken,
            0,
            accrualRate,
            uint64(block.timestamp),
            LoanRouterPositionManager.AccrualType.Origination
        );
    }

    /**
     * @notice Handle loan repayment hook
     * @param loansStorage Loans storage
     * @param loanTerms Loan terms
     * @param loanTermsHash Loan terms hash
     * @param trancheIndex Tranche index
     * @param loanBalance Loan balance
     */
    function loanRepayment(
        LoanRouterPositionManager.Loans storage loansStorage,
        ILoanRouter.LoanTerms calldata loanTerms,
        bytes32 loanTermsHash,
        uint8 trancheIndex,
        uint256 loanBalance
    ) external {
        /* Get loan */
        LoanRouterPositionManager.Loan storage loan = loansStorage.loan[loanTermsHash];

        /* Compute prorated loan balance */
        uint256 proratedBalance = proratedLoanBalance(loanTerms, loanBalance, trancheIndex);

        /* Update total pending loan balances */
        loansStorage.pendingBalances[loanTerms.currencyToken] =
            loansStorage.pendingBalances[loanTerms.currencyToken] + proratedBalance - loan.pendingBalance;

        /* Compute scaled new accrual rate */
        uint256 newAccrualRate = loanTerms.trancheSpecs[trancheIndex].rate * proratedBalance;

        /* Accrue interest */
        accrue(
            loansStorage,
            loanTerms.currencyToken,
            loan.accrualRate,
            newAccrualRate,
            loan.lastRepaymentTimestamp,
            LoanRouterPositionManager.AccrualType.Repayment
        );

        /* Delete loan if loan balance is zero */
        if (loanBalance == 0) {
            delete loansStorage.loan[loanTermsHash];
        } else {
            /* Update loan */
            loan.accrualRate = newAccrualRate;
            loan.pendingBalance = proratedBalance;
            loan.lastRepaymentTimestamp = uint64(block.timestamp);
        }
    }

    /**
     * @notice Handle loan liquidated hook
     * @param loansStorage Loans storage
     * @param loanTerms Loan terms
     * @param loanTermsHash Loan terms hash
     */
    function loanLiquidated(
        LoanRouterPositionManager.Loans storage loansStorage,
        ILoanRouter.LoanTerms calldata loanTerms,
        bytes32 loanTermsHash
    ) external {
        /* Get loan */
        LoanRouterPositionManager.Loan memory loan = loansStorage.loan[loanTermsHash];

        /* Accrue interest */
        accrue(
            loansStorage,
            loanTerms.currencyToken,
            loan.accrualRate,
            0,
            loan.lastRepaymentTimestamp,
            LoanRouterPositionManager.AccrualType.Liquidated
        );
    }

    /**
     * @notice Handle loan collateral liquidated hook
     * @param loansStorage Loans storage
     * @param loanTerms Loan terms
     * @param loanTermsHash Loan terms hash
     */
    function loanCollateralLiquidated(
        LoanRouterPositionManager.Loans storage loansStorage,
        ILoanRouter.LoanTerms calldata loanTerms,
        bytes32 loanTermsHash
    ) external {
        /* Get loan */
        LoanRouterPositionManager.Loan memory loan = loansStorage.loan[loanTermsHash];

        /* Subtract loan balance from pending balances storage */
        loansStorage.pendingBalances[loanTerms.currencyToken] -= loan.pendingBalance;

        /* Accrue interest */
        accrue(
            loansStorage,
            loanTerms.currencyToken,
            loan.accrualRate,
            0,
            loan.lastRepaymentTimestamp,
            LoanRouterPositionManager.AccrualType.CollateralLiquidated
        );

        /* Delete loan */
        delete loansStorage.loan[loanTermsHash];
    }

    /*------------------------------------------------------------------------*/
    /* Internal helpers */
    /*------------------------------------------------------------------------*/

    /*
     * @notice Get value in USDai
     * @param priceOracle Price oracle
     * @param currencyToken Currency token address
     * @param amount Amount of currency token
     * @return Value in USDai
     */
    function _value(IPriceOracle priceOracle_, address currencyToken, uint256 amount) internal view returns (uint256) {
        /* Get price of currency token in terms of USDai */
        uint256 price = priceOracle_.price(currencyToken);

        /* Get decimals of currency token */
        uint256 decimals = IERC20Metadata(currencyToken).decimals();

        return Math.mulDiv(amount, price, 10 ** decimals);
    }
}
