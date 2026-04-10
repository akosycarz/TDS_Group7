#!/bin/bash

#PBS -N model3_xgboost_cvd602020
#PBS -l nodes=1:ppn=16
#PBS -l mem=64gb
#PBS -l walltime=12:00:00
#PBS -j oe
#PBS -m abe

# Move to scripts folder
cd $PBS_O_WORKDIR/scripts

# Activate conda environment
eval "$(~/anaconda3/bin/conda shell.bash hook)"
conda activate r45

# Print job info
echo "============================================"
echo "Job ID:        $PBS_JOBID"
echo "Job Name:      $PBS_JOBNAME"
echo "Node:          $(hostname)"
echo "Working dir:   $(pwd)"
echo "Start time:    $(date)"
echo "Python:        $(which python)"
echo "============================================"

# Run script
python 15-python-boost.py

# Done
echo "============================================"
echo "End time: $(date)"
echo "Exit code: $?"
echo "============================================"

