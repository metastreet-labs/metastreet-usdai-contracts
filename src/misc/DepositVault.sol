// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import "../interfaces/IDepositVault.sol";

/**
 * @title Deposit Vault
 * @author MetaStreet Foundation
 */
contract DepositVault is ReentrancyGuardUpgradeable, AccessControlUpgradeable, IDepositVault {
    using SafeERC20 for IERC20;

    /*------------------------------------------------------------------------*/
    /* Constants */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Implementation version
     */
    string public constant IMPLEMENTATION_VERSION = "1.0";

    /**
     * @notice Deposit cap storage location
     * @dev keccak256(abi.encode(uint256(keccak256("depositVault.depositCap")) - 1)) &
     * ~bytes32(uint256(0xff));
     */
    bytes32 private constant DEPOSIT_CAP_STORAGE_LOCATION =
        0xf6ec18980986255516f8f1a097842232a4ba3fc274a724745dd2d31d673a6d00;

    /**
     * @notice Vault admin role
     */
    bytes32 internal constant VAULT_ADMIN_ROLE = keccak256("VAULT_ADMIN_ROLE");

    /*------------------------------------------------------------------------*/
    /* Structures */
    /*------------------------------------------------------------------------*/

    /**
     * @custom:storage-location erc7201:DepositVault.depositCap
     */
    struct DepositCap {
        uint256 cap;
        uint256 counter;
    }

    /*------------------------------------------------------------------------*/
    /* Immutable state */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Deposit token
     */
    address internal immutable _depositToken;

    /**
     * @notice Deposit amount minimum
     */
    uint256 internal immutable _depositAmountMinimum;

    /**
     * @notice Destination EID
     */
    uint32 internal immutable _dstEid;

    /**
     * @notice Scale factor
     */
    uint256 internal immutable _scaleFactor;

    /*------------------------------------------------------------------------*/
    /* Constructor */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Deposit Vault Constructor
     * @param depositToken_ Deposit token
     * @param depositAmountMinimum_ Deposit amount minimum
     * @param dstEid_ Destination EID
     */
    constructor(address depositToken_, uint256 depositAmountMinimum_, uint32 dstEid_) {
        _disableInitializers();

        _depositToken = depositToken_;
        _depositAmountMinimum = depositAmountMinimum_;
        _dstEid = dstEid_;

        _scaleFactor = 10 ** (18 - IERC20Metadata(depositToken_).decimals());
    }

    /*------------------------------------------------------------------------*/
    /* Initialization */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Initializer
     * @param admin Default admin address
     */
    function initialize(
        address admin
    ) external initializer {
        __ReentrancyGuard_init();
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /*------------------------------------------------------------------------*/
    /* Storage getters */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Get reference to ERC-7201 deposit cap storage
     *
     * @return $ Reference to deposit cap storage
     */
    function _getDepositCapStorage() internal pure returns (DepositCap storage $) {
        assembly {
            $.slot := DEPOSIT_CAP_STORAGE_LOCATION
        }
    }

    /*------------------------------------------------------------------------*/
    /* Getters */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IDepositVault
     */
    function depositToken() external view returns (address) {
        return _depositToken;
    }

    /**
     * @inheritdoc IDepositVault
     */
    function depositAmountMinimum() external view returns (uint256) {
        return _depositAmountMinimum;
    }

    /**
     * @inheritdoc IDepositVault
     */
    function depositCapInfo() external view returns (uint256 cap, uint256 counter) {
        return (_getDepositCapStorage().cap, _getDepositCapStorage().counter);
    }

    /*------------------------------------------------------------------------*/
    /* Public API */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IDepositVault
     * @notice Caller has to ensure that recipient (e.g. Gnosis Safe) can receive ERC20 tokens on destination chain
     */
    function deposit(DepositType depositType, uint256 amount, address recipient) external nonReentrant {
        /* Validate deposit amount */
        if (amount == 0 || amount < _depositAmountMinimum) revert InvalidAmount();

        /* Scale the amount */
        uint256 scaledAmount = amount * _scaleFactor;

        /* Validate deposit cap */
        if (_getDepositCapStorage().counter + scaledAmount > _getDepositCapStorage().cap) revert InvalidAmount();

        /* Validate recipient */
        if (recipient == address(0)) revert InvalidRecipient();

        /* Update deposit cap counter */
        _getDepositCapStorage().counter += scaledAmount;

        /* Transfer deposit token to this contract */
        IERC20(_depositToken).safeTransferFrom(msg.sender, address(this), amount);

        /* Emit deposited event */
        emit Deposited(depositType, _depositToken, recipient, msg.sender, amount, _dstEid);
    }

    /*------------------------------------------------------------------------*/
    /* Permissioned API */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IDepositVault
     */
    function withdraw(address to, uint256 amount) external onlyRole(VAULT_ADMIN_ROLE) {
        IERC20(_depositToken).safeTransfer(to, amount);

        emit Withdrawn(to, amount);
    }

    /**
     * @inheritdoc IDepositVault
     */
    function rescue(address token, address to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        IERC20(token).safeTransfer(to, amount);
    }

    /**
     * @inheritdoc IDepositVault
     * @dev depositCap needs to be scaled to 18 decimals
     */
    function updateDepositCap(uint256 depositCap, bool resetCounter) external onlyRole(DEFAULT_ADMIN_ROLE) {
        /* Update deposit cap */
        _getDepositCapStorage().cap = depositCap;

        /* Reset counter if needed */
        if (resetCounter) {
            _getDepositCapStorage().counter = 0;
        }

        /* Emit deposit cap updated event */
        emit DepositCapUpdated(depositCap);
    }
}
