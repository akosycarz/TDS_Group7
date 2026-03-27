#!/bin/bash
#PBS -l walltime=12:00:00
#PBS -l select=1:ncpus=128:ompthreads=128:mem=192gb
#PBS -N impute_split
#PBS -J 1-3

set -euxo pipefail

echo "===== JOB START ====="
date
echo "PBS_JOBID=${PBS_JOBID:-unset}"
echo "PBS_ARRAY_INDEX=${PBS_ARRAY_INDEX:-unset}"
echo "PBS_O_WORKDIR=${PBS_O_WORKDIR:-unset}"
echo "HOSTNAME=$(hostname)"
echo "PWD before cd: $(pwd)"

cd "${PBS_O_WORKDIR}/scripts"

echo "PWD after cd: $(pwd)"
echo "Contents of scripts dir:"
ls -lah

echo "Checking R script exists:"
ls -l 8-imputation_full_dataset.R

echo "Checking conda executable:"
ls -l "${HOME}/anaconda3/bin/conda"

echo "Initializing conda..."
eval "$(${HOME}/anaconda3/bin/conda shell.bash hook)"

echo "Activating env..."
conda activate r45

echo "Which R:"
which R
R --version

echo "Which Rscript:"
which Rscript
Rscript --version

echo "Running test R command..."
Rscript -e 'cat("Hello from R\n")'

echo "Running actual script..."
Rscript 8-imputation_full_dataset.R "${PBS_ARRAY_INDEX}"

echo "===== JOB END ====="
date
