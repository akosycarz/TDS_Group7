#!/bin/bash
#PBS -l walltime=4:00:00
#PBS -l select=1:ncpus=1:mem=50gb
#PBS -N preprocessing

set -euo pipefail

# Go to the scripts folder inside the directory where qsub was run
cd "$PBS_O_WORKDIR/scripts" || exit 1

# Set log directory
console_dir="${PBS_O_WORKDIR}/logs"
mkdir -p "$console_dir"

# Activate conda
eval "$(~/anaconda3/bin/conda shell.bash hook)" || exit 1
conda activate r413 || exit 1

# Paths used by some scripts
ukb_path=/rds/general/project/hda_25-26/live/TDS/General/Data/tabular.tsv
cvd_path=/rds/general/project/hda_25-26/live/TDS/TDS_Group7/extraction_and_recoding_new/cvd_events.rds

# Master log for the whole pipeline
master_log="${console_dir}/${PBS_JOBNAME}_${PBS_JOBID}.out"

echo "Job started at $(date)" > "$master_log"
echo "Running in $(pwd)" >> "$master_log"

run_step () {
    step_name="$1"
    shift

    echo "" | tee -a "$master_log"
    echo "==============================" | tee -a "$master_log"
    echo "Starting ${step_name} at $(date)" | tee -a "$master_log"
    echo "Command: $*" | tee -a "$master_log"
    echo "==============================" | tee -a "$master_log"

    "$@" >> "$master_log" 2>&1

    echo "Finished ${step_name} at $(date)" | tee -a "$master_log"
}

run_step "2-extract_selected"         Rscript 2-extract_selected.R "$ukb_path"
run_step "3-recode_variables_change"  Rscript 3-recode_variables_change.R
run_step "4-recoding"                 Rscript 4-recoding.R
run_step "5-collapsing"               Rscript 5-collapsing.R "$cvd_path"
run_step "5.5-feature_engineering"    Rscript 5.5-feature_engineering.R
run_step "6-preprocessing"            Rscript 6-preprocessing.R
run_step "6.5-releveling"             Rscript 6.5-releveling.R
run_step "7-cleaning"                 Rscript 7-cleaning.R
run_step "7.5-plot_labels"            Rscript 7.5-plot_labels.R
run_step "7.6-plot_functions"         Rscript 7.6-plot_functions.R

echo "" | tee -a "$master_log"
echo "Pipeline finished successfully at $(date)" | tee -a "$master_log"