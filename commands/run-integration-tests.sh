#!/usr/bin/env bash

set -e

COMMANDS_DIR="$(dirname "$(realpath "$0")")"
source "$COMMANDS_DIR/lib/env-utils.sh"

validate_env "MAINNET_RPC_URL"

export DEPLOY_ARTIFACT_FILE_NAME=""
export GRANT_REQUIRED_PERMISSIONS=true
export RUN_SOLVENCY_SIMULATION_TEST=false
export ENABLE_REGRESSION_TEST_COMPLETE_RAGE_QUIT=false

forge test -vv --match-path "test/{regressions,scenario}/*"