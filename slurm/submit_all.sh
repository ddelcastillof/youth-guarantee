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
#        ./slurm/submit_all.sh --stage effects       # re-run the cohort comparison in place
#        ./slurm/submit_all.sh --download [X ...]    # on your machine: fetch the summaries
#
# Submitting queues this same file as every job, with `--stage <stage> <scenario>`
# appended; the #SBATCH lines above are what all stages share.
#
# SimPaths/config and the input database SimPaths builds in SimPaths/input are
# shared mutable state: each scenario writes its own config and rebuilds the
# database, so no two runs may overlap. Each run job therefore depends on the
# previous run job. Summarising reads copies under data/simpaths_output and is
# free to overlap with later runs. The effects job compares every scenario with
# baseline, so it waits for all of them to be summarised.
#
#   run(A) --afterok--> run(B) --afterok--> run(C)
#     |                   |                   |
#  afterok             afterok             afterok
#     v                   v                   v
#  summarise(A)       summarise(B)       summarise(C)
#     |                   |                   |
#     +------------- afterok (all) -----------+
#                         v
#                      effects

set -euo pipefail

# Run in this order. Every name but baseline must be listed in src/00_stage_config.py,
# which switches on its supported employment, its MCS shock, or both.
SCENARIOS=(baseline yg-scenario-only hi-only both-scenarios)

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

    # Switches this scenario's interventions on or off in SimPaths/config.
    # Must run inside the job: writing it at submit time would have every
    # scenario overwrite SimPaths/config before any job started.
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

stage_effects() {
    # Reads every scenario's person_years.parquet, whichever job wrote it
    python3 src/03_cohort_effects.py
}

submit() {
    (( $# )) || set -- "${SCENARIOS[@]}"

    # #SBATCH --output=logs/%x-%j.out fails the job if this is missing
    mkdir -p logs

    local scenario run_id sum_id effects_id prev_run="" sum_ids=()
    for scenario in "$@"; do
        run_id=$(sbatch --parsable ${prev_run:+--dependency=afterok:$prev_run} \
            -J "run_$scenario" --time=2-00:00:00 --mem=8G \
            "$SELF" --stage run "$scenario")

        sum_id=$(sbatch --parsable --dependency=afterok:"$run_id" \
            -J "sum_$scenario" --time=01:00:00 --mem=4G \
            "$SELF" --stage summarise "$scenario")

        printf '%-16s run=%-10s summarise=%s\n' "$scenario" "$run_id" "$sum_id"
        prev_run=$run_id
        sum_ids+=("$sum_id")
    done

    # Scenarios summarised by earlier submissions are compared too, as their
    # person_years.parquet is already in place
    effects_id=$(sbatch --parsable --dependency=afterok:"$(IFS=:; echo "${sum_ids[*]}")" \
        -J effects --time=01:00:00 --mem=8G \
        "$SELF" --stage effects)
    printf '%-16s effects=%s\n' "(all)" "$effects_id"

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
        # person_years.parquet lets src/03_cohort_effects.py be re-run locally
        for file in output_dirs.txt person_years.parquet simpaths_config.yml; do
            echo "Fetching $scenario/$file"
            scp "$HPC_LOGIN:$HPC_REPO/data/simpaths_output/$scenario/$file" \
                "data/simpaths_output/$scenario/$file"
        done
    done

    # Written once for all scenarios by the effects stage; what simpaths-results.qmd reads
    for file in cohort_levels.csv cohort_effects.csv; do
        echo "Fetching $file"
        scp "$HPC_LOGIN:$HPC_REPO/data/simpaths_output/$file" "data/simpaths_output/$file"
    done

    echo "Downloaded $# scenarios"
}

if [[ ${1:-} == --stage ]]; then
    # A job runs a spooled copy of this file, so BASH_SOURCE no longer points into
    # the repo; it starts where it was submitted from, which submit() makes the root
    cd "${SLURM_SUBMIT_DIR:-$(dirname "${BASH_SOURCE[0]}")/..}"
    # effects covers every scenario at once, so it is the one stage without a name
    export SCENARIO=${3:-}
    if [[ ${2:-} != effects && -z $SCENARIO ]]; then
        echo "--stage ${2:-} needs a scenario name" >&2
        exit 1
    fi
    activate_env
    case $2 in
        run) stage_run ;;
        summarise) stage_summarise ;;
        effects) stage_effects ;;
        *) echo "Unknown stage: $2 (expected run, summarise or effects)" >&2; exit 1 ;;
    esac
    exit
fi

SELF=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")
cd "$(dirname "$SELF")/.."

case ${1:-} in
    --download) shift; download "$@" ;;
    *) submit "$@" ;;
esac
