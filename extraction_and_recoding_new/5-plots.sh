#!/bin/bash
#PBS -l walltime=4:00:00
#PBS -l select=1:ncpus=1:mem=50gb
#PBS -N plots

set -euo pipefail

cd "${PBS_O_WORKDIR}/scripts"

# Log directory
console_dir="${PBS_O_WORKDIR}/logs"
mkdir -p "$console_dir"

log_file="${console_dir}/${PBS_JOBNAME}_${PBS_JOBID}.out"

# Redirect EVERYTHING to one log file (stdout + stderr)
exec > "$log_file" 2>&1

# Activate conda
eval "$(~/anaconda3/bin/conda shell.bash hook)"
conda activate r413

echo "============================================"
echo "Job ID:      $PBS_JOBID"
echo "Job Name:    $PBS_JOBNAME"
echo "Node:        $(hostname)"
echo "Working dir: $(pwd)"
echo "Start time:  $(date)"
echo "Rscript:     $(which Rscript)"
echo "============================================"

run_step () {
  local script_name="$1"

  echo ""
  echo "--------------------------------------------"
  echo "Running: $script_name"
  echo "Start:   $(date)"
  echo "--------------------------------------------"

  Rscript "$script_name"

  echo "Finished: $script_name"
  echo "End:      $(date)"
}

run_step 21-lasso_forest.R
run_step 22-lasso_incremental.R
run_step 23-elastic_net_forest.R
run_step 24-elastic_net_incremental.R
run_step 25-uni_analysis_combined.R
run_step 26-forest_plot_combined.R
run_step 27-comparison_ROC.R

echo ""
echo "============================================"
echo "End time:  $(date)"
echo "Exit code: 0"
echo "============================================"