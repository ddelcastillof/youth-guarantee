#!/bin/bash

# Submits every scenario in slurm/scenarios.txt, strictly one at a time.
#
# SimPaths/input is shared mutable state: each scenario stages its own inputs
# there, so no two runs may overlap. Each run job therefore depends on the
# previous run job. Summarising reads copies under data/simpaths_output and is
# free to overlap with later runs.
#
#   run(A) --afterok--> run(B) --afterok--> run(C)
#     |                   |                   |
#  afterok             afterok             afterok
#     v                   v                   v
#  summarise(A)       summarise(B)       summarise(C)
#
# Usage: ./slurm/submit_all.sh              # every scenario in scenarios.txt
#        ./slurm/submit_all.sh hi-only      # just the ones named

set -euo pipefail

SLURM_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(dirname "$SLURM_DIR")
source "$SLURM_DIR/scenario_list.sh"

cd "$REPO_ROOT"

SCENARIOS=()
if [[ $# -gt 0 ]]; then
    SCENARIOS=("$@")
else
    while IFS= read -r scenario; do
        SCENARIOS+=("$scenario")
    done < <(scenario_names)
fi

if [[ ${#SCENARIOS[@]} -eq 0 ]]; then
    echo "No scenarios to submit" >&2
    exit 1
fi

if [[ ! -d data/scenario_inputs/pristine ]]; then
    echo "No pristine input snapshot found." >&2
    echo "Run ./slurm/00_init_pristine_inputs.sh once before submitting." >&2
    exit 1
fi

# #SBATCH --output=logs/%x-%j.out fails the job if this is missing
mkdir -p logs

prev_run=""
for scenario in "${SCENARIOS[@]}"; do
    run_id=$(sbatch --parsable ${prev_run:+--dependency=afterok:$prev_run} \
        -J "run_$scenario" --export=ALL,SCENARIO="$scenario" \
        slurm/01_run_simpaths.sbatch)

    sum_id=$(sbatch --parsable --dependency=afterok:"$run_id" \
        -J "sum_$scenario" --export=ALL,SCENARIO="$scenario" \
        slurm/03_summarise.sbatch)

    printf '%-16s run=%-10s summarise=%s\n' "$scenario" "$run_id" "$sum_id"
    prev_run=$run_id
done

echo
echo "Submitted ${#SCENARIOS[@]} scenarios. Watch with: squeue -u \$USER"
echo "A failed run leaves the rest pending on afterok forever: scancel them and resubmit"
echo "from the scenario that failed, e.g. ./slurm/submit_all.sh hi-only"
