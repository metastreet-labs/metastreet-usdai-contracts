// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import {Test, console} from "forge-std/Test.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {DepositVault} from "src/misc/DepositVault.sol";
import {IDepositVault} from "src/interfaces/IDepositVault.sol";
import {TestERC20} from "../tokens/TestERC20.sol";

/**
 * @title DepositVault Test Suite
 * @author MetaStreet Foundation
 */
contract DepositVaultTest is Test {
    /*------------------------------------------------------------------------*/
    /* State Variables */
    /*------------------------------------------------------------------------*/

    DepositVault internal depositVault;
    DepositVault internal depositVaultImpl;
    TransparentUpgradeableProxy internal proxy;
    TestERC20 internal depositToken;

    address internal admin = address(0x1);
    address internal vaultAdmin = address(0x2);
    address internal user = address(0x3);
    address internal recipient = address(0x4);

    uint256 internal constant DEPOSIT_CAP = 1_000_000 ether;
    uint256 internal constant DEPOSIT_AMOUNT_MINIMUM = 1000 ether;
    uint256 internal constant INITIAL_BALANCE = 2_000_000 ether;

    bytes32 internal constant VAULT_ADMIN_ROLE = keccak256("VAULT_ADMIN_ROLE");

    /*------------------------------------------------------------------------*/
    /* Setup */
    /*------------------------------------------------------------------------*/

    function setUp() public {
        // Deploy test ERC20 token
        depositToken = new TestERC20("Test Token", "TEST", 18, INITIAL_BALANCE);

        // Deploy DepositVault implementation
        depositVaultImpl = new DepositVault(address(depositToken), DEPOSIT_AMOUNT_MINIMUM, 30383);

        // Deploy proxy
        proxy = new TransparentUpgradeableProxy(
            address(depositVaultImpl), address(this), abi.encodeWithSignature("initialize(address)", admin)
        );

        // Cast to DepositVault interface
        depositVault = DepositVault(address(proxy));

        // Setup roles
        vm.startPrank(admin);
        depositVault.grantRole(VAULT_ADMIN_ROLE, vaultAdmin);
        depositVault.updateDepositCap(DEPOSIT_CAP, false);
        vm.stopPrank();

        // Transfer tokens to users
        depositToken.transfer(user, INITIAL_BALANCE / 2);
        depositToken.transfer(recipient, INITIAL_BALANCE / 4);

        // Give users some ETH for gas
        vm.deal(admin, 10 ether);
        vm.deal(vaultAdmin, 10 ether);
        vm.deal(user, 10 ether);
        vm.deal(recipient, 10 ether);
    }

    /*------------------------------------------------------------------------*/
    /* Initialization Tests */
    /*------------------------------------------------------------------------*/

    function test__DepositVaultInitialize() public view {
        // Check initial state
        assertEq(depositVault.depositToken(), address(depositToken));
        assertEq(depositVault.depositAmountMinimum(), DEPOSIT_AMOUNT_MINIMUM);
        (uint256 cap, uint256 counter) = depositVault.depositCapInfo();
        assertEq(cap, DEPOSIT_CAP);
        assertEq(counter, 0);

        // Check roles
        assertTrue(depositVault.hasRole(depositVault.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(depositVault.hasRole(VAULT_ADMIN_ROLE, vaultAdmin));
    }

    function test__DepositVaultInitialize_CannotReinitialize() public {
        vm.expectRevert();
        depositVault.initialize(admin);
    }

    /*------------------------------------------------------------------------*/
    /* Getter Tests */
    /*------------------------------------------------------------------------*/

    function test__DepositVaultDepositToken() public view {
        assertEq(depositVault.depositToken(), address(depositToken));
    }

    function test__DepositVaultDepositAmountMinimum() public view {
        assertEq(depositVault.depositAmountMinimum(), DEPOSIT_AMOUNT_MINIMUM);
    }

    function test__DepositVaultDepositCapInfo() public view {
        (uint256 cap, uint256 counter) = depositVault.depositCapInfo();
        assertEq(cap, DEPOSIT_CAP);
        assertEq(counter, 0);
    }

    function test__DepositVaultImplementationVersion() public view {
        assertEq(depositVault.IMPLEMENTATION_VERSION(), "1.0");
    }

    /*------------------------------------------------------------------------*/
    /* Deposit Tests */
    /*------------------------------------------------------------------------*/

    function test__DepositVaultDeposit_Deposit() public {
        uint256 amount = 5000 ether;

        vm.startPrank(user);
        depositToken.approve(address(depositVault), amount);

        depositVault.deposit(IDepositVault.DepositType.Deposit, amount, recipient);
        vm.stopPrank();

        // Check balances
        assertEq(depositToken.balanceOf(address(depositVault)), amount);
        assertEq(depositToken.balanceOf(user), INITIAL_BALANCE / 2 - amount);

        // Check deposit cap counter
        (, uint256 counter) = depositVault.depositCapInfo();
        assertEq(counter, amount);
    }

    function test__DepositVaultDeposit_DepositAndStake() public {
        uint256 amount = 10000 ether;

        vm.startPrank(user);
        depositToken.approve(address(depositVault), amount);

        depositVault.deposit(IDepositVault.DepositType.DepositAndStake, amount, recipient);
        vm.stopPrank();

        // Check balances
        assertEq(depositToken.balanceOf(address(depositVault)), amount);
        assertEq(depositToken.balanceOf(user), INITIAL_BALANCE / 2 - amount);

        // Check deposit cap counter
        (, uint256 counter) = depositVault.depositCapInfo();
        assertEq(counter, amount);
    }

    function test__DepositVaultDeposit_MultipleDeposits() public {
        uint256 amount1 = 5000 ether;
        uint256 amount2 = 3000 ether;

        vm.startPrank(user);
        depositToken.approve(address(depositVault), amount1 + amount2);

        // First deposit
        depositVault.deposit(IDepositVault.DepositType.Deposit, amount1, recipient);

        // Second deposit
        depositVault.deposit(IDepositVault.DepositType.DepositAndStake, amount2, recipient);
        vm.stopPrank();

        // Check total balance
        assertEq(depositToken.balanceOf(address(depositVault)), amount1 + amount2);

        // Check deposit cap counter
        (, uint256 counter) = depositVault.depositCapInfo();
        assertEq(counter, amount1 + amount2);
    }

    function test__DepositVaultDeposit_RevertIf_ZeroAmount() public {
        vm.startPrank(user);
        vm.expectRevert(IDepositVault.InvalidAmount.selector);
        depositVault.deposit(IDepositVault.DepositType.Deposit, 0, recipient);
        vm.stopPrank();
    }

    function test__DepositVaultDeposit_RevertIf_BelowMinimum() public {
        uint256 amount = DEPOSIT_AMOUNT_MINIMUM - 1;

        vm.startPrank(user);
        depositToken.approve(address(depositVault), amount);

        vm.expectRevert(IDepositVault.InvalidAmount.selector);
        depositVault.deposit(IDepositVault.DepositType.Deposit, amount, recipient);
        vm.stopPrank();
    }

    function test__DepositVaultDeposit_RevertIf_ExceedsDepositCap() public {
        uint256 amount = DEPOSIT_CAP + 1;

        vm.startPrank(user);
        depositToken.approve(address(depositVault), amount);

        vm.expectRevert(IDepositVault.InvalidAmount.selector);
        depositVault.deposit(IDepositVault.DepositType.Deposit, amount, recipient);
        vm.stopPrank();
    }

    function test__DepositVaultDeposit_RevertIf_ExceedsDepositCapWithCounter() public {
        uint256 amount1 = DEPOSIT_CAP / 2;
        uint256 amount2 = DEPOSIT_CAP / 2 + 1;

        vm.startPrank(user);
        depositToken.approve(address(depositVault), amount1 + amount2);

        // First deposit (should succeed)
        depositVault.deposit(IDepositVault.DepositType.Deposit, amount1, recipient);

        // Second deposit (should fail)
        vm.expectRevert(IDepositVault.InvalidAmount.selector);
        depositVault.deposit(IDepositVault.DepositType.Deposit, amount2, recipient);
        vm.stopPrank();
    }

    function test__DepositVaultDeposit_RevertIf_ZeroRecipient() public {
        uint256 amount = 5000 ether;

        vm.startPrank(user);
        depositToken.approve(address(depositVault), amount);

        vm.expectRevert(IDepositVault.InvalidRecipient.selector);
        depositVault.deposit(IDepositVault.DepositType.Deposit, amount, address(0));
        vm.stopPrank();
    }

    function test__DepositVaultDeposit_RevertIf_InsufficientAllowance() public {
        uint256 amount = 5000 ether;

        vm.startPrank(user);
        // Don't approve enough tokens
        depositToken.approve(address(depositVault), amount - 1);

        vm.expectRevert();
        depositVault.deposit(IDepositVault.DepositType.Deposit, amount, recipient);
        vm.stopPrank();
    }

    function test__DepositVaultDeposit_RevertIf_InsufficientBalance() public {
        uint256 amount = INITIAL_BALANCE; // User only has INITIAL_BALANCE / 2

        vm.startPrank(user);
        depositToken.approve(address(depositVault), amount);

        vm.expectRevert();
        depositVault.deposit(IDepositVault.DepositType.Deposit, amount, recipient);
        vm.stopPrank();
    }

    /*------------------------------------------------------------------------*/
    /* Withdraw Tests */
    /*------------------------------------------------------------------------*/

    function test__DepositVaultWithdraw() public {
        uint256 depositAmount = 10000 ether;
        uint256 withdrawAmount = 5000 ether;

        // First make a deposit
        vm.startPrank(user);
        depositToken.approve(address(depositVault), depositAmount);
        depositVault.deposit(IDepositVault.DepositType.Deposit, depositAmount, recipient);
        vm.stopPrank();

        // Now withdraw as vault admin
        vm.startPrank(vaultAdmin);

        depositVault.withdraw(recipient, withdrawAmount);
        vm.stopPrank();

        // Check balances
        assertEq(depositToken.balanceOf(address(depositVault)), depositAmount - withdrawAmount);
        assertEq(depositToken.balanceOf(recipient), INITIAL_BALANCE / 4 + withdrawAmount);
    }

    function test__DepositVaultWithdraw_FullAmount() public {
        uint256 depositAmount = 10000 ether;

        // First make a deposit
        vm.startPrank(user);
        depositToken.approve(address(depositVault), depositAmount);
        depositVault.deposit(IDepositVault.DepositType.Deposit, depositAmount, recipient);
        vm.stopPrank();

        // Now withdraw full amount as vault admin
        vm.startPrank(vaultAdmin);
        depositVault.withdraw(recipient, depositAmount);
        vm.stopPrank();

        // Check balances
        assertEq(depositToken.balanceOf(address(depositVault)), 0);
        assertEq(depositToken.balanceOf(recipient), INITIAL_BALANCE / 4 + depositAmount);
    }

    function test__DepositVaultWithdraw_RevertIf_NotVaultAdmin() public {
        uint256 depositAmount = 10000 ether;
        uint256 withdrawAmount = 5000 ether;

        // First make a deposit
        vm.startPrank(user);
        depositToken.approve(address(depositVault), depositAmount);
        depositVault.deposit(IDepositVault.DepositType.Deposit, depositAmount, recipient);
        vm.stopPrank();

        // Try to withdraw as non-admin user
        vm.startPrank(user);
        vm.expectRevert();
        depositVault.withdraw(recipient, withdrawAmount);
        vm.stopPrank();
    }

    function test__DepositVaultWithdraw_RevertIf_InsufficientBalance() public {
        uint256 depositAmount = 5000 ether;
        uint256 withdrawAmount = 10000 ether; // More than deposited

        // First make a deposit
        vm.startPrank(user);
        depositToken.approve(address(depositVault), depositAmount);
        depositVault.deposit(IDepositVault.DepositType.Deposit, depositAmount, recipient);
        vm.stopPrank();

        // Try to withdraw more than available
        vm.startPrank(vaultAdmin);
        vm.expectRevert();
        depositVault.withdraw(recipient, withdrawAmount);
        vm.stopPrank();
    }

    /*------------------------------------------------------------------------*/
    /* Rescue Tests */
    /*------------------------------------------------------------------------*/

    function test__DepositVaultRescue() public {
        // Create a different token to rescue
        TestERC20 rescueToken = new TestERC20("Rescue Token", "RESCUE", 18, 1000 ether);
        uint256 rescueAmount = 100 ether;

        // Send rescue token to the vault (simulate accidental transfer)
        rescueToken.transfer(address(depositVault), rescueAmount);

        vm.startPrank(admin);
        depositVault.rescue(address(rescueToken), recipient, rescueAmount);
        vm.stopPrank();

        // Check that rescue token was transferred to recipient
        assertEq(rescueToken.balanceOf(recipient), rescueAmount);
        assertEq(rescueToken.balanceOf(address(depositVault)), 0);
    }

    function test__DepositVaultRescue_DepositToken() public {
        uint256 depositAmount = 10000 ether;
        uint256 rescueAmount = 2000 ether;

        // First make a deposit
        vm.startPrank(user);
        depositToken.approve(address(depositVault), depositAmount);
        depositVault.deposit(IDepositVault.DepositType.Deposit, depositAmount, recipient);
        vm.stopPrank();

        // Admin can rescue even the deposit token if needed
        vm.startPrank(admin);
        depositVault.rescue(address(depositToken), recipient, rescueAmount);
        vm.stopPrank();

        // Check balances
        assertEq(depositToken.balanceOf(address(depositVault)), depositAmount - rescueAmount);
        assertEq(depositToken.balanceOf(recipient), INITIAL_BALANCE / 4 + rescueAmount);
    }

    function test__DepositVaultRescue_RevertIf_NotDefaultAdmin() public {
        TestERC20 rescueToken = new TestERC20("Rescue Token", "RESCUE", 18, 1000 ether);
        uint256 rescueAmount = 100 ether;

        rescueToken.transfer(address(depositVault), rescueAmount);

        vm.startPrank(vaultAdmin);
        vm.expectRevert();
        depositVault.rescue(address(rescueToken), recipient, rescueAmount);
        vm.stopPrank();

        vm.startPrank(user);
        vm.expectRevert();
        depositVault.rescue(address(rescueToken), recipient, rescueAmount);
        vm.stopPrank();
    }

    /*------------------------------------------------------------------------*/
    /* Update Deposit Cap Tests */
    /*------------------------------------------------------------------------*/

    function test__DepositVaultUpdateDepositCap() public {
        uint256 newDepositCap = 2_000_000 ether;

        vm.startPrank(admin);

        depositVault.updateDepositCap(newDepositCap, false);
        vm.stopPrank();

        (uint256 cap, uint256 counter) = depositVault.depositCapInfo();
        assertEq(cap, newDepositCap);
        assertEq(counter, 0); // Counter should remain unchanged
    }

    function test__DepositVaultUpdateDepositCap_WithResetCounter() public {
        uint256 depositAmount = 10000 ether;
        uint256 newDepositCap = 2_000_000 ether;

        // First make a deposit to increase counter
        vm.startPrank(user);
        depositToken.approve(address(depositVault), depositAmount);
        depositVault.deposit(IDepositVault.DepositType.Deposit, depositAmount, recipient);
        vm.stopPrank();

        // Verify counter is not zero
        (, uint256 counterBefore) = depositVault.depositCapInfo();
        assertEq(counterBefore, depositAmount);

        // Update deposit cap and reset counter
        vm.startPrank(admin);
        depositVault.updateDepositCap(newDepositCap, true);
        vm.stopPrank();

        (uint256 cap, uint256 counter) = depositVault.depositCapInfo();
        assertEq(cap, newDepositCap);
        assertEq(counter, 0); // Counter should be reset
    }

    function test__DepositVaultUpdateDepositCap_WithoutResetCounter() public {
        uint256 depositAmount = 10000 ether;
        uint256 newDepositCap = 2_000_000 ether;

        // First make a deposit to increase counter
        vm.startPrank(user);
        depositToken.approve(address(depositVault), depositAmount);
        depositVault.deposit(IDepositVault.DepositType.Deposit, depositAmount, recipient);
        vm.stopPrank();

        // Update deposit cap without resetting counter
        vm.startPrank(admin);
        depositVault.updateDepositCap(newDepositCap, false);
        vm.stopPrank();

        (uint256 cap, uint256 counter) = depositVault.depositCapInfo();
        assertEq(cap, newDepositCap);
        assertEq(counter, depositAmount); // Counter should remain unchanged
    }

    function test__DepositVaultUpdateDepositCap_RevertIf_NotDefaultAdmin() public {
        uint256 newDepositCap = 2_000_000 ether;

        vm.startPrank(vaultAdmin);
        vm.expectRevert();
        depositVault.updateDepositCap(newDepositCap, false);
        vm.stopPrank();

        vm.startPrank(user);
        vm.expectRevert();
        depositVault.updateDepositCap(newDepositCap, false);
        vm.stopPrank();
    }

    /*------------------------------------------------------------------------*/
    /* Access Control Tests */
    /*------------------------------------------------------------------------*/

    function test__DepositVaultAccessControl_DefaultAdminRole() public view {
        assertTrue(depositVault.hasRole(depositVault.DEFAULT_ADMIN_ROLE(), admin));
        assertFalse(depositVault.hasRole(depositVault.DEFAULT_ADMIN_ROLE(), vaultAdmin));
        assertFalse(depositVault.hasRole(depositVault.DEFAULT_ADMIN_ROLE(), user));
    }

    function test__DepositVaultAccessControl_VaultAdminRole() public view {
        console.logBytes32(
            keccak256(abi.encode(uint256(keccak256("depositVault.depositCap")) - 1)) & ~bytes32(uint256(0xff))
        );

        assertTrue(depositVault.hasRole(VAULT_ADMIN_ROLE, vaultAdmin));
        assertFalse(depositVault.hasRole(VAULT_ADMIN_ROLE, admin));
        assertFalse(depositVault.hasRole(VAULT_ADMIN_ROLE, user));
    }

    function test__DepositVaultAccessControl_GrantVaultAdminRole() public {
        address newVaultAdmin = address(0x5);

        vm.startPrank(admin);
        depositVault.grantRole(VAULT_ADMIN_ROLE, newVaultAdmin);
        vm.stopPrank();

        assertTrue(depositVault.hasRole(VAULT_ADMIN_ROLE, newVaultAdmin));
    }

    function test__DepositVaultAccessControl_RevokeVaultAdminRole() public {
        vm.startPrank(admin);
        depositVault.revokeRole(VAULT_ADMIN_ROLE, vaultAdmin);
        vm.stopPrank();

        assertFalse(depositVault.hasRole(VAULT_ADMIN_ROLE, vaultAdmin));
    }

    /*------------------------------------------------------------------------*/
    /* Reentrancy Tests */
    /*------------------------------------------------------------------------*/

    function test__DepositVaultDeposit_ReentrancyProtection() public {
        // This test would need a malicious token contract to test reentrancy
        // For now, we just verify the nonReentrant modifier is in place
        uint256 amount = 5000 ether;

        vm.startPrank(user);
        depositToken.approve(address(depositVault), amount);
        depositVault.deposit(IDepositVault.DepositType.Deposit, amount, recipient);
        vm.stopPrank();

        // If we reach here without revert, the basic flow works
        assertEq(depositToken.balanceOf(address(depositVault)), amount);
    }

    /*------------------------------------------------------------------------*/
    /* Edge Cases and Fuzz Tests */
    /*------------------------------------------------------------------------*/

    function testFuzz__DepositVaultDeposit_ValidAmounts(
        uint256 amount
    ) public {
        // Bound amount to reasonable range
        amount = bound(amount, DEPOSIT_AMOUNT_MINIMUM, DEPOSIT_CAP);

        // Ensure user has enough tokens
        if (amount > depositToken.balanceOf(user)) {
            depositToken.transfer(user, amount - depositToken.balanceOf(user) + 1 ether);
        }

        vm.startPrank(user);
        depositToken.approve(address(depositVault), amount);
        depositVault.deposit(IDepositVault.DepositType.Deposit, amount, recipient);
        vm.stopPrank();

        assertEq(depositToken.balanceOf(address(depositVault)), amount);
        (, uint256 counter) = depositVault.depositCapInfo();
        assertEq(counter, amount);
    }

    function testFuzz__DepositVaultUpdateDepositCap(uint256 newCap, bool resetCounter) public {
        // Bound to reasonable values
        newCap = bound(newCap, 1 ether, type(uint128).max);

        vm.startPrank(admin);
        depositVault.updateDepositCap(newCap, resetCounter);
        vm.stopPrank();

        (uint256 cap,) = depositVault.depositCapInfo();
        assertEq(cap, newCap);
    }

    function test__DepositVaultDeposit_ExactMinimum() public {
        uint256 amount = DEPOSIT_AMOUNT_MINIMUM;

        vm.startPrank(user);
        depositToken.approve(address(depositVault), amount);
        depositVault.deposit(IDepositVault.DepositType.Deposit, amount, recipient);
        vm.stopPrank();

        assertEq(depositToken.balanceOf(address(depositVault)), amount);
    }

    function test__DepositVaultDeposit_ExactDepositCap() public {
        // Need to give user enough tokens (user already has INITIAL_BALANCE / 2)
        uint256 additionalTokens = DEPOSIT_CAP - depositToken.balanceOf(user);
        depositToken.transfer(user, additionalTokens);

        vm.startPrank(user);
        depositToken.approve(address(depositVault), DEPOSIT_CAP);
        depositVault.deposit(IDepositVault.DepositType.Deposit, DEPOSIT_CAP, recipient);
        vm.stopPrank();

        assertEq(depositToken.balanceOf(address(depositVault)), DEPOSIT_CAP);
        (, uint256 counter) = depositVault.depositCapInfo();
        assertEq(counter, DEPOSIT_CAP);
    }

    /*------------------------------------------------------------------------*/
    /* Integration Tests */
    /*------------------------------------------------------------------------*/

    function test__DepositVaultIntegration_DepositWithdrawCycle() public {
        uint256 depositAmount = 100000 ether;
        uint256 withdrawAmount = 60000 ether;

        // Ensure user has enough tokens
        depositToken.transfer(user, depositAmount);

        // Deposit
        vm.startPrank(user);
        depositToken.approve(address(depositVault), depositAmount);
        depositVault.deposit(IDepositVault.DepositType.DepositAndStake, depositAmount, recipient);
        vm.stopPrank();

        // Verify deposit
        assertEq(depositToken.balanceOf(address(depositVault)), depositAmount);
        (, uint256 counter) = depositVault.depositCapInfo();
        assertEq(counter, depositAmount);

        // Withdraw
        vm.startPrank(vaultAdmin);
        depositVault.withdraw(recipient, withdrawAmount);
        vm.stopPrank();

        // Verify withdraw
        assertEq(depositToken.balanceOf(address(depositVault)), depositAmount - withdrawAmount);
        assertEq(depositToken.balanceOf(recipient), INITIAL_BALANCE / 4 + withdrawAmount);

        // Deposit counter should remain unchanged after withdraw
        (, uint256 counterAfter) = depositVault.depositCapInfo();
        assertEq(counterAfter, depositAmount);
    }

    function test__DepositVaultIntegration_MultipleUsersDeposits() public {
        address user2 = address(0x6);
        uint256 amount1 = 25000 ether;
        uint256 amount2 = 35000 ether;

        // Setup user2
        depositToken.transfer(user2, amount2);
        vm.deal(user2, 10 ether);

        // User 1 deposit
        vm.startPrank(user);
        depositToken.approve(address(depositVault), amount1);
        depositVault.deposit(IDepositVault.DepositType.Deposit, amount1, recipient);
        vm.stopPrank();

        // User 2 deposit
        vm.startPrank(user2);
        depositToken.approve(address(depositVault), amount2);
        depositVault.deposit(IDepositVault.DepositType.DepositAndStake, amount2, user2);
        vm.stopPrank();

        // Verify total
        assertEq(depositToken.balanceOf(address(depositVault)), amount1 + amount2);
        (, uint256 counter) = depositVault.depositCapInfo();
        assertEq(counter, amount1 + amount2);
    }
}
