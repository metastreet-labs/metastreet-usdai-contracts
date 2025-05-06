// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/MulticallUpgradeable.sol";

import "./interfaces/IUSDai.sol";
import "./interfaces/ISwapAdapter.sol";
import "./interfaces/IMintableBurnable.sol";

/**
 * @title USDai ERC20
 * @author MetaStreet Foundation
 */
contract USDai is
    IUSDai,
    IMintableBurnable,
    ERC165Upgradeable,
    ERC20Upgradeable,
    ERC20PermitUpgradeable,
    MulticallUpgradeable,
    ReentrancyGuardUpgradeable,
    AccessControlUpgradeable
{
    using SafeERC20 for IERC20;

    /*------------------------------------------------------------------------*/
    /* Constant */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Minter role
     */
    bytes32 internal constant BRIDGE_ADMIN_ROLE = keccak256("BRIDGE_ADMIN_ROLE");

    /*------------------------------------------------------------------------*/
    /* Immutable state */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Swap adapter
     */
    ISwapAdapter internal immutable _swapAdapter;

    /**
     * @notice Base token
     */
    IERC20 internal immutable _baseToken;

    /**
     * @notice Scale factor
     */
    uint256 internal immutable _scaleFactor;

    /*------------------------------------------------------------------------*/
    /* Constructor */
    /*------------------------------------------------------------------------*/

    /**
     * @notice USDai Constructor
     * @param swapAdapter_ Swap Adapter
     */
    constructor(
        address swapAdapter_
    ) {
        _disableInitializers();

        _swapAdapter = ISwapAdapter(swapAdapter_);
        _baseToken = IERC20(_swapAdapter.baseToken());
        _scaleFactor = 10 ** (18 - IERC20Metadata(_swapAdapter.baseToken()).decimals());
    }

    /*------------------------------------------------------------------------*/
    /* Initialization  */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Initialize the contract
     */
    function initialize() public initializer {
        __ERC20_init("USDai", "USDai");
        __ERC20Permit_init("USDai");
        __Multicall_init();
        __ReentrancyGuard_init();
        __AccessControl_init();

        /* Grant roles */
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
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

    /*------------------------------------------------------------------------*/
    /* Getters  */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Get implementation name
     * @return Implementation name
     */
    function IMPLEMENTATION_NAME() external pure returns (string memory) {
        return "USDai";
    }

    /**
     * @notice Get implementation version
     * @return Implementation version
     */
    function IMPLEMENTATION_VERSION() external pure returns (string memory) {
        return "1.0";
    }

    /**
     * @inheritdoc IUSDai
     */
    function swapAdapter() external view returns (address) {
        return address(_swapAdapter);
    }

    /**
     * @inheritdoc IUSDai
     */
    function baseToken() external view returns (address) {
        return address(_baseToken);
    }

    /*------------------------------------------------------------------------*/
    /* Internal helpers */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Helper function to scale up a value
     * @param value Value
     * @return Scaled value
     */
    function _scale(
        uint256 value
    ) public view returns (uint256) {
        return value * _scaleFactor;
    }

    /**
     * @notice Helper function to scale down a value
     * @param value Value
     * @return Unscaled value
     */
    function _unscale(
        uint256 value
    ) public view returns (uint256) {
        return value / _scaleFactor;
    }

    /**
     * @notice Helper function to scale down a value, rounding up
     * @param value Value
     * @return Unscaled value rounded up
     */
    function _unscaleUp(
        uint256 value
    ) public view returns (uint256) {
        return (value + _scaleFactor - 1) / _scaleFactor;
    }

    /**
     * @notice Deposit
     * @param depositToken Deposit token
     * @param depositAmount Deposit amount
     * @param usdaiAmountMinimum USDai amount minimum
     * @param recipient Recipient address
     * @param data Data
     * @return USDai amount
     */
    function _deposit(
        address depositToken,
        uint256 depositAmount,
        uint256 usdaiAmountMinimum,
        address recipient,
        bytes calldata data
    ) internal nonZeroUint(depositAmount) nonZeroAddress(recipient) returns (uint256) {
        /* Transfer token in from sender to this contract */
        IERC20(depositToken).transferFrom(msg.sender, address(this), depositAmount);

        /* If the deposit token isn't base token, swap in */
        uint256 usdaiAmount;
        if (depositToken != address(_baseToken)) {
            /* Approve the adapter to spend the token in */
            IERC20(depositToken).forceApprove(address(_swapAdapter), depositAmount);

            /* Swap in deposit token for base token */
            usdaiAmount = _scale(_swapAdapter.swapIn(depositToken, depositAmount, _unscaleUp(usdaiAmountMinimum), data));
        } else {
            usdaiAmount = _scale(depositAmount);
        }

        /* Mint to the recipient */
        _mint(recipient, usdaiAmount);

        /* Emit deposited event */
        emit Deposited(msg.sender, recipient, depositToken, depositAmount, usdaiAmount);

        return usdaiAmount;
    }

    /**
     * @notice Withdraw
     * @param withdrawToken Withdraw token
     * @param usdaiAmount USD.ai amount
     * @param withdrawAmountMinimum Minimum withdraw amount (only checked for non-base token withdrawals)
     * @param recipient Recipient address
     * @param data Data
     * @return Withdraw amount
     */
    function _withdraw(
        address withdrawToken,
        uint256 usdaiAmount,
        uint256 withdrawAmountMinimum,
        address recipient,
        bytes calldata data
    ) internal nonZeroUint(usdaiAmount) nonZeroAddress(recipient) returns (uint256) {
        /* Burn USD.ai tokens */
        _burn(msg.sender, usdaiAmount);

        /* If the withdraw token isn't base token, swap out */
        uint256 withdrawAmount;
        if (withdrawToken != address(_baseToken)) {
            uint256 baseTokenAmount = _unscale(usdaiAmount);

            /* Approve the adapter to spend the token in */
            _baseToken.approve(address(_swapAdapter), baseTokenAmount);

            /* Swap base token input for withdraw token */
            withdrawAmount = _swapAdapter.swapOut(withdrawToken, baseTokenAmount, withdrawAmountMinimum, data);
        } else {
            withdrawAmount = _unscale(usdaiAmount);
        }

        /* Transfer token output from this contract to the recipient address */
        IERC20(withdrawToken).transfer(recipient, withdrawAmount);

        /* Emit withdrawn event */
        emit Withdrawn(msg.sender, recipient, withdrawToken, usdaiAmount, withdrawAmount);

        return withdrawAmount;
    }

    /*------------------------------------------------------------------------*/
    /* Public API */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IUSDai
     */
    function deposit(
        address depositToken,
        uint256 depositAmount,
        uint256 usdaiAmountMinimum,
        address recipient
    ) external nonReentrant returns (uint256) {
        return _deposit(depositToken, depositAmount, usdaiAmountMinimum, recipient, msg.data[0:0]);
    }

    /**
     * @inheritdoc IUSDai
     */
    function deposit(
        address depositToken,
        uint256 depositAmount,
        uint256 usdaiAmountMinimum,
        address recipient,
        bytes calldata data
    ) external nonReentrant returns (uint256) {
        return _deposit(depositToken, depositAmount, usdaiAmountMinimum, recipient, data);
    }

    /**
     * @inheritdoc IUSDai
     */
    function withdraw(
        address withdrawToken,
        uint256 usdaiAmount,
        uint256 withdrawAmountMinimum,
        address recipient
    ) external nonReentrant returns (uint256) {
        return _withdraw(withdrawToken, usdaiAmount, withdrawAmountMinimum, recipient, msg.data[0:0]);
    }

    /**
     * @inheritdoc IUSDai
     */
    function withdraw(
        address withdrawToken,
        uint256 usdaiAmount,
        uint256 withdrawAmountMinimum,
        address recipient,
        bytes calldata data
    ) external nonReentrant returns (uint256) {
        return _withdraw(withdrawToken, usdaiAmount, withdrawAmountMinimum, recipient, data);
    }

    /*------------------------------------------------------------------------*/
    /* Minter API */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IMintableBurnable
     */
    function mint(address to, uint256 amount) external onlyRole(BRIDGE_ADMIN_ROLE) {
        _mint(to, amount);
    }

    /**
     * @inheritdoc IMintableBurnable
     */
    function burn(address from, uint256 amount) external onlyRole(BRIDGE_ADMIN_ROLE) {
        _burn(from, amount);
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
        return interfaceId == type(IERC20).interfaceId || interfaceId == type(IUSDai).interfaceId
            || interfaceId == type(IMintableBurnable).interfaceId || super.supportsInterface(interfaceId);
    }
}
