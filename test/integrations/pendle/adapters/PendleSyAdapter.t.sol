// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {BaseTest} from "../../../Base.t.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@pendle-sy-public/contracts/interfaces/IERC4626.sol";

import {PendleERC20WithAdapterSY} from
    "@pendle-sy-public/contracts/core/StandardizedYield/implementations/Adapter/extensions/PendleERC20WithAdapterSY.sol";
import {PendleERC4626NoRedeemWithAdapterSY} from
    "@pendle-sy-public/contracts/core/StandardizedYield/implementations/Adapter/extensions/PendleERC4626NoRedeemWithAdapterSY.sol";
import {PendleUSDaiAdapter} from
    "@pendle-sy-public/contracts/core/StandardizedYield/implementations/USDai/PendleUSDaiAdapter.sol";

import {IStandardizedYield} from "@pendle-sy-public/contracts/interfaces/IStandardizedYield.sol";

import {IStakedUSDai} from "src/interfaces/IStakedUSDai.sol";
import {IUSDai} from "src/interfaces/IUSDai.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract PendleSyAdapterTest is BaseTest {
    PendleUSDaiAdapter internal pendleUsdaiAdapter;

    PendleERC20WithAdapterSY internal pendleSyAdapter1;
    PendleERC4626NoRedeemWithAdapterSY internal pendleSyAdapter2;

    IStakedUSDai internal stakedUsdai_ = IStakedUSDai(0x0B2b2B2076d95dda7817e785989fE353fe955ef9);
    IUSDai internal usdai_ = IUSDai(0x0A1a1A107E45b7Ced86833863f482BC5f4ed82EF);

    function setUp() public override {
        super.setUp();

        vm.rollFork(369363837);

        /* Transfer tokens to users */
        vm.startPrank(0xB50A1f651A5ACb2679c8f679D782c728f3702E53);
        /// forge-lint: disable-next-line
        WRAPPED_M_TOKEN.transfer(address(users.normalUser1), 5000 * 1e6);
        /// forge-lint: disable-next-line
        WRAPPED_M_TOKEN.transfer(address(users.normalUser2), 5000 * 1e6);
        vm.stopPrank();

        vm.startPrank(0xDCCdD480E14f7061D64745CE1F9299bC5bb7eCd8);
        /// forge-lint: disable-next-line
        usdai_.transfer(address(users.normalUser1), 5000 * 1e18);
        /// forge-lint: disable-next-line
        usdai_.transfer(address(users.normalUser2), 5000 * 1e18);
        vm.stopPrank();

        pendleUsdaiAdapter = new PendleUSDaiAdapter();

        PendleERC20WithAdapterSY pendleSyAdapterImpl1 = new PendleERC20WithAdapterSY(address(usdai_));
        PendleERC4626NoRedeemWithAdapterSY pendleSyAdapterImpl2 =
            new PendleERC4626NoRedeemWithAdapterSY(address(stakedUsdai_));

        TransparentUpgradeableProxy pendleSyAdapter1Proxy = new TransparentUpgradeableProxy(
            address(pendleSyAdapterImpl1),
            address(users.admin),
            abi.encodeWithSignature(
                "initialize(string,string,address)", "PendleSyAdapter1", "PendleSyAdapter1", address(pendleUsdaiAdapter)
            )
        );

        TransparentUpgradeableProxy pendleSyAdapter2Proxy = new TransparentUpgradeableProxy(
            address(pendleSyAdapterImpl2),
            address(users.admin),
            abi.encodeWithSignature(
                "initialize(string,string,address)", "PendleSyAdapter2", "PendleSyAdapter2", address(pendleUsdaiAdapter)
            )
        );

        pendleSyAdapter1 = PendleERC20WithAdapterSY(payable(address(pendleSyAdapter1Proxy)));
        pendleSyAdapter2 = PendleERC4626NoRedeemWithAdapterSY(payable(address(pendleSyAdapter2Proxy)));
    }

    // ============ PendleERC20WithAdapterSY Tests ============

    function test_PendleSyAdapter1_Initialization() public view {
        assertEq(pendleSyAdapter1.name(), "PendleSyAdapter1");
        assertEq(pendleSyAdapter1.symbol(), "PendleSyAdapter1");
        assertEq(pendleSyAdapter1.adapter(), address(pendleUsdaiAdapter));
        assertEq(pendleSyAdapter1.yieldToken(), address(usdai_));
    }

    function test_PendleSyAdapter1_ExchangeRate() public view {
        assertEq(pendleSyAdapter1.exchangeRate(), 1e18);
    }

    function test_PendleSyAdapter1_GetTokensIn() public view {
        address[] memory tokensIn = pendleSyAdapter1.getTokensIn();
        assertEq(tokensIn.length, 2);
        assertEq(tokensIn[0], address(WRAPPED_M_TOKEN)); // Base token from adapter
        assertEq(tokensIn[1], address(usdai_)); // Yield token
    }

    function test_PendleSyAdapter1_GetTokensOut() public view {
        address[] memory tokensOut = pendleSyAdapter1.getTokensOut();
        assertEq(tokensOut.length, 2);
        assertEq(tokensOut[0], address(WRAPPED_M_TOKEN)); // Base token from adapter
        assertEq(tokensOut[1], address(usdai_)); // Yield token
    }

    function test_PendleSyAdapter1_IsValidTokenIn() public view {
        assertTrue(pendleSyAdapter1.isValidTokenIn(address(WRAPPED_M_TOKEN)));
    }

    function test_PendleSyAdapter1_IsValidTokenOut() public view {
        assertTrue(pendleSyAdapter1.isValidTokenOut(address(WRAPPED_M_TOKEN)));
    }

    function test_PendleSyAdapter1_PreviewDeposit_YieldToken() public view {
        uint256 amount = 1000e18;
        uint256 preview = pendleSyAdapter1.previewDeposit(address(usdai_), amount);
        assertEq(preview, amount);
    }

    function test_PendleSyAdapter1_PreviewDeposit_BaseToken() public view {
        uint256 amount = 1000e6;
        uint256 preview = pendleSyAdapter1.previewDeposit(address(WRAPPED_M_TOKEN), amount);
        uint256 expected = pendleUsdaiAdapter.previewConvertToDeposit(address(WRAPPED_M_TOKEN), amount);
        assertEq(preview, expected);
    }

    function test_PendleSyAdapter1_PreviewRedeem_YieldToken() public view {
        uint256 amount = 1000e18;
        uint256 preview = pendleSyAdapter1.previewRedeem(address(usdai_), amount);
        assertEq(preview, amount);
    }

    function test_PendleSyAdapter1_PreviewRedeem_BaseToken() public view {
        uint256 amount = 1000e6;
        uint256 preview = pendleSyAdapter1.previewRedeem(address(WRAPPED_M_TOKEN), amount);
        uint256 expected = pendleUsdaiAdapter.previewConvertToRedeem(address(WRAPPED_M_TOKEN), amount);
        assertEq(preview, expected);
    }

    function test_PendleSyAdapter1_Deposit_YieldToken() public {
        uint256 amount = 1000e18;
        uint256 balanceBefore = usdai_.balanceOf(address(users.normalUser1));

        vm.startPrank(users.normalUser1);
        usdai_.approve(address(pendleSyAdapter1), amount);
        uint256 sharesOut = pendleSyAdapter1.deposit(address(users.normalUser1), address(usdai_), amount, 0);
        vm.stopPrank();

        assertEq(sharesOut, amount);
        assertEq(pendleSyAdapter1.balanceOf(address(users.normalUser1)), amount);
        assertEq(usdai_.balanceOf(address(users.normalUser1)), balanceBefore - amount);
    }

    function test_PendleSyAdapter1_Deposit_BaseToken() public {
        uint256 amount = 1000e6;
        uint256 balanceBefore = WRAPPED_M_TOKEN.balanceOf(address(users.normalUser1));

        vm.startPrank(users.normalUser1);
        WRAPPED_M_TOKEN.approve(address(pendleSyAdapter1), amount);
        uint256 sharesOut = pendleSyAdapter1.deposit(address(users.normalUser1), address(WRAPPED_M_TOKEN), amount, 0);
        vm.stopPrank();

        assertGt(sharesOut, 0);
        assertEq(pendleSyAdapter1.balanceOf(address(users.normalUser1)), sharesOut);
        assertEq(WRAPPED_M_TOKEN.balanceOf(address(users.normalUser1)), balanceBefore - amount);
    }

    function test_PendleSyAdapter1_Redeem_YieldToken() public {
        // First deposit some tokens
        uint256 depositAmount = 1000e18;
        vm.startPrank(users.normalUser1);
        usdai_.approve(address(pendleSyAdapter1), depositAmount);
        pendleSyAdapter1.deposit(address(users.normalUser1), address(usdai_), depositAmount, 0);

        // Then redeem
        uint256 redeemAmount = 500e18;
        uint256 balanceBefore = usdai_.balanceOf(address(users.normalUser1));
        uint256 tokenOut = pendleSyAdapter1.redeem(address(users.normalUser1), redeemAmount, address(usdai_), 0, false);
        vm.stopPrank();

        assertEq(tokenOut, redeemAmount);
        assertEq(usdai_.balanceOf(address(users.normalUser1)), balanceBefore + redeemAmount);
        assertEq(pendleSyAdapter1.balanceOf(address(users.normalUser1)), depositAmount - redeemAmount);
    }

    function test_PendleSyAdapter1_Redeem_BaseToken() public {
        // First deposit some base tokens
        uint256 depositAmount = 1000e6;
        vm.startPrank(users.normalUser1);
        WRAPPED_M_TOKEN.approve(address(pendleSyAdapter1), depositAmount);
        uint256 shares =
            pendleSyAdapter1.deposit(address(users.normalUser1), address(WRAPPED_M_TOKEN), depositAmount, 0);

        // Then redeem to base token
        uint256 balanceBefore = WRAPPED_M_TOKEN.balanceOf(address(users.normalUser1));
        uint256 tokenOut =
            pendleSyAdapter1.redeem(address(users.normalUser1), shares, address(WRAPPED_M_TOKEN), 0, false);
        vm.stopPrank();

        assertGt(tokenOut, 0);
        assertEq(WRAPPED_M_TOKEN.balanceOf(address(users.normalUser1)), balanceBefore + tokenOut);
    }

    // ============ PendleERC4626NoRedeemWithAdapterSY Tests ============

    function test_PendleSyAdapter2_Initialization() public view {
        assertEq(pendleSyAdapter2.name(), "PendleSyAdapter2");
        assertEq(pendleSyAdapter2.symbol(), "PendleSyAdapter2");
        assertEq(pendleSyAdapter2.adapter(), address(pendleUsdaiAdapter));
        assertEq(pendleSyAdapter2.yieldToken(), address(stakedUsdai_));
        assertEq(pendleSyAdapter2.asset(), address(usdai_));
    }

    function test_PendleSyAdapter2_ExchangeRate() public view {
        uint256 rate = pendleSyAdapter2.exchangeRate();
        assertGt(rate, 0);
    }

    function test_PendleSyAdapter2_GetTokensIn() public view {
        address[] memory tokensIn = pendleSyAdapter2.getTokensIn();
        assertEq(tokensIn.length, 3);
        assertEq(tokensIn[0], address(WRAPPED_M_TOKEN)); // Base token from adapter
        assertEq(tokensIn[1], address(usdai_)); // Yield token
        assertEq(tokensIn[2], address(stakedUsdai_)); // Yield token
    }

    function test_PendleSyAdapter2_GetTokensOut() public view {
        address[] memory tokensOut = pendleSyAdapter2.getTokensOut();
        assertEq(tokensOut.length, 1);
        assertEq(tokensOut[0], address(stakedUsdai_)); // Only yield token (no redeem)
    }

    function test_PendleSyAdapter2_IsValidTokenIn() public view {
        assertTrue(pendleSyAdapter2.isValidTokenIn(address(WRAPPED_M_TOKEN)));
    }

    function test_PendleSyAdapter2_IsValidTokenOut() public view {
        assertFalse(pendleSyAdapter2.isValidTokenOut(address(WRAPPED_M_TOKEN)));
        assertFalse(pendleSyAdapter2.isValidTokenOut(address(usdai_)));
        assertTrue(pendleSyAdapter2.isValidTokenOut(address(stakedUsdai_)));
    }

    function test_PendleSyAdapter2_PreviewDeposit_YieldToken() public view {
        uint256 amount = 1000e18;
        uint256 preview = pendleSyAdapter2.previewDeposit(address(stakedUsdai_), amount);
        assertEq(preview, amount);
    }

    function test_PendleSyAdapter2_PreviewDeposit_Asset() public view {
        uint256 amount = 1000e18;
        uint256 preview = pendleSyAdapter2.previewDeposit(address(usdai_), amount);
        uint256 expected = IERC4626(address(stakedUsdai_)).previewDeposit(amount);
        assertEq(preview, expected);
    }

    function test_PendleSyAdapter2_PreviewDeposit_BaseToken() public view {
        uint256 amount = 1000e6;
        uint256 preview = pendleSyAdapter2.previewDeposit(address(WRAPPED_M_TOKEN), amount);
        uint256 usdaiAmount = pendleUsdaiAdapter.previewConvertToDeposit(address(WRAPPED_M_TOKEN), amount);
        uint256 expected = IERC4626(address(stakedUsdai_)).previewDeposit(usdaiAmount);
        assertEq(preview, expected);
    }

    function test_PendleSyAdapter2_PreviewRedeem() public view {
        uint256 amount = 1000e18;
        uint256 preview = pendleSyAdapter2.previewRedeem(address(stakedUsdai_), amount);
        assertEq(preview, amount);
    }

    function test_PendleSyAdapter2_Deposit_YieldToken() public {
        uint256 amount = 1000e18;
        uint256 balanceBefore = IERC20(address(usdai_)).balanceOf(address(users.normalUser1));

        uint256 expected = IERC4626(address(stakedUsdai_)).previewDeposit(amount);

        vm.startPrank(users.normalUser1);
        usdai_.approve(address(pendleSyAdapter2), amount);
        uint256 sharesOut = pendleSyAdapter2.deposit(address(users.normalUser1), address(usdai_), amount, 0);
        vm.stopPrank();

        assertEq(sharesOut, expected);
        assertEq(pendleSyAdapter2.balanceOf(address(users.normalUser1)), expected);
        assertEq(usdai_.balanceOf(address(users.normalUser1)), balanceBefore - amount);
    }

    function test_PendleSyAdapter2_Deposit_Asset() public {
        uint256 amount = 1000e18;
        uint256 balanceBefore = usdai_.balanceOf(address(users.normalUser1));

        vm.startPrank(users.normalUser1);
        usdai_.approve(address(pendleSyAdapter2), amount);
        uint256 sharesOut = pendleSyAdapter2.deposit(address(users.normalUser1), address(usdai_), amount, 0);
        vm.stopPrank();

        assertGt(sharesOut, 0);
        assertEq(pendleSyAdapter2.balanceOf(address(users.normalUser1)), sharesOut);
        assertEq(usdai_.balanceOf(address(users.normalUser1)), balanceBefore - amount);
    }

    function test_PendleSyAdapter2_Deposit_BaseToken() public {
        uint256 amount = 1000e6;
        uint256 balanceBefore = WRAPPED_M_TOKEN.balanceOf(address(users.normalUser1));

        vm.startPrank(users.normalUser1);
        WRAPPED_M_TOKEN.approve(address(pendleSyAdapter2), amount);
        uint256 sharesOut = pendleSyAdapter2.deposit(address(users.normalUser1), address(WRAPPED_M_TOKEN), amount, 0);
        vm.stopPrank();

        assertGt(sharesOut, 0);
        assertEq(pendleSyAdapter2.balanceOf(address(users.normalUser1)), sharesOut);
        assertEq(WRAPPED_M_TOKEN.balanceOf(address(users.normalUser1)), balanceBefore - amount);
    }

    function test_PendleSyAdapter2_Redeem() public {
        // First deposit some tokens
        uint256 depositAmount = 1000e18;
        vm.startPrank(users.normalUser1);
        usdai_.approve(address(pendleSyAdapter2), depositAmount);
        uint256 shares = pendleSyAdapter2.deposit(address(users.normalUser1), address(usdai_), depositAmount, 0);

        // Then redeem
        uint256 balanceBefore = IERC20(address(stakedUsdai_)).balanceOf(address(users.normalUser1));
        uint256 tokenOut = pendleSyAdapter2.redeem(address(users.normalUser1), shares, address(stakedUsdai_), 0, false);
        vm.stopPrank();

        assertEq(tokenOut, shares);
        assertEq(IERC20(address(stakedUsdai_)).balanceOf(address(users.normalUser1)), balanceBefore + shares);
        assertEq(pendleSyAdapter2.balanceOf(address(users.normalUser1)), 0);
    }

    function test_PendleSyAdapter2_Redeem_RevertWith_BaseToken() public {
        uint256 depositAmount = 1000e6;
        vm.startPrank(users.normalUser1);
        usdai_.approve(address(pendleSyAdapter2), depositAmount);
        uint256 shares = pendleSyAdapter2.deposit(address(users.normalUser1), address(usdai_), depositAmount, 0);

        vm.expectRevert();
        pendleSyAdapter2.redeem(address(users.normalUser1), shares, address(WRAPPED_M_TOKEN), 0, false);
    }

    function test_PendleSyAdapter2_Redeem_RevertWith_Asset() public {
        uint256 depositAmount = 1000e6;
        vm.startPrank(users.normalUser1);
        usdai_.approve(address(pendleSyAdapter2), depositAmount);
        uint256 shares = pendleSyAdapter2.deposit(address(users.normalUser1), address(usdai_), depositAmount, 0);

        vm.expectRevert();
        pendleSyAdapter2.redeem(address(users.normalUser1), shares, address(usdai_), 0, false);
    }

    function test_PendleSyAdapter2_AssetInfo() public view {
        (IStandardizedYield.AssetType assetType, address assetAddress, uint8 assetDecimals) =
            pendleSyAdapter2.assetInfo();
        assertEq(uint8(assetType), 0); // TOKEN = 0
        assertEq(assetAddress, address(usdai_));
        assertEq(assetDecimals, 18);
    }

    // ============ Integration Tests ============

    function test_AdapterIntegration_DepositAndRedeem() public {
        uint256 depositAmount = 1000e6;

        // Test adapter1 (ERC20)
        vm.startPrank(users.normalUser1);
        WRAPPED_M_TOKEN.approve(address(pendleSyAdapter1), depositAmount);
        uint256 shares1 =
            pendleSyAdapter1.deposit(address(users.normalUser1), address(WRAPPED_M_TOKEN), depositAmount, 0);
        uint256 redeemed1 =
            pendleSyAdapter1.redeem(address(users.normalUser1), shares1, address(WRAPPED_M_TOKEN), 0, false);
        vm.stopPrank();

        assertGt(shares1, 0);
        assertGt(redeemed1, 0);

        // Test adapter2 (ERC4626)
        vm.startPrank(users.normalUser2);
        WRAPPED_M_TOKEN.approve(address(pendleSyAdapter2), depositAmount);
        uint256 shares2 =
            pendleSyAdapter2.deposit(address(users.normalUser2), address(WRAPPED_M_TOKEN), depositAmount, 0);
        uint256 redeemed2 =
            pendleSyAdapter2.redeem(address(users.normalUser2), shares2, address(stakedUsdai_), 0, false);
        vm.stopPrank();

        assertGt(shares2, 0);
        assertEq(redeemed2, shares2);
    }

    function test_AdapterIntegration_ExchangeRates() public view {
        // Both adapters should have different exchange rates
        uint256 rate1 = pendleSyAdapter1.exchangeRate();
        uint256 rate2 = pendleSyAdapter2.exchangeRate();

        assertEq(rate1, 1e18); // ERC20 adapter always has 1:1 rate
        assertGt(rate2, 0); // ERC4626 adapter has variable rate
    }
}
