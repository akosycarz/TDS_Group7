#!/bin/bash
#PBS -l walltime=24:00:00
#PBS -l select=1:ncpus=128:ompthreads=128:mem=192gb
#PBS -N imputation
#PBS -J 1-3

set -Eeuo pipefail

echo "===== JOB START ====="
date

cd "${PBS_O_WORKDIR}/scripts"

# Logging
LOGDIR="${PBS_O_WORKDIR}/logs"
mkdir -p "$LOGDIR"

exec > >(tee -a "${LOGDIR}/imputation.${PBS_JOBID}.${PBS_ARRAY_INDEX}.out")
exec 2> >(tee -a "${LOGDIR}/imputation.${PBS_JOBID}.${PBS_ARRAY_INDEX}.err" >&2)

trap 'rc=$?; echo "ERROR at line ${LINENO}: ${BASH_COMMAND}" >&2; exit ${rc}' ERR

# Activate conda
eval "$(${HOME}/anaconda3/bin/conda shell.bash hook)"
conda activate r45

run_step () {
  echo ""
  echo "=============================="
  echo "Running: $*"
  echo "Time: $(date)"
  echo "=============================="
  
  "$@"
}

# Pipeline steps (ALL keep array index)
run_step Rscript 8-imputation_full_dataset.R "${PBS_ARRAY_INDEX}"
run_step Rscript 10-dataset_splitting.R "${PBS_ARRAY_INDEX}"
run_step Rscript 9-table1.R "${PBS_ARRAY_INDEX}"
run_step Rscript 11a_impute_selection.R "${PBS_ARRAY_INDEX}"
run_step Rscript 11b_impute_refit.R "${PBS_ARRAY_INDEX}"
run_step Rscript 11c_impute_test.R "${PBS_ARRAY_INDEX}"

echo "===== JOB END ====="
date