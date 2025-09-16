// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.29;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {ISwapRouter02} from "../../src/interfaces/external/ISwapRouter02.sol";

interface INonfungiblePositionManager {
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    function mint(
        MintParams calldata params
    ) external payable returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
}

library UniswapPoolHelpers {
    /* Uniswap V3 Factory address on Arbitrum */
    IUniswapV3Factory internal constant UNISWAP_V3_FACTORY =
        IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);

    /* Uniswap V3 Router address on Arbitrum */
    ISwapRouter02 internal constant UNISWAP_ROUTER = ISwapRouter02(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45);

    INonfungiblePositionManager internal constant NONFUNGIBLE_POSITION_MANAGER =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

    uint256 internal constant MAX_TICK = 887272;

    function setupUniswapPool(
        address user,
        address tok1,
        address tok2,
        uint256 tok1Amount,
        uint256 tok2Amount
    ) internal {
        // Create the pool with 0.3% fee tier
        address poolAddress = UNISWAP_V3_FACTORY.createPool(
            tok1,
            tok2,
            100 // 0.1% fee tier
        );
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);

        // Initialize pool with a price of 1:1
        pool.initialize(getSqrtRatioAtTick(0));

        (address token0, address token1) = tok1 < tok2 ? (tok1, tok2) : (tok2, tok1);

        (uint256 amount0, uint256 amount1) = tok1 < tok2 ? (tok1Amount, tok2Amount) : (tok2Amount, tok1Amount);

        // Approve tokens
        IERC20(tok1).approve(address(NONFUNGIBLE_POSITION_MANAGER), type(uint256).max);
        IERC20(tok2).approve(address(NONFUNGIBLE_POSITION_MANAGER), type(uint256).max);

        // Add liquidity parameters
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: token0,
            token1: token1,
            fee: 100,
            tickLower: -1, // Approx price range 0.1 to 10
            tickUpper: 1,
            amount0Desired: amount0,
            amount1Desired: amount1,
            amount0Min: 0,
            amount1Min: 0,
            recipient: user,
            deadline: block.timestamp + 1
        });

        // Add liquidity
        NONFUNGIBLE_POSITION_MANAGER.mint(params);
    }

    /// @notice Calculates sqrt(1.0001^tick) * 2^96
    /// @dev Throws if |tick| > max tick
    /// @param tick The input tick for the above formula
    /// @return sqrtPriceX96 A Fixed point Q64.96 number representing the sqrt of the ratio of the two assets
    /// (token1/token0)
    /// at the given tick
    function getSqrtRatioAtTick(
        int24 tick
    ) internal pure returns (uint160 sqrtPriceX96) {
        uint256 absTick = tick < 0 ? uint256(-int256(tick)) : uint256(int256(tick));
        require(absTick <= uint256(MAX_TICK), "T");

        uint256 ratio = absTick & 0x1 != 0 ? 0xfffcb933bd6fad37aa2d162d1a594001 : 0x100000000000000000000000000000000;
        if (absTick & 0x2 != 0) {
            ratio = (ratio * 0xfff97272373d413259a46990580e213a) >> 128;
        }
        if (absTick & 0x4 != 0) {
            ratio = (ratio * 0xfff2e50f5f656932ef12357cf3c7fdcc) >> 128;
        }
        if (absTick & 0x8 != 0) {
            ratio = (ratio * 0xffe5caca7e10e4e61c3624eaa0941cd0) >> 128;
        }
        if (absTick & 0x10 != 0) {
            ratio = (ratio * 0xffcb9843d60f6159c9db58835c926644) >> 128;
        }
        if (absTick & 0x20 != 0) {
            ratio = (ratio * 0xff973b41fa98c081472e6896dfb254c0) >> 128;
        }
        if (absTick & 0x40 != 0) {
            ratio = (ratio * 0xff2ea16466c96a3843ec78b326b52861) >> 128;
        }
        if (absTick & 0x80 != 0) {
            ratio = (ratio * 0xfe5dee046a99a2a811c461f1969c3053) >> 128;
        }
        if (absTick & 0x100 != 0) {
            ratio = (ratio * 0xfcbe86c7900a88aedcffc83b479aa3a4) >> 128;
        }
        if (absTick & 0x200 != 0) {
            ratio = (ratio * 0xf987a7253ac413176f2b074cf7815e54) >> 128;
        }
        if (absTick & 0x400 != 0) {
            ratio = (ratio * 0xf3392b0822b70005940c7a398e4b70f3) >> 128;
        }
        if (absTick & 0x800 != 0) {
            ratio = (ratio * 0xe7159475a2c29b7443b29c7fa6e889d9) >> 128;
        }
        if (absTick & 0x1000 != 0) {
            ratio = (ratio * 0xd097f3bdfd2022b8845ad8f792aa5825) >> 128;
        }
        if (absTick & 0x2000 != 0) {
            ratio = (ratio * 0xa9f746462d870fdf8a65dc1f90e061e5) >> 128;
        }
        if (absTick & 0x4000 != 0) {
            ratio = (ratio * 0x70d869a156d2a1b890bb3df62baf32f7) >> 128;
        }
        if (absTick & 0x8000 != 0) {
            ratio = (ratio * 0x31be135f97d08fd981231505542fcfa6) >> 128;
        }
        if (absTick & 0x10000 != 0) {
            ratio = (ratio * 0x9aa508b5b7a84e1c677de54f3e99bc9) >> 128;
        }
        if (absTick & 0x20000 != 0) {
            ratio = (ratio * 0x5d6af8dedb81196699c329225ee604) >> 128;
        }
        if (absTick & 0x40000 != 0) {
            ratio = (ratio * 0x2216e584f5fa1ea926041bedfe98) >> 128;
        }
        if (absTick & 0x80000 != 0) {
            ratio = (ratio * 0x48a170391f7dc42444e8fa2) >> 128;
        }

        if (tick > 0) ratio = type(uint256).max / ratio;

        // this divides by 1<<32 rounding up to go from a Q128.128 to a Q128.96.
        // we then downcast because we know the result always fits within 160 bits due to our tick input constraint
        // we round up in the division so getTickAtSqrtRatio of the output price is always consistent
        sqrtPriceX96 = uint160((ratio >> 32) + (ratio % (1 << 32) == 0 ? 0 : 1));
    }
}
