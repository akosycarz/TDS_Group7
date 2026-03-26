#PBS -l walltime=12:00:00
#PBS -l select=1:ncpus=128:ompthreads=128:mem=192gb
#PBS -N impute
#PBS -o /rds/general/project/hda_25-26/live/TDS/TDS_Group7/extraction_and_recoding/logs_ms4925
#PBS -e /rds/general/project/hda_25-26/live/TDS/TDS_Group7/extraction_and_recoding/logs_ms4925

cd $PBS_O_WORKDIR

# Activate conda environment
eval "$(~/anaconda3/bin/conda shell.bash hook)"
source activate r45

console_dir=/rds/general/project/hda_25-26/live/TDS/TDS_Group7/extraction_and_recoding/logs_ms4925
R CMD BATCH scripts/8-imputation_full_dataset.R \
${console_dir}/${PBS_JOBNAME}_${PBS_JOBID}.Rout