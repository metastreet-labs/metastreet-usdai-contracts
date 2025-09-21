// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import "../interfaces/IPredepositVault.sol";

/**
 * @title Predeposit Vault
 * @author MetaStreet Foundation
 */
contract PredepositVault is ReentrancyGuardUpgradeable, AccessControlUpgradeable, IPredepositVault {
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
     * @dev keccak256(abi.encode(uint256(keccak256("predepositVault.depositCap")) - 1)) & ~bytes32(uint256(0xff));
     */
    bytes32 private constant DEPOSIT_CAP_STORAGE_LOCATION =
        0xbdedafde14722ae45d6ffda31d1d233d0f8a07469ea5d7d5ac5ee483bb474800;

    /**
     * @notice Vault admin role
     */
    bytes32 internal constant VAULT_ADMIN_ROLE = keccak256("VAULT_ADMIN_ROLE");

    /*------------------------------------------------------------------------*/
    /* Structures */
    /*------------------------------------------------------------------------*/

    /**
     * @custom:storage-location erc7201:depositVault.depositCap
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
     * @notice Scale factor
     */
    uint256 internal immutable _scaleFactor;

    /*------------------------------------------------------------------------*/
    /* State */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Name
     */
    string internal _name;

    /**
     * @notice Destination EID
     */
    uint32 internal _dstEid;

    /*------------------------------------------------------------------------*/
    /* Constructor */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Predeposit Vault Constructor
     * @param depositToken_ Deposit token
     * @param depositAmountMinimum_ Deposit amount minimum
     */
    constructor(address depositToken_, uint256 depositAmountMinimum_) {
        _disableInitializers();

        _depositToken = depositToken_;
        _depositAmountMinimum = depositAmountMinimum_;

        _scaleFactor = 10 ** (18 - IERC20Metadata(depositToken_).decimals());
    }

    /*------------------------------------------------------------------------*/
    /* Initialization */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Initializer
     * @param name_ Name
     * @param dstEid_ Destination EID
     * @param admin Default admin address
     */
    function initialize(string memory name_, uint32 dstEid_, address admin) external initializer {
        __ReentrancyGuard_init();
        __AccessControl_init();

        _name = name_;
        _dstEid = dstEid_;

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
     * @notice Get name
     * @return Name
     */
    function name() public view returns (string memory) {
        return _name;
    }

    /**
     * @notice Get destination EID
     * @return Destination EID
     */
    function dstEid() public view returns (uint32) {
        return _dstEid;
    }

    /**
     * @inheritdoc IPredepositVault
     */
    function depositToken() external view returns (address) {
        return _depositToken;
    }

    /**
     * @inheritdoc IPredepositVault
     */
    function depositAmountMinimum() external view returns (uint256) {
        return _depositAmountMinimum;
    }

    /**
     * @inheritdoc IPredepositVault
     */
    function depositCapInfo() external view returns (uint256 cap, uint256 counter) {
        return (_getDepositCapStorage().cap, _getDepositCapStorage().counter);
    }

    /*------------------------------------------------------------------------*/
    /* Public API */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IPredepositVault
     * @notice Caller has to ensure that recipient (e.g. Gnosis Safe) can receive ERC20 tokens on destination chain
     */
    function deposit(DepositType depositType, uint256 amount, address recipient) external nonReentrant {
        /* Validate deposit amount */
        if (amount == 0 || amount < _depositAmountMinimum) revert InvalidAmount();

        /* Validate recipient */
        if (recipient == address(0)) revert InvalidRecipient();

        /* Scale the amount */
        uint256 scaledAmount = amount * _scaleFactor;

        /* Validate deposit cap */
        if (_getDepositCapStorage().counter + scaledAmount > _getDepositCapStorage().cap) revert InvalidAmount();

        /* Update deposit cap counter */
        _getDepositCapStorage().counter += scaledAmount;

        /* Transfer deposit token to this contract */
        IERC20(_depositToken).safeTransferFrom(msg.sender, address(this), amount);

        /* Emit deposited event */
        emit Deposited(depositType, _depositToken, msg.sender, recipient, amount, _dstEid);
    }

    /*------------------------------------------------------------------------*/
    /* Permissioned API */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IPredepositVault
     */
    function withdraw(address to, uint256 amount) external onlyRole(VAULT_ADMIN_ROLE) {
        IERC20(_depositToken).safeTransfer(to, amount);

        emit Withdrawn(to, amount);
    }

    /**
     * @inheritdoc IPredepositVault
     */
    function rescue(address token, address to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        IERC20(token).safeTransfer(to, amount);
    }

    /**
     * @inheritdoc IPredepositVault
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
