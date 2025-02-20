#!/usr/bin/env bash
set -e

export $(grep -v '^#' .env | xargs)

SCRIPT_PATH="$1"
shift

CONTRACT_NAME=$(basename "$SCRIPT_PATH" .s.sol)

# Run Foundry script
forge \
    script $SCRIPT_PATH:$CONTRACT_NAME \
    --rpc-url $RPC_URL \
    --account $DEPLOYER_ACCOUNT \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --force \
    $@