#!/bin/bash

#SBATCH --job-name=run_simpaths
#SBATCH --account=none
#SBATCH --output=logs/%x-%j.out
#SBATCH --error=logs/%x-%j.err
#SBATCH --partition=nodes
#SBATCH --time=2-00:00:00
#SBATCH --mem=8G
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --ntasks-per-node=1
#SBATCH --mail-user=darwin.delcastillofernandez@glasgow.ac.uk
#SBATCH --mail-type=ALL

module purge
module load apps/miniforge
module load apps/java/23.0.1/noarch

# src/00_stage_scenario.py imports openpyxl, which the bare apps/python3 module
# does not carry. Use the same env slurm/03_summarise.sh activates, built from
# requirements.txt.
source "$(conda info --base)/etc/profile.d/conda.sh"
if ! conda activate yg-py; then
    echo "Could not activate conda env yg-py; create it from requirements.txt" >&2
    exit 1
fi

export JAVA_TOOL_OPTIONS="-Xmx6g -XX:+ExitOnOutOfMemoryError"

# Overridden per scenario by slurm/submit_all.sh via --export=ALL,SCENARIO=<name>
export SCENARIO=${SCENARIO:-baseline}
export FIRST_YEAR=2023
export LAST_YEAR=2035
export POPULATION=2500
# Seeds must be identical across scenarios: the report pairs them by seed
# (simpaths-results.qmd merges by c("seed", "time", "strata"))
export STARTING_SEED=100
export RUNS_PER_BATCH=5
export BATCHES=5
export SIMPATHS_PATH=../SimPaths

# Restore pristine inputs, then apply this scenario's mutation.
# Must run inside the job: staging at submit time would have every scenario
# overwrite SimPaths/input before any job started.
if ! python3 src/00_stage_scenario.py; then
    echo "Staging failed for scenario $SCENARIO, refusing to run the simulation" >&2
    exit 1
fi

python3 src/01_run_simpaths.py
