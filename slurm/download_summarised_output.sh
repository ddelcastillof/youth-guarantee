#!/bin/bash

# Utility script

HPC_USER=dd198b
HPC_HOST=mars-login.ice.gla.ac.uk
HPC_DIR=/users/dd198b/Documents/GitHub

scp -r $HPC_USER@$HPC_HOST:$HPC_DIR/youth-guarantee/data/simpaths_output/baseline/output_dirs.txt ./data/simpaths_output/baseline/output_dirs.txt
scp -r $HPC_USER@$HPC_HOST:$HPC_DIR/youth-guarantee/data/simpaths_output/baseline/summarised_output.csv ./data/simpaths_output/baseline/summarised_output.csv

scp -r $HPC_USER@$HPC_HOST:$HPC_DIR/youth-guarantee/data/simpaths_output/hi-only/output_dirs.txt ./data/simpaths_output/hi-only/output_dirs.txt
scp -r $HPC_USER@$HPC_HOST:$HPC_DIR/youth-guarantee/data/simpaths_output/hi-only/summarised_output.csv ./data/simpaths_output/hi-only/summarised_output.csv