#!/bin/bash

export JAVA_TOOL_OPTIONS="-Xmx6g -XX:+ExitOnOutOfMemoryError"

export SCENARIO=baseline
export FIRST_YEAR=2023
export LAST_YEAR=2036
export POPULATION=2500
export STARTING_SEED=42
export RUNS_PER_BATCH=1
export BATCHES=10
export SIMPATHS_PATH=../SimPaths

Rscript src/01_run_simpaths.R