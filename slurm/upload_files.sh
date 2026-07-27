#!/bin/bash 

# Utilities
# Uploading files to the cluster

HPC_USER=dd198b
HPC_HOST=mars-login.ice.gla.ac.uk
HPC_DIR=/users/dd198b/Documents/GitHub/

scp -r ../SimPaths/multirun.jar $HPC_USER@$HPC_HOST:$HPC_DIR/SimPaths/multirun.jar
scp -r ../SimPaths/singlerun.jar $HPC_USER@$HPC_HOST:$HPC_DIR/SimPaths/singlerun.jar
scp -r ../SimPaths/input/InitialPopulations/population_initial_UK_*.csv $HPC_USER@$HPC_HOST:$HPC_DIR/SimPaths/input/InitialPopulations/