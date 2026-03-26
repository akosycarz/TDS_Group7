#!/bin/bash
#PBS -N tds_pipeline
#PBS -l walltime=24:00:00
#PBS -l select=1:ncpus=4:mem=64gb
#PBS -o logs/pipeline.stdout
#PBS -e logs/pipeline.stderr
#PBS -j oe

# ---- Load R ----
module load r/4.4.0

# ---- Move to script directory ----
SCRIPT_DIR="/rds/general/project/hda_25-26/live/TDS/TDS_Group7/extraction_and_recoding/scripts"
cd "$SCRIPT_DIR" || { echo "ERROR: could not cd to $SCRIPT_DIR"; exit 1; }

# ---- Create logs directory if it doesn't exist ----
mkdir -p logs

echo "============================="
echo "Job:       $PBS_JOBID"
echo "Node:      $(hostname)"
echo "Started:   $(date)"
echo "Directory: $(pwd)"
echo "============================="

Rscript run_pipeline.R

EXIT_CODE=$?

echo "============================="
echo "Finished: $(date)"
echo "Exit code: $EXIT_CODE"
echo "============================="

exit $EXIT_CODE
