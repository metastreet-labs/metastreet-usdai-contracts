// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

// Forge imports
import "forge-std/console.sol";

// Test imports
import {IMintableBurnable} from "src/interfaces/IMintableBurnable.sol";

// Implementation imports
import {OAdapter} from "src/omnichain/OAdapter.sol";
import {OToken} from "src/omnichain/OToken.sol";

// OApp imports
import {OptionsBuilder} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";

// OFT imports
import {IOFT, SendParam, OFTReceipt} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFTCore.sol";
import {MessagingFee, MessagingReceipt} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFTCore.sol";
import {RateLimiter} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/utils/RateLimiter.sol";

// OZ imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

// DevTools imports
import {TestHelperOz5} from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";

// Implementation imports
import {OUSDaiUtility} from "src/omnichain/OUSDaiUtility.sol";
import {USDaiQueuedDepositor} from "src/queuedDepositor/USDaiQueuedDepositor.sol";
import {ReceiptToken} from "src/queuedDepositor/ReceiptToken.sol";

// Mock imports
import {MockUSDai} from "../mocks/MockUSDai.sol";
import {MockStakedUSDai} from "../mocks/MockStakedUSDai.sol";

// Interface imports
import {IUSDai} from "src/interfaces/IUSDai.sol";
import {IStakedUSDai} from "src/interfaces/IStakedUSDai.sol";
import {IUSDaiQueuedDepositor} from "src/interfaces/IUSDaiQueuedDepositor.sol";

import {TestERC20} from "../tokens/TestERC20.sol";

/**
 * @title Omnichain Base test setup
 *
 * @author MetaStreet Foundation
 * @author Modified from https://github.com/PaulRBerg/prb-proxy/blob/main/test/Base.t.sol
 *
 */
abstract contract OmnichainBaseTest is TestHelperOz5 {
    using OptionsBuilder for bytes;

    IUSDaiQueuedDepositor internal usdaiQueuedDepositor;

    uint32 internal usdtHomeEid = 1;
    uint32 internal usdtAwayEid = 2;
    uint32 internal usdaiHomeEid = 3;
    uint32 internal usdaiAwayEid = 4;
    uint32 internal stakedUsdaiHomeEid = 5;
    uint32 internal stakedUsdaiAwayEid = 6;

    TestERC20 internal usdtHomeToken6Decimals;

    OToken internal usdtHomeToken;
    OToken internal usdtAwayToken;
    OToken internal usdaiAwayToken;
    OToken internal stakedUsdaiAwayToken;

    OAdapter internal usdtHomeOAdapter;
    OAdapter internal usdtAwayOAdapter;

    OAdapter internal usdaiHomeOAdapter;
    OAdapter internal usdaiAwayOAdapter;

    OAdapter internal stakedUsdaiHomeOAdapter;
    OAdapter internal stakedUsdaiAwayOAdapter;

    OUSDaiUtility internal oUsdaiUtility;

    uint256 internal initialBalance = 20_000_000 ether;

    IUSDai internal usdai;
    IStakedUSDai internal stakedUsdai;

    address internal user = address(0x1);
    address internal blacklistedUser = address(0x2);

    address internal queuedUSDaiToken;
    address internal queuedStakedUSDaiToken;

    function setUp() public virtual override {
        // Call the base setup function from the TestHelperOz5 contract
        TestHelperOz5.setUp();

        // Deploy mock USDai
        IUSDai usdaiImpl = new MockUSDai();

        /* Deploy usdai proxy */
        TransparentUpgradeableProxy usdaiProxy =
            new TransparentUpgradeableProxy(address(usdaiImpl), address(this), abi.encodeWithSignature("initialize()"));

        /* Cast usdai */
        usdai = IUSDai(address(usdaiProxy));

        // Deploy mock staked usdai implementation
        IStakedUSDai stakedUsdaiImpl = new MockStakedUSDai(address(usdai));

        /* Deploy staked usdai proxy */
        TransparentUpgradeableProxy stakedUsdaiProxy = new TransparentUpgradeableProxy(
            address(stakedUsdaiImpl), address(this), abi.encodeWithSignature("initialize(uint64)", 0)
        );

        /* Cast staked usdai */
        stakedUsdai = IStakedUSDai(address(stakedUsdaiProxy));

        // Provide initial Ether balances to users for testing purposes
        vm.deal(user, 1000 ether);
        vm.deal(blacklistedUser, 1000 ether);

        // Initialize 6 endpoints, using UltraLightNode as the library type
        setUpEndpoints(6, LibraryType.UltraLightNode);

        // Deploy tokens
        OToken usdtHomeTokenImpl = new OToken();
        OToken usdtAwayTokenImpl = new OToken();
        OToken usdaiAwayTokenImpl = new OToken();
        OToken stakedUsdaiAwayTokenImpl = new OToken();

        vm.prank(user);
        usdtHomeToken6Decimals = new TestERC20("USDT Home Token", "USDT", 6, initialBalance / 1e12);

        // Deploy USDT proxies
        TransparentUpgradeableProxy usdtHomeTokenProxy = new TransparentUpgradeableProxy(
            address(usdtHomeTokenImpl),
            address(this),
            abi.encodeWithSignature(
                "initialize(string,string,address)", "usdtHomeToken", "usdtHomeToken", address(this)
            )
        );
        TransparentUpgradeableProxy usdtAwayTokenProxy = new TransparentUpgradeableProxy(
            address(usdtAwayTokenImpl),
            address(this),
            abi.encodeWithSignature(
                "initialize(string,string,address)", "usdtAwayToken", "usdtAwayToken", address(this)
            )
        );
        TransparentUpgradeableProxy usdaiAwayTokenProxy = new TransparentUpgradeableProxy(
            address(usdaiAwayTokenImpl),
            address(this),
            abi.encodeWithSignature(
                "initialize(string,string,address)", "usdaiAwayToken", "usdaiAwayToken", address(this)
            )
        );
        TransparentUpgradeableProxy stakedUsdaiAwayTokenProxy = new TransparentUpgradeableProxy(
            address(stakedUsdaiAwayTokenImpl),
            address(this),
            abi.encodeWithSignature(
                "initialize(string,string,address)", "stakedUsdaiAwayToken", "stakedUsdaiAwayToken", address(this)
            )
        );
        usdtHomeToken = OToken(address(usdtHomeTokenProxy));
        usdtAwayToken = OToken(address(usdtAwayTokenProxy));
        usdaiAwayToken = OToken(address(usdaiAwayTokenProxy));
        stakedUsdaiAwayToken = OToken(address(stakedUsdaiAwayTokenProxy));

        // Deploy USDT rate limit configs
        RateLimiter.RateLimitConfig[] memory rateLimitConfigsUsdtHome = new RateLimiter.RateLimitConfig[](1);
        rateLimitConfigsUsdtHome[0] =
            RateLimiter.RateLimitConfig({dstEid: usdtAwayEid, limit: initialBalance, window: 1 days});
        RateLimiter.RateLimitConfig[] memory rateLimitConfigsUsdtAway = new RateLimiter.RateLimitConfig[](1);
        rateLimitConfigsUsdtAway[0] =
            RateLimiter.RateLimitConfig({dstEid: usdtHomeEid, limit: initialBalance, window: 1 days});

        // Deploy USDAI rate limit configs
        RateLimiter.RateLimitConfig[] memory rateLimitConfigsUsdaiHome = new RateLimiter.RateLimitConfig[](1);
        rateLimitConfigsUsdaiHome[0] =
            RateLimiter.RateLimitConfig({dstEid: usdaiAwayEid, limit: initialBalance, window: 1 days});
        RateLimiter.RateLimitConfig[] memory rateLimitConfigsUsdaiAway = new RateLimiter.RateLimitConfig[](1);
        rateLimitConfigsUsdaiAway[0] =
            RateLimiter.RateLimitConfig({dstEid: usdaiHomeEid, limit: initialBalance, window: 1 days});

        // Deploy staked USDAI rate limit configs
        RateLimiter.RateLimitConfig[] memory rateLimitConfigsStakedUsdaiHome = new RateLimiter.RateLimitConfig[](1);
        rateLimitConfigsStakedUsdaiHome[0] =
            RateLimiter.RateLimitConfig({dstEid: stakedUsdaiAwayEid, limit: initialBalance, window: 1 days});
        RateLimiter.RateLimitConfig[] memory rateLimitConfigsStakedUsdaiAway = new RateLimiter.RateLimitConfig[](1);
        rateLimitConfigsStakedUsdaiAway[0] =
            RateLimiter.RateLimitConfig({dstEid: stakedUsdaiHomeEid, limit: initialBalance, window: 1 days});

        // Deploy two instances of USDT OAdapter for testing, associating them with respective endpoints
        usdtHomeOAdapter = OAdapter(
            _deployOApp(
                type(OAdapter).creationCode,
                abi.encode(address(usdtHomeToken), address(endpoints[usdtHomeEid]), address(this))
            )
        );
        usdtAwayOAdapter = OAdapter(
            _deployOApp(
                type(OAdapter).creationCode,
                abi.encode(address(usdtAwayToken), address(endpoints[usdtAwayEid]), address(this))
            )
        );
        usdtHomeOAdapter.setRateLimits(rateLimitConfigsUsdtHome);
        usdtAwayOAdapter.setRateLimits(rateLimitConfigsUsdtAway);

        // Deploy two instances of USDAI OAdapter for testing, associating them with respective endpoints
        usdaiHomeOAdapter = OAdapter(
            _deployOApp(
                type(OAdapter).creationCode, abi.encode(address(usdai), address(endpoints[usdaiHomeEid]), address(this))
            )
        );
        usdaiAwayOAdapter = OAdapter(
            _deployOApp(
                type(OAdapter).creationCode,
                abi.encode(address(usdaiAwayToken), address(endpoints[usdaiAwayEid]), address(this))
            )
        );
        usdaiHomeOAdapter.setRateLimits(rateLimitConfigsUsdaiHome);
        usdaiAwayOAdapter.setRateLimits(rateLimitConfigsUsdaiAway);

        // Deploy two instances of staked USDAI OAdapter for testing, associating them with respective endpoints
        stakedUsdaiHomeOAdapter = OAdapter(
            _deployOApp(
                type(OAdapter).creationCode,
                abi.encode(address(stakedUsdai), address(endpoints[stakedUsdaiHomeEid]), address(this))
            )
        );
        stakedUsdaiAwayOAdapter = OAdapter(
            _deployOApp(
                type(OAdapter).creationCode,
                abi.encode(address(stakedUsdaiAwayToken), address(endpoints[stakedUsdaiAwayEid]), address(this))
            )
        );
        stakedUsdaiHomeOAdapter.setRateLimits(rateLimitConfigsStakedUsdaiHome);
        stakedUsdaiAwayOAdapter.setRateLimits(rateLimitConfigsStakedUsdaiAway);

        // Deploy receipt tokens
        ReceiptToken receiptTokenImpl = new ReceiptToken();

        // Deploy usdai queued depositor
        address usdaiQueuedDepositorImpl = address(
            new USDaiQueuedDepositor(
                address(usdai),
                address(stakedUsdai),
                address(usdaiHomeOAdapter),
                address(stakedUsdaiHomeOAdapter),
                address(receiptTokenImpl)
            )
        );

        /* Deploy usdai queued depositor proxy */
        address[] memory whitelistedTokens = new address[](2);
        whitelistedTokens[0] = address(usdtHomeToken);
        whitelistedTokens[1] = address(usdtHomeToken6Decimals);
        uint256[] memory minAmounts = new uint256[](2);
        minAmounts[0] = 1_000_000 * 1e18;
        minAmounts[1] = 1_000_000 * 1e6;
        TransparentUpgradeableProxy usdaiQueuedDepositorProxy = new TransparentUpgradeableProxy(
            usdaiQueuedDepositorImpl,
            address(this),
            abi.encodeWithSignature(
                "initialize(address,address[],uint256[])", address(this), whitelistedTokens, minAmounts
            )
        );
        usdaiQueuedDepositor = USDaiQueuedDepositor(address(usdaiQueuedDepositorProxy));
        AccessControl(address(usdaiQueuedDepositor)).grantRole(keccak256("CONTROLLER_ADMIN_ROLE"), address(this));
        queuedUSDaiToken = address(usdaiQueuedDepositor.queuedUSDaiToken());
        queuedStakedUSDaiToken = address(usdaiQueuedDepositor.queuedStakedUSDaiToken());

        // Configure and wire the USDT OAdapters together
        address[] memory oAdapters = new address[](6);
        oAdapters[0] = address(usdtHomeOAdapter);
        oAdapters[1] = address(usdtAwayOAdapter);
        oAdapters[2] = address(usdaiHomeOAdapter);
        oAdapters[3] = address(usdaiAwayOAdapter);
        oAdapters[4] = address(stakedUsdaiHomeOAdapter);
        oAdapters[5] = address(stakedUsdaiAwayOAdapter);
        this.wireOApps(oAdapters);

        // Deploy the composer receiver
        address[] memory oAdaptersUtility = new address[](1);
        oAdaptersUtility[0] = address(usdtHomeOAdapter);
        OUSDaiUtility oUsdaiUtilityImpl = new OUSDaiUtility(
            address(endpoints[usdtHomeEid]),
            address(usdai),
            address(stakedUsdai),
            address(usdaiHomeOAdapter),
            address(stakedUsdaiHomeOAdapter),
            address(usdaiQueuedDepositor)
        );
        TransparentUpgradeableProxy oUsdaiUtilityProxy = new TransparentUpgradeableProxy(
            address(oUsdaiUtilityImpl),
            address(this),
            abi.encodeWithSignature("initialize(address,address[])", address(this), oAdaptersUtility)
        );
        oUsdaiUtility = OUSDaiUtility(payable(address(oUsdaiUtilityProxy)));

        // Grant minter roles
        AccessControl(address(usdtHomeToken)).grantRole(usdtHomeToken.BRIDGE_ADMIN_ROLE(), address(usdtHomeOAdapter));
        AccessControl(address(usdtAwayToken)).grantRole(usdtAwayToken.BRIDGE_ADMIN_ROLE(), address(usdtAwayOAdapter));

        // Grant bridge admin roles for USDAI and staked USDAI
        AccessControl(address(usdai)).grantRole(keccak256("BRIDGE_ADMIN_ROLE"), address(usdaiHomeOAdapter));
        AccessControl(address(usdaiAwayToken)).grantRole(keccak256("BRIDGE_ADMIN_ROLE"), address(usdaiAwayOAdapter));
        AccessControl(address(stakedUsdai)).grantRole(keccak256("BRIDGE_ADMIN_ROLE"), address(stakedUsdaiHomeOAdapter));
        AccessControl(address(stakedUsdaiAwayToken)).grantRole(
            keccak256("BRIDGE_ADMIN_ROLE"), address(stakedUsdaiAwayOAdapter)
        );

        // Mint tokens to users
        AccessControl(address(usdtAwayToken)).grantRole(usdtAwayToken.BRIDGE_ADMIN_ROLE(), address(this));
        usdtAwayToken.mint(user, initialBalance);
        usdtAwayToken.mint(blacklistedUser, initialBalance);
        AccessControl(address(usdtHomeToken)).grantRole(usdtHomeToken.BRIDGE_ADMIN_ROLE(), address(this));
        usdtHomeToken.mint(user, initialBalance);

        // Set user as blacklisted
        AccessControl(address(stakedUsdai)).grantRole(keccak256("BLACKLIST_ADMIN_ROLE"), address(this));
        stakedUsdai.setBlacklist(blacklistedUser, true);
    }
}
