// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "../Base.t.sol";

import {IPoolPositionManager} from "src/interfaces/IPoolPositionManager.sol";

contract StakedUSDaiPoolRedeemTest is BaseTest {
    function setUp() public override {
        super.setUp();

        // User approves USDai to spend their USD
        vm.startPrank(users.normalUser1);
        usd.approve(address(usdai), 100_050 * 1e6);

        // User deposits USD into USDai
        uint256 amount = usdai.deposit(address(usd), 100_050 * 1e6, 0, users.normalUser1);

        // User deposits USDai into StakedUSDai
        stakedUsdai.deposit(amount, users.normalUser1);

        vm.stopPrank();

        vm.startPrank(users.manager);

        // Encode path for wrapped M -> usd -> USDT -> WETH
        bytes memory path = abi.encodePacked(
            address(WRAPPED_M_TOKEN),
            uint24(100), // 0.01% fee
            address(usd),
            uint24(100), // 0.01% fee
            address(USDT),
            uint24(500), // 0.05% fee
            address(WETH)
        );

        // Deposit
        IPoolPositionManager(stakedUsdai).poolDeposit(address(metastreetPool1), TICK, 100_000 * 1e18, 54 ether, 0, path);

        vm.stopPrank();
    }

    function test__PoolRedeem() public {
        // Get redemption share price before loan
        uint256 redemptionSharePriceBeforeLoan = stakedUsdai.redemptionSharePrice();

        // Create loan for a principal of 20 WETH
        bytes memory loanReceipt = createLoan(metastreetPool1, address(users.normalUser1), 20 ether);

        vm.startPrank(users.manager);

        // Redeem
        uint128 redemptionId = IPoolPositionManager(stakedUsdai).poolRedeem(address(metastreetPool1), TICK, 20 ether);

        // Redemption ID should be 0
        assertEq(redemptionId, 0);

        // There should still be one pool
        assertEq(IPoolPositionManager(stakedUsdai).pools().length, 1);

        // Validate pool ticks
        uint256[] memory ticks = IPoolPositionManager(stakedUsdai).poolTicks(address(metastreetPool1));
        assertEq(ticks.length, 1);
        assertEq(ticks[0], TICK);

        // Advance time to loan maturity
        vm.warp(block.timestamp + 30 days);

        vm.stopPrank();

        // Repay loan
        repayLoan(metastreetPool1, address(users.normalUser1), loanReceipt);

        vm.startPrank(users.manager);

        // Redeem
        (uint256 shares,) = metastreetPool1.deposits(address(stakedUsdai), TICK);
        IPoolPositionManager(stakedUsdai).poolRedeem(address(metastreetPool1), TICK, shares);

        vm.stopPrank();

        // Get redemption share price after loan
        uint256 redemptionSharePriceAfterLoan = stakedUsdai.redemptionSharePrice();

        // Redemption share price should be greater after loan repayment
        assertGt(redemptionSharePriceAfterLoan, redemptionSharePriceBeforeLoan);
    }
}
