#!/usr/bin/env bash

set -e

# deploy a contract
run() {
    local network="$1"
    local rpc_url_var="$2"
    local contract="$3"

    case $network in
        "local")
            echo "Running locally"
            forge script "$contract" --fork-url http://localhost:8545 --private-key $PRIVATE_KEY --broadcast -vvvv "${@:4}"
            ;;

        "goerli"|"sepolia"|"mainnet"|"blast"|"base"|"arbitrum_sepolia"|"arbitrum")
            local rpc_url="${!rpc_url_var}"
            if [[ -z $rpc_url ]]; then
                echo "$rpc_url_var is not set"
                exit 1
            fi
            echo "Running on $network"
            if [ ! -z $LEDGER_DERIVATION_PATH ]; then
                forge script "$contract" --rpc-url "$rpc_url" --ledger --hd-paths $LEDGER_DERIVATION_PATH --sender $LEDGER_ADDRESS --broadcast -vvvv "${@:4}"
            else
                forge script "$contract" --rpc-url "$rpc_url" --private-key $PRIVATE_KEY --broadcast -vvvv "${@:4}"
            fi
            ;;

        *)
            echo "Invalid NETWORK value"
            exit 1
            ;;
    esac
}

usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  deploy-test-environment <wrapped M token> <swap router> <mnav price feed> <tokens> <price feeds> <redemption timelock>"
    echo ""
    echo "  deploy-test-mnav-price-feed"
    echo "  deploy-swap-adapter <wrapped M token> <swap router> <tokens>"
    echo "  deploy-price-oracle <M NAV price feed> <tokens> <price feeds>"
    echo "  deploy-oadapter <token> <lz endpoint>"
    echo "  deploy-otoken <name> <symbol>"
    echo "  deploy-ousdai-utility <o adapter> <lz endpoint>"
    echo ""
    echo "  upgrade-usdai"
    echo "  upgrade-staked-usdai"
    echo "  upgrade-otoken <token>"
    echo "  upgrade-ousdai-utility <lz endpoint>"
    echo ""
    echo "  swap-adapter-set-token-whitelist <tokens>"
    echo "  price-oracle-set-price-feeds <tokens> <price feeds>"
    echo "  grant-role <target> <role> <account>"
    echo ""
    echo "  deploy-production-environment <wrapped M token> <swap router> <mnav price feed> <tokens> <price feeds> <multisig>"
    echo "  deploy-omnichain-environment <deployer> <lz endpoint> <multisig>"
    echo "  create3-proxy-calldata <deployer> <salt> <implementation> <data>"
    echo ""
    echo "  show"
    echo ""
    echo "Options:"
    echo "  NETWORK: Set this environment variable to either 'local' or a network name."
}

### deployment manager ###

DEPLOYMENTS_FILE="deployments/${NETWORK}.json"

if [[ -z "$NETWORK" ]]; then
    echo "Error: Set NETWORK."
    echo ""
    usage
    exit 1
fi

case $1 in
   "test")
        run "$NETWORK" "${NETWORK^^}_RPC_URL" "script/Test.s.sol:Test" --sig "run()"
        ;;

   "deploy-test-environment")
        if [ "$#" -ne 7 ]; then
            echo "Invalid argument count"
            exit 1
        fi

        run "$NETWORK" "${NETWORK^^}_RPC_URL" "script/DeployTestEnvironment.s.sol:DeployTestEnvironment" --sig "run(address,address,address,address[],address[],uint64)" $2 $3 $4 "$5" "$6" $7
        ;;

   "deploy-test-mnav-price-feed")
        run "$NETWORK" "${NETWORK^^}_RPC_URL" "script/DeployTestMNAVPriceFeed.s.sol:DeployTestMNAVPriceFeed" --sig "run()"
        ;;

   "deploy-swap-adapter")
        if [ "$#" -ne 4 ]; then
            echo "Invalid argument count"
            exit 1
        fi

        run "$NETWORK" "${NETWORK^^}_RPC_URL" "script/DeploySwapAdapter.s.sol:DeploySwapAdapter" --sig "run(address,address,address[])" $2 $3 "$4"
        ;;

   "deploy-price-oracle")
        if [ "$#" -ne 4 ]; then
            echo "Invalid argument count"
            exit 1
        fi

        run "$NETWORK" "${NETWORK^^}_RPC_URL" "script/DeployPriceOracle.s.sol:DeployPriceOracle" --sig "run(address,address[],address[])" $2 "$3" "$4"
        ;;

   "deploy-oadapter")
        if [ "$#" -ne 3 ]; then
            echo "Invalid argument count"
            exit 1
        fi

        run "$NETWORK" "${NETWORK^^}_RPC_URL" "script/DeployOAdapter.s.sol:DeployOAdapter" --sig "run(address,address)" $2 $3
        ;;

   "deploy-otoken")
        if [ "$#" -ne 3 ]; then
            echo "Invalid argument count"
            exit 1
        fi

        run "$NETWORK" "${NETWORK^^}_RPC_URL" "script/DeployOToken.s.sol:DeployOToken" --sig "run(string,string)" "$2" "$3"
        ;;

   "deploy-ousdai-utility")
        if [ "$#" -ne 3 ]; then
            echo "Invalid argument count"
            exit 1
        fi

        run "$NETWORK" "${NETWORK^^}_RPC_URL" "script/DeployOUSDaiUtility.s.sol:DeployOUSDaiUtility" --sig "run(address,address)" $2 $3
        ;;

   "upgrade-usdai")
        run "$NETWORK" "${NETWORK^^}_RPC_URL" "script/UpgradeUSDai.s.sol:UpgradeUSDai" --sig "run()"
        ;;

   "upgrade-staked-usdai")
        run "$NETWORK" "${NETWORK^^}_RPC_URL" "script/UpgradeStakedUSDai.s.sol:UpgradeStakedUSDai" --sig "run()"
        ;;

   "upgrade-otoken")
        if [ "$#" -ne 2 ]; then
            echo "Invalid argument count"
            exit 1
        fi

        run "$NETWORK" "${NETWORK^^}_RPC_URL" "script/UpgradeOToken.s.sol:UpgradeOToken" --sig "run(address)" $2
        ;;

   "upgrade-ousdai-utility")
        if [ "$#" -ne 2 ]; then
            echo "Invalid argument count"
            exit 1
        fi

        run "$NETWORK" "${NETWORK^^}_RPC_URL" "script/UpgradeOUSDaiUtility.s.sol:UpgradeOUSDaiUtility" --sig "run(address)" $2
        ;;

   "swap-adapter-set-token-whitelist")
        if [ "$#" -ne 2 ]; then
            echo "Invalid argument count"
            exit 1
        fi

        run "$NETWORK" "${NETWORK^^}_RPC_URL" "script/SwapAdapterSetTokenWhitelist.s.sol:SwapAdapterSetTokenWhitelist" --sig "run(address[])" "$2"
        ;;

   "price-oracle-add-price-feeds")
        if [ "$#" -ne 3 ]; then
            echo "Invalid argument count"
            exit 1
        fi

        run "$NETWORK" "${NETWORK^^}_RPC_URL" "script/PriceOracleAddPriceFeeds.s.sol:PriceOracleAddPriceFeeds" --sig "run(address[],address[])" "$2" "$3"
        ;;

   "grant-role")
        if [ "$#" -ne 4 ]; then
            echo "Invalid argument count"
            exit 1
        fi

        run "$NETWORK" "${NETWORK^^}_RPC_URL" "script/GrantRole.s.sol:GrantRole" --sig "run(address,string,address)" $2 $3 $4
        ;;

   "deploy-production-environment")
        if [ "$#" -ne 7 ]; then
            echo "Invalid argument count"
            exit 1
        fi

        run "$NETWORK" "${NETWORK^^}_RPC_URL" "script/DeployProductionEnvironment.s.sol:DeployProductionEnvironment" --sig "run(address,address,address,address[],address[],address)" $2 $3 $4 "$5" "$6" $7
        ;;

   "deploy-omnichain-environment")
        if [ "$#" -ne 4 ]; then
            echo "Invalid argument count"
            exit 1
        fi

        run "$NETWORK" "${NETWORK^^}_RPC_URL" "script/DeployOmnichainEnvironment.s.sol:DeployOmnichainEnvironment" --sig "run(address,address,address)" $2 $3 $4
        ;;

   "create3-proxy-calldata")
        if [ "$#" -ne 5 ]; then
            echo "Invalid argument count"
            exit 1
        fi

        run "$NETWORK" "${NETWORK^^}_RPC_URL" "script/Create3ProxyCalldata.s.sol:Create3ProxyCalldata" --sig "run(address,bytes32,address,bytes)" $2 $3 $4 $5
        ;;

    "show")
        run "$NETWORK" "${NETWORK^^}_RPC_URL" "script/Show.s.sol:Show" --sig "run()"
        ;;
    *)
        usage
        exit 1
        ;;
esac
