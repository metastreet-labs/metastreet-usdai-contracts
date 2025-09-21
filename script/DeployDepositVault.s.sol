// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.29;

import "forge-std/Script.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {DepositVault} from "src/misc/DepositVault.sol";

import {Deployer} from "./utils/Deployer.s.sol";

contract DeployDepositVault is Deployer {
    function run(
        address deployer,
        address multisig,
        address depositToken,
        uint256 depositAmountMinimum,
        uint32 dstEid
    ) public broadcast useDeployment returns (address) {
        // Deploy OUSDaiUtility implementation
        DepositVault depositVaultImpl = new DepositVault(depositToken, depositAmountMinimum, dstEid);
        console.log("DepositVault implementation", address(depositVaultImpl));

        // Deploy OUSDaiUtility proxy
        TransparentUpgradeableProxy depositVault = new TransparentUpgradeableProxy(
            address(depositVaultImpl), deployer, abi.encodeWithSelector(DepositVault.initialize.selector, multisig)
        );
        console.log("DepositVault proxy", address(depositVault));

        _deployment.depositVault = address(depositVault);

        return (address(depositVault));
    }
}
