// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.29;

import "forge-std/Script.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {PredepositVault} from "src/omnichain/PredepositVault.sol";

import {Deployer} from "./utils/Deployer.s.sol";

contract DeployPredepositVault is Deployer {
    function run(
        address deployer,
        address depositToken,
        uint256 depositAmountMinimum,
        string memory name,
        uint32 dstEid,
        address multisig
    ) public broadcast useDeployment returns (address) {
        // Deploy Predeposit Vault implementation
        PredepositVault predepositVaultImpl = new PredepositVault(depositToken, depositAmountMinimum);
        console.log("PredepositVault implementation", address(predepositVaultImpl));

        // Deploy Predeposit Vault proxy
        TransparentUpgradeableProxy predepositVault = new TransparentUpgradeableProxy(
            address(predepositVaultImpl),
            deployer,
            abi.encodeWithSelector(PredepositVault.initialize.selector, name, dstEid, multisig)
        );
        console.log("PredepositVault proxy", address(predepositVault));

        return (address(predepositVault));
    }
}
