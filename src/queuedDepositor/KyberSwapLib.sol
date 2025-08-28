// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IKyberRouter} from "../interfaces/external/IKyberRouter.sol";

library KyberSwapLib {
    /**
     * @notice Decode the message
     * @param data Data
     * @return Source token, destination token, destination receiver, and input amount
     */
    function decodeMessage(
        bytes memory data
    ) internal pure returns (address, address, address, uint256) {
        (IKyberRouter.SwapExecutionParams memory swapExecutionParams) =
            abi.decode(data, (IKyberRouter.SwapExecutionParams));

        return (
            address(swapExecutionParams.desc.srcToken),
            address(swapExecutionParams.desc.dstToken),
            swapExecutionParams.desc.dstReceiver,
            swapExecutionParams.desc.amount
        );
    }
}
