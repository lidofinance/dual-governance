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
GHCRTS=''
kontrol_build() {
  notif "Kontrol Build"
  # shellcheck disable=SC2086
  run kontrol build
  return $?
}

kontrol_prove() {
  notif "Kontrol Prove"
  # shellcheck disable=SC2086
  run kontrol prove
  return $?
}

get_log_results(){
  trap clean_docker ERR
    RESULTS_FILE="results-$(date +'%Y-%m-%d-%H-%M-%S').tar.gz"
    LOG_PATH="$SCRIPT_HOME/logs"
    RESULTS_LOG="$LOG_PATH/$RESULTS_FILE"

    if [ ! -d $LOG_PATH ]; then
      mkdir $LOG_PATH
    fi

    notif "Generating Results Log: $LOG_PATH"

    run tar -czvf results.tar.gz "$OUT_DIR" > /dev/null 2>&1
    if [ "$LOCAL" = true ]; then
      mv results.tar.gz "$RESULTS_LOG"
    else
      docker cp "$CONTAINER_NAME:/home/user/workspace/results.tar.gz" "$RESULTS_LOG"
      tar -xzvf "$RESULTS_LOG" > /dev/null 2>&1
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


#############
# RUN TESTS #
#############
# Set up the trap to run the function on failure
trap on_failure ERR INT TERM
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
