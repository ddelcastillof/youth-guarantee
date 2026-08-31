#!/bin/bash

#SBATCH --job-name=sum_out
#SBATCH --account=none
#SBATCH --output=logs/%x-%j.out
#SBATCH --error=logs/%x-%j.err
#SBATCH --partition=nodes
#SBATCH --time=12:00:00
#SBATCH --mem=4G
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --ntasks-per-node=1
#SBATCH --mail-user=darwin.delcastillofernandez@glasgow.ac.uk
#SBATCH --mail-type=ALL
#SBATCH --array=0-4

module load apps/python3
module load apps/R/4.4.1/gcc-8.5.0+openblas-0.3.28

export SCENARIO=baseline

python3 src/02_outputs_sum.py