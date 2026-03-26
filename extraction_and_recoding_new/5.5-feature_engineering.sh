#!/bin/bash
#PBS -N feature_engineering
#PBS -l walltime=02:00:00
#PBS -l select=1:ncpus=2:mem=32gb
#PBS -o logs/feature_engineering.stdout
#PBS -e logs/feature_engineering.stderr
#PBS -j oe

# --- Move to submission directory --------------------------------------------
cd /rds/general/project/hda_25-26/live/TDS/TDS_Group7/extraction_and_recoding/scripts

# --- Create logs directory if it doesn't exist --------------------------------
mkdir -p logs

eval "$(~/miniforge3/bin/conda shell.bash hook)"
source activate r413

echo "============================="
echo "Job:       $PBS_JOBID"
echo "Node:      $(hostname)"
echo "Started:   $(date)"
echo "Directory: $(pwd)"
echo "============================="

Rscript 5.5-feature_engineering.R