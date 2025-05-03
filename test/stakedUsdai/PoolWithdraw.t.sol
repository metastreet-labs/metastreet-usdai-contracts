// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "../Base.t.sol";

import {IPoolPositionManager} from "src/interfaces/IPoolPositionManager.sol";

contract StakedUSDaiPoolWithdrawTest is BaseTest {
    uint256 initialShares;

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
        initialShares = IPoolPositionManager(stakedUsdai).poolDeposit(
            address(metastreetPool1), TICK, 100_000 * 1e18, 54 ether, 0, path
        );

        vm.stopPrank();
    }

    function test__PoolWithdraw() public {
        // Create loan for a principal of 10 WETH
        bytes memory loanReceipt1 = createLoan(metastreetPool1, address(users.normalUser1), 10 ether);

        // Create another loan for a principal of 10 WETH
        bytes memory loanReceipt2 = createLoan(metastreetPool1, address(users.normalUser2), 10 ether);

        // Advance time to loan maturity
        vm.warp(block.timestamp + 30 days);

        // Repay loan
        repayLoan(metastreetPool1, address(users.normalUser1), loanReceipt1);

        vm.startPrank(users.manager);

        // Redeem
        uint128 redemptionId =
            IPoolPositionManager(stakedUsdai).poolRedeem(address(metastreetPool1), TICK, initialShares);

        // Encode path for WETH -> usd -> USDT -> wrapped M
        bytes memory path = abi.encodePacked(
            address(WETH),
            uint24(500), // 0.05% fee
            address(USDT),
            uint24(100), // 0.01% fee
            address(usd),
            uint24(100), // 0.01% fee
            address(WRAPPED_M_TOKEN)
        );

        // Withdraw
        uint256 usdaiAmount =
            IPoolPositionManager(stakedUsdai).poolWithdraw(address(metastreetPool1), TICK, redemptionId, 0, path);

        // USDai amount should be greater than 0
        assertGt(usdaiAmount, 0);

        // Validate pool ticks
        uint256[] memory ticks = IPoolPositionManager(stakedUsdai).poolTicks(address(metastreetPool1));
        assertEq(ticks.length, 1);
        assertEq(ticks[0], TICK);

        vm.stopPrank();

        // Repay loan
        repayLoan(metastreetPool1, address(users.normalUser2), loanReceipt2);

        vm.startPrank(users.manager);

        // Withdraw
        IPoolPositionManager(stakedUsdai).poolWithdraw(address(metastreetPool1), TICK, redemptionId, 0, path);

        // Validate pool positions
        assertEq(IPoolPositionManager(stakedUsdai).poolTicks(address(metastreetPool1)).length, 0);
        assertEq(IPoolPositionManager(stakedUsdai).pools().length, 0);

        vm.stopPrank();
    }
}
