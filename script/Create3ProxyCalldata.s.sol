// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.29;

import "forge-std/Script.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {Deployer} from "./utils/Deployer.s.sol";

interface ICreateX {
    function computeCreate3Address(
        bytes32 salt
    ) external view returns (address computedAddress);
    function deployCreate3(bytes32 salt, bytes memory initCode) external payable returns (address newContract);
}

contract Create3ProxyCalldata is Deployer {
    ICreateX internal constant CREATEX = ICreateX(0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed);

    function run(address deployer, bytes32 salt, address implementation, bytes calldata data) public view {
        address predicted = CREATEX.computeCreate3Address(keccak256(abi.encode(deployer, salt)));

        bytes memory calldata_ = abi.encodeWithSelector(
            ICreateX.deployCreate3.selector,
            salt,
            abi.encodePacked(type(TransparentUpgradeableProxy).creationCode, abi.encode(implementation, deployer, data))
        );

        console.log("predicted address", predicted);
        console.log("target", address(CREATEX));
        console.log("calldata");
        console.logBytes(calldata_);
    }
}
