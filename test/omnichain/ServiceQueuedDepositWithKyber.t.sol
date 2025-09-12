// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {Vm} from "forge-std/Vm.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

import {console} from "forge-std/console.sol";
import {Vm} from "forge-std/Vm.sol";

import {BaseTest} from "../Base.t.sol";
import {USDai} from "src/USDai.sol";
import {StakedUSDai} from "src/StakedUSDai.sol";
import {USDaiQueuedDepositor} from "src/queuedDepositor/USDaiQueuedDepositor.sol";
import {ReceiptToken} from "src/queuedDepositor/ReceiptToken.sol";

import {IUSDaiQueuedDepositor} from "src/interfaces/IUSDaiQueuedDepositor.sol";
import {OUSDaiUtility} from "src/omnichain/OUSDaiUtility.sol";
import {IOUSDaiUtility} from "src/interfaces/IOUSDaiUtility.sol";

contract USDaiServiceQueuedDepositWithKyberTest is BaseTest {
    IERC20 internal usdt = IERC20(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9);
    USDaiQueuedDepositor internal queuedDepositor = USDaiQueuedDepositor(0x81cc0DEE5e599784CBB4862c605c7003B0aC5A53);
    address internal oUsdaiUtility = 0x24a92E28a8C5D8812DcfAf44bCb20CC0BaBd1392;
    address internal endpoint = 0x1a44076050125825900e736c501f859c50fE728c;

    address internal kyberTarget = 0x6131B5fae19EA4f9D964eAc0408E4408b66337b5;
    /* KyberSwap execution data */
    /* Token In: USDT */
    /* Token Out: wM */
    /* Amount: 4,000,000 USDT */
    bytes internal kyberExecutionData =
        hex"e21fd0e900000000000000000000000000000000000000000000000000000000000000200000000000000000000000006e4141d33021b52c91c28608403db4a0ffb50ec6000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000840000000000000000000000000000000000000000000000000000000000000053b07020000003c0000003c0441b42195f4ad6aa9a0978e06096ea616cda7000000000000000000000145f680b000af88d065e77c8cc2239327c5edb3a432268e583102580000002e02000000b50a1f651a5acb2679c8f679d782c728f3702e5301010000000000000001014530ed8dc1f014325d91e70a020000007002000000a17afcab059f3c6751f5b64347b5a503c3291868af88d065e77c8cc2239327c5edb3a432268e583100000000000000000000005d21dba0000000000000000000000000000000000000000000000000000000000000000000fffd8963efd1fc6a506488495d951d5263988d25150000002e02000000b50a1f651a5acb2679c8f679d782c728f3702e5301010000000000000001014530ed8dc1f014325d91e70a030000002b010000007f90122bf0700f9e7e1f688fe926940e8839f3530000000000000000000000002e90edd0000000090000006102000000c86eb7b85807020b4548ee05b54bfc956eebbfcdaf88d065e77c8cc2239327c5edb3a432268e5831010000000000000000000000000000000000000000000000000000000000000000000000000000001f9f6d9a3bc5ab22441f2925e8150000002e02000000b50a1f651a5acb2679c8f679d782c728f3702e5301010000000000000001014530ed8dc1f014325d91e70a0200000094000000360e68faccca8ca495c1b759fd9eee466db9fb3200000000000000000000002e90edd00001fd086bc7cd5c481dcc9c85ebe478a1c0b69fcbb900000000000000000000002e90edd00001af88d065e77c8cc2239327c5edb3a432268e5831000008000001000000000000000000000000000000000000000000000000fffd8963efd1fc6a506488495d951d5263988d25024c0000002e02000000b50a1f651a5acb2679c8f679d782c728f3702e5301010000000000000001014530ed8dc1f014325d91e70a020000003d02000000be3ad6a5669dc0b8b12febc03608860c31e2eef6000000000000000000000145f680b00001fffd8963efd1fc6a506488495d951d5263988d250a0000002e02000000b50a1f651a5acb2679c8f679d782c728f3702e5301010000000000000001014530ed8dc1f014325d91e70a020000003d02000000df63268af25a2a69c07d09a88336cd9424269a1f00000000000000000000002e90edd00001fffd8963efd1fc6a506488495d951d5263988d250a0000002e02000000b50a1f651a5acb2679c8f679d782c728f3702e5301010000000000000001014530ed8dc1f014325d91e70a02000000bc000000ad89051bed8d96f045e8912ae1672c6c0bf8a85e0103a6d12574efb239fc1d2099732bd8b5dc6306897fa6d12574efb239fc1d2099732bd8b5dc6306897f0119b001e6bc2d89154c18e2216eec5c8c6047b6d87f6501d3b98ee91f9b9535e4b0ac710fb0f9e0bc007f6501d3b98ee91f9b9535e4b0ac710fb0f9e0bcaf88d065e77c8cc2239327c5edb3a432268e58310100000000000000000000002e90edd000000000000022d473030f116ddee9f6b43ac78ba300000000460000002e02000000b50a1f651a5acb2679c8f679d782c728f3702e5301010000000000000001014530ed8dc1f014325d91e70afd086bc7cd5c481dcc9c85ebe478a1c0b69fcbb9437cc33344a0b27a429f795ff6b469c72698b29181cc0dee5e599784cbb4862c605c7003b0ac5a5300000000000000000000000068b8ab3f000000540000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003d0bd70000000000000000000003a37dedb6844f82e73edb06d29ff62c91ec8f5ff06571bdeb290000000000000000000000000000000000fd086bc7cd5c481dcc9c85ebe478a1c0b69fcbb9000000000000000000000000437cc33344a0b27a429f795ff6b469c72698b291000000000000000000000000000000000000000000000000000000000000016000000000000000000000000000000000000000000000000000000000000001a000000000000000000000000000000000000000000000000000000000000001e0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000081cc0dee5e599784cbb4862c605c7003b0ac5a53000000000000000000000000000000000000000000000000000003a352944000000000000000000000000000000000000000000000000000000003a36615166a0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000022000000000000000000000000000000000000000000000000000000000000000010000000000000000000000006e4141d33021b52c91c28608403db4a0ffb50ec60000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000003a35294400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002857b22536f75726365223a224d79417765736f6d65417070222c22416d6f756e74496e555344223a22343030323930392e34303236313738323835222c22416d6f756e744f7574555344223a22343030373936312e373630343338343439222c22526566657272616c223a22222c22466c616773223a302c22416d6f756e744f7574223a2234303030373237323833333331222c2254696d657374616d70223a313735363933313732372c22526f7574654944223a2261646438353238612d306230392d346135392d613761392d3736346661616536313363663a61646438353238612d306230392d346135392d613761392d373634666161653631336366222c22496e74656772697479496e666f223a7b224b65794944223a2231222c225369676e6174757265223a224a7339706e4d34734644457a4479746647597946717a37506262754f727076794a702b443349304b7650364174544b476141634f44462f71485672573447705a573877577063616e42786e66516c6634413349627865656c6b574f576e392f314c394670336737326f49354144446735525357656f64504950746970694837522f4b3046546e7856787a50514332364a7a59495a305134626d616a6a664674706d7668552f39484b4a67535a5530775545646d614236434e45634634527771416b56544d70667362467357374b624c497437555532507436707152436f494f374e6c535269683037462b6d48326b41747932417a6d37716a3844566579762b612f796d38302b656b70537a5337543151414e30423778746f65504b66386e646e504f42303842424e444d6e42464f4d7165756b3242494e54754c42644a2f796d522f67537064776f664b794f38735039676d69454d513d3d227d7d000000000000000000000000000000000000000000000000000000";

    function setUp() public override {
        super.setUp();

        vm.createSelectFork(vm.envString("ARBITRUM_RPC_URL"));
        vm.rollFork(375372496);

        usdai = USDai(0x0A1a1A107E45b7Ced86833863f482BC5f4ed82EF);
        stakedUsdai = StakedUSDai(0x0B2b2B2076d95dda7817e785989fE353fe955ef9);
        address oAdapterUSDai = 0xffA10065Ce1d1C42FABc46e06B84Ed8FfEb4baE5;
        address oAdapterStakedUSDai = 0xffB20098FD7B8E84762eea4609F299D101427f24;
        address receiptTokenImpl = address(new ReceiptToken());

        /* Lookup proxy admin */
        address proxyAdmin1 = address(uint160(uint256(vm.load(address(queuedDepositor), ERC1967Utils.ADMIN_SLOT))));

        vm.startPrank(0x783B08aA21DE056717173f72E04Be0E91328A07b);

        // Deploy USDai implemetation
        USDaiQueuedDepositor queuedDepositorImpl = new USDaiQueuedDepositor(
            address(usdai), address(stakedUsdai), oAdapterUSDai, oAdapterStakedUSDai, receiptTokenImpl, oUsdaiUtility
        );

        /* Upgrade Proxy */
        ProxyAdmin(proxyAdmin1).upgradeAndCall(
            ITransparentUpgradeableProxy(address(queuedDepositor)), address(queuedDepositorImpl), ""
        );

        /* Lookup proxy admin */
        address proxyAdmin2 = address(uint160(uint256(vm.load(oUsdaiUtility, ERC1967Utils.ADMIN_SLOT))));

        // Deploy OUSDaiUtility implemetation
        OUSDaiUtility oUSDaiUtilityImpl = new OUSDaiUtility(
            endpoint, address(usdai), address(stakedUsdai), oAdapterUSDai, oAdapterStakedUSDai, address(queuedDepositor)
        );

        /* Upgrade Proxy */
        ProxyAdmin(proxyAdmin2).upgradeAndCall(
            ITransparentUpgradeableProxy(oUsdaiUtility), address(oUSDaiUtilityImpl), ""
        );
        vm.stopPrank();

        /* Update deposit cap and supply cap */
        vm.startPrank(0x5F0BC72FB5952b2f3F2E11404398eD507B25841F);

        queuedDepositor.updateDepositCap(0, type(uint256).max, true);
        usdai.setSupplyCap(type(uint256).max);

        vm.stopPrank();
    }

    function test__USDaiServiceQueued_WithKyberQuote_ForDeposit() public {
        address usdtHolder = 0x7c490d17af51292b513C338Ebe1323B7e3BA56fA;

        vm.startPrank(usdtHolder);
        usdt.approve(oUsdaiUtility, 4_000_000 * 1e6);

        // Data for queued deposit
        bytes memory queuedDepositData = abi.encode(IUSDaiQueuedDepositor.QueueType.Deposit, usdtHolder, 0);

        // Record logs to capture the Deposit event
        vm.recordLogs();

        // Deposit the USD
        IOUSDaiUtility(oUsdaiUtility).localCompose(
            IOUSDaiUtility.ActionType.QueuedDeposit, address(usdt), 4_000_000 * 1e6, queuedDepositData
        );

        // Get logs and extract queueIndex from Deposit event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 queueIndex;

        // Find the Deposit event log
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("Deposit(uint8,address,uint256,address,uint256,address)")) {
                // Extract queueIndex from the third topic (indexed parameter)
                queueIndex = uint256(logs[i].topics[3]);
                break;
            }
        }

        vm.stopPrank();

        bytes memory data = abi.encode(address(usdt), 4_000_000 * 1e6, kyberTarget, kyberExecutionData, 0, 0);

        vm.startPrank(0xe7E53F940F8242fec57CBE88054463d4944B3670);
        queuedDepositor.service(
            IUSDaiQueuedDepositor.QueueType.Deposit, abi.encode(IUSDaiQueuedDepositor.SwapType.Aggregator, data)
        );
        vm.stopPrank();

        assertGt(usdai.balanceOf(usdtHolder), 4_000_000 * 1e18);

        IUSDaiQueuedDepositor.QueueItem memory queueItem =
            queuedDepositor.queueItem(IUSDaiQueuedDepositor.QueueType.Deposit, address(usdt), queueIndex);
        assertEq(queueItem.pendingDeposit, 0);
        assertEq(queueItem.dstEid, 0);
        assertEq(queueItem.depositor, oUsdaiUtility);
        assertEq(queueItem.recipient, usdtHolder);
    }

    function test__USDaiServiceQueued_WithKyberQuote_ForDepositAndStake() public {
        address usdtHolder = 0x7c490d17af51292b513C338Ebe1323B7e3BA56fA;

        vm.startPrank(usdtHolder);
        usdt.approve(oUsdaiUtility, 4_000_000 * 1e6);

        // Data for queued deposit
        bytes memory queuedDepositData = abi.encode(IUSDaiQueuedDepositor.QueueType.DepositAndStake, usdtHolder, 0);

        // Record logs to capture the Deposit event
        vm.recordLogs();

        // Deposit the USD
        IOUSDaiUtility(oUsdaiUtility).localCompose(
            IOUSDaiUtility.ActionType.QueuedDeposit, address(usdt), 4_000_000 * 1e6, queuedDepositData
        );

        // Get logs and extract queueIndex from Deposit event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 queueIndex;

        // Find the Deposit event log
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("Deposit(uint8,address,uint256,address,uint256,address)")) {
                // Extract queueIndex from the third topic (indexed parameter)
                queueIndex = uint256(logs[i].topics[3]);
                break;
            }
        }

        vm.stopPrank();

        uint256 depositSharePrice = stakedUsdai.depositSharePrice() + 1;

        bytes memory data =
            abi.encode(address(usdt), 4_000_000 * 1e6, kyberTarget, kyberExecutionData, 0, depositSharePrice);

        vm.startPrank(0xe7E53F940F8242fec57CBE88054463d4944B3670);
        queuedDepositor.service(
            IUSDaiQueuedDepositor.QueueType.DepositAndStake, abi.encode(IUSDaiQueuedDepositor.SwapType.Aggregator, data)
        );
        vm.stopPrank();

        assertGt(stakedUsdai.balanceOf(usdtHolder), 4_000_000 * 1e18 * 1e18 / depositSharePrice);

        IUSDaiQueuedDepositor.QueueItem memory queueItem =
            queuedDepositor.queueItem(IUSDaiQueuedDepositor.QueueType.DepositAndStake, address(usdt), queueIndex);
        assertEq(queueItem.pendingDeposit, 0);
        assertEq(queueItem.dstEid, 0);
        assertEq(queueItem.depositor, oUsdaiUtility);
        assertEq(queueItem.recipient, usdtHolder);
    }
}
