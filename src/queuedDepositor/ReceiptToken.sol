// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "../interfaces/IReceiptToken.sol";

/**
 * @title Queued Depositor Receipt Token (ERC20)
 * @author MetaStreet Foundation
 */
contract ReceiptToken is ERC20Upgradeable, OwnableUpgradeable, IReceiptToken {
    /*------------------------------------------------------------------------*/
    /* Constants */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Implementation version
     */
    string public constant IMPLEMENTATION_VERSION = "1.0";

    /*------------------------------------------------------------------------*/
    /* Constructor */
    /*------------------------------------------------------------------------*/

    /**
     * @notice ReceiptToken constructor
     */
    constructor() {
        _disableInitializers();
    }

    /*------------------------------------------------------------------------*/
    /* Initialization  */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Initialize the contract
     * @param name Name
     * @param symbol Symbol
     */
    function initialize(string memory name, string memory symbol) external initializer {
        __ERC20_init(name, symbol);
        __Ownable_init(msg.sender);
    }

    /*------------------------------------------------------------------------*/
    /* ERC20 overrides */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc ERC20Upgradeable
     */
    function approve(address, uint256) public pure override returns (bool) {
        revert("Transfers are disabled");
    }

    /**
     * @inheritdoc ERC20Upgradeable
     */
    function transferFrom(address, address, uint256) public pure override returns (bool) {
        revert("Transfers are disabled");
    }

    /**
     * @inheritdoc ERC20Upgradeable
     */
    function transfer(address, uint256) public pure override returns (bool) {
        revert("Transfers are disabled");
    }

    /*------------------------------------------------------------------------*/
    /* Receipt Token API */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IReceiptToken
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /**
     * @inheritdoc IReceiptToken
     */
    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }
}
