#!/bin/bash
#PBS -l walltime=12:00:00
#PBS -l select=1:ncpus=128:ompthreads=128:mem=192gb
#PBS -N impute_selection
#PBS -J 1-3

set -Eeuo pipefail

echo "===== JOB START ====="
date
echo "PBS_JOBID=${PBS_JOBID:-unset}"
echo "PBS_ARRAY_INDEX=${PBS_ARRAY_INDEX:-unset}"
echo "PBS_O_WORKDIR=${PBS_O_WORKDIR:-unset}"
echo "HOSTNAME=$(hostname)"
echo "PWD before cd: $(pwd)"

# Make a log directory
LOGDIR="${PBS_O_WORKDIR}/logs"
mkdir -p "$LOGDIR"

# Redirect stdout and stderr to explicit files
exec > >(tee -a "${LOGDIR}/impute_selection.${PBS_JOBID}.${PBS_ARRAY_INDEX}.out")
exec 2> >(tee -a "${LOGDIR}/impute_selection.${PBS_JOBID}.${PBS_ARRAY_INDEX}.err" >&2)

# Print the failing command and line if something errors
trap 'rc=$?; echo "ERROR: command failed at line ${LINENO}: ${BASH_COMMAND}" >&2; echo "Exit code: ${rc}" >&2; exit ${rc}' ERR

cd "${PBS_O_WORKDIR}/scripts"

echo "PWD after cd: $(pwd)"
echo "Contents of scripts dir:"
ls -lah

echo "Checking R script exists:"
ls -l 11a_impute_selection.R

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
Rscript 11a_impute_selection.R "${PBS_ARRAY_INDEX}"

echo "===== JOB END ====="
date