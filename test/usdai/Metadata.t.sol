// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

import "../Base.t.sol";

contract USDaiMetadataTest is BaseTest {
    function test__USDaiMetadata() public view {
        IERC20Metadata usdai_ = IERC20Metadata(address(usdai));

        // Test token name
        assertEq(usdai_.name(), "USDai");

        // Test token symbol
        assertEq(usdai_.symbol(), "USDai");

        // Test token decimals
        assertEq(usdai_.decimals(), 18);
    }

    function test__USDaiDomainSeparator() public view {
        // Test domain separator for EIP-2612 permits
        bytes32 expectedDomainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("USDai")),
                keccak256(bytes("1")),
                block.chainid,
                address(usdai)
            )
        );

        assertEq(IERC20Permit(address(usdai)).DOMAIN_SEPARATOR(), expectedDomainSeparator);
    }
}
