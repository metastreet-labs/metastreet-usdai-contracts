// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {console} from "forge-std/console.sol";

import {BaseLoanRouterTest} from "./Base.t.sol";

import {ILoanRouter} from "@usdai-loan-router-contracts/interfaces/ILoanRouter.sol";
import {ILoanRouterHooks} from "@usdai-loan-router-contracts/interfaces/ILoanRouterHooks.sol";

/**
 * @title Mock Lender - Tracks repayment amounts
 */
contract MockLender is ILoanRouterHooks, IERC165, IERC721Receiver {
    struct RepaymentRecord {
        uint256 principal;
        uint256 prepayment;
    }

    RepaymentRecord[] public repayments;
    uint256 public totalPrincipalReceived;
    uint256 public totalPrepaymentReceived;
    uint256 public expectedAmount;

    address public loanRouter;
    address public currencyToken;

    constructor(address _loanRouter, address _currencyToken, uint256 _expectedAmount) {
        loanRouter = _loanRouter;
        currencyToken = _currencyToken;
        expectedAmount = _expectedAmount;

        // Approve loan router to spend tokens
        IERC20(currencyToken).approve(loanRouter, type(uint256).max);
    }

    function onLoanOriginated(ILoanRouter.LoanTerms calldata, bytes32, uint8) external override {}

    function onLoanRepayment(
        ILoanRouter.LoanTerms calldata,
        bytes32,
        uint8,
        uint256,
        uint256 principal,
        uint256,
        uint256 prepay
    ) external override {
        repayments.push(RepaymentRecord({principal: principal, prepayment: prepay}));
        totalPrincipalReceived += principal;
        totalPrepaymentReceived += prepay;
    }

    function onLoanLiquidated(ILoanRouter.LoanTerms calldata, bytes32, uint8) external override {}

    function onLoanCollateralLiquidated(
        ILoanRouter.LoanTerms calldata,
        bytes32,
        uint8,
        uint256,
        uint256
    ) external override {}

    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    function supportsInterface(
        bytes4 interfaceId
    ) external pure override returns (bool) {
        return interfaceId == type(ILoanRouterHooks).interfaceId || interfaceId == type(IERC165).interfaceId
            || interfaceId == type(IERC721Receiver).interfaceId;
    }

    function getRepaymentCount() external view returns (uint256) {
        return repayments.length;
    }

    function getRepayment(
        uint256 index
    ) external view returns (uint256 principal, uint256 prepayment) {
        require(index < repayments.length, "Index out of bounds");
        RepaymentRecord memory record = repayments[index];
        return (record.principal, record.prepayment);
    }
}

/**
 * @title Loan Router Position Manager Tests
 * @author MetaStreet Foundation
 */
contract LoanRouterPositionManagerTest is BaseLoanRouterTest {
    /*------------------------------------------------------------------------*/
    /* Constants */
    /*------------------------------------------------------------------------*/
    // Expected pending balance for 1M USDC loan (converted to USDai using price oracle)
    // This reflects the actual USDC price from the Arbitrum mainnet price oracle
    uint256 constant PENDING_BALANCE_1M = 999958860000000000000000; // ~999.96e18 USDai

    // Note: Refunds from DepositTimelock (excess USDai after swap) are NOT tracked
    // in repaymentBalances because they're already in USDai and don't need swapping
    /*------------------------------------------------------------------------*/
    /* Helper functions */
    /*------------------------------------------------------------------------*/

    function assertBalances(
        string memory context,
        uint256 expectedDepositTimelockBalance,
        uint256 expectedRepaymentBalance,
        uint256 expectedPendingBalance,
        uint256 expectedAccruedInterest
    ) internal view {
        assertEq(
            stakedUsdai.depositTimelockBalance(),
            expectedDepositTimelockBalance,
            string.concat(context, ": depositTimelockBalance mismatch")
        );

        (uint256 repaymentBalance, uint256 pending, uint256 accrued) = stakedUsdai.loanRouterBalances();

        assertEq(repaymentBalance, expectedRepaymentBalance, string.concat(context, ": repaymentBalance mismatch"));

        assertEq(pending, expectedPendingBalance, string.concat(context, ": pendingLoanBalance mismatch"));
        // Accrued interest can have small variations due to timing
        if (expectedAccruedInterest == 0) {
            assertEq(accrued, 0, string.concat(context, ": accruedLoanInterest should be 0"));
        } else {
            // Allow 0.0000001% tolerance for accrued interest
            uint256 tolerance = expectedAccruedInterest / 1000000000;
            assertApproxEqAbs(
                accrued, expectedAccruedInterest, tolerance, string.concat(context, ": accruedLoanInterest mismatch")
            );
        }
    }

    function _depositLoanTimelock(
        uint256 principal,
        uint256 depositAmount
    ) internal returns (ILoanRouter.LoanTerms memory) {
        ILoanRouter.LoanTerms memory loanTerms = createLoanTerms(principal);
        bytes32 loanTermsHash = loanRouter.loanTermsHash(loanTerms);
        vm.startPrank(users.strategyAdmin);
        stakedUsdai.depositLoanTimelock(loanTermsHash, depositAmount, uint64(block.timestamp + 7 days));
        vm.stopPrank();
        return loanTerms;
    }

    function _borrowLoan(
        ILoanRouter.LoanTerms memory loanTerms
    ) internal {
        ILoanRouter.LenderDepositInfo[] memory lenderDepositInfos = new ILoanRouter.LenderDepositInfo[](1);
        lenderDepositInfos[0] = ILoanRouter.LenderDepositInfo({
            depositType: ILoanRouter.DepositType.DepositTimelock,
            data: "" // Empty swap data - USDaiSwapAdapter handles USDai -> USDC internally
        });
        vm.startPrank(users.borrower);
        loanRouter.borrow(loanTerms, lenderDepositInfos);
        vm.stopPrank();
    }
    /*------------------------------------------------------------------------*/
    /* Tests: Initial State */
    /*------------------------------------------------------------------------*/

    function test__LoanRouterPositionManagerInitialState() public view {
        // All balances should be zero initially
        assertBalances("Initial state", 0, 0, 0, 0);
    }
    /*------------------------------------------------------------------------*/
    /* Tests: Getter Functions */
    /*------------------------------------------------------------------------*/

    function test__LoanRouterPositionManagerDepositTimelockBalance_ReturnsZeroInitially() public view {
        assertEq(stakedUsdai.depositTimelockBalance(), 0);
    }

    function test__LoanRouterPositionManagerLoanRouterBalances_ReturnsZeroInitially() public view {
        (uint256 repayment, uint256 pending, uint256 accrued) = stakedUsdai.loanRouterBalances();

        assertEq(repayment, 0);

        assertEq(pending, 0);

        assertEq(accrued, 0);
    }
    /*------------------------------------------------------------------------*/
    /* Tests: depositLoanTimelock and onLoanOriginated Flow */
    /*------------------------------------------------------------------------*/

    function test__LoanRouterPositionManagerdepositLoanTimelock_And_OnOriginated() public {
        uint256 principal = 1_000_000 * 1e6; // 1M USDC
        uint256 depositAmount = (1_000_000 * 1e18 * 100015) / 100000; // 1M USDai + 0.015%

        // Verify NAV before deposit
        uint256 navBefore = stakedUsdai.nav();

        // Deposit funds
        ILoanRouter.LoanTerms memory loanTerms = _depositLoanTimelock(principal, depositAmount);

        // Verify NAV after deposit
        uint256 navAfter = stakedUsdai.nav();

        // NAV should be the same after deposit
        assertEq(navAfter, navBefore, "NAV should be the same after deposit");

        // Verify deposit timelock balance increased
        assertBalances("After depositLoanTimelock", depositAmount, 0, 0, 0);

        navBefore = stakedUsdai.nav();

        // Borrow (triggers onLoanOriginated)
        _borrowLoan(loanTerms);

        // Verify NAV after borrowing
        navAfter = stakedUsdai.nav();

        // NAV should be the same after borrowing
        assertApproxEqRel(navAfter, navBefore, 0.0002e18, "NAV should be the same after borrowing");

        // Verify balances after origination
        // Note: repaymentBalance is 0 because USDai refunds don't need to be tracked
        assertBalances("After onLoanOriginated", 0, 0, PENDING_BALANCE_1M, 0);
    }

    function test__LoanRouterPositionManagerAccruedInterest_AfterOrigination() public {
        uint256 principal = 1_000_000 * 1e6; // 1M USDC
        uint256 depositAmount = (1_000_000 * 1e18 * 100015) / 100000;

        uint256 navBefore = stakedUsdai.nav();

        // Deposit funds
        ILoanRouter.LoanTerms memory loanTerms = _depositLoanTimelock(principal, depositAmount);

        // Verify NAV after deposit
        uint256 navAfter = stakedUsdai.nav();

        assertEq(navAfter, navBefore, "NAV should be the same after deposit");

        navBefore = stakedUsdai.nav();

        // Borrow (triggers onLoanOriginated)
        _borrowLoan(loanTerms);

        // Verify NAV after borrowing
        navAfter = stakedUsdai.nav();

        // NAV should be the same after borrowing
        assertApproxEqRel(navAfter, navBefore, 0.0002e18, "NAV should be the same after borrowing");

        // Warp forward 30 days
        warp(30 days);

        // Calculate expected interest based on pending balance
        uint256 expectedInterest = calculateExpectedInterest(PENDING_BALANCE_1M, RATE_10_PCT, 30 days);

        assertBalances("After 30 days", 0, 0, PENDING_BALANCE_1M, expectedInterest);
    }

    function test__LoanRouterPositionManagerAccruedInterest_CompoundsOverTime() public {
        uint256 principal = 1_000_000 * 1e6;
        uint256 depositAmount = (1_000_000 * 1e18 * 100015) / 100000;

        ILoanRouter.LoanTerms memory loanTerms = _depositLoanTimelock(principal, depositAmount);
        _borrowLoan(loanTerms);

        // Check interest after 30 days
        warp(30 days);

        (,, uint256 interest30Days) = stakedUsdai.loanRouterBalances();

        assertGt(interest30Days, 0, "Interest after 30 days should be > 0");

        // Check interest after another 30 days (60 total)
        warp(30 days);

        (,, uint256 interest60Days) = stakedUsdai.loanRouterBalances();

        // Interest at 60 days should be approximately double interest at 30 days
        assertApproxEqRel(interest60Days, interest30Days * 2, 0.0000001e18, "Interest should double");
    }
    /*------------------------------------------------------------------------*/
    /* Tests: onLoanRepayment Flow */
    /*------------------------------------------------------------------------*/

    function test__LoanRouterPositionManagerOnRepayment_Partial() public {
        uint256 principal = 1_000_000 * 1e6;
        uint256 depositAmount = (1_000_000 * 1e18 * 100015) / 100000;

        // Setup and borrow
        ILoanRouter.LoanTerms memory loanTerms = _depositLoanTimelock(principal, depositAmount);
        _borrowLoan(loanTerms);

        // Warp to repayment window
        warp(REPAYMENT_INTERVAL);

        // Make partial repayment
        (, uint64 maturity, uint64 repaymentDeadline, uint256 balance) =
            loanRouter.loanState(loanRouter.loanTermsHash(loanTerms));
        (uint256 principalPayment, uint256 interestPayment,,,) =
            interestRateModel.repayment(loanTerms, balance, repaymentDeadline, maturity, uint64(block.timestamp));

        // Convert from scaled (18 decimals) to USDC (6 decimals)
        uint256 paymentAmount = (principalPayment + interestPayment) / 1e12;
        if ((principalPayment + interestPayment) % 1e12 != 0) {
            paymentAmount += 1; // Round up
        }

        // Verify NAV before repayment
        uint256 navBefore = stakedUsdai.nav();

        vm.startPrank(users.borrower);
        loanRouter.repay(loanTerms, paymentAmount);
        vm.stopPrank();

        // Verify NAV after repayment
        uint256 navAfter = stakedUsdai.nav();

        // Allow 0.00000001% tolerance for NAV
        assertApproxEqRel(navAfter, navBefore, 0.0000000001e18, "NAV should be the same after repayment");

        // Verify repayment increased
        (uint256 repayment, uint256 pending,) = stakedUsdai.loanRouterBalances();

        assertGt(repayment, 0, "Repayment balance should be > 0");

        // Verify pending balance still exists
        assertGt(pending, 0, "Pending balance should still be > 0");
    }

    function test__LoanRouterPositionManagerOnRepayment_Full() public {
        uint256 principal = 1_000_000 * 1e6;
        uint256 depositAmount = (1_000_000 * 1e18 * 100015) / 100000;

        // Setup and borrow
        ILoanRouter.LoanTerms memory loanTerms = _depositLoanTimelock(principal, depositAmount);
        _borrowLoan(loanTerms);

        // Warp to repayment window
        warp(REPAYMENT_INTERVAL);

        // Verify NAV before repayment
        uint256 navBefore = stakedUsdai.nav();

        // Make full repayment
        uint256 fullRepaymentAmount = 2_000_000 * 1e6; // Large enough to cover everything
        vm.startPrank(users.borrower);
        loanRouter.repay(loanTerms, fullRepaymentAmount);
        vm.stopPrank();

        // Verify NAV after repayment
        uint256 navAfter = stakedUsdai.nav();

        // Allow 0.00001% tolerance for NAV
        assertApproxEqRel(navAfter, navBefore, 0.0000001e18, "NAV should be the same after repayment");

        // Verify balances after full repayment
        (uint256 repayment,,) = stakedUsdai.loanRouterBalances();

        assertBalances("After full repayment", 0, repayment, 0, 0);

        assertGt(repayment, depositAmount, "Repayment should be > depositAmount");
    }
    /*------------------------------------------------------------------------*/
    /* Tests: onLoanLiquidated Flow */
    /*------------------------------------------------------------------------*/

    function test__LoanRouterPositionManagerOnLiquidated_StopsInterestAccrual() public {
        uint256 principal = 1_000_000 * 1e6;
        uint256 depositAmount = (1_000_000 * 1e18 * 100015) / 100000;

        // Setup and borrow
        ILoanRouter.LoanTerms memory loanTerms = _depositLoanTimelock(principal, depositAmount);
        _borrowLoan(loanTerms);

        // Warp past grace period
        warp(REPAYMENT_INTERVAL + GRACE_PERIOD_DURATION + 1);

        // Store accrued interest before liquidation
        (,, uint256 accruedBefore) = stakedUsdai.loanRouterBalances();

        // Verify NAV before liquidation
        uint256 navBefore = stakedUsdai.nav();

        // Liquidate
        vm.prank(users.admin);
        loanRouter.liquidate(loanTerms);

        // Verify NAV after liquidation
        uint256 navAfter = stakedUsdai.nav();

        // NAV should be the same after liquidation
        assertEq(navAfter, navBefore, "NAV should be the same after liquidation");

        // Verify interest stopped accruing
        assertBalances("After onLoanLiquidated", 0, 0, PENDING_BALANCE_1M, accruedBefore);

        // Warp forward and verify interest doesn't increase
        warp(30 days);

        assertBalances("30 days after liquidation", 0, 0, PENDING_BALANCE_1M, accruedBefore);
    }

    function test__LoanRouterPositionManagerOnLiquidated_AccrualStateTransition() public {
        uint256 principal = 1_000_000 * 1e6;
        uint256 depositAmount = (1_000_000 * 1e18 * 100015) / 100000;
        // Setup and borrow
        ILoanRouter.LoanTerms memory loanTerms = _depositLoanTimelock(principal, depositAmount);
        _borrowLoan(loanTerms);

        // Accrue interest for 30 days
        warp(REPAYMENT_INTERVAL);

        (,, uint256 accruedAtRepaymentDeadline) = stakedUsdai.loanRouterBalances();

        assertGt(accruedAtRepaymentDeadline, 0, "Interest should have accrued");
        // Continue past grace period (additional 30 days)
        warp(GRACE_PERIOD_DURATION + 1);

        // Calculate total accrued including grace period
        (uint256 repaymentBefore, uint256 pendingBefore, uint256 accruedBeforeLiquidation) =
            stakedUsdai.loanRouterBalances();

        assertGt(accruedBeforeLiquidation, accruedAtRepaymentDeadline, "Grace period interest should accrue");
        // Liquidate the loan
        vm.prank(users.admin);
        loanRouter.liquidate(loanTerms);

        // After liquidation:
        // - Accrued interest should freeze at the liquidation amount
        // - Pending balance should remain (not yet liquidated)
        // - Repayment should remain the same
        assertBalances("Immediately after liquidation", 0, repaymentBefore, pendingBefore, accruedBeforeLiquidation);

        // Verify interest doesn't continue to accrue after liquidation
        warp(60 days);

        assertBalances("60 days after liquidation", 0, repaymentBefore, pendingBefore, accruedBeforeLiquidation);
    }

    function test__LoanRouterPositionManagerOnCollateralLiquidated_FullProceeds() public {
        uint256 principal = 1_000_000 * 1e6;
        uint256 depositAmount = (1_000_000 * 1e18 * 100015) / 100000;
        // Setup and borrow
        ILoanRouter.LoanTerms memory loanTerms = _depositLoanTimelock(principal, depositAmount);
        _borrowLoan(loanTerms);

        // Warp past grace period and liquidate
        warp(REPAYMENT_INTERVAL + GRACE_PERIOD_DURATION + 1);
        vm.prank(users.admin);
        loanRouter.liquidate(loanTerms);

        // Simulate collateral liquidation with full recovery (120% of principal)
        uint256 liquidationProceeds = (principal * 120) / 100;

        // The liquidator would have sold the collateral and needs to transfer proceeds to LoanRouter
        // Fund the liquidator and transfer to LoanRouter
        deal(USDC, ENGLISH_AUCTION_LIQUIDATOR, liquidationProceeds);
        vm.prank(ENGLISH_AUCTION_LIQUIDATOR);
        IERC20(USDC).transfer(address(loanRouter), liquidationProceeds);

        // Get balances before onCollateralLiquidated
        (uint256 repaymentBefore,, uint256 accruedBefore) = stakedUsdai.loanRouterBalances();

        // Call onCollateralLiquidated from the liquidator
        vm.prank(ENGLISH_AUCTION_LIQUIDATOR);
        loanRouter.onCollateralLiquidated(abi.encode(loanTerms), liquidationProceeds);

        // After collateral liquidation, verify accrual state
        // Note: onLoanLiquidated was ALREADY called by liquidate(), which froze interest
        // So onLoanCollateralLiquidated just clears the loan and distributes proceeds
        (uint256 repaymentAfter,, uint256 accruedAfter) = stakedUsdai.loanRouterBalances();

        // Accrued interest is 0 after collateral liquidation
        assertEq(accruedAfter, 0, "Accrued interest is 0");

        // Repayment should increase with proceeds
        assertGt(repaymentAfter, repaymentBefore, "Repayment should increase with liquidation proceeds");

        // Verify interest does NOT continue to accrue (rate was reduced by onLoanLiquidated)
        warp(30 days);

        (,, uint256 accruedLater) = stakedUsdai.loanRouterBalances();

        assertEq(accruedLater, 0, "Interest remains 0");
    }

    function test__LoanRouterPositionManagerOnCollateralLiquidated_PartialProceeds() public {
        uint256 principal = 1_000_000 * 1e6;
        uint256 depositAmount = (1_000_000 * 1e18 * 100015) / 100000;
        // Setup and borrow
        ILoanRouter.LoanTerms memory loanTerms = _depositLoanTimelock(principal, depositAmount);
        _borrowLoan(loanTerms);

        // Warp past grace period and liquidate
        warp(REPAYMENT_INTERVAL + GRACE_PERIOD_DURATION + 1);

        vm.prank(users.admin);
        loanRouter.liquidate(loanTerms);

        // Simulate collateral liquidation with partial recovery (50% of principal)
        uint256 liquidationProceeds = principal / 2;

        // The liquidator would have sold the collateral and needs to transfer proceeds to LoanRouter
        // Fund the liquidator and transfer to LoanRouter
        deal(USDC, ENGLISH_AUCTION_LIQUIDATOR, liquidationProceeds);
        vm.prank(ENGLISH_AUCTION_LIQUIDATOR);
        IERC20(USDC).transfer(address(loanRouter), liquidationProceeds);

        // Call onCollateralLiquidated from the liquidator
        vm.prank(ENGLISH_AUCTION_LIQUIDATOR);
        loanRouter.onCollateralLiquidated(abi.encode(loanTerms), liquidationProceeds);

        // After partial collateral liquidation - same accrual behavior
        (uint256 repaymentAfter,, uint256 accruedAfter) = stakedUsdai.loanRouterBalances();

        // Accrued interest is cleared
        assertEq(accruedAfter, 0, "Accrued interest is 0");

        // Repayment should be less than principal
        assertLt(repaymentAfter, principal * 1e12 / 2, "Repayment should be less than principal");

        // Verify interest remains 0
        warp(30 days);

        (,, uint256 accruedFinal) = stakedUsdai.loanRouterBalances();

        assertEq(accruedFinal, 0, "Interest remains 0");
    }

    function test__LoanRouterPositionManagerMultipleLoans_OneLiquidated() public {
        // Create two loans
        uint256 principal1 = 1_000_000 * 1e6;
        uint256 principal2 = 500_000 * 1e6;
        uint256 deposit1 = (1_000_000 * 1e18 * 100015) / 100000;
        uint256 deposit2 = (500_000 * 1e18 * 100015) / 100000;

        // Setup first loan
        ILoanRouter.LoanTerms memory loanTerms1 = createLoanTerms(principal1, wrappedTokenId, encodedBundle);
        bytes32 loanTermsHash1 = loanRouter.loanTermsHash(loanTerms1);
        vm.prank(users.strategyAdmin);
        stakedUsdai.depositLoanTimelock(loanTermsHash1, deposit1, uint64(block.timestamp + 7 days));
        _borrowLoan(loanTerms1);

        // Setup second loan
        ILoanRouter.LoanTerms memory loanTerms2 = createLoanTerms(principal2, wrappedTokenId2, encodedBundle2);
        bytes32 loanTermsHash2 = loanRouter.loanTermsHash(loanTerms2);
        vm.prank(users.strategyAdmin);
        stakedUsdai.depositLoanTimelock(loanTermsHash2, deposit2, uint64(block.timestamp + 7 days));
        _borrowLoan(loanTerms2);
        (, uint256 totalPending,) = stakedUsdai.loanRouterBalances();

        // Accrue interest for 30 days
        warp(REPAYMENT_INTERVAL);

        (,, uint256 accruedBoth) = stakedUsdai.loanRouterBalances();

        assertGt(accruedBoth, 0, "Interest should accrue on both loans");

        // Continue past grace period for first loan and liquidate it
        warp(GRACE_PERIOD_DURATION + 1);

        (,, uint256 accruedBeforeLiquidation) = stakedUsdai.loanRouterBalances();
        vm.prank(users.admin);
        loanRouter.liquidate(loanTerms1);

        // After liquidating first loan:
        // - Interest on first loan stops accruing
        // - Interest on second loan continues to accrue
        // - Pending balance should still include both loans
        (, uint256 pendingAfterLiq,) = stakedUsdai.loanRouterBalances();

        assertEq(pendingAfterLiq, totalPending, "Pending balance should include both loans");

        // Warp forward and verify only second loan accrues interest
        warp(30 days);

        (,, uint256 accruedAfter) = stakedUsdai.loanRouterBalances();

        // The accrued interest should only increase for the second (non-liquidated) loan
        // First loan's interest is frozen, second loan continues to accrue
        assertGt(accruedAfter, accruedBeforeLiquidation, "Second loan should continue accruing interest");

        // Now repay the second loan to verify it's still functioning correctly
        (, uint64 maturity, uint64 repaymentDeadline, uint256 balance) =
            loanRouter.loanState(loanRouter.loanTermsHash(loanTerms2));
        (uint256 principalPayment, uint256 interestPayment,,,) =
            interestRateModel.repayment(loanTerms2, balance, repaymentDeadline, maturity, uint64(block.timestamp));
        uint256 paymentAmount = (principalPayment + interestPayment) / 1e12;
        if ((principalPayment + interestPayment) % 1e12 != 0) paymentAmount += 1;
        vm.prank(users.borrower);
        loanRouter.repay(loanTerms2, paymentAmount);

        // After repaying second loan, its accrued interest should be cleared
        (,, uint256 finalAccrued) = stakedUsdai.loanRouterBalances();

        assertLt(finalAccrued, accruedAfter, "Accrued interest should decrease after repayment");
    }
    /*------------------------------------------------------------------------*/
    /* Tests: cancelLoanTimelock */
    /*------------------------------------------------------------------------*/

    function test__LoanRouterPositionManagercancelLoanTimelock() public {
        uint256 principal = 1_000_000 * 1e6;
        uint256 depositAmount = (1_000_000 * 1e18 * 100015) / 100000;
        ILoanRouter.LoanTerms memory loanTerms = createLoanTerms(principal);
        bytes32 loanTermsHash = loanRouter.loanTermsHash(loanTerms);
        vm.startPrank(users.strategyAdmin);
        // Deposit funds with short expiration
        stakedUsdai.depositLoanTimelock(loanTermsHash, depositAmount, uint64(block.timestamp + 1 hours));

        assertBalances("After deposit", depositAmount, 0, 0, 0);
        uint256 usdaiBalanceBefore = IERC20(USDAI).balanceOf(address(stakedUsdai));
        // Warp past expiration
        warp(2 hours);

        // Cancel deposit
        stakedUsdai.cancelLoanTimelock(loanTermsHash);
        vm.stopPrank();

        assertBalances("After cancel", 0, 0, 0, 0);

        assertEq(
            IERC20(USDAI).balanceOf(address(stakedUsdai)),
            usdaiBalanceBefore + depositAmount,
            "USDAI balance should increase by deposit amount"
        );
    }

    /*------------------------------------------------------------------------*/
    /* Tests: depositLoanRepayment */
    /*------------------------------------------------------------------------*/

    function test__LoanRouterPositionManagerDepositLoanRepayment_ConvertsUSDCToUSDai() public {
        uint256 principal = 1_000_000 * 1e6;
        uint256 depositAmount = (1_000_000 * 1e18 * 100015) / 100000;
        // Setup, borrow, and repay to get USDC balance
        ILoanRouter.LoanTerms memory loanTerms = _depositLoanTimelock(principal, depositAmount);
        _borrowLoan(loanTerms);
        warp(REPAYMENT_INTERVAL);

        // Make a partial repayment
        uint256 repaymentAmount = 100_000 * 1e6;
        vm.startPrank(users.borrower);
        IERC20(USDC).approve(address(loanRouter), repaymentAmount);
        loanRouter.repay(loanTerms, repaymentAmount);
        vm.stopPrank();

        // USDC is transferred directly to StakedUSDai during repayment
        uint256 usdcBalance = IERC20(USDC).balanceOf(address(stakedUsdai));

        assertGt(usdcBalance, 0, "StakedUSDai should have USDC balance after repayment");

        (uint256 repaymentBefore,,) = stakedUsdai.loanRouterBalances();

        assertGt(repaymentBefore, 0, "Should have repayment balance after repayment");

        // Convert half of physical USDC balance (conservative amount to ensure we don't exceed repayment)
        // The repayment amount is less than physical due to admin fee reserve
        uint256 usdcToConvert = usdcBalance / 2;

        // Convert USDC to USDai
        vm.startPrank(users.strategyAdmin);
        stakedUsdai.depositLoanRepayment(
            USDC,
            usdcToConvert,
            usdcToConvert * 1e12 * 98 / 100, // 2% slippage tolerance
            ""
        );
        vm.stopPrank();

        // Verify conversion worked - repayment should decrease
        (uint256 repaymentAfter,,) = stakedUsdai.loanRouterBalances();

        assertLt(repaymentAfter, repaymentBefore, "Repayment should decrease after conversion");
    }

    /*------------------------------------------------------------------------*/
    /* Tests: Complex Multi-Loan Scenarios */
    /*------------------------------------------------------------------------*/

    function test__LoanRouterPositionManagerTwoLoansSimultaneously() public {
        // Create and fund two different loans with different collateral
        uint256 principal1 = 1_000_000 * 1e6;
        uint256 principal2 = 500_000 * 1e6;
        uint256 deposit1 = (1_000_000 * 1e18 * 100015) / 100000;
        uint256 deposit2 = (500_000 * 1e18 * 100015) / 100000;

        // Create loan terms with first bundle
        ILoanRouter.LoanTerms memory loanTerms1 = createLoanTerms(principal1, wrappedTokenId, encodedBundle);
        bytes32 loanTermsHash1 = loanRouter.loanTermsHash(loanTerms1);

        // Deposit funds for first loan
        vm.startPrank(users.strategyAdmin);
        stakedUsdai.depositLoanTimelock(loanTermsHash1, deposit1, uint64(block.timestamp + 7 days));
        vm.stopPrank();

        // Create loan terms with second bundle
        ILoanRouter.LoanTerms memory loanTerms2 = createLoanTerms(principal2, wrappedTokenId2, encodedBundle2);
        bytes32 loanTermsHash2 = loanRouter.loanTermsHash(loanTerms2);

        // Deposit funds for second loan
        vm.startPrank(users.strategyAdmin);
        stakedUsdai.depositLoanTimelock(loanTermsHash2, deposit2, uint64(block.timestamp + 7 days));
        vm.stopPrank();

        // Verify total deposit timelock balance
        assertBalances("After both deposits", deposit1 + deposit2, 0, 0, 0);
        // Borrow both loans
        _borrowLoan(loanTerms1);
        _borrowLoan(loanTerms2);

        // Verify total pending balance
        // Read actual pending balance after both loans (includes slippage)
        (uint256 totalRepayment, uint256 totalPending,) = stakedUsdai.loanRouterBalances();

        assertBalances("After both loans", 0, totalRepayment, totalPending, 0);

        // Warp and verify interest accrues for both
        warp(30 days);
        uint256 expectedInterest = calculateExpectedInterest(totalPending, RATE_10_PCT, 30 days);

        assertBalances("After 30 days", 0, totalRepayment, totalPending, expectedInterest);
    }

    function test__LoanRouterPositionManagerFullLoanLifecycle() public {
        uint256 principal = 1_000_000 * 1e6;
        uint256 depositAmount = (1_000_000 * 1e18 * 100015) / 100000;

        // 1. Deposit
        ILoanRouter.LoanTerms memory loanTerms = _depositLoanTimelock(principal, depositAmount);

        assertBalances("1. After deposit", depositAmount, 0, 0, 0);
        // 2. Originate
        _borrowLoan(loanTerms);

        assertBalances("2. After origination", 0, 0, PENDING_BALANCE_1M, 0);

        // 3. Wait and accrue interest
        warp(30 days);
        uint256 expectedInterest = calculateExpectedInterest(PENDING_BALANCE_1M, RATE_10_PCT, 30 days);

        assertBalances("3. After 30 days", 0, 0, PENDING_BALANCE_1M, expectedInterest);

        // 4. Full repayment
        warp(REPAYMENT_INTERVAL - 30 days);

        vm.startPrank(users.borrower);
        loanRouter.repay(loanTerms, 2_000_000 * 1e6);
        vm.stopPrank();

        (uint256 repayment, uint256 pending, uint256 accrued) = stakedUsdai.loanRouterBalances();

        assertBalances("4. After full repayment", 0, repayment, 0, 0);

        assertEq(accrued, 0, "Accrued interest should be 0");

        assertEq(pending, 0, "Pending balance should be 0");

        // 5. Convert to USDai
        // USDC is transferred directly to StakedUSDai during repayment
        uint256 usdcBalance = IERC20(USDC).balanceOf(address(stakedUsdai));

        // Convert half of physical USDC balance (conservative amount to ensure we don't exceed repayment)
        uint256 usdcToConvert = usdcBalance / 2;

        vm.startPrank(users.strategyAdmin);
        stakedUsdai.depositLoanRepayment(USDC, usdcToConvert, usdcToConvert * 1e12 * 98 / 100, "");
        vm.stopPrank();

        (uint256 repaymentAfterConversion,,) = stakedUsdai.loanRouterBalances();

        assertLt(repaymentAfterConversion, repayment, "5. Repayment should decrease after conversion");
    }
    /*------------------------------------------------------------------------*/
    /* Tests: Multiple Repayments with Accrual Verification */
    /*------------------------------------------------------------------------*/

    function test__LoanRouterPositionManagerMultipleRepayments_AccrualCorrectness() public {
        uint256 principal = 1_000_000 * 1e6; // 1M USDC
        uint256 depositAmount = (1_000_000 * 1e18 * 100015) / 100000;

        // Setup and borrow
        ILoanRouter.LoanTerms memory loanTerms = _depositLoanTimelock(principal, depositAmount);
        _borrowLoan(loanTerms);

        // Verify initial state
        assertBalances("After origination", 0, 0, PENDING_BALANCE_1M, 0);

        // ===== First repayment period (30 days) =====
        warp(REPAYMENT_INTERVAL);

        // Calculate expected interest before first repayment
        uint256 expectedInterestBeforeRepay1 =
            calculateExpectedInterest(PENDING_BALANCE_1M, RATE_10_PCT, REPAYMENT_INTERVAL);

        assertBalances("Before first repayment", 0, 0, PENDING_BALANCE_1M, expectedInterestBeforeRepay1);

        // Make first partial repayment
        (, uint64 maturity, uint64 repaymentDeadline, uint256 balance) =
            loanRouter.loanState(loanRouter.loanTermsHash(loanTerms));
        (uint256 principalPayment1, uint256 interestPayment1,,,) =
            interestRateModel.repayment(loanTerms, balance, repaymentDeadline, maturity, uint64(block.timestamp));

        // Convert from scaled (18 decimals) to USDC (6 decimals) and round up
        uint256 paymentAmount1 = (principalPayment1 + interestPayment1) / 1e12;
        if ((principalPayment1 + interestPayment1) % 1e12 != 0) {
            paymentAmount1 += 1;
        }
        vm.startPrank(users.borrower);
        loanRouter.repay(loanTerms, paymentAmount1);
        vm.stopPrank();

        // Get new pending balance after first repayment
        (uint256 repayment1, uint256 pendingBalance1,) = stakedUsdai.loanRouterBalances();

        // After repayment, accrued interest should be 0
        assertBalances("After first repayment", 0, repayment1, pendingBalance1, 0);

        // ===== Second repayment period (30 days) =====
        warp(REPAYMENT_INTERVAL);

        // Calculate expected interest on the new reduced balance
        uint256 expectedInterestBeforeRepay2 =
            calculateExpectedInterest(pendingBalance1, RATE_10_PCT, REPAYMENT_INTERVAL);

        assertBalances("Before second repayment", 0, repayment1, pendingBalance1, expectedInterestBeforeRepay2);

        // Make second partial repayment
        (, maturity, repaymentDeadline, balance) = loanRouter.loanState(loanRouter.loanTermsHash(loanTerms));
        (uint256 principalPayment2, uint256 interestPayment2,,,) =
            interestRateModel.repayment(loanTerms, balance, repaymentDeadline, maturity, uint64(block.timestamp));
        uint256 paymentAmount2 = (principalPayment2 + interestPayment2) / 1e12;
        if ((principalPayment2 + interestPayment2) % 1e12 != 0) {
            paymentAmount2 += 1;
        }
        vm.startPrank(users.borrower);
        loanRouter.repay(loanTerms, paymentAmount2);
        vm.stopPrank();

        // Get new pending balance after second repayment
        (uint256 repayment2, uint256 pendingBalance2,) = stakedUsdai.loanRouterBalances();

        // After second repayment, accrued interest should be 0 again
        assertBalances("After second repayment", 0, repayment2, pendingBalance2, 0);

        // ===== Third repayment period (15 days partial) =====
        warp(15 days);

        // Calculate expected interest on the further reduced balance
        uint256 expectedInterestMidPeriod = calculateExpectedInterest(pendingBalance2, RATE_10_PCT, 15 days);

        assertBalances("15 days after second repayment", 0, repayment2, pendingBalance2, expectedInterestMidPeriod);

        // Warp to next repayment window
        warp(15 days);

        // Calculate expected interest for full period
        uint256 expectedInterestBeforeRepay3 =
            calculateExpectedInterest(pendingBalance2, RATE_10_PCT, REPAYMENT_INTERVAL);

        assertBalances("Before third repayment", 0, repayment2, pendingBalance2, expectedInterestBeforeRepay3);

        // Make third partial repayment
        (, maturity, repaymentDeadline, balance) = loanRouter.loanState(loanRouter.loanTermsHash(loanTerms));
        (uint256 principalPayment3, uint256 interestPayment3,,,) =
            interestRateModel.repayment(loanTerms, balance, repaymentDeadline, maturity, uint64(block.timestamp));
        uint256 paymentAmount3 = (principalPayment3 + interestPayment3) / 1e12;
        if ((principalPayment3 + interestPayment3) % 1e12 != 0) {
            paymentAmount3 += 1;
        }
        vm.startPrank(users.borrower);
        loanRouter.repay(loanTerms, paymentAmount3);
        vm.stopPrank();

        // Verify final state
        (uint256 repayment3, uint256 pendingBalance3,) = stakedUsdai.loanRouterBalances();

        assertBalances("After third repayment", 0, repayment3, pendingBalance3, 0);

        // Verify loan balance is decreasing with each repayment
        assertLt(pendingBalance1, PENDING_BALANCE_1M, "Balance should decrease after first repayment");

        assertLt(pendingBalance2, pendingBalance1, "Balance should decrease after second repayment");

        assertLt(pendingBalance3, pendingBalance2, "Balance should decrease after third repayment");
    }

    function test__LoanRouterPositionManagerMultipleRepayments_DetailedAccrualVerification() public {
        uint256 principal = 1_000_000 * 1e6; // 1M USDC
        uint256 depositAmount = (1_000_000 * 1e18 * 100015) / 100000;

        // Setup and borrow
        ILoanRouter.LoanTerms memory loanTerms = _depositLoanTimelock(principal, depositAmount);
        _borrowLoan(loanTerms);
        (, uint256 startBalance,) = stakedUsdai.loanRouterBalances();

        // ===== Period 1: 30 days =====
        warp(REPAYMENT_INTERVAL);

        (,, uint256 accruedBefore1) = stakedUsdai.loanRouterBalances();
        uint256 expectedAccrued1 = calculateExpectedInterest(startBalance, RATE_10_PCT, REPAYMENT_INTERVAL);

        // Verify accrual is correct (within 0.0001% tolerance)
        assertApproxEqRel(accruedBefore1, expectedAccrued1, 0.000001e18, "Period 1: Accrued interest mismatch");

        // Make first repayment
        (, uint64 maturity, uint64 repaymentDeadline, uint256 balance) =
            loanRouter.loanState(loanRouter.loanTermsHash(loanTerms));
        (uint256 principalPayment1, uint256 interestPayment1,,,) =
            interestRateModel.repayment(loanTerms, balance, repaymentDeadline, maturity, uint64(block.timestamp));
        uint256 paymentAmount1 = (principalPayment1 + interestPayment1) / 1e12;
        if ((principalPayment1 + interestPayment1) % 1e12 != 0) paymentAmount1 += 1;
        vm.prank(users.borrower);
        loanRouter.repay(loanTerms, paymentAmount1);
        (, uint256 balanceAfter1, uint256 accruedAfter1) = stakedUsdai.loanRouterBalances();

        // After repayment, accrued should be 0
        assertEq(accruedAfter1, 0, "Period 1: Accrued should be 0 after repayment");

        // Balance should have decreased
        assertLt(balanceAfter1, startBalance, "Period 1: Balance should decrease");

        // ===== Period 2: Wait 10 days (partial period) =====
        warp(10 days);

        (,, uint256 accruedMidPeriod) = stakedUsdai.loanRouterBalances();
        uint256 expectedMidPeriod = calculateExpectedInterest(balanceAfter1, RATE_10_PCT, 10 days);

        // Verify accrual on reduced balance
        assertApproxEqRel(
            accruedMidPeriod, expectedMidPeriod, 0.0000001e18, "Period 2 (mid): Accrued interest mismatch"
        );

        // Wait another 20 days (complete the 30-day period)
        warp(20 days);

        (,, uint256 accruedBefore2) = stakedUsdai.loanRouterBalances();
        uint256 expectedAccrued2 = calculateExpectedInterest(balanceAfter1, RATE_10_PCT, REPAYMENT_INTERVAL);

        // Verify full period accrual
        assertApproxEqRel(accruedBefore2, expectedAccrued2, 0.0000001e18, "Period 2 (full): Accrued interest mismatch");

        // Verify accrual increased from mid-period
        assertGt(accruedBefore2, accruedMidPeriod, "Period 2: Accrued should increase over time");

        // Make second repayment
        (, maturity, repaymentDeadline, balance) = loanRouter.loanState(loanRouter.loanTermsHash(loanTerms));
        (uint256 principalPayment2, uint256 interestPayment2,,,) =
            interestRateModel.repayment(loanTerms, balance, repaymentDeadline, maturity, uint64(block.timestamp));
        uint256 paymentAmount2 = (principalPayment2 + interestPayment2) / 1e12;
        if ((principalPayment2 + interestPayment2) % 1e12 != 0) paymentAmount2 += 1;
        vm.prank(users.borrower);
        loanRouter.repay(loanTerms, paymentAmount2);
        (, uint256 balanceAfter2, uint256 accruedAfter2) = stakedUsdai.loanRouterBalances();

        // After second repayment, accrued should be 0 again
        assertEq(accruedAfter2, 0, "Period 2: Accrued should be 0 after repayment");

        // Balance should continue to decrease
        assertLt(balanceAfter2, balanceAfter1, "Period 2: Balance should decrease further");

        // ===== Period 3: 30 days =====
        warp(REPAYMENT_INTERVAL);

        (,, uint256 accruedBefore3) = stakedUsdai.loanRouterBalances();
        uint256 expectedAccrued3 = calculateExpectedInterest(balanceAfter2, RATE_10_PCT, REPAYMENT_INTERVAL);

        // Verify accrual on further reduced balance
        assertApproxEqRel(accruedBefore3, expectedAccrued3, 0.0000001e18, "Period 3: Accrued interest mismatch");

        // Verify the rate of accrual decreases as balance decreases
        // Interest rate is the same, but balance is lower, so absolute interest is lower
        assertLt(expectedAccrued3, expectedAccrued2, "Period 3: Expected interest should be lower than period 2");

        assertLt(expectedAccrued2, expectedAccrued1, "Period 2: Expected interest should be lower than period 1");
    }

    /*------------------------------------------------------------------------*/
    /* Tests: Multiple Repayments with Two Lenders - Rounding Losses */
    /*------------------------------------------------------------------------*/

    function test__LoanRouterPositionManagerOnMultipleRepayments_Full() public {
        // No negative overflow when updating pendingBalance and pendingBalances

        uint256 stakedUsdaiPrincipal = 2_000_005 * 1e6; // 2.000005 USDC - larger amount, first tranche
        uint256 mockLenderPrincipal = 1_000_003 * 1e6; // 1.000003 USDC - smaller amount, second tranche
        uint256 totalPrincipal = stakedUsdaiPrincipal + mockLenderPrincipal;

        // Deploy mock lender
        MockLender mockLender = new MockLender(address(loanRouter), USDC, mockLenderPrincipal);

        // Fund the mock lender with USDai for deposit timelock
        deal(USDAI, address(mockLender), mockLenderPrincipal * 1e12 * 2);

        // Deposit funds for StakedUSDai tranche
        uint256 stakedUsdaiDeposit = (stakedUsdaiPrincipal * 1e12 * 100015) / 100000; // Add buffer for slippage
        uint256 mockLenderDeposit = (mockLenderPrincipal * 1e12 * 100015) / 100000;

        // Create loan terms with 2 tranches
        ILoanRouter.TrancheSpec[] memory trancheSpecs = new ILoanRouter.TrancheSpec[](2);
        trancheSpecs[0] =
            ILoanRouter.TrancheSpec({lender: address(stakedUsdai), amount: stakedUsdaiPrincipal, rate: RATE_10_PCT});
        trancheSpecs[1] =
            ILoanRouter.TrancheSpec({lender: address(mockLender), amount: mockLenderPrincipal, rate: RATE_10_PCT});

        ILoanRouter.LoanTerms memory loanTerms = ILoanRouter.LoanTerms({
            expiration: uint64(block.timestamp + 7 days),
            borrower: users.borrower,
            currencyToken: USDC,
            collateralToken: address(bundleCollateralWrapper),
            collateralTokenId: wrappedTokenId,
            duration: LOAN_DURATION,
            repaymentInterval: REPAYMENT_INTERVAL,
            interestRateModel: address(interestRateModel),
            gracePeriodRate: GRACE_PERIOD_RATE,
            gracePeriodDuration: uint256(GRACE_PERIOD_DURATION),
            feeSpec: ILoanRouter.FeeSpec({originationFee: totalPrincipal / 100, exitFee: 0}),
            trancheSpecs: trancheSpecs,
            collateralWrapperContext: encodedBundle,
            options: ""
        });

        bytes32 loanTermsHash = loanRouter.loanTermsHash(loanTerms);

        // Deposit funds through StakedUSDai
        vm.prank(users.strategyAdmin);
        stakedUsdai.depositLoanTimelock(loanTermsHash, stakedUsdaiDeposit, uint64(block.timestamp + 7 days));

        // Deposit funds through MockLender via DepositTimelock
        vm.startPrank(address(mockLender));
        IERC20(USDAI).approve(address(depositTimelock), type(uint256).max);
        depositTimelock.deposit(
            address(loanRouter), loanTermsHash, USDAI, mockLenderDeposit, uint64(block.timestamp + 7 days)
        );
        vm.stopPrank();

        // Borrow
        ILoanRouter.LenderDepositInfo[] memory depositInfos = new ILoanRouter.LenderDepositInfo[](2);
        depositInfos[0] =
            ILoanRouter.LenderDepositInfo({depositType: ILoanRouter.DepositType.DepositTimelock, data: ""});
        depositInfos[1] =
            ILoanRouter.LenderDepositInfo({depositType: ILoanRouter.DepositType.DepositTimelock, data: ""});

        vm.prank(users.borrower);
        loanRouter.borrow(loanTerms, depositInfos);

        // ===== First Repayment: Required Amount =====
        warp(REPAYMENT_INTERVAL);

        (, uint64 maturity, uint64 repaymentDeadline, uint256 balance) = loanRouter.loanState(loanTermsHash);
        (uint256 principalPayment1, uint256 interestPayment1,,,) =
            interestRateModel.repayment(loanTerms, balance, repaymentDeadline, maturity, uint64(block.timestamp));

        uint256 paymentAmount1 = (principalPayment1 + interestPayment1) / 1e12;
        if ((principalPayment1 + interestPayment1) % 1e12 != 0) {
            paymentAmount1 += 1;
        }

        vm.prank(users.borrower);
        loanRouter.repay(loanTerms, paymentAmount1);

        // ===== Second Repayment: Full Repayment =====
        warp(REPAYMENT_INTERVAL);

        // Make full repayment (pay off everything)
        uint256 fullPaymentAmount = totalPrincipal; // Large enough to cover remaining principal

        vm.prank(users.borrower);
        loanRouter.repay(loanTerms, fullPaymentAmount);

        // Verify hook executed successfully and loan was deleted
        // If hook reverted (silently caught by try-catch), balances would be non-zero
        (uint256 claimable, uint256 pending, uint256 accrued) = stakedUsdai.loanRouterBalances();

        // Pending and accrued should be 0 after full repayment, confirming:
        // 1. Hook didn't revert due to underflow
        // 2. Loan was deleted from storage (isFullRepayment == true path)
        // 3. State accounting is accurate
        assertEq(pending, 0, "Pending balance should be 0 (confirms hook didn't revert)");
        assertEq(accrued, 0, "Accrued balance should be 0 (confirms loan was deleted)");

        // Claimable balance should have received principal + interest
        assertGt(claimable, 0, "Should have claimable balance from repayments");
    }

    /*------------------------------------------------------------------------*/
    /* Tests: Dust Accumulation with 18-Decimal Token (USDai) */
    /*------------------------------------------------------------------------*/

    function test__LoanRouterPositionManagerDustAccumulation_USDai_ExceedsTrancheAmount() public {
        // This test verifies the fix for POSITIVE rounding errors (excess) with USDai (18 decimals)
        // With 18 decimals, scaleFactor = 1, so NO unscaling rounding losses
        // Tests that the fix prevents positive overflow and ensures accurate state accounting

        // Use amounts that create remainders when divided
        uint256 stakedUsdaiPrincipal = 333333333333333333333; // Odd number to create dust
        uint256 mockLenderPrincipal = 2666666666666666666667; // Odd number
        uint256 totalPrincipal = stakedUsdaiPrincipal + mockLenderPrincipal;

        // Create mock lender for USDai
        MockLender mockLender = new MockLender(address(loanRouter), USDAI, mockLenderPrincipal);

        // Fund the mock lender with USDai
        deal(USDAI, address(mockLender), mockLenderPrincipal * 2);

        // Create loan terms with USDai as currency token
        ILoanRouter.TrancheSpec[] memory trancheSpecs = new ILoanRouter.TrancheSpec[](2);
        trancheSpecs[0] =
            ILoanRouter.TrancheSpec({lender: address(stakedUsdai), amount: stakedUsdaiPrincipal, rate: RATE_10_PCT});
        trancheSpecs[1] =
            ILoanRouter.TrancheSpec({lender: address(mockLender), amount: mockLenderPrincipal, rate: RATE_10_PCT});

        ILoanRouter.LoanTerms memory loanTerms = ILoanRouter.LoanTerms({
            expiration: uint64(block.timestamp + 7 days),
            borrower: users.borrower,
            currencyToken: USDAI, // <<<< Using USDai (18 decimals) instead of USDC!
            collateralToken: address(bundleCollateralWrapper),
            collateralTokenId: wrappedTokenId,
            duration: LOAN_DURATION,
            repaymentInterval: REPAYMENT_INTERVAL,
            interestRateModel: address(interestRateModel),
            gracePeriodRate: GRACE_PERIOD_RATE,
            gracePeriodDuration: uint256(GRACE_PERIOD_DURATION),
            feeSpec: ILoanRouter.FeeSpec({originationFee: totalPrincipal / 100, exitFee: 0}),
            trancheSpecs: trancheSpecs,
            collateralWrapperContext: encodedBundle,
            options: ""
        });

        bytes32 loanTermsHash = loanRouter.loanTermsHash(loanTerms);

        // Deposit funds through StakedUSDai for tranche 0
        vm.prank(users.strategyAdmin);
        stakedUsdai.depositLoanTimelock(loanTermsHash, stakedUsdaiPrincipal, uint64(block.timestamp + 7 days));

        // Deposit funds through MockLender via DepositTimelock
        vm.startPrank(address(mockLender));
        IERC20(USDAI).approve(address(depositTimelock), type(uint256).max);
        depositTimelock.deposit(
            address(loanRouter), loanTermsHash, USDAI, mockLenderPrincipal, uint64(block.timestamp + 7 days)
        );
        vm.stopPrank();

        // Borrow
        ILoanRouter.LenderDepositInfo[] memory depositInfos = new ILoanRouter.LenderDepositInfo[](2);
        depositInfos[0] =
            ILoanRouter.LenderDepositInfo({depositType: ILoanRouter.DepositType.DepositTimelock, data: ""});
        depositInfos[1] =
            ILoanRouter.LenderDepositInfo({depositType: ILoanRouter.DepositType.DepositTimelock, data: ""});

        vm.prank(users.borrower);
        loanRouter.borrow(loanTerms, depositInfos);

        // Make one regular repayment
        warp(REPAYMENT_INTERVAL);

        (, uint64 maturity, uint64 repaymentDeadline, uint256 balance) = loanRouter.loanState(loanTermsHash);

        (uint256 principalPayment, uint256 interestPayment,,,) =
            interestRateModel.repayment(loanTerms, balance, repaymentDeadline, maturity, uint64(block.timestamp));

        uint256 paymentAmount = principalPayment + interestPayment; // No unscaling needed for 18 decimals

        // Fund borrower with USDai for repayment
        deal(USDAI, users.borrower, paymentAmount * 10);

        vm.startPrank(users.borrower);
        IERC20(USDAI).approve(address(loanRouter), type(uint256).max);
        loanRouter.repay(loanTerms, paymentAmount);
        vm.stopPrank();

        // Make second repayment
        warp(REPAYMENT_INTERVAL);

        (, maturity, repaymentDeadline, balance) = loanRouter.loanState(loanTermsHash);

        (principalPayment, interestPayment,,,) =
            interestRateModel.repayment(loanTerms, balance, repaymentDeadline, maturity, uint64(block.timestamp));

        paymentAmount = principalPayment + interestPayment;

        // Fund borrower with more USDai
        deal(USDAI, users.borrower, paymentAmount * 10);

        vm.prank(users.borrower);
        loanRouter.repay(loanTerms, paymentAmount);

        // Make final full repayment
        warp(1);
        (,,, balance) = loanRouter.loanState(loanTermsHash);

        if (balance > 0) {
            uint256 finalPayment = totalPrincipal * 2;

            // Fund borrower with USDai for final payment
            deal(USDAI, users.borrower, finalPayment);

            vm.prank(users.borrower);
            loanRouter.repay(loanTerms, finalPayment);
        }

        // Verify hook executed successfully and loan was deleted
        // If hook reverted (silently caught by try-catch), balances would be non-zero
        (uint256 claimable2, uint256 pending2, uint256 accrued2) = stakedUsdai.loanRouterBalances();

        // Pending and accrued should be 0 after full repayment, confirming:
        // 1. Hook didn't revert due to dust accumulation causing overflow
        // 2. Loan was deleted from storage (isFullRepayment == true path)
        // 3. No excess from dust accumulation
        assertEq(pending2, 0, "Pending balance should be 0 (confirms hook didn't revert)");
        assertEq(accrued2, 0, "Accrued balance should be 0 (confirms loan was deleted)");

        // Claimable balance should have received principal + interest
        assertGt(claimable2, 0, "Should have claimable balance from repayments");
    }

    /*------------------------------------------------------------------------*/
    /* Tests: Attempt to force underflow scenario */
    /*------------------------------------------------------------------------*/

    function test__LoanRouterPositionManager_ForceUnderflowScenario() public {
        // This test attempts to create conditions where principalAndPrepayment > loan.pendingBalance
        // during a PARTIAL repayment (not final repayment), which would cause underflow

        // Strategy: Create a very small loan, do many repayments to accumulate dust
        // Then check if dust causes principalAndPrepayment to exceed pendingBalance

        uint256 stakedUsdaiPrincipal = 3; // Extremely small
        uint256 mockLenderPrincipal = 2999999999999999999997; // Almost everything
        uint256 totalPrincipal = stakedUsdaiPrincipal + mockLenderPrincipal;

        // Create mock lender for USDai
        MockLender mockLender = new MockLender(address(loanRouter), USDAI, mockLenderPrincipal);
        deal(USDAI, address(mockLender), mockLenderPrincipal * 2);

        // Create loan terms
        ILoanRouter.TrancheSpec[] memory trancheSpecs = new ILoanRouter.TrancheSpec[](2);
        trancheSpecs[0] =
            ILoanRouter.TrancheSpec({lender: address(stakedUsdai), amount: stakedUsdaiPrincipal, rate: RATE_10_PCT});
        trancheSpecs[1] =
            ILoanRouter.TrancheSpec({lender: address(mockLender), amount: mockLenderPrincipal, rate: RATE_10_PCT});

        ILoanRouter.LoanTerms memory loanTerms = ILoanRouter.LoanTerms({
            expiration: uint64(block.timestamp + 7 days),
            borrower: users.borrower,
            currencyToken: USDAI,
            collateralToken: address(bundleCollateralWrapper),
            collateralTokenId: wrappedTokenId,
            duration: LOAN_DURATION,
            repaymentInterval: REPAYMENT_INTERVAL,
            interestRateModel: address(interestRateModel),
            gracePeriodRate: GRACE_PERIOD_RATE,
            gracePeriodDuration: uint256(GRACE_PERIOD_DURATION),
            feeSpec: ILoanRouter.FeeSpec({originationFee: totalPrincipal / 100, exitFee: 0}),
            trancheSpecs: trancheSpecs,
            collateralWrapperContext: encodedBundle,
            options: ""
        });

        bytes32 loanTermsHash = loanRouter.loanTermsHash(loanTerms);

        // Fund and approve
        deal(USDAI, users.borrower, totalPrincipal);
        vm.prank(users.borrower);
        IERC20(USDAI).approve(address(loanRouter), type(uint256).max);

        // Deposit funds
        vm.prank(users.strategyAdmin);
        stakedUsdai.depositLoanTimelock(loanTermsHash, stakedUsdaiPrincipal, uint64(block.timestamp + 7 days));

        vm.startPrank(address(mockLender));
        IERC20(USDAI).approve(address(depositTimelock), type(uint256).max);
        depositTimelock.deposit(
            address(loanRouter), loanTermsHash, USDAI, mockLenderPrincipal, uint64(block.timestamp + 7 days)
        );
        vm.stopPrank();

        // Borrow
        ILoanRouter.LenderDepositInfo[] memory depositInfos = new ILoanRouter.LenderDepositInfo[](2);
        depositInfos[0] =
            ILoanRouter.LenderDepositInfo({depositType: ILoanRouter.DepositType.DepositTimelock, data: ""});
        depositInfos[1] =
            ILoanRouter.LenderDepositInfo({depositType: ILoanRouter.DepositType.DepositTimelock, data: ""});

        vm.prank(users.borrower);
        loanRouter.borrow(loanTerms, depositInfos);

        console.log("\n=== Making Many Repayments to Accumulate Dust ===");

        // Make many small repayments
        for (uint256 i = 0; i < 20; i++) {
            warp(REPAYMENT_INTERVAL);

            (, uint64 maturity, uint64 repaymentDeadline, uint256 balance) = loanRouter.loanState(loanTermsHash);

            (uint256 principalPayment, uint256 interestPayment,,,) =
                interestRateModel.repayment(loanTerms, balance, repaymentDeadline, maturity, uint64(block.timestamp));

            uint256 paymentAmount = principalPayment + interestPayment;

            deal(USDAI, users.borrower, paymentAmount * 2);

            vm.prank(users.borrower);
            loanRouter.repay(loanTerms, paymentAmount);
        }

        // Final repayment
        warp(1);
        (,,, uint256 balance) = loanRouter.loanState(loanTermsHash);

        if (balance > 0) {
            uint256 finalPayment = totalPrincipal * 2;
            deal(USDAI, users.borrower, finalPayment);

            vm.prank(users.borrower);
            loanRouter.repay(loanTerms, finalPayment);
        }

        // Verify hook executed successfully and loan was deleted
        // If hook reverted (silently caught by try-catch), balances would be non-zero
        (, uint256 pending3, uint256 accrued3) = stakedUsdai.loanRouterBalances();

        // Pending and accrued should be 0 after full repayment, confirming:
        // 1. Hook didn't revert due to underflow (Math.min prevented it)
        // 2. Loan was deleted from storage
        assertEq(pending3, 0, "Pending balance should be 0 (confirms hook didn't revert)");
        assertEq(accrued3, 0, "Accrued balance should be 0 (confirms loan was deleted)");
    }
}
