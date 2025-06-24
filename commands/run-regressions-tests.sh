#!/usr/bin/env bash

set -e

COMMANDS_DIR="$(dirname "$(realpath "$0")")"
source "$COMMANDS_DIR/lib/env-utils.sh"

validate_env "DEPLOY_ARTIFACT_FILE_NAME" "MAINNET_RPC_URL"

export GRANT_REQUIRED_PERMISSIONS=false

forge test -vv --match-path "test/regressions/*"