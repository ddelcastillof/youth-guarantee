#!/bin/bash

# Utility script
# Pulls each scenario's summarised output down from the cluster.

set -euo pipefail

SLURM_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(dirname "$SLURM_DIR")
source "$SLURM_DIR/scenario_list.sh"

cd "$REPO_ROOT"

HPC_USER=dd198b
HPC_HOST=mars-login.ice.gla.ac.uk
HPC_DIR=/users/dd198b/Documents/GitHub

REMOTE_ROOT=$HPC_DIR/youth-guarantee/data/simpaths_output
LOCAL_ROOT=./data/simpaths_output

SCENARIOS=()
if [[ $# -gt 0 ]]; then
    SCENARIOS=("$@")
else
    while IFS= read -r scenario; do
        SCENARIOS+=("$scenario")
    done < <(scenario_names)
fi

for scenario in "${SCENARIOS[@]}"; do
    mkdir -p "$LOCAL_ROOT/$scenario"
    for filename in output_dirs.txt summarised_output.csv staged_inputs.txt; do
        echo "Fetching $scenario/$filename"
        scp "$HPC_USER@$HPC_HOST:$REMOTE_ROOT/$scenario/$filename" \
            "$LOCAL_ROOT/$scenario/$filename"
    done
done

echo "Downloaded ${#SCENARIOS[@]} scenarios"
