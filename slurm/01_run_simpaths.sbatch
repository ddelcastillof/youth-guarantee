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

module load apps/python3
module load apps/java/23.0.1/noarch

export JAVA_TOOL_OPTIONS="-Xmx6g -XX:+ExitOnOutOfMemoryError"

export SCENARIO=baseline
export FIRST_YEAR=2023
export LAST_YEAR=2035
export POPULATION=2000
export STARTING_SEED=100
export RUNS_PER_BATCH=5
export BATCHES=5
export SIMPATHS_PATH=../SimPaths

python3 src/01_run_simpaths.py