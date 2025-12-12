// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import {PositionManager} from "./PositionManager.sol";
import {StakedUSDaiStorage} from "../StakedUSDaiStorage.sol";
import {PoolPositionManagerLogic} from "./PoolPositionManagerLogic.sol";

import {IPoolPositionManager} from "../interfaces/IPoolPositionManager.sol";
import {IPool} from "../interfaces/external/IPool.sol";

/**
 * @title Pool Position Manager
 * @author MetaStreet Foundation
 */
abstract contract PoolPositionManager is
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    PositionManager,
    StakedUSDaiStorage,
    IPoolPositionManager
{
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;

    /*------------------------------------------------------------------------*/
    /* Constants */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Pools storage location
     * @dev keccak256(abi.encode(uint256(keccak256("stakedUSDai.pools")) - 1)) & ~bytes32(uint256(0xff));
     */
    bytes32 private constant POOLS_STORAGE_LOCATION = 0x0a32e6e3ec9caf40523489fb56ffc3afa6eadc68c0df235d444c084ba724fc00;

    /*------------------------------------------------------------------------*/
    /* Structures */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Pool position
     * @param ticks Ticks
     * @param redemptionIds Redemption ids
     */
    struct PoolPosition {
        EnumerableSet.UintSet ticks;
        mapping(uint128 => EnumerableSet.UintSet) redemptionIds;
    }

    /**
     * @custom:storage-location erc7201:stakedUSDai.pools
     */
    struct Pools {
        EnumerableSet.AddressSet pools;
        mapping(address => PoolPosition) position;
    }

    /*------------------------------------------------------------------------*/
    /* Constructor */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Constructor
     */
    constructor() {}

    /*------------------------------------------------------------------------*/
    /* Internal helpers */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Get reference to ERC-7201 pools storage
     *
     * @return $ Reference to pools storage
     */
    function _getPoolsStorage() internal pure returns (Pools storage $) {
        assembly {
            $.slot := POOLS_STORAGE_LOCATION
        }
    }

    /**
     * @inheritdoc PositionManager
     */
    function _assets(
        PositionManager.ValuationType valuationType
    ) internal view virtual override returns (uint256 nav_) {
        return PoolPositionManagerLogic._assets(_getPoolsStorage(), _priceOracle, valuationType);
    }

    /*------------------------------------------------------------------------*/
    /* Permissioned API */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IPoolPositionManager
     */
    function poolGarbageCollect(
        address pool,
        uint128 tick,
        uint128 redemptionId
    ) external onlyRole(STRATEGY_ADMIN_ROLE) nonReentrant {
        PoolPositionManagerLogic._garbageCollect(_getPoolsStorage(), pool, tick, redemptionId);
    }
}
