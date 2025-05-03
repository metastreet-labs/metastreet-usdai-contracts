// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "../Base.t.sol";

import {IPoolPositionManager} from "src/interfaces/IPoolPositionManager.sol";

contract StakedUSDaiPoolDepositTest is BaseTest {
    function setUp() public override {
        super.setUp();

        // User approves USDai to spend their USD
        vm.startPrank(users.normalUser1);
        usd.approve(address(usdai), 100_050 * 1e6);

        // User deposits USD into USDai
        uint256 amount = usdai.deposit(address(usd), 100_050 * 1e6, 0, users.normalUser1);

        // User deposits USDai into StakedUSDai
        stakedUsdai.deposit(amount, users.normalUser1);

        usdai.balanceOf(address(stakedUsdai));

        vm.stopPrank();
    }

    function test__PoolDeposit() public {
        vm.startPrank(users.manager);

        // Get initial total assets
        uint256 totalAssetsBefore = stakedUsdai.totalAssets();

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

        // Get total assets after
        uint256 totalAssetsAfterPoolDeposit = stakedUsdai.totalAssets();

        // Total assets should be greater than 96% of the initial total assets
        assertGt(totalAssetsAfterPoolDeposit, (totalAssetsBefore * 9.6e17) / 1e18);

        // Create loan for a principal of 20 WETH
        bytes memory loanReceipt = createLoan(metastreetPool1, address(users.normalUser1), 20 ether);

        // There should be one pool
        assertEq(IPoolPositionManager(stakedUsdai).pools().length, 1);

        // Validate pool ticks
        uint256[] memory ticks = IPoolPositionManager(stakedUsdai).poolTicks(address(metastreetPool1));
        assertEq(ticks.length, 1);
        assertEq(ticks[0], TICK);

        // Advance time to loan maturity
        vm.warp(block.timestamp + 30 days);

        // Repay loan
        repayLoan(metastreetPool1, address(users.normalUser1), loanReceipt);

        // Get total assets after
        uint256 totalAssetsAfterRepayment = stakedUsdai.totalAssets();

        // Total assets should be greater than before repayment
        assertGt(totalAssetsAfterRepayment, totalAssetsAfterPoolDeposit);

        vm.stopPrank();
    }
}
