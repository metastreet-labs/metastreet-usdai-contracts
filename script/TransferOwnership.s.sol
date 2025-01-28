// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.29;

import "forge-std/Script.sol";

import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {Deployer} from "script/utils/Deployer.s.sol";

contract TransferOwnership is Deployer {
    function run(address proxy, address account) public broadcast {
        console.log("Transferring ownership of proxy %s to %s...\n", proxy, account);

        /* Lookup proxy admin */
        address proxyAdmin = address(uint160(uint256(vm.load(proxy, ERC1967Utils.ADMIN_SLOT))));

        console.log("Proxy admin: %s", proxyAdmin);
        console.log("Current owner: %s", Ownable(proxyAdmin).owner());

        /* Transfer proxy admin */
        Ownable(proxyAdmin).transferOwnership(account);
    }
}
