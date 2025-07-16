#!/usr/bin/env bash
# Lightweight wrapper around `forge script` used throughout the repo.
#
# Environment variables used (can be supplied via .env):
#   RPC_URL                 – RPC endpoint to broadcast transactions.
#   ETHERSCAN_API_KEY       – API key for contract verification.
# optional:
#   DEPLOYER_ACCOUNT        – Foundry account cast wallet name.
#   DEPLOYER_ADDRESS        – Explicit sender address (optional).

set -e

export $(grep -vE '^\s*#' .env | sed -E 's/[[:space:]]+#.*$//' | xargs)

source "$(dirname "$(realpath "$0")")/lib/env-utils.sh"

validate_env "RPC_URL" "ETHERSCAN_API_KEY"

SCRIPT_PATH="$1"
shift

CONTRACT_NAME=$(basename "$SCRIPT_PATH" .s.sol)

args=(
  "$SCRIPT_PATH:$CONTRACT_NAME"
  "--rpc-url" "$RPC_URL"
  "--etherscan-api-key" "$ETHERSCAN_API_KEY"
  "--force"
)

if [[ -n "${DEPLOYER_ACCOUNT:-}" ]]; then
  args+=("--account" "$DEPLOYER_ACCOUNT")
fi

if [[ -n "${DEPLOYER_ADDRESS:-}" ]]; then
  args+=("--sender" "$DEPLOYER_ADDRESS")
fi

# Forward any extra CLI args
args+=("$@")

echo "Running: forge script ${args[*]}" >&2
forge script "${args[@]}"
