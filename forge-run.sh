#!/usr/bin/env bash
set -e

export $(grep -vE '^\s*#' .env | sed -E 's/[[:space:]]+#.*$//' | xargs)

SCRIPT_PATH="$1"
shift

CONTRACT_NAME=$(basename "$SCRIPT_PATH" .s.sol)

args=(
  "$SCRIPT_PATH:$CONTRACT_NAME"
  "--rpc-url" "$RPC_URL"
  "--etherscan-api-key" "$ETHERSCAN_API_KEY"
  "--force"
)

if [[ -n "$DEPLOYER_ACCOUNT" ]]; then
  args+=( "--account" "$DEPLOYER_ACCOUNT" )
fi

if [[ -n "$DEPLOYER_ADDRESS" ]]; then
  args+=( "--sender" "$DEPLOYER_ADDRESS" )
fi

args+=( "$@" )

# Run Foundry script

forge script "${args[@]}"
