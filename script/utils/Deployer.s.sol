// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.29;

import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {console2 as console} from "forge-std/console2.sol";
import {VmSafe} from "forge-std/Vm.sol";

import {BaseScript} from "./Base.s.sol";

contract Deployer is BaseScript {
    /*--------------------------------------------------------------------------*/
    /* Errors                                                                   */
    /*--------------------------------------------------------------------------*/

    error MissingDependency();

    error AlreadyDeployed();

    error InvalidParameter();

    /*--------------------------------------------------------------------------*/
    /* Structures                                                               */
    /*--------------------------------------------------------------------------*/

    struct Deployment {
        address USDai;
        address stakedUSDai;
        address swapAdapter;
        address priceOracle;
        address oAdapterUSDai;
        address oAdapterStakedUSDai;
    }

    /*--------------------------------------------------------------------------*/
    /* State Variables                                                          */
    /*--------------------------------------------------------------------------*/

    Deployment internal _deployment;

    /*--------------------------------------------------------------------------*/
    /* Modifier                                                                 */
    /*--------------------------------------------------------------------------*/

    /**
     * @dev Add useDeployment modifier to deployment script run() function to
     *      deserialize deployments json and make properties available to read,
     *      write and modify. Changes are re-serialized at end of script.
     */
    modifier useDeployment() {
        console.log("Using deployment\n");
        console.log("Network: %s\n", _chainIdToNetwork[block.chainid]);

        _deserialize();

        _;

        _serialize();

        console.log("Using deployment completed\n");
    }

    /*--------------------------------------------------------------------------*/
    /* Internal Helpers                                                         */
    /*--------------------------------------------------------------------------*/

    /**
     * @notice Internal helper to get deployment file path for current network
     *
     * @return Path
     */
    function _getJsonFilePath() internal view returns (string memory) {
        return string(abi.encodePacked(vm.projectRoot(), "/deployments/", _chainIdToNetwork[block.chainid], ".json"));
    }

    /**
     * @notice Internal helper to read and return json string
     *
     * @return Json string
     */
    function _getJson() internal view returns (string memory) {
        string memory path = _getJsonFilePath();

        string memory json = "{}";

        try vm.readFile(path) returns (string memory _json) {
            json = _json;
        } catch {
            console.log("No json file found at: %s\n", path);
        }

        return json;
    }

    /*--------------------------------------------------------------------------*/
    /* API                                                                      */
    /*--------------------------------------------------------------------------*/

    /**
     * @notice Serialize the _deployment storage struct
     */
    function _serialize() internal {
        /* Initialize json string */
        string memory json = "";

        json = stdJson.serialize("", "USDai", _deployment.USDai);
        json = stdJson.serialize("", "StakedUSDai", _deployment.stakedUSDai);
        json = stdJson.serialize("", "SwapAdapter", _deployment.swapAdapter);
        json = stdJson.serialize("", "PriceOracle", _deployment.priceOracle);
        json = stdJson.serialize("", "OAdapterUSDai", _deployment.oAdapterUSDai);
        json = stdJson.serialize("", "OAdapterStakedUSDai", _deployment.oAdapterStakedUSDai);

        console.log("Writing json to file: %s\n", json);
        vm.writeJson(json, _getJsonFilePath());
    }

    /**
     * @notice Deserialize the deployment json
     *
     * @dev Deserialization loads the json into the _deployment struct
     */
    function _deserialize() internal {
        string memory json = _getJson();

        /* Deserialize USDai */
        try vm.parseJsonAddress(json, ".USDai") returns (address instance) {
            _deployment.USDai = instance;
        } catch {
            console.log("Could not parse USDai");
        }

        /* Deserialize StakedUSDai */
        try vm.parseJsonAddress(json, ".StakedUSDai") returns (address instance) {
            _deployment.stakedUSDai = instance;
        } catch {
            console.log("Could not parse StakedUSDai");
        }

        /* Deserialize SwapAdapter */
        try vm.parseJsonAddress(json, ".SwapAdapter") returns (address instance) {
            _deployment.swapAdapter = instance;
        } catch {
            console.log("Could not parse SwapAdapter");
        }

        /* Deserialize PriceOracle */
        try vm.parseJsonAddress(json, ".PriceOracle") returns (address instance) {
            _deployment.priceOracle = instance;
        } catch {
            console.log("Could not parse PriceOracle");
        }

        /* Deserialize OAdapterUSDai */
        try vm.parseJsonAddress(json, ".OAdapterUSDai") returns (address instance) {
            _deployment.oAdapterUSDai = instance;
        } catch {
            console.log("Could not parse OAdapterUSDai");
        }

        /* Deserialize OAdapterStakedUSDai */
        try vm.parseJsonAddress(json, ".OAdapterStakedUSDai") returns (address instance) {
            _deployment.oAdapterStakedUSDai = instance;
        } catch {
            console.log("Could not parse OAdapterStakedUSDai");
        }
    }
}
