#!/bin/bash
set -euo pipefail

SCRIPT_HOME="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
# shellcheck source=/dev/null
source "$SCRIPT_HOME/common.sh"
export RUN_KONTROL=true
CUSTOM_FOUNDRY_PROFILE=kprove
export FOUNDRY_PROFILE=$CUSTOM_FOUNDRY_PROFILE
export OUT_DIR=kout # out dir of $FOUNDRY_PROFILE
parse_args "$@"

#############
# Functions #
#############
kontrol_build() {
  notif "Kontrol Build"
  # shellcheck disable=SC2086
  run kontrol build \
    --verbose \
    --require $lemmas \
    --module-import $module \
    $rekompile
  return $?
}

kontrol_prove() {
  notif "Kontrol Prove"
  # shellcheck disable=SC2086
  run kontrol prove \
    --verbose \
    --max-depth $max_depth \
    --max-iterations $max_iterations \
    --smt-timeout $smt_timeout \
    --workers $workers \
    --max-frontier-parallel $max_frontier_parallel \
    $reinit \
    $bug_report \
    $break_on_calls \
    $break_every_step \
    $auto_abstract \
    $tests \
    $use_booster
  return $?
}

get_log_results(){
  trap clean_docker ERR
    RESULTS_FILE="results-$(date +'%Y-%m-%d-%H-%M-%S').tar.gz"
    LOG_PATH="$SCRIPT_HOME/logs"
    RESULTS_LOG="$LOG_PATH/$RESULTS_FILE"

    if [ ! -d "$LOG_PATH" ]; then
      mkdir "$LOG_PATH"
    fi

    notif "Generating Results Log: $LOG_PATH"

    run tar -czvf results.tar.gz "$OUT_DIR" > /dev/null 2>&1
    if [ "$LOCAL" = true ]; then
      mv results.tar.gz "$RESULTS_LOG"
    else
      docker cp "$CONTAINER_NAME:/home/user/workspace/results.tar.gz" "$RESULTS_LOG"
      tar -xzvf "$RESULTS_LOG"
    fi
    if [ -f "$RESULTS_LOG" ]; then
      cp "$RESULTS_LOG" "$LOG_PATH/kontrol-results_latest.tar.gz"
    else
      notif "Results Log: $RESULTS_LOG not found, skipping.."
    fi
    # Report where the file was generated and placed
    notif "Results Log: $(dirname "$RESULTS_LOG") generated"

    if [ "$LOCAL" = false ]; then
      notif "Results Log: $RESULTS_LOG generated"
      RUN_LOG="run-kontrol-$(date +'%Y-%m-%d-%H-%M-%S').log"
      docker logs "$CONTAINER_NAME" > "$LOG_PATH/$RUN_LOG"
    fi
}

#########################
# kontrol build options #
#########################
# NOTE: This script has a recurring pattern of setting and unsetting variables,
# such as `rekompile`. Such a pattern is intended for easy use while locally
# developing and executing the proofs via this script. Comment/uncomment the
# empty assignment to activate/deactivate the corresponding flag
lemmas=test/kontrol/lido-lemmas.k
base_module=LIDO-LEMMAS
module=VetoSignallingTest:$base_module
rekompile=--rekompile
rekompile=
regen=--regen
# shellcheck disable=SC2034
regen=

#################################
# Tests to symbolically execute #
#################################
test_list=()
if [ "$SCRIPT_TESTS" == true ]; then
    # Here go the list of tests to execute with the `script` option
    test_list=(
        "VetoCooldownTest.testVetoCooldownDuration"
        "VetoSignallingTest.testTransitionNormalToVetoSignalling"
        "VetoSignallingTest.testVetoSignallingInvariantsHoldInitially"
        "EscrowAccountingTest.testRageQuitSupport"
        "EscrowAccountingTest.testEscrowInvariantsHoldInitially"
        "EscrowAccountingTest.testLockStEth"
        "EscrowAccountingTest.testUnlockStEth"
        "EscrowOperationsTest.testCannotUnlockBeforeMinLockTime"
        "EscrowOperationsTest.testCannotLockUnlockInRageQuitEscrowState"
        #"EscrowOperationsTest.testCannotWithdrawBeforeEthClaimTimelockElapsed"
    )
elif [ "$CUSTOM_TESTS" != 0 ]; then
    test_list=( "${@:${CUSTOM_TESTS}}" )
fi
tests=""
# If test_list is empty, tests will be empty as well
# This will make kontrol execute any `test`, `prove` or `check` prefixed-function
# under the foundry-defined `test` directory
for test_name in "${test_list[@]}"; do
    tests+="--match-test $test_name "
done

#########################
# kontrol prove options #
#########################
max_depth=10000
max_iterations=10000
smt_timeout=1000
max_workers=16 # Should be at most (M - 8) / 8 in a machine with M GB of RAM
# workers is the minimum between max_workers and the length of test_list
# unless no test arguments are provided, in which case we default to max_workers
if [ "$CUSTOM_TESTS" == 0 ] && [ "$SCRIPT_TESTS" == false ]; then
    workers=${max_workers}
else
    workers=$((${#test_list[@]}>max_workers ? max_workers : ${#test_list[@]}))
fi
max_frontier_parallel=6
reinit=--reinit
reinit=
break_on_calls=--no-break-on-calls
break_on_calls=
break_every_step=--no-break-every-step
break_every_step=
auto_abstract=--auto-abstract-gas
auto_abstract=
bug_report=--bug-report
bug_report=
use_booster=--no-use-booster
use_booster=


#############
# RUN TESTS #
#############
# Set up the trap to run the function on failure
trap on_failure ERR INT
trap clean_docker EXIT
conditionally_start_docker

results=()
# Run kontrol_build and store the result
kontrol_build
results[0]=$?

# Run kontrol_prove and store the result
kontrol_prove
results[1]=$?

get_log_results

# Now you can use ${results[0]} and ${results[1]}
# to check the results of kontrol_build and kontrol_prove, respectively
if [ ${results[0]} -ne 0 ] && [ ${results[1]} -ne 0 ]; then
  echo "Kontrol Build and Prove Failed"
  exit 1
elif [ ${results[0]} -ne 0 ]; then
  echo "Kontrol Build Failed"
  exit 1
elif [ ${results[1]} -ne 0 ]; then
  echo "Kontrol Prove Failed"
  exit 2
  # Handle failure
else
  echo "Kontrol Passed"
fi

notif "DONE"
