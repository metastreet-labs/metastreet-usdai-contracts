// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.29;

import {ILiquidity} from "metastreet-contracts-v2/interfaces/ILiquidity.sol";
import {IPool} from "metastreet-contracts-v2/interfaces/IPool.sol";
import {IPoolFactory} from "metastreet-contracts-v2/interfaces/IPoolFactory.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

error INSUFFICIENT_LIQUIDITY(uint256 amount);
error INVALID_TICK_PARAMETERS();

library MetastreetPoolHelpers {
    /* Metastreet Pool factory */
    IPoolFactory internal constant METASTREET_POOL_FACTORY = IPoolFactory(0x41cF7ea4Ba650191e829A6bD31B9e2049C78D858);

    address internal constant METASTREET_POOL_IMPL = 0x34F753B7A1A9CE68d276dc4F6Ec6E5061a22C022;

    enum LimitType {
        Absolute,
        Ratio
    }

    uint256 internal constant FIXED_POINT_SCALE = 1e18;
    uint256 internal constant BASIS_POINTS_SCALE = 10_000;

    uint128 internal constant TICK_LIMIT_SHIFT = 8;
    uint256 internal constant TICK_LIMIT_MASK = 0xffffffffffffffffffffffffffffff;
    uint128 internal constant TICK_DURATION_SHIFT = 5;
    uint256 internal constant TICK_DURATION_MASK = 0x7;
    uint128 internal constant TICK_RATE_SHIFT = 2;
    uint256 internal constant TICK_RATE_MASK = 0x7;
    uint128 internal constant TICK_LIMIT_TYPE_SHIFT = 0;
    uint256 internal constant TICK_LIMIT_TYPE_MASK = 0x3;

    /*--------------------------------------------------------------------------*/
    /* Internal Helpers                                                         */
    /*--------------------------------------------------------------------------*/

    function _getDurationIdx(IPool pool, uint64 duration) internal view returns (uint256) {
        uint64[] memory durations = pool.durations();
        uint256 durationIdx;
        while (durationIdx < durations.length) {
            if (duration > durations[durationIdx]) break;
            durationIdx++;
        }

        return durationIdx;
    }

    function _computePrice(
        ILiquidity.NodeInfo memory node,
        ILiquidity.AccrualInfo memory accrual
    ) internal view returns (uint256) {
        accrual.accrued += accrual.rate * uint128(block.timestamp - accrual.timestamp);

        return node.shares == 0
            ? FIXED_POINT_SCALE
            : (Math.min(node.value + accrual.accrued, node.available + node.pending) * FIXED_POINT_SCALE) / node.shares;
    }

    /*--------------------------------------------------------------------------*/
    /* Helper Functions                                                         */
    /*--------------------------------------------------------------------------*/

    function normalizeRate(
        uint64 rate
    ) internal pure returns (uint64) {
        return rate / (365 * 86_400);
    }

    function encodeTick(
        uint256 limit,
        uint256 durationIdx,
        uint256 rateIdx,
        uint256 limitType
    ) internal pure returns (uint128) {
        if (limit > type(uint128).max || durationIdx > 7 || rateIdx > 7 || limitType > 1) {
            revert INVALID_TICK_PARAMETERS();
        }

        uint128 encodedTick;

        encodedTick |= uint128(limit) << TICK_LIMIT_SHIFT;
        encodedTick |= uint128(durationIdx) << TICK_DURATION_SHIFT;
        encodedTick |= uint128(rateIdx) << TICK_RATE_SHIFT;
        encodedTick |= uint128(limitType) << TICK_LIMIT_TYPE_SHIFT;

        return encodedTick;
    }

    /**
     * @dev Decode a Tick
     * @param tick Tick
     * @param oraclePrice Oracle price
     * @return limit Limit field
     * @return duration Duration field
     * @return rate Rate field
     * @return limitType Limit type field
     */
    function decodeTick(
        uint128 tick,
        uint256 oraclePrice
    ) internal pure returns (uint256 limit, uint256 duration, uint256 rate, LimitType limitType) {
        limit = ((tick >> TICK_LIMIT_SHIFT) & TICK_LIMIT_MASK);
        duration = ((tick >> TICK_DURATION_SHIFT) & TICK_DURATION_MASK);
        rate = ((tick >> TICK_RATE_SHIFT) & TICK_RATE_MASK);
        limitType = tick == type(uint128).max ? LimitType.Absolute : LimitType(tick & TICK_LIMIT_TYPE_MASK);
        limit = limitType == LimitType.Ratio ? Math.mulDiv(oraclePrice, limit, BASIS_POINTS_SCALE) : limit;
    }

    function sourceLiquidity(
        IPool pool,
        uint256 amount,
        uint64 duration_,
        uint256 multiplier,
        uint256 oraclePrice
    ) internal view returns (uint128[] memory) {
        /* Get duration index */
        uint256 durationIdx = _getDurationIdx(pool, duration_);

        /* Get nodes */
        ILiquidity.NodeInfo[] memory nodes = ILiquidity(address(pool)).liquidityNodes(0, type(uint128).max);

        /* Count number of nodes with matching durations to size array */
        uint256 numNodes;
        for (uint256 i = 0; i < nodes.length; i++) {
            (uint256 limit, uint256 duration,,) = decodeTick(nodes[i].tick, oraclePrice);
            if (limit > 0 && duration == durationIdx) {
                numNodes++;
            }
        }

        uint128[] memory ticks = new uint128[](numNodes);

        uint256 taken = 0;
        uint256 j = 0;
        for (uint256 i = 0; i < nodes.length && taken != amount; i++) {
            (uint256 limit, uint256 duration,,) = decodeTick(nodes[i].tick, oraclePrice);

            if (limit > 0 && durationIdx == duration) {
                uint128 take =
                    uint128(Math.min(Math.min(limit * multiplier - taken, nodes[i].available), amount - taken));
                if (take > 0) {
                    ticks[j] = nodes[i].tick;
                    taken += take;

                    j++;
                }
            }
        }

        if (taken != amount) revert INSUFFICIENT_LIQUIDITY(amount);

        return ticks;
    }

    function getMaximumLimit(IPool pool, uint64 duration_, uint256 oraclePrice) internal view returns (uint128) {
        /* Get duration index */
        uint256 durationIdx = _getDurationIdx(pool, duration_);

        ILiquidity.NodeInfo[] memory nodes = ILiquidity(address(pool)).liquidityNodes(0, type(uint128).max);

        uint128 maxLimit;
        for (uint256 i; i < nodes.length; i++) {
            (uint256 limit, uint256 duration,,) = decodeTick(nodes[i].tick, oraclePrice);

            if (limit > maxLimit && durationIdx == duration && nodes[i].available > 0) {
                maxLimit = uint128(limit);
            }
        }

        return maxLimit;
    }

    function getLiquidityAvailable(IPool pool, uint64 duration_, uint256 oraclePrice) internal view returns (uint256) {
        /* Get duration index */
        uint256 durationIdx = _getDurationIdx(pool, duration_);

        ILiquidity.NodeInfo[] memory nodes = ILiquidity(address(pool)).liquidityNodes(0, type(uint128).max);

        uint256 liquidityAvailable;
        for (uint256 i; i < nodes.length; i++) {
            (uint256 limit, uint256 duration,,) = decodeTick(nodes[i].tick, oraclePrice);

            if (limit > 0 && durationIdx == duration) {
                liquidityAvailable += nodes[i].available;
            }
        }

        return liquidityAvailable;
    }

    function computeExpectedSharesOut(IPool pool, uint128 tick, uint256 deposit) public view returns (uint128) {
        (ILiquidity.NodeInfo memory node, ILiquidity.AccrualInfo memory accrual) =
            ILiquidity(address(pool)).liquidityNodeWithAccrual(tick);

        uint256 price = _computePrice(node, accrual);

        return uint128(((deposit * FIXED_POINT_SCALE) / price));
    }

    function computeExpectedTokensOut(IPool pool, uint128 tick, uint256 deposit) public view returns (uint256) {
        (ILiquidity.NodeInfo memory node, ILiquidity.AccrualInfo memory accrual) =
            ILiquidity(address(pool)).liquidityNodeWithAccrual(tick);

        uint256 price = _computePrice(node, accrual);

        uint128 shares = uint128(((deposit * FIXED_POINT_SCALE) / price));

        uint128 nodeValue_ = node.value + uint128(deposit);
        uint128 nodeShares_ = node.shares + shares;

        return (shares * nodeValue_) / nodeShares_;
    }

    function computeExpectedNodeStateAfterDeposit(
        IPool pool,
        uint128 tick,
        uint256 deposit
    ) public view returns (uint128 nodeShares, uint128 nodeValue) {
        (ILiquidity.NodeInfo memory node, ILiquidity.AccrualInfo memory accrual) =
            ILiquidity(address(pool)).liquidityNodeWithAccrual(tick);

        uint256 price = _computePrice(node, accrual);

        uint128 shares = uint128(((deposit * FIXED_POINT_SCALE) / price));

        uint128 nodeValue_ = node.value + uint128(deposit);
        uint128 nodeShares_ = node.shares + shares;
        uint128 nodeAvailable_ = node.available + uint128(deposit);

        /* Process Redemption */
        if (nodeAvailable_ == 0) {
            return (nodeShares_, nodeValue_);
        }

        uint256 processPrice = (nodeValue_ * FIXED_POINT_SCALE) / nodeShares_;

        uint128 processShares = uint128(Math.min((nodeAvailable_ * FIXED_POINT_SCALE) / processPrice, node.redemptions));
        uint128 amount = uint128(Math.mulDiv(processShares, processPrice, FIXED_POINT_SCALE));

        return (nodeShares_ - processShares, nodeValue_ - amount);
    }

    function computeExpectedNodeStateAfterRedemption(
        IPool pool,
        uint128 tick,
        uint256 redemption
    ) public view returns (uint128 nodeShares, uint128 nodeValue) {
        ILiquidity.NodeInfo memory node = ILiquidity(address(pool)).liquidityNode(tick);

        uint128 nodeRedemptions_ = node.redemptions + uint128(redemption);

        /* Process Redemption */
        uint256 price = (node.value * FIXED_POINT_SCALE) / node.shares;

        uint128 shares = uint128(Math.min((node.available * FIXED_POINT_SCALE) / price, nodeRedemptions_));
        uint128 amount = uint128(Math.mulDiv(shares, price, FIXED_POINT_SCALE));

        return (node.shares - shares, node.value - amount);
    }
}
