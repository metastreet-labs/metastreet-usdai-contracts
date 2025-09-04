// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import {Deployer} from "../../script/utils/Deployer.s.sol";

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

import "../Base.t.sol";

contract USDaiSupplyCapBypassTest is BaseTest {
    IERC20 internal USDC = IERC20(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);

    function setUp() public override {
        super.setUp();

        vm.createSelectFork(vm.envString("ARBITRUM_RPC_URL"));
        vm.rollFork(375673779); // Sep 4

        usdai = USDai(0x0A1a1A107E45b7Ced86833863f482BC5f4ed82EF);

        /* Lookup proxy admin */
        address proxyAdmin = address(uint160(uint256(vm.load(address(usdai), ERC1967Utils.ADMIN_SLOT))));

        vm.startPrank(0x783B08aA21DE056717173f72E04Be0E91328A07b);

        // Deploy USDai implemetation
        USDai USDaiImpl = new USDai(0x5F8deFa807F48e5784b98aEf50ADfC52029f3cf9);

        /* Upgrade Proxy */
        ProxyAdmin(proxyAdmin).upgradeAndCall(ITransparentUpgradeableProxy(address(usdai)), address(USDaiImpl), "");
        vm.stopPrank();

        vm.startPrank(0x5F0BC72FB5952b2f3F2E11404398eD507B25841F);

        usdai.setSupplyCap(0 ether);

        /* Grant depositor admin role to queue depositor */
        USDai(address(usdai)).grantRole(keccak256("DEPOSITOR_ADMIN_ROLE"), 0x81cc0DEE5e599784CBB4862c605c7003B0aC5A53);
        vm.stopPrank();
    }

    function test__USDaiSupplyCapDepositExceedsSupplyCap() public {
        // User approves USDai to spend their USD
        vm.startPrank(0x0a8494F70031623C9C0043aff4D40f334b458b11);
        USDC.approve(address(usdai), type(uint256).max);

        /* User deposits into USDai fails */
        vm.expectRevert(IUSDai.SupplyCapExceeded.selector);
        usdai.deposit(address(USDC), 1_000_000 * 1e6, 0, users.normalUser1);

        vm.stopPrank();

        // Queue depositor can deposit
        vm.startPrank(0x81cc0DEE5e599784CBB4862c605c7003B0aC5A53);
        USDC.approve(address(usdai), 1_000_000 * 1e6);
        usdai.deposit(address(USDC), 1_000_000 * 1e6, 0, 0x81cc0DEE5e599784CBB4862c605c7003B0aC5A53);
        vm.stopPrank();
    }
}
