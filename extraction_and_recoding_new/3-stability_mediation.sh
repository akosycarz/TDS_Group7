#!/bin/bash
#PBS -q v1_medium72a
#PBS -l walltime=30:00:00
#PBS -l select=1:ncpus=16:ompthreads=1:mem=128gb
#PBS -N stability_mediation

set -euo pipefail

cd "${PBS_O_WORKDIR}/scripts"

console_dir="${PBS_O_WORKDIR}/logs"
mkdir -p "$console_dir"

log_file="${console_dir}/${PBS_JOBNAME}_${PBS_JOBID}.out"
exec > "$log_file" 2>&1

eval "$(~/anaconda3/bin/conda shell.bash hook)"
conda activate r45

echo "Job started at $(date)"
echo "Running in $(pwd)"
echo "Job ID: ${PBS_JOBID:-unset}"
echo "Host: $(hostname)"
echo "Allocated CPUs: ${PBS_NCPUS:-unknown}"
echo "OMP threads: ${OMP_NUM_THREADS:-unset}"

run_step () {
    local step_name="$1"
    shift

    echo ""
    echo "=============================="
    echo "Starting ${step_name} at $(date)"
    echo "Command: $*"
    echo "=============================="

    "$@"

    echo "Finished ${step_name} at $(date)"
}


run_step "12-lasso_stability_selection_model1"       R CMD BATCH 12-lasso_stability_selection_model1.R
run_step "13-elastic_net_stability_selection_model1" R CMD BATCH 13-elastic_net_stability_selection_model1.R
run_step "14-model1_refit_logistic"                  R CMD BATCH 14-model1_refit_logistic.R
run_step "18-final_analysis_mediation"               Rscript 18-final_analysis_mediation.R
run_step "19-mediation_dag_figures"                  Rscript 19-mediation_dag_figures.R
run_step "20-mediation_figures_heatmaps"             Rscript 20-mediation_figures_heatmaps.R

echo ""
echo "Pipeline finished successfully at $(date)"