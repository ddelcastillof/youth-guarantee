#!/bin/bash
#SBATCH --job-name=compile
#SBATCH --account=none
#SBATCH --partition=nodes
#SBATCH --output=logs/%x-%j.out
#SBATCH --error=logs/%x-%j.err
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --ntasks-per-node=1
#SBATCH --time=00:30:00
#SBATCH --mem=4G
#SBATCH --mail-user=darwin.delcastillofernandez@glasgow.ac.uk
#SBATCH --mail-type=ALL

# Builds openjdk25.sif from openjdk25.def in a batch job

set -euo pipefail

if [[ -z ${SLURM_JOB_ID:-} ]]; then
    # The job starts where it was submitted from, so submit from the repo root
    cd "$(dirname "${BASH_SOURCE[0]}")"
    # #SBATCH --output=logs/%x-%j.out fails the job if this is missing
    mkdir -p logs
    exec sbatch "$(basename "${BASH_SOURCE[0]}")"
fi

# module is not written for set -eu
set +eu
module load apptainer/1.5.3/gnu1150
set -eu

# this is an non-interactive job, so it does need --force to avoid the overwriting question
apptainer build --force openjdk25.sif openjdk25.def
