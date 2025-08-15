// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "./Base.t.sol";
import {USDaiQueuedDepositor} from "src/queuedDepositor/USDaiQueuedDepositor.sol";
import {ReceiptToken} from "src/queuedDepositor/ReceiptToken.sol";
import {ReceiptToken} from "src/queuedDepositor/ReceiptToken.sol";
import {IUSDaiQueuedDepositor} from "src/interfaces/IUSDaiQueuedDepositor.sol";

/**
 * @title Enhanced Receipt Token Implementation for Testing
 */
contract EnhancedReceiptToken is ReceiptToken {
    /**
     * @notice New function to test upgrade success
     */
    function getVersion() external pure returns (string memory) {
        return "v2.0.0";
    }

    /**
     * @notice Enhanced mint function with event
     */
    event EnhancedMint(address indexed to, uint256 amount, string version);

    function enhancedMint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
        emit EnhancedMint(to, amount, "v2.0.0");
    }
}

/**
 * @title Receipt Token Upgrade Test
 */
contract ReceiptTokenUpgradeTest is OmnichainBaseTest {
    address internal anotherUser = address(0x3);

    function setUp() public override {
        super.setUp();

        // Mint some tokens to users for testing
        vm.startPrank(user);
        usdtHomeToken.approve(address(usdaiQueuedDepositor), type(uint256).max);
        usdaiQueuedDepositor.deposit(
            IUSDaiQueuedDepositor.QueueType.Deposit, address(usdtHomeToken), 5_000_000 * 1e18, user, 0
        );

        usdaiQueuedDepositor.deposit(
            IUSDaiQueuedDepositor.QueueType.DepositAndStake, address(usdtHomeToken), 3_000_000 * 1e18, user, 0
        );
        vm.stopPrank();

        // Mint some tokens to another user
        usdtHomeToken.mint(anotherUser, initialBalance);
        vm.startPrank(anotherUser);
        usdtHomeToken.approve(address(usdaiQueuedDepositor), type(uint256).max);
        usdaiQueuedDepositor.deposit(
            IUSDaiQueuedDepositor.QueueType.Deposit, address(usdtHomeToken), 2_000_000 * 1e18, anotherUser, 0
        );
        vm.stopPrank();
    }

    /**
     * @notice Test upgrading receipt token implementation and verify storage integrity
     */
    function testUpgradeReceiptToken() public {
        // Store pre-upgrade values
        uint256 preQueuedUSDaiTotalSupply = IERC20Metadata(queuedUSDaiToken).totalSupply();
        uint256 preQueuedStakedUSDaiTotalSupply = IERC20Metadata(queuedStakedUSDaiToken).totalSupply();
        uint256 preUserQueuedUSDaiBalance = IERC20Metadata(queuedUSDaiToken).balanceOf(user);
        uint256 preUserQueuedStakedUSDaiBalance = IERC20Metadata(queuedStakedUSDaiToken).balanceOf(user);

        // Verify pre-upgrade implementation
        address oldImplementation = usdaiQueuedDepositor.receiptTokenImplementation();

        // Perform upgrade
        _performUpgrade();

        // Verify upgrade was successful
        address newImplementation = usdaiQueuedDepositor.receiptTokenImplementation();
        assertNotEq(newImplementation, oldImplementation, "Implementation should have changed");

        // Verify storage integrity
        assertEq(
            IERC20Metadata(queuedUSDaiToken).totalSupply(),
            preQueuedUSDaiTotalSupply,
            "queuedUSDaiToken totalSupply changed"
        );
        assertEq(
            IERC20Metadata(queuedStakedUSDaiToken).totalSupply(),
            preQueuedStakedUSDaiTotalSupply,
            "queuedStakedUSDaiToken totalSupply changed"
        );
        assertEq(
            IERC20Metadata(queuedUSDaiToken).balanceOf(user),
            preUserQueuedUSDaiBalance,
            "User queuedUSDai balance changed"
        );
        assertEq(
            IERC20Metadata(queuedStakedUSDaiToken).balanceOf(user),
            preUserQueuedStakedUSDaiBalance,
            "User queuedStakedUSDai balance changed"
        );

        // Verify token metadata is preserved
        assertEq(IERC20Metadata(queuedUSDaiToken).name(), "Queued USDai", "queuedUSDaiToken name changed");
        assertEq(IERC20Metadata(queuedUSDaiToken).symbol(), "qUSDai", "queuedUSDaiToken symbol changed");
        assertEq(
            IERC20Metadata(queuedStakedUSDaiToken).name(), "Queued Staked USDai", "queuedStakedUSDaiToken name changed"
        );
        assertEq(IERC20Metadata(queuedStakedUSDaiToken).symbol(), "qsUSDai", "queuedStakedUSDaiToken symbol changed");

        // Verify ownership is preserved
        assertEq(Ownable(queuedUSDaiToken).owner(), address(usdaiQueuedDepositor), "queuedUSDaiToken owner changed");
        assertEq(
            Ownable(queuedStakedUSDaiToken).owner(),
            address(usdaiQueuedDepositor),
            "queuedStakedUSDaiToken owner changed"
        );
    }

    /**
     * @notice Test that storage slots are preserved at the byte level
     */
    function testStorageSlotIntegrity() public {
        _testStorageSlotIntegrityForToken(queuedUSDaiToken, "queuedUSDaiToken");
        _testStorageSlotIntegrityForToken(queuedStakedUSDaiToken, "queuedStakedUSDaiToken");
    }

    /**
     * @notice Helper to test storage slot integrity for a single token
     */
    function _testStorageSlotIntegrityForToken(address token, string memory tokenName) internal {
        // ERC7201 namespaced storage locations from OpenZeppelin contracts
        bytes32 erc20StorageLocation = 0x52c63247e1f47db19d5ce0460030c497f067ca4cebf71ba98eeadabe20bace00;
        bytes32 ownableStorageLocation = 0x9016d09d72d40fdae2fd8ceac6b6234c7706214fd39c1cd1e609a0528c199300;

        // ERC20Storage struct layout: _balances, _allowances, _totalSupply, _name, _symbol
        bytes32 totalSupplySlot = bytes32(uint256(erc20StorageLocation) + 2); // _totalSupply is 3rd field
        bytes32 ownerSlot = ownableStorageLocation; // _owner is the only field in OwnableStorage

        // Capture critical storage slots before upgrade
        bytes32 totalSupplyBefore = vm.load(token, totalSupplySlot);
        bytes32 ownerBefore = vm.load(token, ownerSlot);

        // Perform upgrade
        _performUpgrade();

        // Capture storage slots after upgrade
        bytes32 totalSupplyAfter = vm.load(token, totalSupplySlot);
        bytes32 ownerAfter = vm.load(token, ownerSlot);

        // Assert storage slots are unchanged
        assertEq(totalSupplyBefore, totalSupplyAfter, string(abi.encodePacked(tokenName, " totalSupply slot changed")));
        assertEq(ownerBefore, ownerAfter, string(abi.encodePacked(tokenName, " owner slot changed")));
    }

    /**
     * @notice Test that balances are preserved through upgrade
     */
    function testBalanceIntegrityThroughUpgrade() public {
        // Record pre-upgrade balances
        uint256 userQueuedUSDaiBalanceBefore = IERC20Metadata(queuedUSDaiToken).balanceOf(user);
        uint256 userQueuedStakedUSDaiBalanceBefore = IERC20Metadata(queuedStakedUSDaiToken).balanceOf(user);
        uint256 anotherUserQueuedUSDaiBalanceBefore = IERC20Metadata(queuedUSDaiToken).balanceOf(anotherUser);

        // Perform upgrade
        _performUpgrade();

        // Record post-upgrade balances
        uint256 userQueuedUSDaiBalanceAfter = IERC20Metadata(queuedUSDaiToken).balanceOf(user);
        uint256 userQueuedStakedUSDaiBalanceAfter = IERC20Metadata(queuedStakedUSDaiToken).balanceOf(user);
        uint256 anotherUserQueuedUSDaiBalanceAfter = IERC20Metadata(queuedUSDaiToken).balanceOf(anotherUser);

        // Assert balances are preserved
        assertEq(userQueuedUSDaiBalanceBefore, userQueuedUSDaiBalanceAfter, "User queuedUSDai balance changed");
        assertEq(
            userQueuedStakedUSDaiBalanceBefore,
            userQueuedStakedUSDaiBalanceAfter,
            "User queuedStakedUSDai balance changed"
        );
        assertEq(
            anotherUserQueuedUSDaiBalanceBefore,
            anotherUserQueuedUSDaiBalanceAfter,
            "Another user queuedUSDai balance changed"
        );

        // Verify total supplies are preserved
        assertEq(
            IERC20Metadata(queuedUSDaiToken).totalSupply(),
            userQueuedUSDaiBalanceAfter + anotherUserQueuedUSDaiBalanceAfter
        );
        assertEq(IERC20Metadata(queuedStakedUSDaiToken).totalSupply(), userQueuedStakedUSDaiBalanceAfter);
    }

    /**
     * @notice Test new functionality after upgrade
     */
    function testNewFunctionality() public {
        // Perform upgrade first
        _performUpgrade();

        // Test new getVersion function
        (bool success, bytes memory data) = queuedUSDaiToken.call(abi.encodeWithSignature("getVersion()"));
        assertTrue(success, "getVersion call failed");
        string memory version = abi.decode(data, (string));
        assertEq(version, "v2.0.0", "New version function not working");

        // Test enhanced mint functionality - must be called as the USDaiQueuedDepositor (owner)
        uint256 balanceBefore = IERC20Metadata(queuedUSDaiToken).balanceOf(user);

        vm.expectEmit(true, true, false, true, queuedUSDaiToken);
        emit EnhancedReceiptToken.EnhancedMint(user, 100 ether, "v2.0.0");

        vm.prank(address(usdaiQueuedDepositor));
        (success,) = queuedUSDaiToken.call(abi.encodeWithSignature("enhancedMint(address,uint256)", user, 100 ether));
        assertTrue(success, "enhancedMint call failed");

        uint256 balanceAfter = IERC20Metadata(queuedUSDaiToken).balanceOf(user);
        assertEq(balanceAfter, balanceBefore + 100 ether, "Enhanced mint did not increase balance");
    }

    /**
     * @notice Test that old functionality still works after upgrade
     */
    function testOldFunctionality() public {
        // Perform upgrade first
        _performUpgrade();

        // Test regular mint function still works - must be called as owner (USDaiQueuedDepositor)
        uint256 balanceBefore = IERC20Metadata(queuedStakedUSDaiToken).balanceOf(anotherUser);

        vm.prank(address(usdaiQueuedDepositor));
        ReceiptToken(queuedStakedUSDaiToken).mint(anotherUser, 50 ether);

        uint256 balanceAfter = IERC20Metadata(queuedStakedUSDaiToken).balanceOf(anotherUser);
        assertEq(balanceAfter, balanceBefore + 50 ether, "Regular mint function broken after upgrade");

        // Test burn function still works
        vm.prank(address(usdaiQueuedDepositor));
        ReceiptToken(queuedStakedUSDaiToken).burn(anotherUser, 25 ether);

        uint256 balanceAfterBurn = IERC20Metadata(queuedStakedUSDaiToken).balanceOf(anotherUser);
        assertEq(balanceAfterBurn, balanceAfter - 25 ether, "Burn function broken after upgrade");

        // Test transfers are still disabled
        vm.startPrank(user);
        vm.expectRevert("Transfers are disabled");
        IERC20Metadata(queuedUSDaiToken).transfer(anotherUser, 1 ether);

        vm.expectRevert("Transfers are disabled");
        IERC20Metadata(queuedUSDaiToken).approve(anotherUser, 1 ether);
        vm.stopPrank();
    }

    /**
     * @notice Helper function to perform the upgrade
     */
    function _performUpgrade() internal {
        // Get proxy admin address
        address proxyAdmin = address(uint160(uint256(vm.load(address(usdaiQueuedDepositor), ERC1967Utils.ADMIN_SLOT))));

        // Deploy new enhanced receipt token implementation
        EnhancedReceiptToken newReceiptTokenImpl = new EnhancedReceiptToken();

        // Deploy new USDaiQueuedDepositor implementation with new receipt token implementation
        USDaiQueuedDepositor newUsdaiQueuedDepositorImpl = new USDaiQueuedDepositor(
            address(usdai),
            address(stakedUsdai),
            address(usdaiHomeOAdapter),
            address(stakedUsdaiHomeOAdapter),
            address(newReceiptTokenImpl)
        );

        // Perform the upgrade
        ProxyAdmin(proxyAdmin).upgradeAndCall(
            ITransparentUpgradeableProxy(address(usdaiQueuedDepositor)), address(newUsdaiQueuedDepositorImpl), ""
        );
    }
}
