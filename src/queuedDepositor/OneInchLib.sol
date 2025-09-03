// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IOneInchRouter} from "../interfaces/external/IOneInchRouter.sol";

library OneInchLib {
    /**
     * @notice Decode the message
     * @param data Data
     * @return Source token, destination token, destination receiver, and input amount
     */
    function decodeMessage(
        bytes memory data
    ) internal pure returns (address, address, address, uint256) {
        (
            address executor,
            IOneInchRouter.SwapDescription memory swapDescription,
            bytes memory permit,
            bytes memory calls
        ) = abi.decode(data, (address, IOneInchRouter.SwapDescription, bytes, bytes));

        /* Silence compiler warnings */
        executor;
        permit;
        calls;

        return (
            address(swapDescription.srcToken),
            address(swapDescription.dstToken),
            swapDescription.dstReceiver,
            swapDescription.amount
        );
    }
}
