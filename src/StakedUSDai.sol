// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC4626.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/MulticallUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import "./StakedUSDaiStorage.sol";
import "./RedemptionLogic.sol";

import "./positionManagers/BasePositionManager.sol";
import "./positionManagers/PoolPositionManager.sol";

import "./interfaces/IUSDai.sol";
import "./interfaces/IStakedUSDai.sol";
import "./interfaces/IERC7540.sol";
import "./interfaces/IERC7575.sol";
import "./interfaces/IPoolPositionManager.sol";
import "./interfaces/IBasePositionManager.sol";
import "./interfaces/IMintableBurnable.sol";

/**
 * @title Staked USDai ERC20
 * @author MetaStreet Foundation
 */
contract StakedUSDai is
    ERC165Upgradeable,
    ERC20Upgradeable,
    ERC20PermitUpgradeable,
    MulticallUpgradeable,
    PausableUpgradeable,
    StakedUSDaiStorage,
    BasePositionManager,
    PoolPositionManager,
    IStakedUSDai,
    IMintableBurnable,
    IERC4626,
    IERC7540Redeem,
    IERC7540Operator
{
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.UintSet;

    /*------------------------------------------------------------------------*/
    /* Constants */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Implementation version
     */
    string public constant IMPLEMENTATION_VERSION = "1.0";

    /**
     * @notice Fixed point scale
     */
    uint256 private constant FIXED_POINT_SCALE = 1e18;

    /**
     * @notice Amount of shares to lock for initial deposit
     */
    uint128 private constant LOCKED_SHARES = 1e6;

    /*------------------------------------------------------------------------*/
    /* Constructor */
    /*------------------------------------------------------------------------*/

    /**
     * @notice sUSDai Constructor
     * @param usdai_ USDai token
     * @param baseToken_ Base token
     * @param priceOracle_ Price oracle
     */
    constructor(
        address usdai_,
        address baseToken_,
        address priceOracle_
    ) StakedUSDaiStorage(usdai_) BasePositionManager(baseToken_) PoolPositionManager(priceOracle_) {
        _disableInitializers();
    }

    /*------------------------------------------------------------------------*/
    /* Initialization  */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Initialize the contract
     * @param admin Default admin address
     * @param timelock_ Timelock period for redemptions
     */
    function initialize(address admin, uint64 timelock_) external initializer {
        __ERC165_init();
        __ERC20_init("Staked USDai", "sUSDai");
        __ERC20Permit_init("Staked USDai");
        __Multicall_init();
        __ReentrancyGuard_init();
        __AccessControl_init();

        _getTimelockStorage().timelock = timelock_;

        /* Grant roles */
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /*------------------------------------------------------------------------*/
    /* Modifiers  */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Non-zero value modifier
     * @param value Value to check
     */
    modifier nonZeroUint(
        uint256 value
    ) {
        if (value == 0) revert InvalidAmount();
        _;
    }

    /**
     * @notice Non-zero address modifier
     * @param value Value to check
     */
    modifier nonZeroAddress(
        address value
    ) {
        if (value == address(0)) revert InvalidAddress();
        _;
    }

    /**
     * @notice Not blacklisted modifier
     * @param value Value to check
     */
    modifier notBlacklisted(
        address value
    ) {
        if (_getBlacklistStorage().blacklist[value]) {
            revert BlacklistedAddress(value);
        }
        _;
    }

    /*------------------------------------------------------------------------*/
    /* Getters  */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IStakedUSDai
     */
    function timelock() external view returns (uint64) {
        return _getTimelockStorage().timelock;
    }

    /**
     * @inheritdoc IStakedUSDai
     */
    function redemptionQueueInfo()
        external
        view
        returns (uint256 index, uint256 head, uint256 tail, uint256 pending, uint256 redemptionBalance)
    {
        return (
            _getRedemptionStateStorage().index,
            _getRedemptionStateStorage().head,
            _getRedemptionStateStorage().tail,
            _getRedemptionStateStorage().pending,
            _getRedemptionStateStorage().redemptionBalance
        );
    }

    /**
     * @inheritdoc IStakedUSDai
     */
    function redemption(
        uint256 redemptionId
    ) external view returns (Redemption memory, uint256) {
        return RedemptionLogic._redemption(_getRedemptionStateStorage(), redemptionId);
    }

    /**
     * @inheritdoc IStakedUSDai
     */
    function redemptionIds(
        address controller
    ) external view nonZeroAddress(controller) returns (uint256[] memory) {
        return _getRedemptionStateStorage().redemptionIds[controller].values();
    }

    /**
     * @inheritdoc IStakedUSDai
     */
    function nav() external view returns (uint256) {
        return _assets(ValuationType.OPTIMISTIC);
    }

    /**
     * @inheritdoc IStakedUSDai
     */
    function depositSharePrice() public view returns (uint256) {
        return _sharePrice(ValuationType.OPTIMISTIC);
    }

    /**
     * @inheritdoc IStakedUSDai
     */
    function redemptionSharePrice() public view returns (uint256) {
        return _sharePrice(ValuationType.CONSERVATIVE);
    }

    /**
     * @inheritdoc IStakedUSDai
     */
    function totalShares() public view returns (uint256) {
        return totalSupply() + _getBridgedSupplyStorage().bridgedSupply + _getRedemptionStateStorage().pending;
    }

    /*------------------------------------------------------------------------*/
    /* Internal helpers  */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc PositionManager
     */
    function _assets(
        ValuationType valuationType
    ) internal view override(BasePositionManager, PoolPositionManager) returns (uint256) {
        return BasePositionManager._assets(valuationType) + PoolPositionManager._assets(valuationType) + _usdaiBalance();
    }

    /**
     * @notice USDai balance in this contract less serviced redemption
     * @return USDai balance less serviced redemption
     */
    function _usdaiBalance() internal view returns (uint256) {
        return _usdai.balanceOf(address(this)) - _getRedemptionStateStorage().redemptionBalance;
    }

    /**
     * @notice Compute share price
     * @param valuationType Valuation type
     * @return Share price
     */
    function _sharePrice(
        ValuationType valuationType
    ) internal view returns (uint256) {
        return totalShares() == 0 ? FIXED_POINT_SCALE : (_assets(valuationType) * FIXED_POINT_SCALE) / totalShares();
    }

    /**
     * @notice Deposit assets
     * @param amount Amount to deposit
     * @param receiver Receiver address
     * @param minShares Minimum shares
     * @return Shares minted
     */
    function _deposit(
        uint256 amount,
        address receiver,
        uint256 minShares
    ) internal whenNotPaused nonReentrant nonZeroUint(amount) nonZeroAddress(receiver) returns (uint256) {
        /* Compute shares */
        uint256 shares = convertToShares(amount);

        /* If shares is 0 or less than min shares, revert */
        if (shares == 0 || shares < minShares) revert InvalidAmount();

        /* If initial deposit, mint locked shares */
        _mintLockedShares();

        /* Mint shares */
        _mint(receiver, shares);

        /* Deposit assets */
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), amount);

        /* Emit Deposit */
        emit Deposit(msg.sender, receiver, amount, shares);

        return shares;
    }

    function _mint(
        uint256 shares,
        address receiver,
        uint256 maxAmount
    ) internal whenNotPaused nonReentrant nonZeroUint(shares) nonZeroAddress(receiver) returns (uint256 assets) {
        /* Compute amount */
        uint256 amount = convertToAssets(shares);

        /* If amount is 0 or more than max amount, revert */
        if (amount == 0 || amount > maxAmount) revert InvalidAmount();

        /* If initial deposit, mint locked shares */
        _mintLockedShares();

        /* Mint shares */
        _mint(receiver, shares);

        /* Deposit assets */
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), amount);

        /* Emit Deposit */
        emit Deposit(msg.sender, receiver, amount, shares);

        return amount;
    }

    /**
     * @notice Mint locked shares
     */
    function _mintLockedShares() internal {
        if (totalSupply() < LOCKED_SHARES) _mint(address(0xdead), LOCKED_SHARES);
    }

    /*------------------------------------------------------------------------*/
    /* ERC20Upgradeable overrides */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc ERC20Upgradeable
     */
    function _update(
        address from,
        address to,
        uint256 value
    ) internal override notBlacklisted(msg.sender) notBlacklisted(from) notBlacklisted(to) {
        super._update(from, to, value);
    }

    /*------------------------------------------------------------------------*/
    /* ERC4626  */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IERC4626
     */
    function asset() public view returns (address) {
        return address(_usdai);
    }

    /**
     * @inheritdoc IERC4626
     */
    function totalAssets() external view returns (uint256) {
        return _assets(ValuationType.OPTIMISTIC);
    }

    /**
     * @inheritdoc IERC4626
     */
    function previewWithdraw(
        uint256
    ) external pure returns (uint256) {
        revert DisabledImplementation();
    }

    /**
     * @inheritdoc IERC4626
     */
    function previewRedeem(
        uint256
    ) external pure returns (uint256) {
        revert DisabledImplementation();
    }

    /**
     * @inheritdoc IERC4626
     */
    function maxWithdraw(
        address controller
    ) external view returns (uint256) {
        (uint256 amount,) = RedemptionLogic._redemptionAvailable(_getRedemptionStateStorage(), controller);

        /* Return amount */
        return amount;
    }

    /**
     * @inheritdoc IERC4626
     */
    function maxRedeem(
        address controller
    ) external view returns (uint256) {
        (, uint256 shares) = RedemptionLogic._redemptionAvailable(_getRedemptionStateStorage(), controller);

        /* Return shares */
        return shares;
    }

    /**
     * @inheritdoc IERC4626
     */
    function maxDeposit(
        address
    ) external pure returns (uint256) {
        return type(uint256).max;
    }

    /**
     * @inheritdoc IERC4626
     */
    function maxMint(
        address
    ) external pure returns (uint256) {
        return type(uint256).max;
    }

    /**
     * @inheritdoc IERC4626
     */
    function convertToShares(
        uint256 assets
    ) public view returns (uint256) {
        /* Check if initial deposit */
        bool initialDeposit = totalSupply() < LOCKED_SHARES;

        /* Compute shares. If initial deposit, remove locked shares */
        return ((assets * FIXED_POINT_SCALE) / depositSharePrice()) - (initialDeposit ? LOCKED_SHARES : 0);
    }

    /**
     * @inheritdoc IERC4626
     */
    function convertToAssets(
        uint256 shares
    ) public view returns (uint256) {
        /* Check if initial deposit */
        bool initialDeposit = totalSupply() < LOCKED_SHARES;

        /* Compute assets. If initial deposit, price locked shares */
        return ((((initialDeposit ? LOCKED_SHARES : 0) + shares) * depositSharePrice()) + FIXED_POINT_SCALE - 1)
            / FIXED_POINT_SCALE;
    }

    /**
     * @inheritdoc IERC4626
     */
    function previewDeposit(
        uint256 assets
    ) external view returns (uint256) {
        return convertToShares(assets);
    }

    /**
     * @inheritdoc IERC4626
     */
    function previewMint(
        uint256 shares
    ) external view returns (uint256) {
        return convertToAssets(shares);
    }

    /**
     * @inheritdoc IERC4626
     */
    function deposit(uint256 amount, address receiver) external returns (uint256) {
        return _deposit(amount, receiver, 0);
    }

    /**
     * @inheritdoc IERC4626
     */
    function mint(uint256 shares, address receiver) external returns (uint256 assets) {
        return _mint(shares, receiver, type(uint256).max);
    }

    /**
     * @inheritdoc IERC4626
     */
    function withdraw(
        uint256 amount,
        address receiver,
        address controller
    )
        external
        whenNotPaused
        notBlacklisted(msg.sender)
        notBlacklisted(controller)
        notBlacklisted(receiver)
        nonReentrant
        nonZeroUint(amount)
        nonZeroAddress(receiver)
        nonZeroAddress(controller)
        returns (uint256)
    {
        /* Validate caller */
        if (controller != msg.sender && !_getIsOperatorStorage().isOperator[controller][msg.sender]) {
            revert InvalidCaller();
        }

        /* Withdraw amount */
        uint256 shares = RedemptionLogic._withdraw(_getRedemptionStateStorage(), amount, controller);

        /* Transfer assets */
        IERC20(asset()).safeTransfer(receiver, amount);

        /* Emit Withdraw */
        emit Withdraw(msg.sender, receiver, controller, amount, shares);

        return shares;
    }

    /**
     * @inheritdoc IERC4626
     */
    function redeem(
        uint256 shares,
        address receiver,
        address controller
    )
        external
        whenNotPaused
        notBlacklisted(msg.sender)
        notBlacklisted(controller)
        notBlacklisted(receiver)
        nonReentrant
        nonZeroUint(shares)
        nonZeroAddress(receiver)
        nonZeroAddress(controller)
        returns (uint256)
    {
        /* Validate caller */
        if (controller != msg.sender && !_getIsOperatorStorage().isOperator[controller][msg.sender]) {
            revert InvalidCaller();
        }

        /* Redeem shares */
        uint256 amount = RedemptionLogic._redeem(_getRedemptionStateStorage(), shares, controller);

        /* Transfer assets */
        if (amount > 0) IERC20(asset()).safeTransfer(receiver, amount);

        /* Emit Withdraw */
        emit Withdraw(msg.sender, receiver, controller, amount, shares);

        return amount;
    }

    /*------------------------------------------------------------------------*/
    /* ERC4626 Overload */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IStakedUSDai
     */
    function deposit(uint256 amount, address receiver, uint256 minShares) external returns (uint256) {
        return _deposit(amount, receiver, minShares);
    }

    /**
     * @inheritdoc IStakedUSDai
     */
    function mint(uint256 shares, address receiver, uint256 maxAmount) external returns (uint256) {
        return _mint(shares, receiver, maxAmount);
    }

    /*------------------------------------------------------------------------*/
    /* ERC7540Operator */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IERC7540Operator
     */
    function isOperator(address controller, address operator) external view returns (bool status) {
        return _getIsOperatorStorage().isOperator[controller][operator];
    }

    /**
     * @inheritdoc IERC7540Operator
     */
    function setOperator(
        address operator,
        bool approved
    ) external whenNotPaused notBlacklisted(msg.sender) nonReentrant nonZeroAddress(operator) returns (bool) {
        /* Validate caller */
        if (msg.sender == operator) revert InvalidAddress();

        /* Set operator */
        _getIsOperatorStorage().isOperator[msg.sender][operator] = approved;

        /* Emit OperatorSet */
        emit OperatorSet(msg.sender, operator, approved);

        return true;
    }

    /*------------------------------------------------------------------------*/
    /* ERC7540Redeem */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IERC7540Redeem
     */
    function pendingRedeemRequest(uint256 redemptionId, address controller) external view returns (uint256) {
        /* Get redemption */
        Redemption storage redemption_ = _getRedemptionStateStorage().redemptions[redemptionId];

        /* If controller is not the same, return 0 */
        if (redemption_.controller != controller) return 0;

        return redemption_.pendingShares;
    }

    /**
     * @inheritdoc IERC7540Redeem
     */
    function claimableRedeemRequest(uint256 redemptionId, address controller) external view returns (uint256) {
        /* Get redemption */
        Redemption storage redemption_ = _getRedemptionStateStorage().redemptions[redemptionId];

        /* If controller is not the same or redemption is not past cliff, return 0 */
        if (redemption_.controller != controller || redemption_.cliff >= block.timestamp) return 0;

        return redemption_.redeemableShares;
    }

    /**
     * @inheritdoc IERC7540Redeem
     */
    function requestRedeem(
        uint256 shares,
        address controller,
        address owner
    )
        external
        whenNotPaused
        notBlacklisted(controller)
        nonReentrant
        nonZeroUint(shares)
        nonZeroAddress(controller)
        nonZeroAddress(owner)
        returns (uint256)
    {
        /* Validate caller */
        if (owner != msg.sender && !_getIsOperatorStorage().isOperator[owner][msg.sender]) revert InvalidCaller();

        /* Validate balance */
        if (balanceOf(owner) < shares) revert InsufficientBalance();

        /* Burn sUSDai shares */
        _burn(owner, shares);

        /* Request redeem */
        uint256 redemptionId = RedemptionLogic._requestRedeem(
            _getRedemptionStateStorage(), _getTimelockStorage().timelock, shares, controller
        );

        /* Emit redeem request */
        emit RedeemRequest(controller, owner, redemptionId, msg.sender, shares);

        return redemptionId;
    }

    /*------------------------------------------------------------------------*/
    /* ERC7575 */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Get share address
     * @return Share address
     */
    function share() external view returns (address) {
        return address(this);
    }

    /*------------------------------------------------------------------------*/
    /* Default admin API */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IStakedUSDai
     */
    function setTimelock(
        uint64 timelock_
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _getTimelockStorage().timelock = timelock_;
    }

    /*------------------------------------------------------------------------*/
    /* Blacklister API */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IStakedUSDai
     */
    function setBlacklist(address account, bool isBlacklisted) external onlyRole(BLACKLIST_ADMIN_ROLE) {
        _getBlacklistStorage().blacklist[account] = isBlacklisted;

        /* Emit Blacklisted */
        emit Blacklisted(account, isBlacklisted);
    }

    /*------------------------------------------------------------------------*/
    /* Pause admin API */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IStakedUSDai
     */
    function pause() external onlyRole(PAUSE_ADMIN_ROLE) {
        _pause();
    }

    /**
     * @inheritdoc IStakedUSDai
     */
    function unpause() external onlyRole(PAUSE_ADMIN_ROLE) {
        _unpause();
    }

    /*------------------------------------------------------------------------*/
    /* Manager API */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IStakedUSDai
     */
    function serviceRedemptions(
        uint256 shares
    ) external onlyRole(STRATEGY_ADMIN_ROLE) nonZeroUint(shares) returns (uint256) {
        /* Process redemptions */
        (uint256 amountProcessed, bool allRedemptionsServiced) =
            RedemptionLogic._processRedemptions(_getRedemptionStateStorage(), shares, redemptionSharePrice());

        /* Validate amount is available to be serviced */
        if (amountProcessed > _usdaiBalance()) revert InsufficientBalance();

        /* Update redemption balance */
        _getRedemptionStateStorage().redemptionBalance += amountProcessed;

        /* Emit RedemptionsServiced */
        emit RedemptionsServiced(shares, amountProcessed, allRedemptionsServiced);

        return amountProcessed;
    }

    /*------------------------------------------------------------------------*/
    /* Minter API */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IMintableBurnable
     */
    function mint(address to, uint256 amount) external whenNotPaused onlyRole(BRIDGE_ADMIN_ROLE) {
        /* Mint supply */
        _mint(to, amount);

        /* Update bridged supply */
        _getBridgedSupplyStorage().bridgedSupply -= amount;
    }

    /**
     * @inheritdoc IMintableBurnable
     */
    function burn(address from, uint256 amount) external whenNotPaused onlyRole(BRIDGE_ADMIN_ROLE) {
        /* Burn supply */
        _burn(from, amount);

        /* Update bridged supply */
        _getBridgedSupplyStorage().bridgedSupply += amount;
    }

    /*------------------------------------------------------------------------*/
    /* ERC165 */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IERC165
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(AccessControlUpgradeable, ERC165Upgradeable) returns (bool) {
        return interfaceId == type(IERC20).interfaceId || interfaceId == type(IERC4626).interfaceId
            || interfaceId == type(IERC7540Redeem).interfaceId || interfaceId == type(IERC7540Operator).interfaceId
            || interfaceId == type(IStakedUSDai).interfaceId || interfaceId == type(IMintableBurnable).interfaceId
            || interfaceId == type(IERC7575).interfaceId || super.supportsInterface(interfaceId);
    }
}
