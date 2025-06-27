#!/usr/bin/env bash

set -e

COMMANDS_DIR="$(dirname "$(realpath "$0")")"
source "$COMMANDS_DIR/lib/env-utils.sh"

validate_env "DEPLOY_ARTIFACT_FILE_NAME" "MAINNET_RPC_URL"

# Check for --load-accounts flag
if [[ $# -gt 0 && "$1" == "--load-accounts" ]]; then
    echo "Collecting stETH & wstETH holders for the tests..."
    node test/regressions/regression-test-utils/download_vetoers.js
fi

export GRANT_REQUIRED_PERMISSIONS=false
export RUN_SOLVENCY_SIMULATION_TEST=false
export ENABLE_REGRESSION_TEST_COMPLETE_RAGE_QUIT=false

forge test -vv --match-path "test/regressions/*"