#!/bin/bash

module purge
module load apps/miniforge

source "$(conda info --base)/etc/profile.d/conda.sh"
conda activate yg-py

# Set by slurm/03_summarise.sbatch, or override by hand:
#   SCENARIO=hi-only ./slurm/03_summarise.sh
export SCENARIO=${SCENARIO:-baseline}

python3 src/02_outputs_sum.py
