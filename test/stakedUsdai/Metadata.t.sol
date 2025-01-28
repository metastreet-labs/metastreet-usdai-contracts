// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

import "../Base.t.sol";

contract StakedUSDaiMetadataTest is BaseTest {
    function test__StakedUSDaiMetadata() public view {
        IERC20Metadata stakedUsdai_ = IERC20Metadata(address(stakedUsdai));

        // Test token name
        assertEq(stakedUsdai_.name(), "Staked USD.ai");

        // Test token symbol
        assertEq(stakedUsdai_.symbol(), "sUSDai");

        // Test token decimals
        assertEq(stakedUsdai_.decimals(), 18);
    }

    function test__StakedUSDaiDomainSeparator() public view {
        // Test domain separator for EIP-2612 permits
        bytes32 expectedDomainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("Staked USD.ai")),
                keccak256(bytes("1")),
                block.chainid,
                address(stakedUsdai)
            )
        );

        assertEq(IERC20Permit(address(stakedUsdai)).DOMAIN_SEPARATOR(), expectedDomainSeparator);
    }
}
