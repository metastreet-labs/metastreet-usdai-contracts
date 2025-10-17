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
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";
import {IUSDai} from "../USDai.sol";

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
     * @notice Currency tokens storage location
     * @dev keccak256(abi.encode(uint256(keccak256("stakedUSDai.currencyTokens")) - 1)) & ~bytes32(uint256(0xff));
     */
    bytes32 private constant CURRENCY_TOKENS_STORAGE_LOCATION =
        0x3609199db53dda60578a30fdbda9ff959759369fb2e5b3d34ee1ef5d7b677e00;

    /**
     * @notice Deposit timelock storage location
     * @dev keccak256(abi.encode(uint256(keccak256("stakedUSDai.depositTimelock")) - 1)) & ~bytes32(uint256(0xff));
     */
    bytes32 private constant DEPOSIT_TIMELOCK_STORAGE_LOCATION =
        0x72b00b63109b4e6aee66bd1f7e7025e905e83a0c587b163ff4a34364f92e6c00;

    /**
     * @notice Loans storage location
     * @dev keccak256(abi.encode(uint256(keccak256("stakedUSDai.loans")) - 1)) & ~bytes32(uint256(0xff));
     */
    bytes32 private constant LOANS_STORAGE_LOCATION = 0x7f96c7b8bebd6cdb1805e199be6097032ca93a91558ca770dc01baea06a3dd00;

    /*------------------------------------------------------------------------*/
    /* Structures */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Accrual type
     * @param Origination Origination accrual
     * @param Repayment Repayment accrual
     * @param Liquidated Liquidated accrual
     * @param CollateralLiquidated Collateral liquidated accrual
     */
    enum AccrualType {
        Origination,
        Repayment,
        Liquidated,
        CollateralLiquidated
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
     */
    struct Loan {
        uint256 accrualRate;
        uint256 pendingBalance;
        uint64 lastRepaymentTimestamp;
    }

    /**
     * @custom:storage-location erc7201:stakedUSDai.currencyTokens
     */
    struct CurrencyTokens {
        EnumerableSet.AddressSet currencyTokens;
    }

    /**
     * @custom:storage-location erc7201:stakedUSDai.loans
     */
    struct Loans {
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
     * @param depositTimelock_ Deposit timelock
     * @param loanRouterAdminFeeRate_ Loan router admin fee rate
     */
    constructor(address loanRouter_, address depositTimelock_, uint256 loanRouterAdminFeeRate_) {
        _loanRouter = loanRouter_;
        _depositTimelock = depositTimelock_;
        _loanRouterAdminFeeRate = loanRouterAdminFeeRate_;
    }

    /*------------------------------------------------------------------------*/
    /* Modifiers */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Only loan router modifier
     */
    modifier onlyLoanRouter() {
        if (msg.sender != _loanRouter) revert InvalidLoanRouter();
        _;
    }

    /**
     * @notice Valid lender modifier
     * @param loanTerms Loan terms
     * @param trancheIndex Tranche index
     */
    modifier validLender(ILoanRouter.LoanTerms calldata loanTerms, uint256 trancheIndex) {
        if (loanTerms.trancheSpecs[trancheIndex].lender != address(this)) revert InvalidLender();
        _;
    }

    /*------------------------------------------------------------------------*/
    /* Getter */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc ILoanRouterPositionManager
     */
    function depositTimelockBalance() external view returns (uint256) {
        /* Return USDai balance in deposit timelock */
        return _getDepositTimelockStorage().balance;
    }

    /**
     * @inheritdoc ILoanRouterPositionManager
     */
    function claimableLoanRepayment() public view returns (uint256) {
        return LoanRouterPositionManagerLogic.claimableLoanRepayment(_getCurrencyTokensStorage(), _priceOracle);
    }

    /**
     * @inheritdoc ILoanRouterPositionManager
     */
    function pendingLoanBalance() public view returns (uint256) {
        return LoanRouterPositionManagerLogic.pendingLoanBalance(
            _getCurrencyTokensStorage(), _getLoansStorage(), _priceOracle
        );
    }

    /**
     * @inheritdoc ILoanRouterPositionManager
     */
    function accruedLoanInterest() public view returns (uint256) {
        return LoanRouterPositionManagerLogic.accruedLoanInterest(
            _getCurrencyTokensStorage(), _getLoansStorage(), _priceOracle
        );
    }

    /*------------------------------------------------------------------------*/
    /* Internal helpers */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Get reference to currency tokens storage
     *
     * @return $ Reference to currency tokens storage
     */
    function _getCurrencyTokensStorage() internal pure returns (CurrencyTokens storage $) {
        assembly {
            $.slot := CURRENCY_TOKENS_STORAGE_LOCATION
        }
    }

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
        /* Compute total loan value */
        uint256 totalLoanValue = claimableLoanRepayment() + pendingLoanBalance()
            + (valuationType == PositionManager.ValuationType.CONSERVATIVE ? 0 : accruedLoanInterest());

        /* Compute admin fee */
        uint256 adminFee = (totalLoanValue * _loanRouterAdminFeeRate) / BASIS_POINTS_SCALE;

        /* Return total assets in terms of USDai */
        return _getDepositTimelockStorage().balance + totalLoanValue - adminFee;
    }

    /*------------------------------------------------------------------------*/
    /* ERC721 Receiver Hooks */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Handle receipt of an NFT
     * @dev Required to receive ERC721 tokens (collateral from loans)
     * Note: This function is called during deposit, while depositFunds has nonReentrant active.
     * It must not modify state or trigger reentrancy checks.
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
    ) external onlyLoanRouter validLender(loanTerms, trancheIndex) nonReentrant {
        LoanRouterPositionManagerLogic.loanOriginated(
            _getDepositTimelockStorage(), _getLoansStorage(), loanTerms, loanTermsHash, trancheIndex
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
        uint256,
        uint256,
        uint256
    ) external onlyLoanRouter validLender(loanTerms, trancheIndex) nonReentrant {
        LoanRouterPositionManagerLogic.loanRepayment(
            _getLoansStorage(), loanTerms, loanTermsHash, trancheIndex, loanBalance
        );
    }

    /**
     * @inheritdoc ILoanRouterHooks
     */
    function onLoanLiquidated(
        ILoanRouter.LoanTerms calldata loanTerms,
        bytes32 loanTermsHash,
        uint8 trancheIndex
    ) external onlyLoanRouter validLender(loanTerms, trancheIndex) nonReentrant {
        LoanRouterPositionManagerLogic.loanLiquidated(_getLoansStorage(), loanTerms, loanTermsHash);
    }

    /**
     * @inheritdoc ILoanRouterHooks
     */
    function onLoanCollateralLiquidated(
        ILoanRouter.LoanTerms calldata loanTerms,
        bytes32 loanTermsHash,
        uint8 trancheIndex,
        uint256,
        uint256
    ) external onlyLoanRouter validLender(loanTerms, trancheIndex) nonReentrant {
        LoanRouterPositionManagerLogic.loanCollateralLiquidated(_getLoansStorage(), loanTerms, loanTermsHash);
    }

    /*------------------------------------------------------------------------*/
    /* Permissioned API */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc ILoanRouterPositionManager
     */
    function depositFunds(ILoanRouter.LoanTerms calldata loanTerms, uint256 usdaiAmount, uint64 expiration) external {
        /* Validate deposit funds */
        bytes32 loanTermsHash = LoanRouterPositionManagerLogic.validateDepositFunds(
            _usdai,
            _depositTimelock,
            _priceOracle,
            _loanRouter,
            loanTerms,
            _getDepositTimelockStorage(),
            _getRedemptionStateStorage().redemptionBalance,
            usdaiAmount
        );

        /* Approve USDai */
        IERC20(_usdai).approve(address(IDepositTimelock(_depositTimelock)), usdaiAmount);

        /* Deposit funds */
        IDepositTimelock(_depositTimelock).deposit(_loanRouter, loanTermsHash, address(_usdai), usdaiAmount, expiration);

        /* Register currency token */
        _getCurrencyTokensStorage().currencyTokens.add(loanTerms.currencyToken);

        /* Update deposit timelock balance and amounts */
        _getDepositTimelockStorage().balance += usdaiAmount;
        _getDepositTimelockStorage().amounts[loanTermsHash] += usdaiAmount;

        /* Emit DepositFunds */
        emit DepositFunds(loanTermsHash, usdaiAmount, expiration);
    }

    /**
     * @inheritdoc ILoanRouterPositionManager
     */
    function cancelDeposit(
        ILoanRouter.LoanTerms calldata loanTerms
    ) external onlyRole(STRATEGY_ADMIN_ROLE) nonReentrant returns (uint256) {
        /* Create loan terms hash */
        bytes32 loanTermsHash = ILoanRouter(_loanRouter).loanTermsHash(loanTerms);

        /* Cancel deposit */
        uint256 usdaiAmount = IDepositTimelock(loanTerms.depositTimelock).cancel(_loanRouter, loanTermsHash);

        /* Subtract from deposit timelock balance */
        _getDepositTimelockStorage().balance -= usdaiAmount;

        /* Delete deposit timelock amount for loan terms hash */
        delete _getDepositTimelockStorage().amounts[loanTermsHash];

        /* Emit LoanDepositCancelled */
        emit LoanDepositCancelled(loanTermsHash, usdaiAmount);

        return usdaiAmount;
    }

    /**
     * @inheritdoc ILoanRouterPositionManager
     */
    function depositLoanRepayment(
        address currencyToken,
        uint256 currencyTokenAmount,
        uint256 usdaiAmountMinimum,
        bytes calldata data
    ) external onlyRole(STRATEGY_ADMIN_ROLE) nonReentrant returns (uint256) {
        /* Validate currency token amount */
        if (currencyTokenAmount > IERC20(currencyToken).balanceOf(address(this))) revert InsufficientBalance();

        /* Approve currency token */
        IERC20(currencyToken).forceApprove(address(_usdai), currencyTokenAmount);

        /* Swap currency token to USDai */
        uint256 usdaiAmount =
            _usdai.deposit(currencyToken, currencyTokenAmount, usdaiAmountMinimum, address(this), data);

        /* Compute admin fee */
        uint256 adminFee = (usdaiAmount * _loanRouterAdminFeeRate) / BASIS_POINTS_SCALE;

        /* Transfer admin fee to admin fee recipient */
        if (adminFee > 0) {
            _usdai.transfer(_adminFeeRecipient, adminFee);

            /* Subtract admin fee from USDai amount */
            usdaiAmount -= adminFee;
        }

        /* Emit LoanRepaymentDeposited */
        emit LoanRepaymentDeposited(currencyToken, currencyTokenAmount, usdaiAmount, adminFee);

        return usdaiAmount;
    }
}
