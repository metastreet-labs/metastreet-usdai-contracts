// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import {BaseTest} from "../Base.t.sol";

contract StakedUSDaiHarvestBaseYieldTest is BaseTest {
    function setUp() public override {
        super.setUp();

        // User approves USDai to spend their USD
        vm.startPrank(users.normalUser1);
        usd.approve(address(usdai), 1_000_000 ether);

        // User deposits USD into USDai
        uint256 initialBalance = usdai.deposit(address(usd), 1_000_000 ether, 0, users.normalUser1);

        // User deposits USDai into StakedUSDai
        usdai.approve(address(stakedUsdai), initialBalance);
        stakedUsdai.deposit(initialBalance, users.normalUser1);

        vm.stopPrank();

        WRAPPED_M_TOKEN.currentIndex();

        vm.warp(block.timestamp + 1 days);

        updateMTokenIndex();
    }

    function test__StakedUSDaiHarvestBaseYield() public {
        vm.startPrank(users.manager);
        uint256 initialUsdaiBalance = usdai.balanceOf(address(stakedUsdai));
        uint256 claimableBaseYield = stakedUsdai.claimableBaseYield();

        assertGt(claimableBaseYield, 0, "Claimable base yield should be greater than 0");

        uint256 adminBalanceBefore = usdai.balanceOf(address(users.admin));

        uint256 navBefore = stakedUsdai.nav();

        WRAPPED_M_TOKEN.claimFor(address(stakedUsdai));
        WRAPPED_M_TOKEN.claimFor(address(usdai));

        (uint256 depositAmount, uint256 adminFee) = stakedUsdai.depositBaseYield(claimableBaseYield);

        assertGt(adminFee, 0, "Admin fee should be greater than 0");
        assertEq(stakedUsdai.claimableBaseYield(), 0, "Claimable base yield should be 0");

        assertEq(
            usdai.balanceOf(address(stakedUsdai)),
            initialUsdaiBalance + depositAmount,
            "USDai balance should be equal to initial balance plus claimable base yield"
        );

        assertEq(
            usdai.balanceOf(address(users.admin)),
            adminBalanceBefore + adminFee,
            "Admin balance should be equal to initial balance plus admin fee"
        );

        assertEq(navBefore, stakedUsdai.nav(), "Nav should be equal to nav after");

        vm.stopPrank();
    }
}
