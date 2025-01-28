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
    echo "  deploy <wrapped M token> <swap router> <staked timelock>"
    echo "  upgrade-usdai <swap adapter>"
    echo "  upgrade-staked-usdai"
    echo "  test"
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

   "deploy")
        if [ "$#" -ne 4 ]; then
            echo "Invalid argument count"
            exit 1
        fi

        run "$NETWORK" "${NETWORK^^}_RPC_URL" "script/Deploy.s.sol:Deploy" --sig "run(address,address,uint64)" $2 $3 $4
        ;;

   "upgrade-usdai")
        if [ "$#" -ne 2 ]; then
            echo "Invalid argument count"
            exit 1
        fi

        run "$NETWORK" "${NETWORK^^}_RPC_URL" "script/UpgradeUSDai.s.sol:UpgradeUSDai" --sig "run(address)" $2
        ;;

   "upgrade-staked-usdai")
        run "$NETWORK" "${NETWORK^^}_RPC_URL" "script/UpgradeStakedUSDai.s.sol:UpgradeStakedUSDai" --sig "run()"
        ;;

    "show")
        run "$NETWORK" "${NETWORK^^}_RPC_URL" "script/Show.s.sol:Show" --sig "run()"
        ;;
    *)
        usage
        exit 1
        ;;
esac
