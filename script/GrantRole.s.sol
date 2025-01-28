// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.29;

import "forge-std/Script.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {Deployer} from "script/utils/Deployer.s.sol";

contract GrantRole is Deployer {
    function run(address target, string memory role, address account) public broadcast {
        console.log('Granting role "%s" to account %s...', role, account);

        IAccessControl(target).grantRole(keccak256(bytes(role)), account);
    }
}
