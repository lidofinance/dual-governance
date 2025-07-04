#!/bin/bash
# Common functions and variables for run-kontrol.sh and make-summary-deployment.sh

notif() { echo "== $0: $*" >&2 ; }

# usage function for the run-kontrol.sh script
usage_run_kontrol() {
  echo "Usage: $0 [-h|--help] [container|local|dev] [script|tests]" 1>&2
  echo "" 1>&2
  echo "  -h, --help         Display this help message." 1>&2
  echo "" 1>&2
  echo "Execution modes:"
  echo "  container          Run in docker container. Reproduce CI execution. (Default)" 1>&2
  echo "  local              Run locally, enforces registered versions.json version for better reproducibility. (Recommended)" 1>&2
  echo "  dev                Run locally, does NOT enforce registered version. (Useful for developing with new versions and features)" 1>&2
  echo "" 1>&2
  echo "Tests executed:"
  echo "  script             Execute the tests recorded in run-kontrol.sh" 1>&2
  echo "  tests              Execute the tests provided as arguments" 1>&2
  exit 0
}

# placeholder usage function for any other scripts
usage_other() {
  echo "Usage: $0 [-h|--help] OPTIONS" 1>&2
  echo "" 1>&2
  echo "  -h, --help         Display this help message." 1>&2
  echo "" 1>&2
  echo "Further Options:"
  echo "  option1            Description1. (Default)" 1>&2
  echo "  Option2            Description2. (Recommended)" 1>&2
  exit 0
}

# Set Run Directory <root>/, This is where the foundtry.toml file generally is located.
WORKSPACE_DIR=$( cd "$SCRIPT_HOME/../../.." >/dev/null 2>&1 && pwd )
pushd "$WORKSPACE_DIR" > /dev/null || exit

# Variables
export CONTAINER_NAME=kontrol-tests
KONTROLRC=$(jq -r .kontrol < "$WORKSPACE_DIR/test/kontrol/scripts/versions.json")
export KONTROL_RELEASE=$KONTROLRC
export LOCAL=false
export SCRIPT_TESTS=false
SCRIPT_OPTION=false
export CUSTOM_TESTS=0 # Store the position where custom tests start, interpreting 0 as no tests
CUSTOM_OPTION=0
export RUN_KONTROL=false # true if any functions are called from run-kontrol.sh

# General usage function, which discerns from which script is being called and displays the appropriate message
usage() {
  if [ "$RUN_KONTROL" = "true" ]; then
    usage_run_kontrol
  else
    usage_other
  fi
}


# Argument Parsing
# The logic behind argument parsing is the following (in order):
# - Execution mode argument: container (or empty), local, dev
# - Tests arguments (first if execution mode empty): script, specific test names
parse_args() {
  if [ $# -eq 0 ]; then
    export LOCAL=false
    export SCRIPT_TESTS=false
    export CUSTOM_TESTS=0
  # `script` argument caps the total possible arguments to its position
  elif { [ $# -gt 1 ] && [ "$1" == "script" ]; } || { [ $# -gt 2 ] && [ "$2" == "script" ]; }; then
    usage
  elif [ $# -eq 1 ]; then
    SCRIPT_OPTION=false
    CUSTOM_OPTION=0
    parse_first_arg "$1"
  elif [ $# -eq 2 ] && [ "$2" == "script" ]; then
    if [ "$1" != "container" ] && [ "$1" != "local" ] && [ "$1" != "dev" ]; then
      notif "Invalid first argument. Must be \`container\`, \`local\` or \`dev\`"
      exit 1
    fi
    SCRIPT_OPTION=true
    CUSTOM_OPTION=0
    parse_first_arg "$1"
  else
    SCRIPT_OPTION=false
    CUSTOM_OPTION=2
    parse_first_arg "$1"
  fi
}

# Parse the first argument passed to `run-kontrol.sh`
parse_first_arg() {
  if [ "$1" == "container" ]; then
    notif "Running in docker container (DEFAULT)"
    export LOCAL=false
    export SCRIPT_TESTS=$SCRIPT_OPTION
    export CUSTOM_TESTS=$CUSTOM_OPTION
  elif [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
    usage
  elif [ "$1" == "local" ]; then
    notif "Running with LOCAL install, .kontrolrc CI version ENFORCED"
    export SCRIPT_TESTS=$SCRIPT_OPTION
    export CUSTOM_TESTS=$CUSTOM_OPTION
    check_kontrol_version
  elif [ "$1" == "dev" ]; then
    notif "Running with LOCAL install, IGNORING .kontrolrc version"
    export LOCAL=true
    export SCRIPT_TESTS=$SCRIPT_OPTION
    export CUSTOM_TESTS=$CUSTOM_OPTION
  elif [ "$1" == "script" ]; then
    notif "Running in docker container (DEFAULT)"
    export LOCAL=false
    NEGATED_SCRIPT_TESTS=$([[ "${SCRIPT_OPTION}" == "true" ]] && echo false || echo true)
    export SCRIPT_TESTS=$NEGATED_SCRIPT_TESTS
    export CUSTOM_TESTS=$CUSTOM_OPTION
  else
    notif "Running in docker container (DEFAULT)"
    export LOCAL=false
    export SCRIPT_TESTS=$SCRIPT_OPTION
    export CUSTOM_TESTS=1 # Store the position where custom tests start
  fi
}

check_kontrol_version() {
  if [ "$(kontrol version | awk -F': ' '{print$2}')" == "$KONTROLRC" ]; then
    notif "Kontrol version matches $KONTROLRC"
    export LOCAL=true
  else
    notif "Kontrol version does NOT match $KONTROLRC"
    notif "Please run 'kup install kontrol --version v$KONTROLRC'"
    exit 1
  fi
}

conditionally_start_docker() {
  if [ "$LOCAL" == false ]; then
    # Is old docker container running?
    if [ "$(docker ps -q -f name="$CONTAINER_NAME")" ]; then
        # Stop old docker container
        notif "Stopping old docker container"
        clean_docker
    fi
    start_docker
  fi
}

start_docker () {
  docker run \
    --name "$CONTAINER_NAME" \
    --rm \
    --interactive \
    --detach \
    --env FOUNDRY_PROFILE="$FOUNDRY_PROFILE" \
    --workdir /home/user/workspace \
    runtimeverificationinc/kontrol:ubuntu-jammy-"$KONTROL_RELEASE"

  copy_to_docker
}

copy_to_docker() {
  # Copy test content to container
  if [ "$LOCAL" == false ]; then
    TMP_DIR=$(mktemp -d)
    cp -r "$WORKSPACE_DIR/." "$TMP_DIR"
    docker cp --follow-link "$TMP_DIR/." $CONTAINER_NAME:/home/user/workspace
    rm -rf "$TMP_DIR"

    docker exec --user root "$CONTAINER_NAME" chown -R user:user /home/user
  fi
}

clean_docker(){
  if [ "$LOCAL" = false ]; then
    notif "Cleaning Docker Container"
    docker stop "$CONTAINER_NAME" > /dev/null 2>&1
    sleep 2 # Give time for system to clean up container
  else
    notif "Not Running in Container. Done."
  fi
}



docker_exec () {
  docker exec --user user --workdir /home/user/workspace $CONTAINER_NAME "${@}"
}

run () {
  if [ "$LOCAL" = true ]; then
    notif "Running local"
    # shellcheck disable=SC2086
    "${@}"
  else
    notif "Running in docker"
    docker_exec "${@}"
  fi
}

# Define the function to run on failure
on_failure() {
  get_log_results

  if [ "$LOCAL" = false ]; then
    clean_docker
  fi

  notif "Failure Cleanup Complete."
  exit 1
}
