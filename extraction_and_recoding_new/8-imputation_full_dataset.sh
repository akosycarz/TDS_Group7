#PBS -l walltime=12:00:00
#PBS -l select=1:ncpus=128:ompthreads=128:mem=192gb
#PBS -N impute_split
#PBS -J 1-3

echo "===== JOB START ====="

cd "${PBS_O_WORKDIR}/scripts"

echo "Initializing conda..."
eval "$(${HOME}/anaconda3/bin/conda shell.bash hook)"

echo "Activating env..."
conda activate phd_r

echo "Running actual script..."
Rscript 8-imputation_full_dataset.R "${PBS_ARRAY_INDEX}"

echo "===== JOB END ====="
date
