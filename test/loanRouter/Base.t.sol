// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {StakedUSDai} from "src/StakedUSDai.sol";
import {IUSDai} from "src/interfaces/IUSDai.sol";
import {IPriceOracle} from "src/interfaces/IPriceOracle.sol";

import {LoanRouter} from "lib/metastreet-usdai-loan-router/src/LoanRouter.sol";
import {DepositTimelock} from "lib/metastreet-usdai-loan-router/src/DepositTimelock.sol";
import {SimpleInterestRateModel} from "lib/metastreet-usdai-loan-router/src/rates/SimpleInterestRateModel.sol";
import {USDaiSwapAdapter} from "lib/metastreet-usdai-loan-router/src/swapAdapters/USDaiSwapAdapter.sol";
import {ILoanRouter} from "@metastreet-usdai-loan-router/interfaces/ILoanRouter.sol";

import {TestERC721} from "test/tokens/TestERC721.sol";

/**
 * @title Base test setup for LoanRouter Position Manager
 * @author MetaStreet Foundation
 */
abstract contract BaseLoanRouterTest is Test {
    /*------------------------------------------------------------------------*/
    /* Constants */
    /*------------------------------------------------------------------------*/

    /* Arbitrum Mainnet addresses */
    address internal constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address internal constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address internal constant USDAI = 0x0A1a1A107E45b7Ced86833863f482BC5f4ed82EF;
    address internal constant STAKED_USDAI_PROXY = 0x0B2b2B2076d95dda7817e785989fE353fe955ef9;
    address internal constant WRAPPED_M_TOKEN = 0x437cc33344a0B27A429f795ff6B469C72698B291;
    address internal constant COLLATERAL_WRAPPER = 0xC2356bf42c8910fD6c28Ee6C843bc0E476ee5D26;
    address internal constant ENGLISH_AUCTION_LIQUIDATOR = 0xceb5856C525bbb654EEA75A8852A0F51073C4a58;
    address internal constant BASE_YIELD_ADMIN_FEE_RECIPIENT = 0x5F0BC72FB5952b2f3F2E11404398eD507B25841F;
    address internal constant PRICE_ORACLE = 0xeC335fb6151354c74A8f97E84E770377945D00B3;

    /* Time constants */
    uint64 internal constant LOAN_DURATION = 1080 days; // 3 years - 5 days
    uint64 internal constant REPAYMENT_INTERVAL = 30 days;
    uint64 internal constant GRACE_PERIOD_DURATION = 30 days;

    /* Rate constants (per second) */
    // 5% per annum = 0.05 / (365 * 86400) = ~1.585e-9 per second
    uint256 internal constant GRACE_PERIOD_RATE = 1585489599; // 5% APR in per-second rate (scaled by 1e18)

    // Interest rates for tranches (per second, scaled by 1e18)
    // 10% APR = ~3.171e-9 per second = 3171469679 (scaled by 1e18)
    uint256 internal constant RATE_10_PCT = 3171469679;

    /* Fixed point scale */
    uint256 internal constant FIXED_POINT_SCALE = 1e18;

    /* Number of token IDs to wrap */
    uint256 internal constant NUM_TOKEN_IDS = 128;

    /* Admin fee rate for loan router (10%) */
    uint256 internal constant LOAN_ROUTER_ADMIN_FEE_RATE = 1000; // 10% in basis points

    /* Basis points scale */
    uint256 internal constant BASIS_POINTS_SCALE = 10_000;

    /*------------------------------------------------------------------------*/
    /* User accounts */
    /*------------------------------------------------------------------------*/

    struct Users {
        address payable deployer;
        address payable admin;
        address payable proxyAdmin;
        address payable feeRecipient;
        address payable borrower;
        address payable strategyAdmin;
    }

    Users internal users;

    /*------------------------------------------------------------------------*/
    /* Contract instances */
    /*------------------------------------------------------------------------*/

    LoanRouter internal loanRouterImpl;
    LoanRouter internal loanRouter;
    TransparentUpgradeableProxy internal loanRouterProxy;

    DepositTimelock internal depositTimelockImpl;
    DepositTimelock internal depositTimelock;
    TransparentUpgradeableProxy internal depositTimelockProxy;

    SimpleInterestRateModel internal interestRateModel;
    USDaiSwapAdapter internal usdaiSwapAdapter;

    StakedUSDai internal stakedUsdai;
    StakedUSDai internal stakedUsdaiImpl;
    IUSDai internal usdai;
    IPriceOracle internal priceOracle;

    TestERC721 internal testNFT;

    /*------------------------------------------------------------------------*/
    /* Test state */
    /*------------------------------------------------------------------------*/

    uint256 internal wrappedTokenId;
    uint256[] internal tokenIdsToWrap;
    bytes internal encodedBundle;

    // Second bundle for multi-loan tests
    uint256 internal wrappedTokenId2;
    uint256[] internal tokenIdsToWrap2;
    bytes internal encodedBundle2;

    /*------------------------------------------------------------------------*/
    /* Setup */
    /*------------------------------------------------------------------------*/

    function setUp() public virtual {
        // Fork Arbitrum mainnet
        vm.createSelectFork(vm.envString("ARBITRUM_RPC_URL"));
        vm.rollFork(391521225);

        // Create users
        users = Users({
            deployer: createUser("deployer"),
            admin: createUser("admin"),
            proxyAdmin: createUser("proxyAdmin"),
            feeRecipient: createUser("feeRecipient"),
            borrower: createUser("borrower"),
            strategyAdmin: createUser("strategyAdmin")
        });

        // Get existing contracts
        usdai = IUSDai(USDAI);
        stakedUsdai = StakedUSDai(STAKED_USDAI_PROXY);
        priceOracle = IPriceOracle(PRICE_ORACLE);

        // Deploy test NFT
        deployTestNFT();

        // Deploy LoanRouter contracts
        deployDepositTimelock();
        deployLoanRouter();
        deployInterestRateModel();
        deployUSDaiSwapAdapter();

        // Upgrade StakedUSDai
        upgradeStakedUSDai();

        // Seed deposits balance
        seedDepositsBalance();

        // Setup
        setupCollateralWrapper();
        fundUsers();
        setApprovals();
    }

    /*------------------------------------------------------------------------*/
    /* Deployment functions */
    /*------------------------------------------------------------------------*/

    function deployDepositTimelock() internal {
        vm.startPrank(users.deployer);

        // Deploy implementation
        depositTimelockImpl = new DepositTimelock();

        // Deploy proxy
        depositTimelockProxy = new TransparentUpgradeableProxy(
            address(depositTimelockImpl),
            address(users.proxyAdmin),
            abi.encodeWithSignature("initialize(address)", users.deployer)
        );

        // Create interface
        depositTimelock = DepositTimelock(address(depositTimelockProxy));

        vm.stopPrank();
    }

    function deployLoanRouter() internal {
        vm.startPrank(users.deployer);

        // Deploy implementation
        loanRouterImpl = new LoanRouter(ENGLISH_AUCTION_LIQUIDATOR, COLLATERAL_WRAPPER, address(depositTimelock));

        // Deploy proxy
        loanRouterProxy = new TransparentUpgradeableProxy(
            address(loanRouterImpl),
            address(users.proxyAdmin),
            abi.encodeWithSignature("initialize(address,address,uint256)", users.deployer, users.feeRecipient, 1000)
        );

        // Create interface
        loanRouter = LoanRouter(address(loanRouterProxy));

        vm.stopPrank();
    }

    function deployInterestRateModel() internal {
        vm.startPrank(users.deployer);
        interestRateModel = new SimpleInterestRateModel();
        vm.stopPrank();
    }

    function deployUSDaiSwapAdapter() internal {
        vm.startPrank(users.deployer);
        usdaiSwapAdapter = new USDaiSwapAdapter(USDAI);
        vm.stopPrank();
    }

    function deployTestNFT() internal {
        vm.startPrank(users.deployer);
        testNFT = new TestERC721("TestNFT", "TNFT", "https://testnft.com/token/");
        vm.stopPrank();
    }

    function upgradeStakedUSDai() internal {
        // Get proxy admin from EIP-1967 storage slot
        address proxyAdminAddress = address(
            uint160(uint256(vm.load(STAKED_USDAI_PROXY, bytes32(uint256(keccak256("eip1967.proxy.admin")) - 1))))
        );

        // Known ProxyAdmin owner (verified from mainnet)
        address proxyAdminOwner = 0x783B08aA21DE056717173f72E04Be0E91328A07b;

        // Deploy new implementation with LoanRouterPositionManager
        vm.startPrank(users.deployer);
        stakedUsdaiImpl = new StakedUSDai(
            USDAI,
            WRAPPED_M_TOKEN,
            100, // baseYieldAdminFeeRate
            BASE_YIELD_ADMIN_FEE_RECIPIENT,
            address(priceOracle),
            address(loanRouter),
            LOAN_ROUTER_ADMIN_FEE_RATE,
            uint64(block.timestamp)
        );
        vm.stopPrank();

        // Upgrade proxy using ProxyAdmin interface
        vm.startPrank(proxyAdminOwner);
        ProxyAdmin(proxyAdminAddress).upgradeAndCall(
            ITransparentUpgradeableProxy(STAKED_USDAI_PROXY), address(stakedUsdaiImpl), ""
        );
        vm.stopPrank();

        // Update reference
        stakedUsdai = StakedUSDai(STAKED_USDAI_PROXY);

        // Set strategy admin to the existing mainnet strategy admin
        users.strategyAdmin = payable(0xe7E53F940F8242fec57CBE88054463d4944B3670);
    }

    function seedDepositsBalance() internal {
        bytes32 depositsStorageLocation = 0x2c5de62bb029e52f8f5651820547ac44294b098c752111b71e5fee4f80a66900;
        uint256 currentBalance = uint256(vm.load(address(stakedUsdai), depositsStorageLocation));
        vm.store(address(stakedUsdai), depositsStorageLocation, bytes32(usdai.balanceOf(address(stakedUsdai))));
    }

    /*------------------------------------------------------------------------*/
    /* Setup functions */
    /*------------------------------------------------------------------------*/

    function setupCollateralWrapper() internal {
        // Mint NFTs to borrower
        vm.startPrank(users.deployer);

        // Create first array of token IDs to wrap
        tokenIdsToWrap = new uint256[](NUM_TOKEN_IDS);
        for (uint256 i = 0; i < NUM_TOKEN_IDS; i++) {
            uint256 tokenId = 1000 + i;
            testNFT.mint(users.borrower, tokenId);
            tokenIdsToWrap[i] = tokenId;
        }

        // Create second array of token IDs to wrap
        tokenIdsToWrap2 = new uint256[](NUM_TOKEN_IDS);
        for (uint256 i = 0; i < NUM_TOKEN_IDS; i++) {
            uint256 tokenId = 2000 + i;
            testNFT.mint(users.borrower, tokenId);
            tokenIdsToWrap2[i] = tokenId;
        }

        vm.stopPrank();

        // Wrap first bundle
        vm.startPrank(users.borrower);

        // Approve collateral wrapper to transfer NFTs
        testNFT.setApprovalForAll(COLLATERAL_WRAPPER, true);

        // Record logs to capture BundleMinted event
        vm.recordLogs();

        // Mint first bundle (wrap NFTs)
        (bool success, bytes memory data) = COLLATERAL_WRAPPER.call(
            abi.encodeWithSignature("mint(address,uint256[])", address(testNFT), tokenIdsToWrap)
        );
        require(success, "Failed to mint bundle");

        // Decode wrapped token ID
        wrappedTokenId = abi.decode(data, (uint256));

        // Get the BundleMinted event and extract encodedBundle
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("BundleMinted(uint256,address,bytes)")) {
                encodedBundle = abi.decode(logs[i].data, (bytes));
                break;
            }
        }

        require(encodedBundle.length > 0, "Failed to capture encodedBundle from event");

        // Wrap second bundle
        vm.recordLogs();

        // Mint second bundle (wrap NFTs)
        (bool success2, bytes memory data2) = COLLATERAL_WRAPPER.call(
            abi.encodeWithSignature("mint(address,uint256[])", address(testNFT), tokenIdsToWrap2)
        );
        require(success2, "Failed to mint bundle 2");

        // Decode second wrapped token ID
        wrappedTokenId2 = abi.decode(data2, (uint256));

        // Get the BundleMinted event and extract encodedBundle2
        Vm.Log[] memory logs2 = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs2.length; i++) {
            if (logs2[i].topics[0] == keccak256("BundleMinted(uint256,address,bytes)")) {
                encodedBundle2 = abi.decode(logs2[i].data, (bytes));
                break;
            }
        }

        require(encodedBundle2.length > 0, "Failed to capture encodedBundle2 from event");

        vm.stopPrank();
    }

    function fundUsers() internal {
        // Give borrower USDC
        deal(USDC, users.borrower, 10_000_000 * 1e6); // 10M USDC
    }

    function setApprovals() internal {
        // Borrower approvals
        vm.startPrank(users.borrower);
        IERC721(COLLATERAL_WRAPPER).setApprovalForAll(address(loanRouter), true);
        IERC20(USDC).approve(address(loanRouter), type(uint256).max);
        vm.stopPrank();

        // StakedUSDai needs to approve DepositTimelock to spend its USDai
        // We do this by pranking as the StakedUSDai contract itself
        vm.prank(address(stakedUsdai));
        IERC20(USDAI).approve(address(depositTimelock), type(uint256).max);

        // Setup swap adapter for USDAI in deposit timelock
        vm.startPrank(users.deployer);
        depositTimelock.addSwapAdapter(USDAI, address(usdaiSwapAdapter));
        vm.stopPrank();
    }

    /*------------------------------------------------------------------------*/
    /* Helper functions */
    /*------------------------------------------------------------------------*/

    function createUser(
        string memory name
    ) internal returns (address payable addr) {
        addr = payable(makeAddr(name));
        vm.label({account: addr, newLabel: name});
        vm.deal({account: addr, newBalance: 100 ether});
    }

    function createLoanTerms(
        uint256 principal
    ) internal view returns (ILoanRouter.LoanTerms memory) {
        return createLoanTerms(principal, wrappedTokenId, encodedBundle);
    }

    function createLoanTerms(
        uint256 principal,
        uint256 _wrappedTokenId,
        bytes memory _encodedBundle
    ) internal view returns (ILoanRouter.LoanTerms memory) {
        ILoanRouter.TrancheSpec[] memory trancheSpecs = new ILoanRouter.TrancheSpec[](1);

        trancheSpecs[0] = ILoanRouter.TrancheSpec({lender: address(stakedUsdai), amount: principal, rate: RATE_10_PCT});

        return ILoanRouter.LoanTerms({
            expiration: uint64(block.timestamp + 7 days),
            borrower: users.borrower,
            currencyToken: USDC,
            collateralToken: COLLATERAL_WRAPPER,
            collateralTokenId: _wrappedTokenId,
            duration: LOAN_DURATION,
            repaymentInterval: REPAYMENT_INTERVAL,
            interestRateModel: address(interestRateModel),
            gracePeriodRate: GRACE_PERIOD_RATE,
            gracePeriodDuration: uint256(GRACE_PERIOD_DURATION),
            feeSpec: ILoanRouter.FeeSpec({
                originationFee: principal / 100, // 1% origination fee
                exitFee: 0
            }),
            trancheSpecs: trancheSpecs,
            collateralWrapperContext: _encodedBundle,
            options: ""
        });
    }

    function warp(
        uint256 timeInSeconds
    ) internal {
        vm.warp(block.timestamp + timeInSeconds);
    }

    function calculateExpectedInterest(
        uint256 principal,
        uint256 rate,
        uint256 duration
    ) internal pure returns (uint256) {
        return (principal * rate * duration) / FIXED_POINT_SCALE;
    }
}
