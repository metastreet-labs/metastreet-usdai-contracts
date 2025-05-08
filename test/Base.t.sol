// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "forge-std/console.sol";

import {Vm} from "forge-std/Vm.sol";

import {Test} from "forge-std/Test.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

import {ISwapRouter02} from "src/interfaces/external/ISwapRouter02.sol";

import {TestERC721} from "./tokens/TestERC721.sol";
import {TestERC20} from "./tokens/TestERC20.sol";

import {MetastreetPoolHelpers} from "./helpers/MetastreetPoolHelpers.sol";
import {UniswapPoolHelpers} from "./helpers/UniswapPoolHelpers.sol";

import {USDai} from "src/USDai.sol";
import {StakedUSDai} from "src/StakedUSDai.sol";
import {ChainlinkPriceOracle} from "src/oracles/ChainlinkPriceOracle.sol";
import {UniswapV3SwapAdapter} from "src/swapAdapters/UniswapV3SwapAdapter.sol";
import {PositionManager} from "src/positionManagers/PositionManager.sol";
import {StakedUSDaiStorage} from "src/StakedUSDaiStorage.sol";

import {IWrappedMToken} from "src/interfaces/external/IWrappedMToken.sol";
import {IStakedUSDai} from "src/interfaces/IStakedUSDai.sol";
import {IUSDai} from "src/interfaces/IUSDai.sol";
import {IPool} from "src/interfaces/external/IPool.sol";

import {TestMNAVPriceFeed} from "../script/DeployTestMNAVPriceFeed.s.sol";

/**
 * @title Base test setup
 *
 * @author MetaStreet Foundation
 * @author Modified from https://github.com/PaulRBerg/prb-proxy/blob/main/test/Base.t.sol
 *
 * @dev Sets up users and token contracts
 */
abstract contract BaseTest is Test {
    /* M portal */
    address internal constant M_PORTAL = 0xD925C84b55E4e44a53749fF5F2a5A13F63D128fd;

    /* M */
    address internal constant M_TOKEN = 0x866A2BF4E572CbcF37D5071A7a58503Bfb36be1b;

    /* Wrapped M */
    IWrappedMToken internal constant WRAPPED_M_TOKEN = IWrappedMToken(0x437cc33344a0B27A429f795ff6B469C72698B291);

    /* M registrar */
    address internal constant M_REGISTRAR = 0x119FbeeDD4F4f4298Fb59B720d5654442b81ae2c;

    /* Earners list role */
    bytes32 internal constant EARNERS_LIST = "earners";

    bytes32 internal constant CLAIM_OVERRIDE_RECIPIENT_PREFIX = "wm_claim_override_recipient";

    /* Staked sUSDai unstake timelock */
    uint64 internal constant TIMELOCK = 7 days;

    address internal constant M_NAV_PRICE_FEED = 0xC28198Df9aee1c4990994B35ff51eFA4C769e534;

    /* MetaStreet Pool durations, rates, tick */
    uint64[] internal DURATIONS = [30 days, 14 days, 7 days];
    uint64[] internal RATES = [
        MetastreetPoolHelpers.normalizeRate(0.1 * 1e18),
        MetastreetPoolHelpers.normalizeRate(0.3 * 1e18),
        MetastreetPoolHelpers.normalizeRate(0.5 * 1e18)
    ];
    uint128 internal TICK = MetastreetPoolHelpers.encodeTick(1_000_000 ether, 0, 0, 0);

    /* Fixed point scale */
    uint256 internal constant FIXED_POINT_SCALE = 1e18;

    /* Locked shares */
    uint128 internal constant LOCKED_SHARES = 1e6;

    /* WETH */
    address internal constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    /* USDT */
    address internal constant USDT = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;

    /* WETH price feed */
    address internal constant WETH_PRICE_FEED = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;

    /* USDT price feed */
    address internal constant USDT_PRICE_FEED = 0x3f3f5dF88dC9F13eac63DF89EC16ef6e7E25DdE7;

    /**
     * @notice User accounts
     */
    struct Users {
        address payable deployer;
        address payable normalUser1;
        address payable normalUser2;
        address payable admin;
        address payable manager;
    }

    Users internal users;
    TestERC20 internal usd;
    TestERC20 internal usd2;
    TestERC721 internal nft;
    UniswapV3SwapAdapter internal uniswapV3SwapAdapter;
    ChainlinkPriceOracle internal priceOracle;
    IUSDai internal usdai;
    StakedUSDai internal stakedUsdai;
    IPool internal metastreetPool1;
    IPool internal metastreetPool2;
    TestMNAVPriceFeed internal testMNAVPriceFeed;

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("ARBITRUM_RPC_URL"));
        vm.rollFork(322784114);

        users = Users({
            deployer: createUser("deployer"),
            normalUser1: createUser("normalUser1"),
            normalUser2: createUser("normalUser2"),
            admin: createUser("admin"),
            manager: createUser("manager")
        });

        /* Get tokens */
        getTokens();

        deployNft();
        deployUsd();
        deployUsdPool();

        deployUniswapV3SwapAdapter();
        deployTestMNAVPriceFeed();
        deployPriceOracle();
        deployUsdai();
        deployStakedUsdai();

        addToEarnersList();
        startEarning();

        setupWrappedMLiquidity();

        /* Deploy MetaStreet pools */
        deployMetastreetPool(address(nft), address(WETH));
        deployMetastreetPool(address(nft), address(USDT));

        /* Set approvals */
        setApprovals();
    }

    function setupWrappedMLiquidity() internal {
        /* Mint to admin as portal */
        vm.startPrank(M_PORTAL);
        (bool success,) =
            M_TOKEN.call(abi.encodeWithSignature("mint(address,uint256)", address(users.admin), 20_000_001 ether));
        require(success, "Mint failed");
        vm.stopPrank();

        /* Wrap as admin */
        vm.startPrank(users.admin);
        IERC20(M_TOKEN).approve(address(WRAPPED_M_TOKEN), 20_000_001 ether);
        WRAPPED_M_TOKEN.wrap(address(users.admin), 20_000_001 ether);

        require(WRAPPED_M_TOKEN.balanceOf(address(users.admin)) >= 20_000_000 ether);

        /* Deploy pool as admin */
        UniswapPoolHelpers.setupUniswapPool(
            address(users.admin), address(usd), address(WRAPPED_M_TOKEN), 20_000_000 ether, 20_000_000 ether
        );
        vm.stopPrank();
    }

    function deployUniswapV3SwapAdapter() internal {
        vm.startPrank(users.deployer);

        /* Deploy Uniswap V3 swap adapter */
        uniswapV3SwapAdapter =
            new UniswapV3SwapAdapter(address(WRAPPED_M_TOKEN), address(UniswapPoolHelpers.UNISWAP_ROUTER));

        address[] memory whitelistedTokens = new address[](3);
        whitelistedTokens[0] = address(usd);
        whitelistedTokens[1] = address(WETH);
        whitelistedTokens[2] = address(USDT);

        uniswapV3SwapAdapter.setWhitelistedTokens(whitelistedTokens);

        vm.stopPrank();
    }

    function deployTestMNAVPriceFeed() internal {
        vm.startPrank(users.deployer);

        /* Deploy mock m chainlink oracle */
        testMNAVPriceFeed = new TestMNAVPriceFeed();

        vm.stopPrank();
    }

    function deployNft() internal {
        vm.startPrank(users.deployer);

        /* Deploy NFT */
        nft = new TestERC721("NFT", "NFT", "https://nft1.com/token/");

        /* Mint NFT to users */
        nft.mint(address(users.normalUser1), 123);
        nft.mint(address(users.normalUser2), 124);

        vm.stopPrank();
    }

    function deployUsd() internal {
        vm.startPrank(users.deployer);

        /* Deploy USD ERC20 */
        usd = new TestERC20("USD", "USD", 6, 300_000_000 ether);

        /* Mint USD to users */
        usd.transfer(address(users.normalUser1), 40_000_000 ether);
        usd.transfer(address(users.normalUser2), 40_000_000 ether);
        usd.transfer(address(users.admin), 50_000_000 ether);
        usd.transfer(address(users.manager), 40_000_000 ether);

        /* Deploy USD2 ERC20 */
        usd2 = new TestERC20("USD", "USD", 6, 300_000_000 ether);

        /* Mint USD2 to users */
        usd2.transfer(address(users.normalUser1), 40_000_000 ether);
        usd2.transfer(address(users.normalUser2), 40_000_000 ether);
        usd2.transfer(address(users.admin), 50_000_000 ether);
        usd2.transfer(address(users.manager), 40_000_000 ether);

        vm.stopPrank();
    }

    function deployUsdPool() internal {
        vm.startPrank(users.admin);

        UniswapPoolHelpers.setupUniswapPool(
            address(users.admin), address(usd), address(usd2), 20_000_000 ether, 20_000_000 ether
        );

        UniswapPoolHelpers.setupUniswapPool(
            address(users.admin), address(usd), address(USDT), 1_000_000 * 1e6, 1_000_000 * 1e6
        );

        vm.stopPrank();
    }

    function deployUsdai() internal {
        vm.startPrank(users.deployer);

        /* Deploy usdai implementation */
        IUSDai usdaiImpl = new USDai(address(uniswapV3SwapAdapter));

        /* Deploy usdai proxy */
        TransparentUpgradeableProxy usdaiProxy = new TransparentUpgradeableProxy(
            address(usdaiImpl), address(users.admin), abi.encodeWithSignature("initialize(address)", users.deployer)
        );

        /* Deploy usdai */
        usdai = IUSDai(address(usdaiProxy));
        vm.stopPrank();

        /* Grant USDai role to Uniswap V3 swap adapter */
        vm.startPrank(users.deployer);
        uniswapV3SwapAdapter.grantRole(keccak256("USDAI_ROLE"), address(usdai));

        vm.stopPrank();
    }

    function deployPriceOracle() internal {
        vm.startPrank(users.deployer);

        /* Deploy staked usdai implementation */
        address[] memory tokens = new address[](2);
        tokens[0] = address(WETH);
        tokens[1] = address(USDT);
        address[] memory priceFeeds = new address[](2);
        priceFeeds[0] = address(WETH_PRICE_FEED);
        priceFeeds[1] = address(USDT_PRICE_FEED);
        priceOracle = new ChainlinkPriceOracle(address(testMNAVPriceFeed), tokens, priceFeeds);

        vm.stopPrank();
    }

    function deployStakedUsdai() internal {
        vm.startPrank(users.deployer);

        /* Deploy staked usdai implementation */
        StakedUSDai stakedUsdaiImpl = new StakedUSDai(address(usdai), address(priceOracle));

        /* Deploy staked usdai proxy */
        TransparentUpgradeableProxy stakedUsdaiProxy = new TransparentUpgradeableProxy(
            address(stakedUsdaiImpl), address(users.admin), abi.encodeWithSignature("initialize(uint64)", TIMELOCK)
        );

        /* Deploy staked usdai */
        stakedUsdai = StakedUSDai(address(stakedUsdaiProxy));

        /* Grant roles */
        stakedUsdai.grantRole(keccak256("BLACKLIST_ADMIN_ROLE"), address(users.deployer));
        stakedUsdai.grantRole(keccak256("PAUSE_ADMIN_ROLE"), address(users.deployer));
        stakedUsdai.grantRole(keccak256("STRATEGY_ADMIN_ROLE"), address(users.manager));

        /* Grant bridge admin role to manager only for testing */
        stakedUsdai.grantRole(keccak256("BRIDGE_ADMIN_ROLE"), address(users.manager));
        vm.stopPrank();
    }

    function addToEarnersList() internal {
        vm.startPrank(M_PORTAL);

        (bool success1,) =
            M_REGISTRAR.call(abi.encodeWithSignature("addToList(bytes32,address)", EARNERS_LIST, address(usdai)));
        require(success1, "Add to earners list failed");

        (bool success2,) =
            M_REGISTRAR.call(abi.encodeWithSignature("addToList(bytes32,address)", EARNERS_LIST, address(stakedUsdai)));
        require(success2, "Add to earners list failed");

        /* Set claim override recipient for usdai */
        bytes32 key = keccak256(abi.encode(CLAIM_OVERRIDE_RECIPIENT_PREFIX, address(usdai)));
        (bool success3,) = M_REGISTRAR.call(
            abi.encodeWithSignature("setKey(bytes32,bytes32)", key, bytes32(uint256(uint160(address(stakedUsdai)))))
        );
        require(success3, "Set key failed");

        vm.stopPrank();
    }

    function startEarning() internal {
        vm.startPrank(users.admin);
        WRAPPED_M_TOKEN.startEarningFor(address(usdai));
        WRAPPED_M_TOKEN.startEarningFor(address(stakedUsdai));
        vm.stopPrank();
    }

    function getTokens() internal {
        /* Get tokens from WETH holder */
        vm.startPrank(0xe50fA9b3c56FfB159cB0FCA61F5c9D750e8128c8);
        IERC20(WETH).balanceOf(0xe50fA9b3c56FfB159cB0FCA61F5c9D750e8128c8);

        IERC20(WETH).transfer(address(users.admin), 10_000 ether);
        IERC20(WETH).transfer(address(users.normalUser1), 2_000 ether);
        IERC20(WETH).transfer(address(users.normalUser2), 2_000 ether);
        vm.stopPrank();

        /* Get tokens from USDT holder */
        vm.startPrank(0xB38e8c17e38363aF6EbdCb3dAE12e0243582891D);
        IERC20(USDT).transfer(address(users.admin), 10_000_000 * 1e6);
        vm.stopPrank();
    }

    function deployMetastreetPool(address nft_, address tok) internal {
        vm.startPrank(users.deployer);

        address[] memory collateralTokens = new address[](1);
        collateralTokens[0] = nft_;

        /* Set pool parameters */
        bytes memory poolParams = abi.encode(collateralTokens, tok, address(0), DURATIONS, RATES);

        if (address(metastreetPool1) == address(0)) {
            /* Deploy pool proxy */
            metastreetPool1 = IPool(
                MetastreetPoolHelpers.METASTREET_POOL_FACTORY.createProxied(
                    MetastreetPoolHelpers.METASTREET_POOL_IMPL, poolParams
                )
            );
            vm.label({account: address(metastreetPool1), newLabel: "Pool1"});
        } else {
            /* Deploy pool proxy */
            metastreetPool2 = IPool(
                MetastreetPoolHelpers.METASTREET_POOL_FACTORY.createProxied(
                    MetastreetPoolHelpers.METASTREET_POOL_IMPL, poolParams
                )
            );
            vm.label({account: address(metastreetPool2), newLabel: "Pool2"});
        }

        vm.stopPrank();
    }

    function createLoan(IPool pool, address user, uint256 principal) internal returns (bytes memory loanReceipt) {
        uint128[] memory ticks = new uint128[](1);
        ticks[0] = TICK;

        vm.startPrank(user);
        vm.recordLogs();
        pool.borrow(principal, 30 days, address(nft), user == users.normalUser1 ? 123 : 124, principal * 2, ticks, "");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        vm.stopPrank();
        return abi.decode(entries[entries.length - 1].data, (bytes));
    }

    function repayLoan(IPool pool, address user, bytes memory loanReceipt) internal {
        vm.startPrank(user);
        pool.repay(loanReceipt);
        vm.stopPrank();
    }

    function createUser(
        string memory name
    ) internal returns (address payable addr) {
        addr = payable(makeAddr(name));
        vm.label({account: addr, newLabel: name});
        vm.deal({account: addr, newBalance: 100 ether});
    }

    function setApprovals() internal {
        address[] memory normalUsers = new address[](2);
        normalUsers[0] = users.normalUser1;
        normalUsers[1] = users.normalUser2;

        for (uint256 i = 0; i < normalUsers.length; i++) {
            vm.startPrank(normalUsers[i]);

            /* Set NFT approvals for all MS pools */
            if (address(metastreetPool1) != address(0)) {
                nft.setApprovalForAll(address(metastreetPool1), true);
                IERC20(WETH).approve(address(metastreetPool1), type(uint256).max);
                IERC20(USDT).approve(address(metastreetPool1), type(uint256).max);
            }
            if (address(metastreetPool2) != address(0)) {
                nft.setApprovalForAll(address(metastreetPool2), true);
                IERC20(WETH).approve(address(metastreetPool2), type(uint256).max);
                IERC20(USDT).approve(address(metastreetPool2), type(uint256).max);
            }

            /* Approve tokens */
            usd.approve(address(usdai), type(uint256).max);
            usdai.approve(address(stakedUsdai), type(uint256).max);

            vm.stopPrank();
        }
    }

    function simulateYieldDeposit(
        uint256 amount
    ) internal {
        vm.startPrank(users.manager);
        usd.approve(address(usdai), amount * 2);

        // User deposits USD into USDai
        usdai.deposit(address(usd), amount * 2, amount, address(users.manager));

        /* Deposit into staked usdai */
        usdai.transfer(address(stakedUsdai), amount);

        vm.stopPrank();
    }

    function serviceRedemptionAndWarp(uint256 requestedShares, bool warp) internal returns (uint256) {
        vm.startPrank(users.manager);

        uint256 amountProcessed = stakedUsdai.serviceRedemptions(requestedShares);

        vm.stopPrank();

        // Warp past timelock
        if (warp) {
            vm.warp(block.timestamp + stakedUsdai.timelock() + 1);
        }

        return amountProcessed;
    }

    function updateMTokenIndex() internal {
        uint256 currentIndex = WRAPPED_M_TOKEN.currentIndex();

        vm.startPrank(M_PORTAL);
        (bool success,) = M_TOKEN.call(abi.encodeWithSignature("updateIndex(uint128)", currentIndex + 1000));
        require(success, "Update M token index failed");
        vm.stopPrank();
    }
}
