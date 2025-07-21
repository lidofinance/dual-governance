#!/usr/bin/env bash

set -e

FUZZ_RUNS="${FUZZ_RUNS:-256}"

forge test -vv --match-path "test/unit/*" --fuzz-runs $FUZZ_RUNS