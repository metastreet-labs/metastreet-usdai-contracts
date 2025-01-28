// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.29;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title Test ERC20 Token
 */
contract TestERC20 is ERC20 {
    /*------------------------------------------------------------------------*/
    /* Properties */
    /*------------------------------------------------------------------------*/

    uint8 private _decimals;

    /*------------------------------------------------------------------------*/
    /* Constructor */
    /*------------------------------------------------------------------------*/

    /**
     * @notice TestERC20 constructor
     * @notice name Token name
     * @notice symbol Token symbol
     * @notice initialSupply Initial supply
     */
    constructor(string memory name, string memory symbol, uint8 decimals_, uint256 initialSupply) ERC20(name, symbol) {
        _decimals = decimals_;

        _mint(msg.sender, initialSupply);
    }

    /*------------------------------------------------------------------------*/
    /* Getter                                                                 */
    /*------------------------------------------------------------------------*/

    function decimals() public view override returns (uint8) {
        return _decimals;
    }
}
