#PBS -l walltime=4:00:00
#PBS -l select=1:ncpus=1:mem=50gb
#PBS -N extraction

# Go to the scripts folder inside the directory where qsub was run
cd "$PBS_O_WORKDIR/scripts" || exit 1

# set log directory
console_dir=../logs
mkdir -p "$console_dir"

eval "$(~/anaconda3/bin/conda shell.bash hook)" || exit 1

conda activate phd_r || exit 1


# Run the R script and save console output to logs
Rscript 7-cleaning.R > "${console_dir}/${PBS_JOBNAME}_${PBS_JOBID}.out" 2>&1

