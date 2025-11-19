// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import {PositionManager} from "./PositionManager.sol";
import {StakedUSDaiStorage} from "../StakedUSDaiStorage.sol";

import {ILoanRouterPositionManager} from "../interfaces/ILoanRouterPositionManager.sol";

import {IDepositTimelock} from "@metastreet-usdai-loan-router/interfaces/IDepositTimelock.sol";
import {ILoanRouter} from "@metastreet-usdai-loan-router/interfaces/ILoanRouter.sol";
import {ILoanRouterHooks} from "@metastreet-usdai-loan-router/interfaces/ILoanRouterHooks.sol";

import {LoanRouterPositionManagerLogic} from "./LoanRouterPositionManagerLogic.sol";

/**
 * @title Loan Router Position Manager
 * @author MetaStreet Foundation
 */
abstract contract LoanRouterPositionManager is
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    PositionManager,
    StakedUSDaiStorage,
    ILoanRouterPositionManager,
    ILoanRouterHooks
{
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    /*------------------------------------------------------------------------*/
    /* Constants */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Deposit timelock storage location
     * @dev keccak256(abi.encode(uint256(keccak256("stakedUSDai.depositTimelock")) - 1)) & ~bytes32(uint256(0xff));
     */
    bytes32 private constant DEPOSIT_TIMELOCK_STORAGE_LOCATION =
        0x7fab4664d57f16410d3bcb5fb74c23268a2f6f0b7b67ca2a4a44fc24e93b6300;

    /**
     * @notice Loans storage location
     * @dev keccak256(abi.encode(uint256(keccak256("stakedUSDai.loans")) - 1)) & ~bytes32(uint256(0xff));
     */
    bytes32 private constant LOANS_STORAGE_LOCATION = 0xeedf9bea8709bd441d5da250df505e80fc82bec74f9f1df28edf19fa1ed4bd00;

    /*------------------------------------------------------------------------*/
    /* Structures */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Repayment
     * @param repayment Repayment amount
     * @param adminFee Admin fee amount
     */
    struct Repayment {
        uint256 repayment;
        uint256 adminFee;
    }

    /**
     * @notice Accrual state
     * @param accrued Accrued interest
     * @param rate Accrual rate
     * @param timestamp Last accrual timestamp
     */
    struct Accrual {
        uint256 accrued;
        uint256 rate;
        uint64 timestamp;
    }

    /**
     * @notice Loan
     * @param accrualRate Accrual rate
     * @param pendingBalance Pending balance
     * @param lastRepaymentTimestamp Last repayment timestamp
     * @param liquidationTimestamp Liquidation timestamp
     */
    struct Loan {
        uint256 accrualRate;
        uint256 pendingBalance;
        uint64 lastRepaymentTimestamp;
        uint64 liquidationTimestamp;
    }

    /**
     * @custom:storage-location erc7201:stakedUSDai.loans
     */
    struct Loans {
        EnumerableSet.AddressSet currencyTokens;
        mapping(address => Repayment) repaymentBalances;
        mapping(address => uint256) pendingBalances;
        mapping(address => Accrual) interestAccruals;
        mapping(bytes32 => Loan) loan;
    }

    /**
     * @custom:storage-location erc7201:stakedUSDai.depositTimelock
     * @param balance Deposit timelock USDai balance
     * @param amounts Deposit amount for each loan terms hash
     */
    struct DepositTimelock {
        uint256 balance;
        mapping(bytes32 => uint256) amounts;
    }

    /*------------------------------------------------------------------------*/
    /* Immutable state */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Loan router
     */
    address internal immutable _loanRouter;

    /**
     * @notice Deposit timelock
     */
    address internal immutable _depositTimelock;

    /**
     * @notice Admin fee rate
     */
    uint256 internal immutable _loanRouterAdminFeeRate;

    /*------------------------------------------------------------------------*/
    /* Constructor */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Constructor
     * @param loanRouter_ Loan router
     * @param loanRouterAdminFeeRate_ Loan router admin fee rate
     */
    constructor(address loanRouter_, uint256 loanRouterAdminFeeRate_) {
        _loanRouter = loanRouter_;
        _depositTimelock = ILoanRouter(loanRouter_).depositTimelock();
        _loanRouterAdminFeeRate = loanRouterAdminFeeRate_;
    }

    /*------------------------------------------------------------------------*/
    /* Getters */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc ILoanRouterPositionManager
     */
    function depositTimelockBalance() public view returns (uint256) {
        /* Return USDai balance in deposit timelock */
        return _getDepositTimelockStorage().balance;
    }

    /**
     * @inheritdoc ILoanRouterPositionManager
     */
    function loanRouterBalances() public view returns (uint256, uint256, uint256) {
        return LoanRouterPositionManagerLogic.loanRouterBalance(_getLoansStorage(), _usdai, _priceOracle);
    }

    /*------------------------------------------------------------------------*/
    /* Internal helpers */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Get reference to deposit timelock storage
     *
     * @return $ Reference to deposit timelock storage
     */
    function _getDepositTimelockStorage() internal pure returns (DepositTimelock storage $) {
        assembly {
            $.slot := DEPOSIT_TIMELOCK_STORAGE_LOCATION
        }
    }

    /**
     * @notice Get reference to loans storage
     *
     * @return $ Reference to loans storage
     */
    function _getLoansStorage() internal pure returns (Loans storage $) {
        assembly {
            $.slot := LOANS_STORAGE_LOCATION
        }
    }

    /**
     * @inheritdoc PositionManager
     */
    function _assets(
        PositionManager.ValuationType valuationType
    ) internal view virtual override returns (uint256) {
        (uint256 repaymentLoanBalance, uint256 pendingLoanBalance, uint256 accruedLoanInterestBalance) =
            loanRouterBalances();

        /* Compute accrued interest and admin fee based on valuation type */
        if (valuationType == PositionManager.ValuationType.CONSERVATIVE) accruedLoanInterestBalance = 0;

        /* Return total assets in terms of USDai */
        return depositTimelockBalance() + repaymentLoanBalance + pendingLoanBalance + accruedLoanInterestBalance
            - (accruedLoanInterestBalance * _loanRouterAdminFeeRate / BASIS_POINTS_SCALE);
    }

    /*------------------------------------------------------------------------*/
    /* ERC721 Receiver Hooks */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Handle receipt of an NFT
     * @dev Required to receive ERC721 tokens (collateral from loans)
     */
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    /*------------------------------------------------------------------------*/
    /* Loan Router Hooks */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc ILoanRouterHooks
     */
    function onLoanOriginated(
        ILoanRouter.LoanTerms calldata loanTerms,
        bytes32 loanTermsHash,
        uint8 trancheIndex
    ) external nonReentrant {
        /* Handle loan originated */
        LoanRouterPositionManagerLogic.loanOriginated(
            _getDepositTimelockStorage(),
            _getLoansStorage(),
            loanTerms,
            loanTermsHash,
            trancheIndex,
            _usdai,
            _priceOracle,
            _loanRouter
        );
    }

    /**
     * @inheritdoc ILoanRouterHooks
     */
    function onLoanRepayment(
        ILoanRouter.LoanTerms calldata loanTerms,
        bytes32 loanTermsHash,
        uint8 trancheIndex,
        uint256 loanBalance,
        uint256 principal,
        uint256 interest,
        uint256 prepayment
    ) external nonReentrant {
        /* Handle loan repayment */
        LoanRouterPositionManagerLogic.loanRepayment(
            _getLoansStorage(),
            loanTerms,
            loanTermsHash,
            trancheIndex,
            loanBalance,
            principal + prepayment,
            interest,
            _loanRouterAdminFeeRate,
            _loanRouter
        );
    }

    /**
     * @inheritdoc ILoanRouterHooks
     */
    function onLoanLiquidated(
        ILoanRouter.LoanTerms calldata loanTerms,
        bytes32 loanTermsHash,
        uint8 trancheIndex
    ) external nonReentrant {
        /* Handle loan liquidated */
        LoanRouterPositionManagerLogic.loanLiquidated(
            _getLoansStorage(), loanTerms, loanTermsHash, trancheIndex, _loanRouter
        );
    }

    /**
     * @inheritdoc ILoanRouterHooks
     */
    function onLoanCollateralLiquidated(
        ILoanRouter.LoanTerms calldata loanTerms,
        bytes32 loanTermsHash,
        uint8 trancheIndex,
        uint256 principal,
        uint256 interest
    ) external nonReentrant {
        /* Handle loan collateral liquidated */
        LoanRouterPositionManagerLogic.loanCollateralLiquidated(
            _getLoansStorage(),
            loanTerms,
            loanTermsHash,
            trancheIndex,
            principal,
            interest,
            _loanRouterAdminFeeRate,
            _loanRouter
        );
    }

    /*------------------------------------------------------------------------*/
    /* Permissioned API */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc ILoanRouterPositionManager
     */
    function depositLoanTimelock(
        bytes32 loanTermsHash,
        uint256 usdaiAmount,
        uint64 expiration
    ) external onlyRole(STRATEGY_ADMIN_ROLE) nonReentrant {
        /* Get USDai balance */
        uint256 usdaiBalance = _getDepositsStorage().balance - _getRedemptionStateStorage().redemptionBalance;

        /* Validate USDai balance */
        if (usdaiAmount > usdaiBalance) revert PositionManager.InsufficientBalance();

        /* Approve USDai */
        IERC20(_usdai).approve(address(IDepositTimelock(_depositTimelock)), usdaiAmount);

        /* Update deposits balance */
        _getDepositsStorage().balance -= usdaiAmount;

        /* Update deposit timelock balance and amounts */
        _getDepositTimelockStorage().balance += usdaiAmount;
        _getDepositTimelockStorage().amounts[loanTermsHash] += usdaiAmount;

        /* Deposit funds */
        IDepositTimelock(_depositTimelock).deposit(_loanRouter, loanTermsHash, address(_usdai), usdaiAmount, expiration);

        /* Emit LoanTimelockDeposited */
        emit LoanTimelockDeposited(loanTermsHash, usdaiAmount, expiration);
    }

    /**
     * @inheritdoc ILoanRouterPositionManager
     */
    function cancelLoanTimelock(
        bytes32 loanTermsHash
    ) external onlyRole(STRATEGY_ADMIN_ROLE) nonReentrant {
        /* Get USDai amount */
        uint256 usdaiAmount = _getDepositTimelockStorage().amounts[loanTermsHash];

        /* Update deposit timelock balance */
        _getDepositTimelockStorage().balance -= usdaiAmount;

        /* Delete deposit timelock amount for loan terms hash */
        delete _getDepositTimelockStorage().amounts[loanTermsHash];

        /* Update deposits balance */
        _getDepositsStorage().balance += usdaiAmount;

        /* Cancel deposit */
        if (IDepositTimelock(_depositTimelock).cancel(_loanRouter, loanTermsHash) != usdaiAmount) {
            revert InvalidTimelockCancellation();
        }

        /* Emit LoanTimelockCancelled */
        emit LoanTimelockCancelled(loanTermsHash, usdaiAmount);
    }

    /**
     * @inheritdoc ILoanRouterPositionManager
     */
    function depositLoanRepayment(
        address currencyToken,
        uint256 depositAmount,
        uint256 usdaiAmountMinimum,
        bytes calldata data
    ) external onlyRole(STRATEGY_ADMIN_ROLE) nonReentrant {
        /* Validate repayment balance */
        if (depositAmount > _getLoansStorage().repaymentBalances[currencyToken].repayment) {
            revert InsufficientBalance();
        }

        /* Update repayment balances */
        _getLoansStorage().repaymentBalances[currencyToken].repayment -= depositAmount;

        /* Get USDai deposit amount */
        uint256 usdaiDepositAmount;
        if (currencyToken == address(_usdai)) {
            usdaiDepositAmount = depositAmount;
        } else {
            /* Approve currency token */
            IERC20(currencyToken).forceApprove(address(_usdai), depositAmount);

            /* Swap currency token to USDai */
            usdaiDepositAmount = _usdai.deposit(currencyToken, depositAmount, usdaiAmountMinimum, address(this), data);
        }

        /* Update deposits balance */
        _getDepositsStorage().balance += usdaiDepositAmount;

        /* Emit LoanRepaymentDeposited */
        emit LoanRepaymentDeposited(currencyToken, depositAmount, usdaiDepositAmount);
    }
}
