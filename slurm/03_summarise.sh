#!/bin/bash

module purge
module load apps/miniforge

source "$(conda info --base)/etc/profile.d/conda.sh"
conda activate yg-py

export SCENARIO=baseline

python3 src/02_outputs_sum.py