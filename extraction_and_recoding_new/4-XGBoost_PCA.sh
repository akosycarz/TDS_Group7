#!/bin/bash

#PBS -N XGBoost_PCA
#PBS -l nodes=1:ppn=16
#PBS -l mem=64gb
#PBS -l walltime=24:00:00
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
echo "R:             $(which Rscript)"
echo "PyTorch:       $(python -c 'import torch; print(torch.__version__)' 2>/dev/null || echo 'not available')"
echo "CUDA:          $(python -c 'import torch; print(torch.cuda.is_available())' 2>/dev/null || echo 'not available')"
echo "============================================"

run_step () {
    echo "--------------------------------------------"
    echo "Running: $1"
    echo "Start:   $(date)"
    echo "--------------------------------------------"

    "$@"
    status=$?

    echo "--------------------------------------------"
    echo "Finished: $1"
    echo "End:      $(date)"
    echo "Exit code: $status"
    echo "--------------------------------------------"

    if [ $status -ne 0 ]; then
        echo "ERROR: step failed: $1"
        exit $status
    fi
}

# Run scripts in sequence
run_step python 15-python-boost.py
run_step python 16-python_xgboost_602020.py
run_step python 17-neural_network.py
run_step Rscript 28-PCA.R
run_step Rscript 29-xgboost-analysis.R

# Done
echo "============================================"
echo "End time: $(date)"
echo "Exit code: 0"
echo "============================================"