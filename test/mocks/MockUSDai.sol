// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/MulticallUpgradeable.sol";

import "src/interfaces/IUSDai.sol";
import "src/interfaces/IMintableBurnable.sol";

/**
 * @title Mock USDai ERC20
 * @author MetaStreet Foundation
 */
contract MockUSDai is
    IUSDai,
    IMintableBurnable,
    ERC165Upgradeable,
    ERC20Upgradeable,
    ERC20PermitUpgradeable,
    MulticallUpgradeable,
    ReentrancyGuardUpgradeable,
    AccessControlUpgradeable
{
    /*------------------------------------------------------------------------*/
    /* Constant */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Minter role
     */
    bytes32 internal constant BRIDGE_ADMIN_ROLE = keccak256("BRIDGE_ADMIN_ROLE");

    /*------------------------------------------------------------------------*/
    /* Constructor */
    /*------------------------------------------------------------------------*/

    /**
     * @notice USD.ai Constructor
     */
    constructor() {
        _disableInitializers();
    }

    /*------------------------------------------------------------------------*/
    /* Initialization  */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Initialize the contract
     */
    function initialize() public initializer {
        __ERC20_init("USD.ai", "USDai");
        __ERC20Permit_init("USD.ai");
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
        return "Mock USDai";
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
    function swapAdapter() external pure returns (address) {
        return address(0);
    }

    /**
     * @inheritdoc IUSDai
     */
    function baseToken() external pure returns (address) {
        return address(0);
    }

    /*------------------------------------------------------------------------*/
    /* Internal helpers */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Deposit
     * @param depositToken Deposit token
     * @param depositAmount Deposit amount
     * @param usdaiAmountMinimum USDai amount minimum
     * @param recipient Recipient address
     * @return USDai amount
     */
    function _deposit(
        address depositToken,
        uint256 depositAmount,
        uint256 usdaiAmountMinimum,
        address recipient,
        bytes calldata
    ) internal nonZeroUint(depositAmount) nonZeroUint(usdaiAmountMinimum) nonZeroAddress(recipient) returns (uint256) {
        /* Transfer token in from sender to this contract */
        IERC20(depositToken).transferFrom(msg.sender, address(this), depositAmount);

        uint256 usdaiAmount = IERC20Metadata(depositToken).decimals() == 6 ? depositAmount * 1e12 : depositAmount;

        /* Check that the USDai amount is greater than the minimum */
        if (usdaiAmount < usdaiAmountMinimum) revert InvalidAmount();

        /* Mint to the recipient */
        _mint(recipient, usdaiAmount);

        /* Emit deposited event */
        emit Deposited(msg.sender, recipient, depositToken, depositAmount, usdaiAmountMinimum);

        return usdaiAmount;
    }

    /**
     * @notice Withdraw
     * @param withdrawToken Withdraw token
     * @param usdaiAmount USD.ai amount
     * @param withdrawAmountMinimum Minimum withdraw amount
     * @param recipient Recipient address
     * @return Withdraw amount
     */
    function _withdraw(
        address withdrawToken,
        uint256 usdaiAmount,
        uint256 withdrawAmountMinimum,
        address recipient,
        bytes calldata
    )
        internal
        nonZeroUint(usdaiAmount)
        nonZeroUint(withdrawAmountMinimum)
        nonZeroAddress(recipient)
        returns (uint256)
    {
        /* Burn USD.ai tokens */
        _burn(msg.sender, usdaiAmount);

        /* Transfer token output from this contract to the recipient address */
        IERC20(withdrawToken).transfer(recipient, withdrawAmountMinimum);

        /* Emit withdrawn event */
        emit Withdrawn(msg.sender, recipient, withdrawToken, usdaiAmount, withdrawAmountMinimum);

        return withdrawAmountMinimum;
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
