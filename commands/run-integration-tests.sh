#!/usr/bin/env bash

set -e

COMMANDS_DIR="$(dirname "$(realpath "$0")")"
source "$COMMANDS_DIR/lib/env-utils.sh"

validate_env "MAINNET_RPC_URL"

# Check for --load-accounts flag
if [[ $# -gt 0 && "$1" == "--load-accounts" ]]; then
    echo "Collecting stETH & wstETH holders for the tests..."
    node test/regressions/regression-test-utils/download_vetoers.js
fi

export GRANT_REQUIRED_PERMISSIONS=true
export RUN_SOLVENCY_SIMULATION_TEST=false
export ENABLE_REGRESSION_TEST_COMPLETE_RAGE_QUIT=false
export FOUNDRY_FORK_RETRIES=15 
export FOUNDRY_FORK_RETRY_BACKOFF=2000

FUZZ_RUNS="${FUZZ_RUNS:-256}"

forge test -vv --match-path "test/{regressions,scenario}/*" --fuzz-runs $FUZZ_RUNS --compute-units-per-second 280