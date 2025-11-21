// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.29;

import "forge-std/Script.sol";

import {IStakedUSDai} from "src/interfaces/IStakedUSDai.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Deployer} from "./utils/Deployer.s.sol";

contract StakedUSDaiServiceRedemptions is Deployer {
    function run(
        uint256 shares
    ) public useDeployment {
        IStakedUSDai stakedUSDai = IStakedUSDai(_deployment.stakedUSDai);

        (,,, uint256 pending, uint256 redemptionBalance,) = stakedUSDai.redemptionQueueInfo();
        uint256 redemptionSharePrice = stakedUSDai.redemptionSharePrice();

        uint256 usdaiBalance = IERC20(_deployment.USDai).balanceOf(_deployment.stakedUSDai);

        console.log("Redemption Shares Pending:     %18e", pending);
        console.log("Redemption Share Price:        %18e", redemptionSharePrice);
        console.log("Redemption Value Pending:      %18e", (pending * redemptionSharePrice) / 1e18);
        console.log("");
        console.log("USDai Balance:                 %18e", usdaiBalance);
        console.log("USDai Redemption Balance:      %18e", redemptionBalance);
        console.log("USDai Available Balance:       %18e", usdaiBalance - redemptionBalance);

        console.log("\nCalldata");
        console.log("Target:   %s", _deployment.stakedUSDai);
        console.log("Calldata:");
        console.logBytes(
            abi.encodeWithSelector(IStakedUSDai.serviceRedemptions.selector, shares == 0 ? pending : shares)
        );
    }
}
