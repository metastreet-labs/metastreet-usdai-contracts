// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.29;

import {Script} from "forge-std/Script.sol";

/**
 * @notice Base deployment script
 */
contract BaseScript is Script {
    uint256 internal _broadcaster;
    mapping(uint256 => string) internal _chainIdToNetwork;

    /*--------------------------------------------------------------------------*/
    /* Constructor                                                              */
    /*--------------------------------------------------------------------------*/

    constructor() {
        try vm.envUint("PRIVATE_KEY") returns (uint256 value) {
            _broadcaster = value;
        } catch {}

        _chainIdToNetwork[1] = "mainnet";
        _chainIdToNetwork[5] = "goerli";
        _chainIdToNetwork[11155111] = "sepolia";
        _chainIdToNetwork[31337] = "local";
        _chainIdToNetwork[421614] = "arbitrum_sepolia";
        _chainIdToNetwork[42161] = "arbitrum";
    }

    modifier broadcast() {
        if (_broadcaster != 0) {
            vm.startBroadcast(_broadcaster);
        } else {
            vm.startBroadcast();
        }

        _;

        vm.stopBroadcast();
    }
}
