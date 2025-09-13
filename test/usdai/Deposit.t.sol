// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import {BaseTest} from "../Base.t.sol";
import {IUSDai} from "src/interfaces/IUSDai.sol";
import {USDai} from "src/USDai.sol";

contract USDaiDepositTest is BaseTest {
    function testFuzz__USDaiDeposit(
        uint256 amount
    ) public {
        vm.assume(amount > 0);
        vm.assume(amount <= 10_000_000 ether);

        uint256 usdBalance = usd.balanceOf(users.normalUser1);

        // User approves USDai to spend their USD
        vm.startPrank(users.normalUser1);
        usd.approve(address(usdai), amount);

        // User deposits 1000 USD into USDai
        uint256 mAmount = usdai.deposit(address(usd), amount, 0, users.normalUser1);

        // Assert user's USDai balance increased by mAmount
        assertEq(usdai.balanceOf(users.normalUser1), mAmount);

        // Assert user's USD balance decreased by amount
        assertEq(usd.balanceOf(users.normalUser1), usdBalance - amount);

        vm.stopPrank();
    }

    function testFuzz__USDaiDepositExceedsSupplyCap(
        uint256 amount
    ) public {
        vm.assume(amount > 1000 ether);
        vm.assume(amount <= 10_000_000 ether);

        /* Set supply cap */
        vm.startPrank(users.deployer);
        usdai.setSupplyCap(1000 ether);
        vm.stopPrank();

        // User approves USDai to spend their USD
        vm.startPrank(users.normalUser1);
        usd.approve(address(usdai), amount);

        /* User deposits 1000 USD into USDai */
        vm.expectRevert(IUSDai.SupplyCapExceeded.selector);
        usdai.deposit(address(usd), amount, 0, users.normalUser1);

        vm.stopPrank();
    }
}
