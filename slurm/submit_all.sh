#!/bin/bash
#SBATCH --account=none
#SBATCH --partition=nodes
#SBATCH --output=logs/%x-%j.out
#SBATCH --error=logs/%x-%j.err
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --ntasks-per-node=1
#SBATCH --mail-user=darwin.delcastillofernandez@glasgow.ac.uk
#SBATCH --mail-type=ALL

# The whole SimPaths pipeline in one file.
#
# Usage: ./slurm/submit_all.sh                       # every scenario in SCENARIOS
#        ./slurm/submit_all.sh hi-only               # just the ones named
#        ./slurm/submit_all.sh --stage summarise X   # one stage in place, e.g. to re-summarise
#        ./slurm/submit_all.sh --download [X ...]    # on your machine: fetch the summaries
#        ./slurm/submit_all.sh --init                # once ever: snapshot the pristine inputs
#
# Submitting queues this same file as every job, with `--stage <stage> <scenario>`
# appended; the #SBATCH lines above are what both stages share.
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

set -euo pipefail

# Run in this order. Each name needs a mutation registered in src/00_stage_scenario.py
# (baseline needs none: it is the pristine inputs). Scenarios that switch on supported
# employment are listed in src/00_stage_config.py.
SCENARIOS=(baseline yg-scenario-only hi-only both-scenarios)

# Input files any scenario mutates; add to this list when a scenario touches a new one
PRISTINE_FILES=(reg_health_wellbeing.xlsx)

export SIMPATHS_PATH=${SIMPATHS_PATH:-../SimPaths}
# Written into SimPaths/config by src/00_stage_config.py each run
export SIMPATHS_CONFIG=youth_guarantee.yml
export FIRST_YEAR=2019
export LAST_YEAR=2026
export POPULATION=50000
# Seeds must be identical across scenarios: the report pairs them by seed
# (simpaths-results.qmd merges by c("seed", "time", "strata"))
export STARTING_SEED=606
export RUNS_PER_BATCH=1
export BATCHES=1

HPC_LOGIN=dd198b@mars-login.ice.gla.ac.uk
HPC_REPO=/users/dd198b/Documents/GitHub/youth-guarantee

activate_env() {
    # module and the conda activation hooks are not written for set -eu
    set +eu
    module purge
    module load apps/miniforge
    # yg-py holds requirements.txt and Java 25, which MARS only offers through conda
    source "$(conda info --base)/etc/profile.d/conda.sh"
    conda activate yg-py
    local status=$?
    set -eu

    if (( status != 0 )); then
        echo "Could not activate conda env yg-py; create it from requirements.txt" >&2
        exit 1
    fi
}

stage_run() {
    export JAVA_TOOL_OPTIONS="-Xmx6g -XX:+ExitOnOutOfMemoryError"

    # Restore pristine inputs, then apply this scenario's mutation.
    # Must run inside the job: staging at submit time would have every scenario
    # overwrite SimPaths/input before any job started.
    python3 src/00_stage_scenario.py
    # Same for SimPaths/config: switches supported employment on or off for this scenario
    python3 src/00_stage_config.py
    python3 src/01_run_simpaths.py
}

stage_summarise() {
    local results=data/simpaths_output/$SCENARIO
    local manifest=$results/output_dirs.txt
    local copied=() run from to

    if [[ ! -f $manifest ]]; then
        echo "No manifest at $manifest: run the run stage for $SCENARIO first" >&2
        exit 1
    fi

    # Copy each run's CSVs out of SimPaths, then point the manifest at the copies.
    # Safe to repeat: a run already copied is kept once SimPaths no longer has it.
    while IFS= read -r run || [[ -n $run ]]; do
        [[ -n $run ]] || continue
        run=$(basename "$run")
        from=$SIMPATHS_PATH/output/$run/csv
        to=$results/$run/csv

        if [[ -f $from/Person.csv && -f $from/BenefitUnit.csv ]]; then
            mkdir -p "$to"
            cp "$from/Person.csv" "$from/BenefitUnit.csv" "$to/"
        elif [[ ! -f $to/Person.csv || ! -f $to/BenefitUnit.csv ]]; then
            echo "Person.csv or BenefitUnit.csv missing for $run, skipping" >&2
            continue
        fi
        copied+=("$PWD/$results/$run")
    done < "$manifest"

    if (( ${#copied[@]} == 0 )); then
        echo "No run listed in $manifest found under $SIMPATHS_PATH/output" >&2
        exit 1
    fi
    printf '%s\n' "${copied[@]}" > "$manifest"
    echo "Copied ${#copied[@]} runs into $results"

    python3 src/02_outputs_sum.py
}

submit() {
    (( $# )) || set -- "${SCENARIOS[@]}"

    if [[ ! -d data/scenario_inputs/pristine ]]; then
        echo "No pristine input snapshot found. Run $0 --init once before submitting." >&2
        exit 1
    fi

    # #SBATCH --output=logs/%x-%j.out fails the job if this is missing
    mkdir -p logs

    local scenario run_id sum_id prev_run=""
    for scenario in "$@"; do
        run_id=$(sbatch --parsable ${prev_run:+--dependency=afterok:$prev_run} \
            -J "run_$scenario" --time=2-00:00:00 --mem=8G \
            "$SELF" --stage run "$scenario")

        sum_id=$(sbatch --parsable --dependency=afterok:"$run_id" \
            -J "sum_$scenario" --time=01:00:00 --mem=4G \
            "$SELF" --stage summarise "$scenario")

        printf '%-16s run=%-10s summarise=%s\n' "$scenario" "$run_id" "$sum_id"
        prev_run=$run_id
    done

    echo
    echo "Submitted $# scenarios. Watch with: squeue -u \$USER"
    echo "A failed run leaves the rest pending on afterok forever: scancel them and resubmit"
    echo "from the scenario that failed, e.g. $0 hi-only"
}

download() {
    (( $# )) || set -- "${SCENARIOS[@]}"

    local scenario file
    for scenario in "$@"; do
        mkdir -p "data/simpaths_output/$scenario"
        for file in output_dirs.txt summarised_output.csv staged_inputs.txt simpaths_config.yml; do
            echo "Fetching $scenario/$file"
            scp "$HPC_LOGIN:$HPC_REPO/data/simpaths_output/$scenario/$file" \
                "data/simpaths_output/$scenario/$file"
        done
    done

    echo "Downloaded $# scenarios"
}

# Snapshots the SimPaths input files that scenarios mutate, so every run can be
# restored to a known-clean starting point. Refuses to capture a snapshot that
# already carries a scenario's effect: that would enshrine an intervention as
# the baseline, silently, for every run afterwards.
init_pristine() {
    local src=$SIMPATHS_PATH/input dest=data/scenario_inputs/pristine file

    if [[ -n $(ls -A "$dest" 2>/dev/null) ]]; then
        echo "Pristine snapshot already exists: $dest" >&2
        echo "Refusing to overwrite it. Delete it by hand if you really mean to re-capture." >&2
        exit 1
    fi

    for file in "${PRISTINE_FILES[@]}"; do
        if [[ ! -f $src/$file ]]; then
            echo "Missing input file: $src/$file" >&2
            exit 1
        fi
    done

    python3 - "$src" <<'PY'
import sys
from pathlib import Path

from openpyxl import load_workbook

sys.path.insert(0, "src")
from scenarios import hi_only

simpaths_input = Path(sys.argv[1])

for scenario in (hi_only,):
    sheet = load_workbook(simpaths_input / scenario.WORKBOOK, read_only=True)[scenario.SHEET]
    regressors = [row[0] for row in sheet.iter_rows(min_row=2, max_col=1, values_only=True)]
    if scenario.REGRESSOR in regressors:
        sys.exit(
            f"{simpaths_input / scenario.WORKBOOK} already contains {scenario.REGRESSOR} in {scenario.SHEET}.\n"
            "These inputs carry a scenario effect and cannot be used as the pristine baseline.\n"
            "Restore a clean copy (git -C <SimPaths> checkout -- input/) and run this again."
        )

print("Contamination check passed: inputs are clean")
PY

    mkdir -p "$dest"
    for file in "${PRISTINE_FILES[@]}"; do
        cp "$src/$file" "$dest/$file"
        echo "Captured $file"
    done
    echo "Pristine snapshot written to $dest"
}

if [[ ${1:-} == --stage ]]; then
    # A job runs a spooled copy of this file, so BASH_SOURCE no longer points into
    # the repo; it starts where it was submitted from, which submit() makes the root
    cd "${SLURM_SUBMIT_DIR:-$(dirname "${BASH_SOURCE[0]}")/..}"
    export SCENARIO=$3
    activate_env
    case $2 in
        run) stage_run ;;
        summarise) stage_summarise ;;
        *) echo "Unknown stage: $2 (expected run or summarise)" >&2; exit 1 ;;
    esac
    exit
fi

SELF=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")
cd "$(dirname "$SELF")/.."

case ${1:-} in
    --init) init_pristine ;;
    --download) shift; download "$@" ;;
    *) submit "$@" ;;
esac
